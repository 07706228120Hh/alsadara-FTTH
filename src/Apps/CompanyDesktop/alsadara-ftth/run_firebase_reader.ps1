# قراءة بيانات Firebase مباشرة
# Firebase Direct Data Reader

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Firebase Data Reader                     " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# نسخ ملف service account إلى المجلد الحالي
$sourceFile = "C:\Users\Msi-x88\Downloads\web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json"
$targetFile = ".\web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json"

if (Test-Path $sourceFile) {
    Write-Host "Copying service account file..." -ForegroundColor Yellow
    Copy-Item $sourceFile $targetFile -Force
    Write-Host "✓ File copied" -ForegroundColor Green
} else {
    Write-Host "⚠ Service account file not found at: $sourceFile" -ForegroundColor Red
    Write-Host "Please place the file in the current directory" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installing dependencies..." -ForegroundColor Yellow

# تثبيت npm packages
npm install

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Reading Firebase data..." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# تشغيل السكريبت
node read_firebase_data.js

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
