ImpactLED Cloud+ Desktop Player  —  Watchdog Toolbar
====================================================
Windows 10 / 11   |   ImpactLED-Watchdog.exe  v1.0.0.0

What it watches
---------------
C:\ImpactLED\CloudPlayer\ImpactLED-Cloud-Player.exe

Installed by full-install.bat. This tool does not run that installer.
It starts the player EXE directly so it does not stack on run_player.bat.

Signed EXE
----------
ImpactLED-Watchdog.exe is Authenticode-signed and timestamped (DigiCert TSA).

The current signature is SELF-SIGNED (publisher = "Impact LED Signs Player
Watchdog"). Windows will still show "Unknown publisher" / SmartScreen until
you re-sign with a purchased company code-signing certificate (.pfx from
DigiCert, Sectigo, or SSL.com).

Re-sign on a tech PC that has Windows SDK:

  .\Sign-WithCompanyCert.ps1 -PfxPath C:\certs\ImpactLED-CodeSign.pfx

No company PFX? Use the self-signed EXE as-is.

On a player PC you control, run Trust-SelfSignedCert.ps1 once as
Administrator. That puts the publisher cert in Trusted Publishers + Root
so Windows stops treating the EXE as an unknown file on that machine.

On a customer's PC where you will not install a cert: click More info ->
Run anyway the first time. After that Windows usually remembers the
choice for that file path.

A purchased OV/EV code-signing cert is the only way to look like
"Impact LED Signs" on machines that have never seen this tool.

A self-signed PFX is in signing\selfsign.pfx
  password: ImpactLED-watchdog
Use that only to test the sign script — it will not clear SmartScreen.

How it decides
--------------
Every 8 seconds:
  missing process              -> start EXE
  process younger than 45s     -> grace (STARTING)
  window Not Responding x3     -> close, kill, start EXE
  cap                          -> 8 restarts per rolling hour

Install on a player PC
----------------------
1. Copy this folder to C:\ImpactLED\CloudPlayer\Watchdog\
2. Double-click ImpactLED-Watchdog.exe  (or Start-Watchdog.bat)
3. Optional logon autostart:
     Right-click Install-Watchdog-Autostart.ps1 -> Run with PowerShell

Config: watchdog.ini next to the EXE.

Samsung PrismView
-----------------
In watchdog.ini set:
  WatchSystemMatrix=True

Toolbar
-------
Top bar: Restart | Pause | Logs | Hide bar
Tray icon: double-click shows the bar; right-click for the rest.

Logs: C:\ImpactLED\CloudPlayer\watchdog-logs\
