#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
Install the bundled self-signed publisher cert on THIS PC so Windows
treats ImpactLED-Watchdog.exe as a known publisher.

This is the practical path when Impact LED does not have a purchased
Authenticode PFX. It does NOT make SmartScreen happy on a random
customer's PC that has never seen this cert.

Run once per player PC, elevated:
  Right-click -> Run with PowerShell
#>
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cer  = Join-Path $here 'signing\selfsign-cert.pem'
if (-not (Test-Path $cer)) { throw "Missing $cer" }

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cer
Write-Host ("Thumbprint : {0}" -f $cert.Thumbprint)
Write-Host ("Subject    : {0}" -f $cert.Subject)

function Add-ToStore([string]$storeName) {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine')
    $store.Open('ReadWrite')
    $store.Add($cert)
    $store.Close()
    Write-Host "Installed into LocalMachine\$storeName"
}

Add-ToStore 'TrustedPublisher'
Add-ToStore 'Root'

Write-Host ''
Write-Host 'Done. Close any SmartScreen prompt and run ImpactLED-Watchdog.exe again.'
Write-Host 'To remove later:'
Write-Host ("  Get-ChildItem Cert:\LocalMachine\TrustedPublisher\{0} | Remove-Item" -f $cert.Thumbprint)
Write-Host ("  Get-ChildItem Cert:\LocalMachine\Root\{0} | Remove-Item" -f $cert.Thumbprint)
