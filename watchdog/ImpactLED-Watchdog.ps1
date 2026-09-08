#Requires -Version 5.1
<#
.SYNOPSIS
  ImpactLED Cloud+ Desktop Player watchdog toolbar for Windows 10/11.

.DESCRIPTION
  Stays in the notification area with an optional always-on-top status bar.
  Watches ImpactLED-Cloud-Player.exe (installed by full-install.bat).
  Restarts the player if it crashes or the UI hangs.

  Does NOT start run_player.bat (that script already has its own restart loop
  and a 20s logon delay). This watchdog launches the EXE directly.

.NOTES
  Impact LED Signs  |  technician tool
  Default install: C:\ImpactLED\CloudPlayer\ImpactLED-Cloud-Player.exe
#>

[CmdletBinding()]
param(
    [string]$PlayerPath = 'C:\ImpactLED\CloudPlayer\ImpactLED-Cloud-Player.exe',
    [string]$ProcessName = 'ImpactLED-Cloud-Player',
    [int]$PollSeconds = 8,
    [int]$HangTimeoutMs = 4000,
    [int]$HangStrikes = 3,
    [int]$RestartDelaySeconds = 8,
    [int]$MaxRestartsPerHour = 8,
    [int]$StartupGraceSeconds = 45,
    [switch]$StartIfMissing,
    [switch]$NoToolbar,
    [switch]$WatchSystemMatrix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HangCheck {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    public const uint WM_NULL = 0;
    public const uint SMTO_ABORTIFHUNG = 0x0002;

    public static bool IsHung(IntPtr hwnd, uint timeoutMs) {
        if (hwnd == IntPtr.Zero) return false;
        UIntPtr result;
        IntPtr ret = SendMessageTimeout(
            hwnd, WM_NULL, UIntPtr.Zero, IntPtr.Zero,
            SMTO_ABORTIFHUNG, timeoutMs, out result);
        return ret == IntPtr.Zero;
    }
}
"@

$script:AppName       = 'ImpactLED Player Watchdog'
$script:InstallDir    = Split-Path -Parent $PlayerPath
$script:LogDir        = Join-Path $InstallDir 'watchdog-logs'
$script:LogFile       = Join-Path $LogDir ("watchdog-{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:Paused        = $false
$script:ToolbarVisible = -not $NoToolbar
$script:HangCount     = 0
$script:RestartTimes  = New-Object System.Collections.Generic.List[datetime]
$script:LastStatus    = 'Starting'
$script:LastPid       = $null
$script:SeenAt        = $null
$script:LastAction    = 'Loaded'

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-WLog {
    param([string]$Level = 'INFO', [string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss}  [{1,-5}]  {2}' -f (Get-Date), $Level, $Message
    try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
    Write-Host $line
}

function Get-PlayerProcesses {
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
}

function Test-WindowHung {
    param($Proc)
    if (-not $Proc) { return $false }
    try {
        if (-not $Proc.Responding) { return $true }
        $hwnd = $Proc.MainWindowHandle
        if ($hwnd -and $hwnd -ne [IntPtr]::Zero) {
            return [HangCheck]::IsHung($hwnd, [uint32]$HangTimeoutMs)
        }
    } catch {}
    return $false
}

function Get-PlayerState {
    $procs = @(Get-PlayerProcesses)
    if ($procs.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'DOWN'
            Detail = 'Process not running'
            Proc   = $null
            Pid    = $null
        }
    }

    # Prefer the process that owns a window (the actual player UI).
    $ui = $procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if (-not $ui) { $ui = $procs | Select-Object -First 1 }

    $age = (Get-Date) - $ui.StartTime
    if ($age.TotalSeconds -lt $StartupGraceSeconds) {
        return [pscustomobject]@{
            Status = 'STARTING'
            Detail = ('PID {0} starting ({1:N0}s)' -f $ui.Id, $age.TotalSeconds)
            Proc   = $ui
            Pid    = $ui.Id
        }
    }

    if (Test-WindowHung $ui) {
        return [pscustomobject]@{
            Status = 'HUNG'
            Detail = ('PID {0} not responding' -f $ui.Id)
            Proc   = $ui
            Pid    = $ui.Id
        }
    }

    $memMb = [math]::Round($ui.WorkingSet64 / 1MB, 0)
    return [pscustomobject]@{
        Status = 'RUNNING'
        Detail = ('PID {0}  {1} MB' -f $ui.Id, $memMb)
        Proc   = $ui
        Pid    = $ui.Id
    }
}

function Test-RestartBudget {
    $cutoff = (Get-Date).AddHours(-1)
    $keep = @($script:RestartTimes | Where-Object { $_ -gt $cutoff })
    $script:RestartTimes = New-Object System.Collections.Generic.List[datetime]
    foreach ($t in $keep) { [void]$script:RestartTimes.Add($t) }
    return ($script:RestartTimes.Count -lt $MaxRestartsPerHour)
}

function Stop-PlayerSoft {
    param($Proc)
    if (-not $Proc) { return }
    Write-WLog WARN "Stopping hung/crashed player PID $($Proc.Id)"
    try { $Proc.CloseMainWindow() | Out-Null } catch {}
    Start-Sleep -Seconds 2
    $still = Get-Process -Id $Proc.Id -ErrorAction SilentlyContinue
    if ($still) {
        try { Stop-Process -Id $Proc.Id -Force -ErrorAction Stop } catch {}
    }
    Start-Sleep -Seconds 1
    Get-PlayerProcesses | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Start-Player {
    if (-not (Test-Path -LiteralPath $PlayerPath)) {
        Write-WLog ERROR "Player EXE not found: $PlayerPath"
        $script:LastAction = 'EXE missing'
        return $false
    }
    if (-not (Test-RestartBudget)) {
        Write-WLog ERROR "Restart budget exhausted ($MaxRestartsPerHour / hour). Waiting."
        $script:LastAction = 'Budget exhausted'
        return $false
    }

    Write-WLog INFO "Starting player: $PlayerPath"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $PlayerPath
        $psi.WorkingDirectory = $script:InstallDir
        $psi.UseShellExecute = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        [void]$script:RestartTimes.Add((Get-Date))
        $script:HangCount = 0
        $script:LastAction = 'Restarted ' + (Get-Date -Format 'HH:mm:ss')
        return $true
    } catch {
        Write-WLog ERROR "Start failed: $($_.Exception.Message)"
        $script:LastAction = 'Start failed'
        return $false
    }
}

function Invoke-WatchdogTick {
    if ($script:Paused) {
        $script:LastStatus = 'PAUSED'
        return
    }

    $state = Get-PlayerState
    $script:LastStatus = $state.Status
    if ($state.Pid) { $script:LastPid = $state.Pid }

    switch ($state.Status) {
        'RUNNING' {
            $script:HangCount = 0
            $script:SeenAt = Get-Date
        }
        'STARTING' {
            $script:HangCount = 0
            $script:SeenAt = Get-Date
        }
        'HUNG' {
            $script:HangCount++
            Write-WLog WARN ("Hang strike {0}/{1} — {2}" -f $script:HangCount, $HangStrikes, $state.Detail)
            if ($script:HangCount -ge $HangStrikes) {
                Stop-PlayerSoft $state.Proc
                Start-Sleep -Seconds $RestartDelaySeconds
                Start-Player | Out-Null
            }
        }
        'DOWN' {
            Write-WLog WARN 'Player is down'
            $script:HangCount = 0
            Start-Sleep -Seconds $RestartDelaySeconds
            Start-Player | Out-Null
        }
    }

    if ($WatchSystemMatrix) {
        $sm = Get-Process -Name 'System Matrix' -ErrorAction SilentlyContinue
        if (-not $sm) {
            $smPath = 'C:\Program Files\Prismview\System Matrix\System Matrix.exe'
            if (Test-Path $smPath) {
                Write-WLog WARN 'System Matrix not running — starting'
                Start-Process -FilePath $smPath
            }
        }
    }
}

function Get-StatusColor {
    switch ($script:LastStatus) {
        'RUNNING'  { return [System.Drawing.Color]::FromArgb(16, 185, 129) }
        'STARTING' { return [System.Drawing.Color]::FromArgb(245, 158, 11) }
        'HUNG'     { return [System.Drawing.Color]::FromArgb(239, 68, 68) }
        'DOWN'     { return [System.Drawing.Color]::FromArgb(239, 68, 68) }
        'PAUSED'   { return [System.Drawing.Color]::FromArgb(148, 163, 184) }
        default    { return [System.Drawing.Color]::FromArgb(59, 130, 246) }
    }
}

# ---- UI ----------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.ShowInTaskbar = $false
$form.FormBorderStyle = 'None'
$form.TopMost = $true
$form.StartPosition = 'Manual'
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Width  = [Math]::Min(920, $wa.Width)
$form.Height = 36
$form.Left   = $wa.Left
$form.Top    = $wa.Bottom - 36
$form.Opacity = 0.94

$lblDot = New-Object System.Windows.Forms.Label
$lblDot.Text = [char]0x25CF
$lblDot.ForeColor = (Get-StatusColor)
$lblDot.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblDot.AutoSize = $true
$lblDot.Left = 10
$lblDot.Top  = 4
$form.Controls.Add($lblDot)

$lbl = New-Object System.Windows.Forms.Label
$lbl.ForeColor = [System.Drawing.Color]::White
$lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$lbl.AutoSize = $true
$lbl.Left = 32
$lbl.Top  = 9
$lbl.Text = "$($script:AppName)  |  starting..."
$form.Controls.Add($lbl)

function Add-BarButton {
    param($Text, $Left, $Click)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $b.Width = 78
    $b.Height = 24
    $b.Left = $Left
    $b.Top  = 6
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_Click($Click)
    $form.Controls.Add($b)
    return $b
}

$btnRestart = Add-BarButton 'Restart' ($form.Width - 340) {
    Write-WLog INFO 'Manual restart requested'
    $p = Get-PlayerProcesses | Select-Object -First 1
    if ($p) { Stop-PlayerSoft $p }
    Start-Sleep -Seconds 2
    Start-Player | Out-Null
}

$btnPause = Add-BarButton 'Pause' ($form.Width - 256) {
    $script:Paused = -not $script:Paused
    $btnPause.Text = $(if ($script:Paused) { 'Resume' } else { 'Pause' })
    Write-WLog INFO $(if ($script:Paused) { 'Watchdog paused' } else { 'Watchdog resumed' })
}

$btnLogs = Add-BarButton 'Logs' ($form.Width - 172) {
    if (Test-Path $script:LogFile) { Start-Process notepad.exe $script:LogFile }
    else { Start-Process explorer.exe $script:LogDir }
}

$btnHide = Add-BarButton 'Hide bar' ($form.Width - 88) {
    $script:ToolbarVisible = $false
    $form.Hide()
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Text = $script:AppName
$tray.Visible = $true
$tray.Icon = [System.Drawing.SystemIcons]::Application

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miToggle = $menu.Items.Add('Show / hide toolbar')
$miToggle.add_Click({
    $script:ToolbarVisible = -not $script:ToolbarVisible
    if ($script:ToolbarVisible) { $form.Show() } else { $form.Hide() }
})
$miRestart = $menu.Items.Add('Restart player now')
$miRestart.add_Click({ $btnRestart.PerformClick() })
$miPause = $menu.Items.Add('Pause / resume')
$miPause.add_Click({ $btnPause.PerformClick() })
$miFolder = $menu.Items.Add('Open player folder')
$miFolder.add_Click({ if (Test-Path $script:InstallDir) { Start-Process explorer.exe $script:InstallDir } })
$miLogs = $menu.Items.Add('Open log')
$miLogs.add_Click({ $btnLogs.PerformClick() })
[void]$menu.Items.Add('-')
$miExit = $menu.Items.Add('Exit watchdog')
$miExit.add_Click({
    Write-WLog INFO 'Watchdog exiting'
    $timer.Stop()
    $tray.Visible = $false
    $form.Close()
    [System.Windows.Forms.Application]::Exit()
})
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({
    $script:ToolbarVisible = $true
    $form.Show()
    $form.Activate()
})

function Update-Ui {
    $color = Get-StatusColor
    $lblDot.ForeColor = $color
    $pidBit = $(if ($script:LastPid) { "PID $($script:LastPid)" } else { 'no PID' })
    $lbl.Text = "Cloud+ Player  |  $($script:LastStatus)  |  $pidBit  |  $($script:LastAction)"
    $tray.Text = "ImpactLED  $($script:LastStatus)"
    $btnPause.Text = $(if ($script:Paused) { 'Resume' } else { 'Pause' })
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(2000, $PollSeconds * 1000)
$timer.Add_Tick({
    try { Invoke-WatchdogTick } catch { Write-WLog ERROR $_.Exception.Message }
    Update-Ui
})

$form.Add_Shown({
    Write-WLog INFO ("Watchdog started. Player={0} Poll={1}s HangStrikes={2}" -f $PlayerPath, $PollSeconds, $HangStrikes)
    if ($StartIfMissing) {
        $st = Get-PlayerState
        if ($st.Status -eq 'DOWN') { Start-Player | Out-Null }
    }
    Invoke-WatchdogTick
    Update-Ui
    if ($NoToolbar) { $form.Hide() }
})

$form.Add_FormClosing({
    $timer.Stop()
    $tray.Visible = $false
})

$timer.Start()
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
