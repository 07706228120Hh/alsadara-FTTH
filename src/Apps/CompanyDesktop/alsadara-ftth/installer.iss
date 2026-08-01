[Setup]
AppName=الصدارة - Alsadara
AppVersion=2.3.0
AppPublisher=Alsadara Platform
AppPublisherURL=https://github.com/07706228120Hh/alsadara-FTTH
DefaultDirName={autopf}\Alsadara
DefaultGroupName=الصدارة
OutputDir=build\installer
OutputBaseFilename=Alsadara-Setup-v2.3.0
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
; شهادة جذر Let's Encrypt (ISRG Root X1) — تُثبّت في مخزن الجذر الموثوق ليثق الجهاز بخادم n8n
Source: "certs\isrgrootx1.der"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\الصدارة"; Filename: "{app}\Alsadara.exe"
Name: "{group}\إزالة الصدارة"; Filename: "{uninstallexe}"
Name: "{autodesktop}\الصدارة - Alsadara"; Filename: "{app}\Alsadara.exe"; Tasks: desktopicon

[InstallDelete]
Type: files; Name: "{app}\*.old"

[Run]
; تثبيت جذر ISRG Root X1 في مخزن الشهادات الموثوقة (يعمل لأن المُثبِّت يشتغل بصلاحيات admin)
Filename: "{sys}\certutil.exe"; Parameters: "-addstore -f Root ""{app}\isrgrootx1.der"""; Flags: runhidden waituntilterminated; StatusMsg: "تثبيت شهادة أمان Let's Encrypt..."
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
