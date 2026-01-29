# ========================================
# Sadara Platform - Windows Deployment Script
# نشر API على VPS من Windows
# ========================================

Write-Host "🚀 Starting Sadara Platform Deployment..." -ForegroundColor Cyan

# متغيرات
$VPS_IP = "72.61.183.61"
$VPS_USER = "root"
$PROJECT_PATH = "C:\SadaraPlatform\src\Backend\API\Sadara.API"
$PUBLISH_PATH = "C:\SadaraPlatform\publish"
$REMOTE_PATH = "/var/www/sadara-api"

# 1. تنظيف مجلد النشر
Write-Host "🧹 Cleaning publish folder..." -ForegroundColor Yellow
if (Test-Path $PUBLISH_PATH) {
    Remove-Item -Path $PUBLISH_PATH -Recurse -Force
}

# 2. نشر المشروع
Write-Host "📦 Publishing project..." -ForegroundColor Yellow
Set-Location $PROJECT_PATH
dotnet publish -c Release -o $PUBLISH_PATH --self-contained false

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Publish failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Project published successfully!" -ForegroundColor Green

# 3. ضغط الملفات
Write-Host "📁 Compressing files..." -ForegroundColor Yellow
$zipPath = "C:\SadaraPlatform\sadara-api.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path "$PUBLISH_PATH\*" -DestinationPath $zipPath

Write-Host "✅ Files compressed!" -ForegroundColor Green

# 4. تعليمات الرفع
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "📋 خطوات الرفع على VPS:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1️⃣ رفع الملف المضغوط إلى VPS:" -ForegroundColor White
Write-Host "   scp C:\SadaraPlatform\sadara-api.zip root@72.61.183.61:/tmp/" -ForegroundColor Gray
Write-Host ""
Write-Host "2️⃣ الاتصال بـ VPS:" -ForegroundColor White
Write-Host "   ssh root@72.61.183.61" -ForegroundColor Gray
Write-Host ""
Write-Host "3️⃣ فك الضغط ونقل الملفات:" -ForegroundColor White
Write-Host "   sudo rm -rf /var/www/sadara-api/*" -ForegroundColor Gray
Write-Host "   sudo unzip /tmp/sadara-api.zip -d /var/www/sadara-api/" -ForegroundColor Gray
Write-Host "   sudo chown -R www-data:www-data /var/www/sadara-api" -ForegroundColor Gray
Write-Host ""
Write-Host "4️⃣ إعادة تشغيل الخدمة:" -ForegroundColor White
Write-Host "   sudo systemctl restart sadara-api" -ForegroundColor Gray
Write-Host "   sudo systemctl status sadara-api" -ForegroundColor Gray
Write-Host ""
Write-Host "5️⃣ اختبار API:" -ForegroundColor White
Write-Host "   curl http://72.61.183.61/health" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🔗 روابط مهمة:" -ForegroundColor Cyan
Write-Host "   API: http://72.61.183.61" -ForegroundColor White
Write-Host "   Swagger: http://72.61.183.61/swagger" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
