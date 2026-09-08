# ImpactLED Player Watchdog — register logon autostart
# Always leaves a log and waits so errors stay visible.
#
# -TargetUser: the account the AtLogOn trigger fires for. Defaults to
# $env:USERNAME for interactive use (a tech running this by hand, or
# full-install.bat running as that tech/kiosk user). Pass it explicitly when
# calling from a SYSTEM-context process (e.g. updater.bat's auto-update task)
# where $env:USERNAME would resolve to SYSTEM instead of the kiosk's logon.
param(
    [string]$TargetUser = $env:USERNAME
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $here) { $here = (Get-Location).Path }
$log  = Join-Path $here 'autostart-install.log'
$taskName = 'ImpactLED Player Watchdog Toolbar'

function Write-Log([string]$msg) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg
    Write-Host $line
    try { Add-Content -Path $log -Value $line -Encoding UTF8 } catch {}
}

function Pause-End {
    Write-Host ''
    Write-Host "Log saved to: $log"
    Write-Host 'Press Enter to close...'
    try { [void][Console]::ReadLine() } catch { Start-Sleep -Seconds 20 }
}

try {
    Write-Log "Installer start"
    Write-Log "Folder : $here"
    Write-Log "User   : $TargetUser"
    Write-Log "PS     : $($PSVersionTable.PSVersion)"

    $exe = Join-Path $here 'ImpactLED-Watchdog.exe'
    $ps1 = Join-Path $here 'ImpactLED-Watchdog.ps1'

    if (Test-Path -LiteralPath $exe) {
        try { Unblock-File -LiteralPath $exe -ErrorAction SilentlyContinue } catch {}
        $runFile = $exe
        $runArgs = $null
        Write-Log "Action : $exe"
    } elseif (Test-Path -LiteralPath $ps1) {
        $runFile = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $runArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" -StartIfMissing"
        Write-Log "Action : $runFile $runArgs"
    } else {
        throw "Put this script in the same folder as ImpactLED-Watchdog.exe. Missing both EXE and PS1 in $here"
    }

    $ok = $false

    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        $action = if ($runArgs) {
            New-ScheduledTaskAction -Execute $runFile -Argument $runArgs
        } else {
            New-ScheduledTaskAction -Execute $runFile
        }
        $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $TargetUser
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        $principal = New-ScheduledTaskPrincipal -UserId $TargetUser -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        $ok = $true
        Write-Log "Registered with Register-ScheduledTask"
    } catch {
        Write-Log "Register-ScheduledTask failed: $($_.Exception.Message)"
    }

    if (-not $ok) {
        $tr = if ($runArgs) { "`"$runFile`" $runArgs" } else { "`"$runFile`"" }
        Write-Log "Trying schtasks /create ..."
        $out = & schtasks.exe /Create /TN $taskName /TR $tr /SC ONLOGON /RU $TargetUser /RL LIMITED /F 2>&1
        Write-Log ($out | Out-String)
        if ($LASTEXITCODE -eq 0) { $ok = $true }
        else { throw "schtasks failed with exit $LASTEXITCODE" }
    }

    Write-Log "Query:"
    $q = & schtasks.exe /Query /TN $taskName /FO LIST /V 2>&1
    Write-Log ($q | Out-String)

    Write-Log "Starting task once to test..."
    $run = & schtasks.exe /Run /TN $taskName 2>&1
    Write-Log ($run | Out-String)

    Write-Host ''
    Write-Host 'SUCCESS. Task name:'
    Write-Host "  $taskName"
    Write-Host 'It will start at every logon for this user.'
    Write-Host 'Look by the clock for the tray icon.'
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Host ''
    Write-Host 'FAILED. Leave this window open and read the text above.'
    Write-Host "Also see: $log"
}

Pause-End
