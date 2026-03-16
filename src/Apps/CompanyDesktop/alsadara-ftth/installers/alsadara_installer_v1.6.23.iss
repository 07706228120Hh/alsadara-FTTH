[Setup]
AppName=Alsadara
AppVersion=1.6.23
AppVerName=Alsadara v1.6.23 - نظام إدارة شبكات FTTH
AppId={{8BC9CEB8-8B4A-11d0-8D11-00A0C91BC942}
AppPublisher=Alsadara Technologies
AppPublisherURL=https://alsadara.tech
AppSupportURL=https://alsadara.tech/support
AppUpdatesURL=https://github.com/07706228120Hh/alsadara-FTTH/releases
AppCopyright=Copyright © 2025-2026 Alsadara Technologies. All rights reserved.
DefaultDirName={autopf}\Alsadara
DefaultGroupName=Alsadara FTTH Management
AllowNoIcons=yes
OutputDir=Distribution_v1.6.23\Installer
OutputBaseFilename=Alsadara_v1.6.23_Setup
Compression=lzma2/ultra64
SolidCompression=yes
InternalCompressLevel=ultra64
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.17763
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=no
DisableReadyPage=no
DisableFinishedPage=no
CloseApplications=force
RestartApplications=yes
WizardStyle=modern
WizardSizePercent=120

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1
Name: "associatefiles"; Description: "ربط ملفات البيانات بالتطبيق"; GroupDescription: "إعدادات إضافية:"; Flags: unchecked
Name: "startuprun"; Description: "تشغيل التطبيق عند بدء تشغيل Windows"; GroupDescription: "إعدادات إضافية:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\README.md"; DestDir: "{app}"; DestName: "README.md"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\Alsadara FTTH"; Filename: "{app}\Alsadara.exe"; Comment: "نظام إدارة شبكات FTTH الصدارة"
Name: "{group}\إلغاء تثبيت Alsadara"; Filename: "{uninstallexe}"; Comment: "إزالة التطبيق من النظام"
Name: "{autodesktop}\Alsadara FTTH"; Filename: "{app}\Alsadara.exe"; Tasks: desktopicon; Comment: "نظام إدارة شبكات FTTH الصدارة"
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\Alsadara"; Filename: "{app}\Alsadara.exe"; Tasks: quicklaunchicon

[Registry]
Root: HKCR; Subkey: ".alsadara"; ValueType: string; ValueName: ""; ValueData: "AlsadaraDataFile"; Flags: uninsdeletevalue; Tasks: associatefiles
Root: HKCR; Subkey: "AlsadaraDataFile"; ValueType: string; ValueName: ""; ValueData: "Alsadara Data File"; Flags: uninsdeletekey; Tasks: associatefiles
Root: HKCR; Subkey: "AlsadaraDataFile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\Alsadara.exe,0"; Tasks: associatefiles
Root: HKCR; Subkey: "AlsadaraDataFile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Alsadara.exe"" ""%1"""; Tasks: associatefiles
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Alsadara"; ValueData: """{app}\Alsadara.exe"""; Tasks: startuprun
Root: HKLM; Subkey: "SOFTWARE\Alsadara Technologies\Alsadara"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Alsadara Technologies\Alsadara"; ValueType: string; ValueName: "Version"; ValueData: "1.6.23"

[Run]
Filename: "{app}\Alsadara.exe"; Description: "تشغيل Alsadara الآن"; Flags: nowait postinstall skipifsilent
Filename: "{app}\Alsadara.exe"; Flags: nowait skipifdoesntexist runasoriginaluser; Check: IsSilentMode

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM Alsadara.exe"; Flags: runhidden; RunOnceId: "StopApp"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\cache"

[Code]
function IsSilentMode(): Boolean;
begin
  Result := WizardSilent();
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
  end;
end;
