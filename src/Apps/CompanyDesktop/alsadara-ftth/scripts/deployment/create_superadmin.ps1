# سكريبت إنشاء مستخدم Super Admin الأول في Firestore
# الاستخدام: .\create_superadmin.ps1

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   إنشاء Super Admin في Firebase    " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# معلومات المستخدم
$username = "superadmin"
$password = "password"  # كلمة المرور الافتراضية
$displayName = "المدير العام"

# تشفير كلمة المرور بـ SHA-256
Write-Host "🔐 تشفير كلمة المرور..." -ForegroundColor Yellow
$hasher = [System.Security.Cryptography.SHA256]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($password)
$hashBytes = $hasher.ComputeHash($bytes)
$hashedPassword = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

Write-Host "✅ كلمة المرور المشفرة: $hashedPassword" -ForegroundColor Green
Write-Host ""

# بيانات المستخدم بصيغة JSON
$userData = @"
{
  "username": "$username",
  "password": "$hashedPassword",
  "displayName": "$displayName",
  "organizationId": null,
  "role": "super_admin",
  "isActive": true,
  "createdAt": "SERVER_TIMESTAMP",
  "lastLogin": null
}
"@

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   معلومات تسجيل الدخول              " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "اسم المستخدم: $username" -ForegroundColor Green
Write-Host "كلمة المرور: $password" -ForegroundColor Green
Write-Host ""

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   خطوات إنشاء المستخدم في Firebase  " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. افتح Firebase Console:" -ForegroundColor Yellow
Write-Host "   https://console.firebase.google.com/" -ForegroundColor White
Write-Host ""
Write-Host "2. اختر مشروع: ramz-alsadara2025" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. اذهب إلى: Firestore Database" -ForegroundColor Yellow
Write-Host ""
Write-Host "4. أنشئ Collection اسمها: users" -ForegroundColor Yellow
Write-Host ""
Write-Host "5. اضغط 'Add Document'" -ForegroundColor Yellow
Write-Host ""
Write-Host "6. انسخ البيانات التالية:" -ForegroundColor Yellow
Write-Host ""
Write-Host $userData -ForegroundColor White
Write-Host ""
Write-Host "7. ملاحظة: استبدل 'SERVER_TIMESTAMP' بـ Timestamp حقيقي" -ForegroundColor Red
Write-Host "   (اختر Field Type: timestamp واضغط 'Use server time')" -ForegroundColor Red
Write-Host ""

# حفظ البيانات في ملف
$outputFile = "superadmin_data.json"
$userData | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host "✅ تم حفظ البيانات في: $outputFile" -ForegroundColor Green
Write-Host ""

# نسخ إلى Clipboard
$userData | Set-Clipboard
Write-Host "✅ تم نسخ البيانات إلى Clipboard" -ForegroundColor Green
Write-Host ""

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   اختبار تسجيل الدخول                " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "بعد إنشاء المستخدم، قم بتشغيل التطبيق:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  cd 'd:\flutter\app\ramz1 top\old_project'" -ForegroundColor White
Write-Host "  flutter run -d windows" -ForegroundColor White
Write-Host ""
Write-Host "ثم سجل الدخول باستخدام:" -ForegroundColor Yellow
Write-Host "  اسم المستخدم: $username" -ForegroundColor Green
Write-Host "  كلمة المرور: $password" -ForegroundColor Green
Write-Host ""

Write-Host "✨ انتهى! استمتع باستخدام نظام Firebase Multi-Tenant ✨" -ForegroundColor Cyan
Write-Host ""

# فتح Firebase Console
$openConsole = Read-Host "هل تريد فتح Firebase Console الآن؟ (y/n)"
if ($openConsole -eq "y" -or $openConsole -eq "Y") {
    Start-Process "https://console.firebase.google.com/project/ramz-alsadara2025/firestore"
}
