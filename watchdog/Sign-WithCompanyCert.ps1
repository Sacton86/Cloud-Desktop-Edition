#Requires -Version 5.1
<#
Re-sign ImpactLED-Watchdog.exe with YOUR company code-signing certificate.

Self-signed builds still show "Unknown publisher" / SmartScreen on a clean PC.
A purchased Authenticode cert (DigiCert, Sectigo, SSL.com) in a .pfx is what
makes Windows treat the file as published by Impact LED Signs.

Usage:
  .\Sign-WithCompanyCert.ps1 -PfxPath C:\certs\ImpactLED-CodeSign.pfx

  $env:IMPACTLED_PFX_PASSWORD = '...'
  .\Sign-WithCompanyCert.ps1 -PfxPath C:\certs\ImpactLED-CodeSign.pfx
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PfxPath,

    [string]$PfxPassword,

    [string]$ExePath = (Join-Path $PSScriptRoot 'ImpactLED-Watchdog.exe'),

    [string]$TimestampUrl = 'http://timestamp.digicert.com',

    [string]$Description = 'ImpactLED Player Watchdog',

    [string]$Url = 'https://impactledsigns.com'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $PfxPath)) { throw "PFX not found: $PfxPath" }
if (-not (Test-Path $ExePath)) { throw "EXE not found: $ExePath" }

if (-not $PfxPassword) {
    $PfxPassword = $env:IMPACTLED_PFX_PASSWORD
}
if (-not $PfxPassword) {
    $sec = Read-Host -AsSecureString 'PFX password'
    $PfxPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

$signtool = $null
$cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($cmd) { $signtool = $cmd.Source }
if (-not $signtool) {
    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    )
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $hit = Get-ChildItem -Path $root -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($hit) { $signtool = $hit.FullName; break }
        }
    }
}
if (-not $signtool) {
    throw "signtool.exe not found. Install Windows SDK / Build Tools, then re-run."
}

Write-Host "Using $signtool"
& $signtool sign /fd SHA256 /td SHA256 /tr $TimestampUrl `
    /f $PfxPath /p $PfxPassword `
    /d $Description /du $Url `
    $ExePath
if ($LASTEXITCODE -ne 0) { throw "signtool failed: $LASTEXITCODE" }

& $signtool verify /pa $ExePath
Write-Host "Signed: $ExePath"
