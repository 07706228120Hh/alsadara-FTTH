[Setup]
; معلومات التطبيق الأساسية
AppName=Alsadara
AppVersion=1.2.8
AppVerName=Alsadara v1.2.8 - نظام إدارة شبكات FTTH
AppId={{8BC9CEB8-8B4A-11d0-8D11-00A0C91BC942}
AppPublisher=Alsadara Technologies
AppPublisherURL=https://alsadara.tech
AppSupportURL=https://alsadara.tech/support
AppUpdatesURL=https://alsadara.tech/updates
AppCopyright=Copyright © 2025 Alsadara Technologies. All rights reserved.

; إعدادات التثبيت
DefaultDirName={autopf}\Alsadara
DefaultGroupName=Alsadara FTTH Management
AllowNoIcons=yes
OutputDir=Distribution_v1.2.8\Installer
OutputBaseFilename=Alsadara_v1.2.8_Setup
Compression=lzma2/ultra64
SolidCompression=yes
InternalCompressLevel=ultra64

; متطلبات النظام والأمان  
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.17763
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=no
DisableReadyPage=no
DisableFinishedPage=no

; واجهة التثبيت
WizardStyle=modern
WizardSizePercent=120

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1
Name: "associatefiles"; Description: "ربط ملفات البيانات بالتطبيق"; GroupDescription: "إعدادات إضافية:"; Flags: unchecked
Name: "startuprun"; Description: "تشغيل التطبيق عند بدء تشغيل Windows"; GroupDescription: "إعدادات إضافية:"; Flags: unchecked

[Files]
; الملفات التنفيذية الرئيسية
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; ملفات إضافية (إذا كانت موجودة)
Source: "README.md"; DestDir: "{app}"; DestName: "README_Technical.md"; Flags: ignoreversion isreadme skipifsourcedoesntexist
Source: "CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
; أيقونات في قائمة ابدأ
Name: "{group}\Alsadara FTTH"; Filename: "{app}\Alsadara.exe"; Comment: "نظام إدارة شبكات FTTH الصدارة"
Name: "{group}\إلغاء تثبيت Alsadara"; Filename: "{uninstallexe}"; Comment: "إزالة التطبيق من النظام"

; أيقونة سطح المكتب
Name: "{autodesktop}\Alsadara FTTH"; Filename: "{app}\Alsadara.exe"; Tasks: desktopicon; Comment: "نظام إدارة شبكات FTTH الصدارة"

; أيقونة شريط الإطلاق السريع
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\Alsadara"; Filename: "{app}\Alsadara.exe"; Tasks: quicklaunchicon; Comment: "نظام إدارة شبكات FTTH الصدارة"

[Registry]
; ربط أنواع الملفات (اختياري)
Root: HKCR; Subkey: ".alsadara"; ValueType: string; ValueName: ""; ValueData: "AlsadaraDataFile"; Flags: uninsdeletevalue; Tasks: associatefiles
Root: HKCR; Subkey: "AlsadaraDataFile"; ValueType: string; ValueName: ""; ValueData: "Alsadara Data File"; Flags: uninsdeletekey; Tasks: associatefiles
Root: HKCR; Subkey: "AlsadaraDataFile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\Alsadara.exe,0"; Tasks: associatefiles
Root: HKCR; Subkey: "AlsadaraDataFile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Alsadara.exe"" ""%1"""; Tasks: associatefiles

; تشغيل تلقائي (اختياري)
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Alsadara"; ValueData: """{app}\Alsadara.exe"""; Tasks: startuprun

; معلومات التطبيق في النظام
Root: HKLM; Subkey: "SOFTWARE\Alsadara Technologies\Alsadara"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Alsadara Technologies\Alsadara"; ValueType: string; ValueName: "Version"; ValueData: "1.2.8"
Root: HKLM; Subkey: "SOFTWARE\Alsadara Technologies\Alsadara"; ValueType: string; ValueName: "InstallDate"; ValueData: "{code:GetCurrentDateTime}"

[Run]
; تشغيل التطبيق بعد التثبيت
Filename: "{app}\Alsadara.exe"; Description: "{cm:LaunchProgram,Alsadara FTTH}"; Flags: nowait postinstall skipifsilent unchecked

; فتح مجلد الوثائق (اختياري)  
Filename: "{app}\Documentation"; Description: "عرض وثائق التطبيق والميزات الجديدة"; Flags: postinstall skipifsilent shellexec unchecked

[UninstallDelete]
; حذف الملفات المؤقتة والبيانات المحلية عند الإلغاء
Type: filesandordirs; Name: "{localappdata}\Alsadara"
Type: filesandordirs; Name: "{userappdata}\Alsadara"

[Code]
// دالات مساعدة للتثبيت

function GetCurrentDateTime(Param: String): String;
begin
  Result := GetDateTimeString('dd/mm/yyyy hh:nn:ss', #0, #0);
end;

// فحص إذا كان التطبيق قيد التشغيل
function IsAppRunning(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('tasklist', '/FI "IMAGENAME eq alsadara.exe" /NH', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := (ResultCode = 0);
end;

// رسالة الترحيب المخصصة
function InitializeSetup(): Boolean;
begin
  Result := True;
  MsgBox('مرحباً بك في برنامج تثبيت Alsadara v1.2.8' + #13#10 + #13#10 +
         'نظام متكامل لإدارة شبكات FTTH' + #13#10 + #13#10 +
         'التحديثات في هذا الإصدار:' + #13#10 +
         '• تحسينات عامة في الأداء' + #13#10 +
         '• إصلاح مشاكل وأخطاء' + #13#10 +
         '• تحسينات في واجهة المستخدم', 
         mbInformation, MB_OK);
end;

// رسالة انتهاء التثبيت
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    MsgBox('تم تثبيت Alsadara v1.2.8 بنجاح!' + #13#10 + #13#10 +
           'يمكنك الآن تشغيل التطبيق من:' + #13#10 +
           '• قائمة ابدأ' + #13#10 +
           '• سطح المكتب (إذا اخترت إنشاء اختصار)', 
           mbInformation, MB_OK);
  end;
end;

// تأكيد إلغاء التثبيت
function InitializeUninstall(): Boolean;
begin
  Result := MsgBox('هل أنت متأكد من إلغاء تثبيت Alsadara؟' + #13#10 + #13#10 +
                   'سيتم حذف جميع ملفات التطبيق.', 
                   mbConfirmation, MB_YESNO) = IDYES;
end;
