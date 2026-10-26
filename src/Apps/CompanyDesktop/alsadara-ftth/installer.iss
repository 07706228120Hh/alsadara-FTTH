[Setup]
AppName=ط§ظ„طµط¯ط§ط±ط© - Alsadara
AppVersion=2.4.28
AppPublisher=Alsadara Platform
AppPublisherURL=https://github.com/07706228120Hh/alsadara-FTTH
DefaultDirName={autopf}\Alsadara
DefaultGroupName=ط§ظ„طµط¯ط§ط±ط©
OutputDir=build\installer
OutputBaseFilename=Alsadara-Setup-v2.4.28
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\Alsadara.exe
DisableProgramGroupPage=yes
CloseApplications=force
CloseApplicationsFilter=Alsadara.exe
AppMutex=AlsadaraFTTHMutex

[Languages]
Name: "arabic"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.lib,*.exp,*.pdb"
; ط´ظ‡ط§ط¯ط© ط¬ط°ط± Let's Encrypt (ISRG Root X1) â€” طھظڈط«ط¨ظ‘طھ ظپظٹ ظ…ط®ط²ظ† ط§ظ„ط¬ط°ط± ط§ظ„ظ…ظˆط«ظˆظ‚ ظ„ظٹط«ظ‚ ط§ظ„ط¬ظ‡ط§ط² ط¨ط®ط§ط¯ظ… n8n
Source: "certs\isrgrootx1.der"; DestDir: "{app}"; Flags: ignoreversion
; ط®ط§ط¯ظ… ظˆط§طھط³ط§ط¨ ط§ظ„ظ…ط­ظ„ظٹ ط§ظ„ظ…ط¯ظ…ط¬ (Node ظ…ط­ظ…ظˆظ„ + ط§ظ„ط­ط²ظ…) â†’ {app}\whatsapp-server
; ظٹظڈط³طھط«ظ†ظ‰ ظƒط§ط´ ط§ظ„ظˆظٹط¨ ظˆظ…ظ„ظپط§طھ ط§ظ„طھط·ظˆظٹط±ط› ط¬ظ„ط³ط§طھ ط§ظ„ظˆط§طھط³ط§ط¨ طھظڈط­ظپط¸ ظپظٹ %LOCALAPPDATA% ظ„ط§ ظ‡ظ†ط§.
Source: "..\..\..\..\modules\sas-agent\whatsapp-server\*"; DestDir: "{app}\whatsapp-server"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".wwebjs_cache,.wwebjs_auth,.data,.gitignore,prepare_bundle.ps1,README.md,*.log"

[Icons]
Name: "{group}\ط§ظ„طµط¯ط§ط±ط©"; Filename: "{app}\Alsadara.exe"
Name: "{group}\ط¥ط²ط§ظ„ط© ط§ظ„طµط¯ط§ط±ط©"; Filename: "{uninstallexe}"
Name: "{autodesktop}\ط§ظ„طµط¯ط§ط±ط© - Alsadara"; Filename: "{app}\Alsadara.exe"; Tasks: desktopicon

[InstallDelete]
Type: files; Name: "{app}\*.old"

[Run]
; طھط«ط¨ظٹطھ ط¬ط°ط± ISRG Root X1 ظپظٹ ظ…ط®ط²ظ† ط§ظ„ط´ظ‡ط§ط¯ط§طھ ط§ظ„ظ…ظˆط«ظˆظ‚ط© (ظٹط¹ظ…ظ„ ظ„ط£ظ† ط§ظ„ظ…ظڈط«ط¨ظگظ‘طھ ظٹط´طھط؛ظ„ ط¨طµظ„ط§ط­ظٹط§طھ admin)
Filename: "{sys}\certutil.exe"; Parameters: "-addstore -f Root ""{app}\isrgrootx1.der"""; Flags: runhidden waituntilterminated; StatusMsg: "طھط«ط¨ظٹطھ ط´ظ‡ط§ط¯ط© ط£ظ…ط§ظ† Let's Encrypt..."
Filename: "{app}\Alsadara.exe"; Description: "طھط´ط؛ظٹظ„ ط§ظ„طµط¯ط§ط±ط©"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // ط¥ط؛ظ„ط§ظ‚ ط§ظ„طھط·ط¨ظٹظ‚ ط§ظ„ظ‚ط¯ظٹظ… ط¥ط°ط§ ظƒط§ظ† ظٹط¹ظ…ظ„
  Exec('taskkill', '/F /IM Alsadara.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  Result := True;
end;
