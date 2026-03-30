[Setup]
AppName=الصدارة - Alsadara
AppVersion=1.6.39
AppPublisher=Alsadara Platform
AppPublisherURL=https://github.com/07706228120Hh/alsadara-FTTH
DefaultDirName={autopf}\Alsadara
DefaultGroupName=الصدارة
OutputDir=build\installer
OutputBaseFilename=Alsadara-Setup-v1.6.39
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\Alsadara.exe
DisableProgramGroupPage=yes
CloseApplications=force

[Languages]
Name: "arabic"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\الصدارة"; Filename: "{app}\Alsadara.exe"
Name: "{group}\إزالة الصدارة"; Filename: "{uninstallexe}"
Name: "{autodesktop}\الصدارة - Alsadara"; Filename: "{app}\Alsadara.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Alsadara.exe"; Description: "تشغيل الصدارة"; Flags: nowait postinstall
