# سكريبت إنشاء Super Admin الأول
# يوضح كيفية إنشاء أول مدير نظام

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  إنشاء Super Admin للنظام" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "📝 البيانات المطلوبة:" -ForegroundColor Yellow
Write-Host ""

# اسم المستخدم
Write-Host "اسم المستخدم (username): " -NoNewline -ForegroundColor Green
$username = Read-Host

# كلمة المرور
Write-Host "كلمة المرور (password): " -NoNewline -ForegroundColor Green
$password = Read-Host -AsSecureString
$passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

# الاسم الكامل
Write-Host "الاسم الكامل (name): " -NoNewline -ForegroundColor Green
$name = Read-Host

# البريد الإلكتروني (اختياري)
Write-Host "البريد الإلكتروني (email) [اختياري]: " -NoNewline -ForegroundColor Green
$email = Read-Host

# رقم الهاتف (اختياري)
Write-Host "رقم الهاتف (phone) [اختياري]: " -NoNewline -ForegroundColor Green
$phone = Read-Host

Write-Host ""
Write-Host "⏳ جاري تشفير كلمة المرور..." -ForegroundColor Yellow

# تشفير كلمة المرور بـ SHA-256
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($passwordPlain)
$hashBytes = $sha256.ComputeHash($passwordBytes)
$passwordHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
$passwordHash = $passwordHash.ToLower()

Write-Host "✅ تم تشفير كلمة المرور" -ForegroundColor Green
Write-Host ""

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  📋 معلومات Super Admin" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Username: $username" -ForegroundColor White
Write-Host "Password Hash: $passwordHash" -ForegroundColor Gray
Write-Host "Name: $name" -ForegroundColor White
if ($email) { Write-Host "Email: $email" -ForegroundColor White }
if ($phone) { Write-Host "Phone: $phone" -ForegroundColor White }
Write-Host ""

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  🔥 خطوات الإضافة في Firebase" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. افتح Firebase Console" -ForegroundColor Yellow
Write-Host "2. اذهب إلى Firestore Database" -ForegroundColor Yellow
Write-Host "3. أنشئ Collection اسمها: " -NoNewline -ForegroundColor Yellow
Write-Host "super_admins" -ForegroundColor Magenta
Write-Host "4. أضف Document جديد" -ForegroundColor Yellow
Write-Host "5. انسخ والصق البيانات التالية:" -ForegroundColor Yellow
Write-Host ""

Write-Host "=====================================" -ForegroundColor Green
Write-Host "  📄 JSON للنسخ" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

$jsonData = @"
{
  "username": "$username",
  "passwordHash": "$passwordHash",
  "name": "$name",
"@

if ($email) {
    $jsonData += @"

  "email": "$email",
"@
}

if ($phone) {
    $jsonData += @"

  "phone": "$phone",
"@
}

$jsonData += @"

  "createdAt": [اختر Timestamp - Server Timestamp]
}
"@

Write-Host $jsonData -ForegroundColor White
Write-Host ""

# حفظ في ملف
$jsonData | Out-File -FilePath "superadmin_data.json" -Encoding UTF8
Write-Host "✅ تم حفظ البيانات في: " -NoNewline -ForegroundColor Green
Write-Host "superadmin_data.json" -ForegroundColor Cyan
Write-Host ""

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  🚀 تسجيل الدخول" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "بعد إضافة Super Admin في Firebase:" -ForegroundColor Yellow
Write-Host "1. شغل التطبيق: " -NoNewline -ForegroundColor Yellow
Write-Host "flutter run -d windows" -ForegroundColor Magenta
Write-Host "2. افتح صفحة Super Admin Login" -ForegroundColor Yellow
Write-Host "3. استخدم:" -ForegroundColor Yellow
Write-Host "   Username: " -NoNewline -ForegroundColor White
Write-Host "$username" -ForegroundColor Cyan
Write-Host "   Password: " -NoNewline -ForegroundColor White
Write-Host "$passwordPlain" -ForegroundColor Cyan
Write-Host ""

Write-Host "=====================================" -ForegroundColor Green
Write-Host "  ✅ تم بنجاح!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

# نسخ passwordHash إلى Clipboard
$passwordHash | Set-Clipboard
Write-Host "📋 تم نسخ Password Hash إلى Clipboard!" -ForegroundColor Magenta
Write-Host ""

Read-Host "اضغط Enter للإغلاق"
