# سكربت النسخ الاحتياطي - Backup Script

param(
    [string]$BackupPath = "C:\SadaraBackups"
)

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$backupName = "SadaraPlatform_$timestamp"
$backupFullPath = "$BackupPath\$backupName"

Write-Host "🔄 بدء النسخ الاحتياطي..." -ForegroundColor Cyan

# إنشاء مجلد النسخ الاحتياطي
if (!(Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

# نسخ المشروع (بدون المجلدات الكبيرة)
Write-Host "📁 جاري النسخ..." -ForegroundColor Yellow

$excludeDirs = @(
    "node_modules",
    "build",
    ".dart_tool",
    "bin",
    "obj",
    "publish",
    "Distribution_v1.2.8",
    "Distribution_v1.3.0"
)

$excludeString = ($excludeDirs | ForEach-Object { "/XD $_" }) -join " "

$robocopyCmd = "robocopy `"C:\SadaraPlatform`" `"$backupFullPath`" /E $excludeString /NFL /NDL /NJH"
Invoke-Expression $robocopyCmd

# ضغط النسخة
Write-Host "📦 جاري الضغط..." -ForegroundColor Yellow
$zipPath = "$backupFullPath.zip"
Compress-Archive -Path $backupFullPath -DestinationPath $zipPath -Force

# حذف المجلد غير المضغوط
Remove-Item -Path $backupFullPath -Recurse -Force

# حذف النسخ القديمة (الاحتفاظ بآخر 5)
$oldBackups = Get-ChildItem -Path $BackupPath -Filter "*.zip" | 
              Sort-Object CreationTime -Descending | 
              Select-Object -Skip 5
foreach ($old in $oldBackups) {
    Remove-Item $old.FullName -Force
    Write-Host "🗑️ حذف نسخة قديمة: $($old.Name)" -ForegroundColor Gray
}

Write-Host "`n✅ تم النسخ الاحتياطي: $zipPath" -ForegroundColor Green
Write-Host "📊 الحجم: $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB" -ForegroundColor Cyan
