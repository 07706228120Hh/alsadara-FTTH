# إنشاء اختصار على سطح المكتب
# تشغيل هذا الملف مرة واحدة لإنشاء اختصار

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "تطبيق السدارة.lnk"
$targetPath = Join-Path $PSScriptRoot "START_APP_AUTO.bat"
$iconPath = Join-Path $PSScriptRoot "assets\app_icon.ico"

# إنشاء كائن WScript Shell
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($shortcutPath)

# تعيين خصائص الاختصار
$Shortcut.TargetPath = $targetPath
$Shortcut.WorkingDirectory = $PSScriptRoot
$Shortcut.Description = "تطبيق السدارة - FTTH Management"

# إضافة أيقونة إن وُجدت
if (Test-Path $iconPath) {
    $Shortcut.IconLocation = $iconPath
}

# حفظ الاختصار
$Shortcut.Save()

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ تم إنشاء الاختصار على سطح المكتب بنجاح!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📍 المسار: $shortcutPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "🚀 الآن يمكنك تشغيل التطبيق من سطح المكتب" -ForegroundColor Green
Write-Host ""
pause
