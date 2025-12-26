# سكربت إنشاء إصدار جديد ورفعه إلى GitHub
# يقوم بتحديث الإصدار وإنشاء tag ورفعه

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,  # مثال: 1.2.9
    
    [Parameter(Mandatory=$false)]
    [string]$Message = "إصدار جديد"
)

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   إنشاء إصدار جديد: v$Version" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# 1. التحقق من وجود Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git غير مثبت!" -ForegroundColor Red
    exit 1
}

# 2. التحقق من أن المستودع نظيف
$status = git status --porcelain
if ($status) {
    Write-Host "⚠️ يوجد تغييرات غير محفوظة:" -ForegroundColor Yellow
    Write-Host $status
    $confirm = Read-Host "هل تريد حفظ التغييرات أولاً؟ (y/n)"
    if ($confirm -eq "y") {
        git add .
        git commit -m "تحديث للإصدار v$Version"
    }
}

# 3. تحديث الإصدار في pubspec.yaml
Write-Host "📝 تحديث pubspec.yaml..." -ForegroundColor Yellow
$pubspecPath = "pubspec.yaml"
$content = Get-Content $pubspecPath -Raw
$pattern = 'version:\s*\d+\.\d+\.\d+\+\d+'
$newVersion = "version: $Version+$([int]($Version.Split('.')[0])*100 + [int]($Version.Split('.')[1])*10 + [int]($Version.Split('.')[2]))"
$content = $content -replace $pattern, $newVersion
Set-Content $pubspecPath $content
Write-Host "✅ تم تحديث الإصدار إلى $Version" -ForegroundColor Green

# 4. تحديث auto_update_service.dart (GitHub owner/repo)
Write-Host ""
Write-Host "⚠️ تأكد من تحديث القيم في lib/services/auto_update_service.dart:" -ForegroundColor Yellow
Write-Host "   - githubOwner = 'YOUR_GITHUB_USERNAME'" -ForegroundColor Gray
Write-Host "   - githubRepo = 'alsadara'" -ForegroundColor Gray
Write-Host ""

# 5. حفظ التغييرات
Write-Host "💾 حفظ التغييرات..." -ForegroundColor Yellow
git add pubspec.yaml
git commit -m "🔖 إصدار v$Version - $Message"

# 6. إنشاء Tag
Write-Host "🏷️ إنشاء Tag..." -ForegroundColor Yellow
git tag -a "v$Version" -m "$Message"

# 7. رفع التغييرات و Tag
Write-Host "🚀 رفع التغييرات إلى GitHub..." -ForegroundColor Yellow
git push origin main
git push origin "v$Version"

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "   ✅ تم إنشاء الإصدار v$Version بنجاح!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "🔗 GitHub Actions سيقوم ببناء التطبيق تلقائياً." -ForegroundColor Cyan
Write-Host "   تابع التقدم في:" -ForegroundColor Gray
Write-Host "   https://github.com/YOUR_USERNAME/alsadara/actions" -ForegroundColor Gray
Write-Host ""
