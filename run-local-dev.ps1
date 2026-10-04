# run-local-dev.ps1 — تشغيل مكدّس الصدارة محلياً لاختبار تبويب «وكيل الساس»
# يضبط كل متغيّرات البيئة الصحيحة في كل مرة (يمنع خطأ CryptographicException بمفاتيح DataProtection).
# الاستخدام:  powershell -ExecutionPolicy Bypass -File C:\SadaraPlatform\run-local-dev.ps1
#
# يشغّل: (1) حاوية Postgres المحلية 5480  (2) خدمة الساس 8100  (3) باكند .NET 5000
# تطبيق Flutter يُشغَّل منفصلاً:  cd src\Apps\CompanyDesktop\alsadara-ftth ;  flutter run -d windows

$ErrorActionPreference = 'Stop'
$root = 'C:\SadaraPlatform'

# ── متغيّرات البيئة الحاسمة (نفس القيم للخدمة والباكند) ──────────────────────────
$secret   = 'sadara-sas-dev-secret-2026'                         # سرّ داخلي مشترك (خدمة ⇄ باكند)
$keysPath = "$root\.dpkeys"                                      # ⚠️ مفاتيح فكّ تشفير كلمات مرور الساس — يجب أن يبقى ثابتاً
$connStr  = 'Host=127.0.0.1;Port=5480;Database=SadaraDB;Username=postgres;Password=devpass'

$env:ASPNETCORE_ENVIRONMENT              = 'Development'
$env:ASPNETCORE_URLS                     = 'http://localhost:5000'
$env:ConnectionStrings__DefaultConnection = $connStr
$env:SADARA_SAS_INTERNAL_SECRET          = $secret
$env:DataProtection__KeysPath            = $keysPath
# مفتاح API الداخلي (X-Api-Key) — يطابق ما يرسله التطبيق (AppSecrets)؛ بدونه كل نقاط
# X-Api-Key (الحسابات/الواتساب/الإحصاءات/الداخلية) ترفض بـ 401 "Invalid API Key".
$env:SADARA_INTERNAL_API_KEY             = 'sadara-internal-2024-secure-key'

if (-not (Test-Path $keysPath)) {
    Write-Warning "مجلد مفاتيح DataProtection غير موجود: $keysPath — قد تفشل كلمات مرور الساس المخزّنة."
}

# ── (1) Postgres المحلي (نسخة إنتاج) على 5480 ───────────────────────────────────
$pg = (docker ps --filter 'name=sadara-postgres-dev' --format '{{.Names}}')
if (-not $pg) {
    Write-Host '[1/3] بدء حاوية Postgres (sadara-postgres-dev)...' -ForegroundColor Cyan
    docker start sadara-postgres-dev | Out-Null
} else {
    Write-Host '[1/3] Postgres يعمل بالفعل (5480).' -ForegroundColor Green
}

# ── (2) خدمة الساس (sidecar) 8100 في نافذة منفصلة ───────────────────────────────
Write-Host '[2/3] بدء خدمة الساس على 127.0.0.1:8100 ...' -ForegroundColor Cyan
$svc = "$root\modules\sas-agent\service"
Start-Process powershell -ArgumentList @(
    '-NoExit','-Command',
    "`$env:SADARA_SAS_INTERNAL_SECRET='$secret'; Set-Location '$svc'; .\.venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 8100 --log-level info"
)

# ── (3) باكند .NET 5000 (في هذه النافذة) ────────────────────────────────────────
Write-Host '[3/3] بدء باكند .NET على http://localhost:5000 (KeysPath=' -NoNewline -ForegroundColor Cyan
Write-Host "$keysPath)" -ForegroundColor Cyan
Set-Location "$root\src\Backend\API\Sadara.API"
& '.\bin\Debug\net9.0\Sadara.API.exe'
