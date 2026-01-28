# سكربت إعداد بيئة التطوير - Setup Development Environment

Write-Host "🔧 إعداد بيئة التطوير لمنصة الصدارة" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Gray

# 1. التحقق من .NET
Write-Host "`n📌 التحقق من .NET..." -ForegroundColor Yellow
$dotnetVersion = dotnet --version 2>$null
if ($dotnetVersion) {
    Write-Host "✅ .NET مثبت: $dotnetVersion" -ForegroundColor Green
} else {
    Write-Host "❌ .NET غير مثبت! يرجى تثبيته من: https://dot.net" -ForegroundColor Red
}

# 2. التحقق من Flutter
Write-Host "`n📌 التحقق من Flutter..." -ForegroundColor Yellow
$flutterVersion = flutter --version 2>$null | Select-Object -First 1
if ($flutterVersion) {
    Write-Host "✅ Flutter مثبت" -ForegroundColor Green
} else {
    Write-Host "❌ Flutter غير مثبت! يرجى تثبيته من: https://flutter.dev" -ForegroundColor Red
}

# 3. التحقق من PostgreSQL
Write-Host "`n📌 التحقق من PostgreSQL..." -ForegroundColor Yellow
$pgVersion = psql --version 2>$null
if ($pgVersion) {
    Write-Host "✅ PostgreSQL مثبت: $pgVersion" -ForegroundColor Green
} else {
    Write-Host "⚠️ PostgreSQL غير مثبت (اختياري للتطوير المحلي)" -ForegroundColor Yellow
}

# 4. استعادة حزم .NET
Write-Host "`n📦 استعادة حزم .NET..." -ForegroundColor Yellow
$backendPath = "$PSScriptRoot\..\src\Backend"
if (Test-Path $backendPath) {
    Set-Location $backendPath
    dotnet restore
    Write-Host "✅ تم استعادة الحزم" -ForegroundColor Green
}

# 5. استعادة حزم Flutter
Write-Host "`n📦 استعادة حزم Flutter..." -ForegroundColor Yellow
$flutterPath = "$PSScriptRoot\..\src\Apps\CompanyDesktop\alsadara-ftth"
if (Test-Path $flutterPath) {
    Set-Location $flutterPath
    flutter pub get
    Write-Host "✅ تم استعادة الحزم" -ForegroundColor Green
}

# 6. التحقق من ملفات الأسرار
Write-Host "`n🔐 التحقق من ملفات الأسرار..." -ForegroundColor Yellow
$secretsPath = "$PSScriptRoot\..\secrets"
$firebaseFile = "$secretsPath\firebase-service-account.json"

if (Test-Path $firebaseFile) {
    Write-Host "✅ ملف Firebase موجود" -ForegroundColor Green
} else {
    Write-Host "⚠️ ملف Firebase غير موجود!" -ForegroundColor Yellow
    Write-Host "   يرجى وضعه في: $firebaseFile" -ForegroundColor Gray
}

Write-Host "`n" + "=" * 50 -ForegroundColor Gray
Write-Host "✅ انتهى الإعداد!" -ForegroundColor Cyan
Write-Host "`n📋 لتشغيل API:" -ForegroundColor White
Write-Host "   cd C:\SadaraPlatform\src\Backend\API\Sadara.API" -ForegroundColor Gray
Write-Host "   dotnet run" -ForegroundColor Gray
Write-Host "`n📋 لتشغيل تطبيق الشركة:" -ForegroundColor White
Write-Host "   cd C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth" -ForegroundColor Gray
Write-Host "   flutter run -d windows" -ForegroundColor Gray
