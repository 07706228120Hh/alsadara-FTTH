[Setup]
AppName=الصدارة - Alsadara
AppVersion=2.2.0
AppPublisher=Alsadara Platform
AppPublisherURL=https://github.com/07706228120Hh/alsadara-FTTH
DefaultDirName={autopf}\Alsadara
DefaultGroupName=الصدارة
OutputDir=build\installer
OutputBaseFilename=Alsadara-Setup-v2.2.0
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

[Icons]
Name: "{group}\الصدارة"; Filename: "{app}\Alsadara.exe"
Name: "{group}\إزالة الصدارة"; Filename: "{uninstallexe}"
Name: "{autodesktop}\الصدارة - Alsadara"; Filename: "{app}\Alsadara.exe"; Tasks: desktopicon

[InstallDelete]
Type: files; Name: "{app}\*.old"

[Run]
Filename: "{app}\Alsadara.exe"; Description: "تشغيل الصدارة"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // إغلاق التطبيق القديم إذا كان يعمل
  Exec('taskkill', '/F /IM Alsadara.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  Result := True;
end;
