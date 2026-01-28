# سكربت النشر - Deploy Script
# يستخدم لنشر API على الخادم

param(
    [string]$Server = "72.61.183.61",
    [string]$User = "root",
    [string]$RemotePath = "/var/www/sadara-api"
)

Write-Host "🚀 بدء عملية النشر..." -ForegroundColor Cyan

# 1. بناء المشروع
Write-Host "📦 جاري بناء المشروع..." -ForegroundColor Yellow
$apiPath = "$PSScriptRoot\..\src\Backend\API\Sadara.API"
Set-Location $apiPath
dotnet publish -c Release -o ./publish

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ فشل البناء!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ تم البناء بنجاح" -ForegroundColor Green

# 2. ضغط الملفات
Write-Host "📁 جاري ضغط الملفات..." -ForegroundColor Yellow
$publishPath = "$apiPath\publish"
$zipPath = "$apiPath\publish.zip"

if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path "$publishPath\*" -DestinationPath $zipPath

Write-Host "✅ تم الضغط" -ForegroundColor Green

# 3. رفع للخادم
Write-Host "📤 جاري الرفع للخادم..." -ForegroundColor Yellow
Write-Host "يرجى تنفيذ الأمر التالي يدوياً:" -ForegroundColor Magenta
Write-Host "scp $zipPath ${User}@${Server}:$RemotePath/" -ForegroundColor White

Write-Host "`n📋 ثم على الخادم نفذ:" -ForegroundColor Magenta
Write-Host @"
cd $RemotePath
unzip -o publish.zip
sudo systemctl restart sadara-api
"@ -ForegroundColor White

Write-Host "`n✅ انتهى السكربت!" -ForegroundColor Green
