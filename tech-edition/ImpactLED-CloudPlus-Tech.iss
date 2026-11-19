; ============================================================================
;  ImpactLED Cloud+ Tech Edition  -  Inno Setup script
; ============================================================================
;  Single-file Windows installer for techs to run the Cloud+ Desktop Player
;  on their OWN PCs for testing.  Same exe as production (built from the same
;  player.py / player.spec) -- only the packaging differs:
;
;    * Per-user install (no admin / no UAC) under %LOCALAPPDATA%\Programs.
;      The player writes player_config.json, downloads\ and screenshots
;      beside the exe, so the install dir MUST be user-writable.
;    * NOTHING is registered to start automatically: no Task Scheduler task,
;      no Run registry key, no Startup-folder shortcut, no watchdog, no
;      updater.  Once the player is closed it stays closed until the tech
;      launches it again from the Start menu / desktop shortcut.
;    * Every shortcut passes -w so the player always starts windowed (quitting
;      saves the config, so without -w a session that ended in fullscreen via
;      F11 would reopen fullscreen).  F11 still works inside a session.
;    * No credentials are baked in.  The optional wizard page writes them to
;      this PC's player_config.json only.
;
;  Build (done by .github/workflows/build-tech.yml, needs dist\ from
;  `pyinstaller player.spec` first):
;      ISCC.exe /DAppVersion=1.0.34 /O<outdir> tech-edition\ImpactLED-CloudPlus-Tech.iss
;
;  Unattended install (optional):
;      Setup.exe /VERYSILENT /TerminalId=XXXX /TerminalSecret=YYYY [/CmsServer=https://...]
; ============================================================================

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
; version.txt uses the same "vX.Y.Z" form as production release tags.
#define VersionTag "v" + AppVersion
#define AppDisplayName "ImpactLED Cloud+ Tech Edition"
#define PlayerExe "ImpactLED-Cloud-Player.exe"

[Setup]
; Unique to the Tech Edition so it never collides with any other install.
AppId={{1F2DC336-1532-4230-8B77-DCC84ACD35F4}
AppName={#AppDisplayName}
AppVersion={#AppVersion}
AppPublisher=Impact LED Signs
AppPublisherURL=https://impactledsigns.com
DefaultDirName={localappdata}\Programs\{#AppDisplayName}
DefaultGroupName={#AppDisplayName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=ImpactLED-CloudPlus-Tech-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#PlayerExe}
UninstallDisplayName={#AppDisplayName}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\dist\{#PlayerExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\fonts\*"; DestDir: "{app}\fonts"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cloudpluslogoinvert.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "README-Tech.md"; DestDir: "{app}"; Flags: ignoreversion
; Deliberately NOT shipped: Watchdog\, updater.bat, Install-Watchdog-Autostart.*
; (those are what make the production install autostart / auto-restart / auto-update).

[Icons]
Name: "{group}\{#AppDisplayName}"; Filename: "{app}\{#PlayerExe}"; Parameters: "-w"; WorkingDir: "{app}"
Name: "{group}\Open install folder (config, downloads)"; Filename: "{win}\explorer.exe"; Parameters: """{app}"""
Name: "{group}\Uninstall {#AppDisplayName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppDisplayName}"; Filename: "{app}\{#PlayerExe}"; Parameters: "-w"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; User-initiated, optional, and registers nothing.
Filename: "{app}\{#PlayerExe}"; Parameters: "-w"; WorkingDir: "{app}"; Description: "Launch {#AppDisplayName} now"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Files the player creates at runtime (the uninstaller only removes what it installed).
; Listed individually -- never delete {app} wholesale, the tech may have picked a shared folder.
Type: filesandordirs; Name: "{app}\downloads"
Type: files; Name: "{app}\player_config.json"
Type: files; Name: "{app}\version.txt"
Type: files; Name: "{app}\screenshot_*.png"

[Code]
const
  PlayerProcessName = 'ImpactLED-Cloud-Player';
  DefaultServer     = 'https://access.impactledsigns.com/';

var
  CredPage: TInputQueryWizardPage;

{ ---- helpers ------------------------------------------------------------- }

function ParamOrDefault(const ParamName, Fallback: String): String;
begin
  Result := Trim(ExpandConstant('{param:' + ParamName + '|}'));
  if Result = '' then
    Result := Fallback;
end;

{ Escape a string for use inside a JSON "..." value. }
function JsonEscape(const S: String): String;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C = '\' then
      Result := Result + '\\'
    else if C = '"' then
      Result := Result + '\"'
    else if Ord(C) < 32 then
      Result := Result + ' '
    else
      Result := Result + C;
  end;
end;

{ Stop a running player that belongs to THIS install dir only.  Matching on the
  full exe path (not just the image name) means we never kill a production
  player that happens to be running from C:\ImpactLED\CloudPlayer on the same PC. }
procedure StopInstalledPlayer(const AppDir: String);
var
  Exe, PsExe, Args: String;
  ResultCode: Integer;
begin
  Exe := AddBackslash(AppDir) + PlayerProcessName + '.exe';
  if not FileExists(Exe) then
    Exit;

  PsExe := Exe;
  StringChangeEx(PsExe, '''', '''''', True);   { escape ' for a PowerShell single-quoted string }

  Args := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' +
          '"Get-Process -Name ''' + PlayerProcessName + ''' -ErrorAction SilentlyContinue | ' +
          'Where-Object { $_.Path -eq ''' + PsExe + ''' } | ' +
          'Stop-Process -Force -ErrorAction SilentlyContinue"';

  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(800);   { let Windows release the exe's file handle }
end;

{ ---- optional credentials page ------------------------------------------- }

procedure InitializeWizard;
begin
  CredPage := CreateInputQueryPage(wpSelectDir,
    'Cloud+ connection (optional)',
    'Enter the TEST Terminal credentials for this PC',
    'Leave these blank to skip -- you can enter them later in the player by pressing F12.' + #13#10 +
    'Use a test Terminal ID and Secret, not the credentials of a live sign.');
  CredPage.Add('Terminal ID:', False);
  CredPage.Add('Terminal Secret:', True);
  CredPage.Add('Cloud+ server URL:', False);

  { Pre-fill from /TerminalId= /TerminalSecret= /CmsServer= (used by silent installs). }
  CredPage.Values[0] := ParamOrDefault('TerminalId', '');
  CredPage.Values[1] := ParamOrDefault('TerminalSecret', '');
  CredPage.Values[2] := ParamOrDefault('CmsServer', DefaultServer);
end;

{ On an upgrade the config already exists -- never ask again, never overwrite it. }
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (CredPage <> nil) and (PageID = CredPage.ID) then
    Result := FileExists(AddBackslash(WizardDirValue) + 'player_config.json');
end;

{ ---- config + version file ----------------------------------------------- }

{ Same keys as player_config.example.json, with Tech Edition defaults
  (windowed 1280x720).  device_sn is intentionally omitted: the player
  generates a unique CLCAPC###### serial on first run. }
procedure WriteDefaultConfig;
var
  ConfigFile, TermId, Secret, Server, Enabled, Json: String;
begin
  ConfigFile := ExpandConstant('{app}\player_config.json');
  if FileExists(ConfigFile) then
    Exit;   { upgrade: keep the tech's existing config }

  TermId := Trim(CredPage.Values[0]);
  Secret := Trim(CredPage.Values[1]);
  Server := Trim(CredPage.Values[2]);
  if Server = '' then
    Server := DefaultServer;
  if TermId <> '' then
    Enabled := 'true'
  else
    Enabled := 'false';

  Json :=
    '{' + #13#10 +
    '  "width": 1280,' + #13#10 +
    '  "height": 720,' + #13#10 +
    '  "fullscreen": false,' + #13#10 +
    '  "fit_mode": "native",' + #13#10 +
    '  "fps": 60,' + #13#10 +
    '  "bar_color": "0xFF000000",' + #13#10 +
    '  "loop": true,' + #13#10 +
    '  "show_hud": false,' + #13#10 +
    '  "show_fps": false,' + #13#10 +
    '  "last_dir": "",' + #13#10 +
    '  "brightness": 100,' + #13#10 +
    '  "timezone": "",' + #13#10 +
    '  "locale_code": "",' + #13#10 +
    '  "cms_enabled": ' + Enabled + ',' + #13#10 +
    '  "cms_server": "' + JsonEscape(Server) + '",' + #13#10 +
    '  "cms_username": "' + JsonEscape(TermId) + '",' + #13#10 +
    '  "cms_password": "' + JsonEscape(Secret) + '",' + #13#10 +
    '  "cms_interval": 30,' + #13#10 +
    '  "cms_dl_dir": "",' + #13#10 +
    '  "device_type": "windows"' + #13#10 +
    '}' + #13#10;

  SaveStringToFile(ConfigFile, Json, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    { Same "vX.Y.Z" form as production; read by player.py _runtime_version(). }
    SaveStringToFile(ExpandConstant('{app}\version.txt'), '{#VersionTag}', False);
    WriteDefaultConfig;
  end;
end;

{ ---- make sure the exe is not running during upgrade / uninstall --------- }

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopInstalledPlayer(WizardDirValue);
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopInstalledPlayer(ExpandConstant('{app}'));
  Result := True;
end;
