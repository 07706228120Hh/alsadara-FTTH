# ═══════════════════════════════════════════════════════════════════════════
# reset_local_postgres_password.ps1
# إعادة تعيين كلمة مرور مستخدم postgres على PostgreSQL *المحلي فقط* (جهاز التطوير).
# لا علاقة له بقاعدة الإنتاج على السيرفر.
#
# يجب تشغيله في PowerShell كـ Administrator:
#   powershell -ExecutionPolicy Bypass -File scripts\reset_local_postgres_password.ps1
#
# الآلية الآمنة:
#   1) نسخة احتياطية من pg_hba.conf.
#   2) تحويل المصادقة المحلية مؤقتاً إلى trust (بدون كلمة مرور).
#   3) إعادة تشغيل الخدمة → ضبط كلمة المرور الجديدة عبر ALTER USER.
#   4) استرجاع pg_hba.conf الأصلي (إعادة الحماية) في كل الأحوال (finally).
#   5) إعادة تشغيل الخدمة + كتابة pgpass + اختبار الاتصال.
# ═══════════════════════════════════════════════════════════════════════════

param(
    [string]$PgBin      = "C:\Program Files\PostgreSQL\16\bin",
    [string]$PgData     = "C:\Program Files\PostgreSQL\16\data",
    [string]$Service    = "postgresql-x64-16",
    [string]$PgUser     = "postgres",
    [int]   $PgPort     = 5432
)

$ErrorActionPreference = "Stop"

# ── تحقّق من صلاحية Administrator ──────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ شغّل هذا السكربت في PowerShell كـ Administrator." -ForegroundColor Red
    Write-Host "   (اضغط بزر الفأرة الأيمن على PowerShell → Run as administrator)" -ForegroundColor Gray
    exit 1
}

$psql = Join-Path $PgBin "psql.exe"
$hba  = Join-Path $PgData "pg_hba.conf"
if (-not (Test-Path $psql)) { Write-Host "❌ psql غير موجود: $psql" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $hba))  { Write-Host "❌ pg_hba.conf غير موجود: $hba" -ForegroundColor Red; exit 1 }

# ── اختيار كلمة المرور الجديدة (مرّتين للتأكيد) ─────────────────────────────
Write-Host "🔐 إعادة تعيين كلمة مرور '$PgUser' المحلي" -ForegroundColor Cyan
Write-Host "   اختر كلمة مرور جديدة (تجنّب علامة الاقتباس الفردية ')" -ForegroundColor Gray
$s1 = Read-Host -Prompt "كلمة المرور الجديدة" -AsSecureString
$s2 = Read-Host -Prompt "أعد كتابتها للتأكيد"  -AsSecureString
$p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
$p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
if ([string]::IsNullOrWhiteSpace($p1)) { Write-Host "❌ كلمة المرور فارغة." -ForegroundColor Red; exit 1 }
if ($p1 -ne $p2) { Write-Host "❌ الكلمتان غير متطابقتين." -ForegroundColor Red; exit 1 }

$stamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$backup  = "$hba.bak.$stamp"

try {
    # ── 1) نسخة احتياطية ───────────────────────────────────────────────────
    Copy-Item $hba $backup -Force
    Write-Host "🧾 نسخة احتياطية من pg_hba.conf → $backup" -ForegroundColor Gray

    # ── 2) تحويل المصادقة مؤقتاً إلى trust ─────────────────────────────────
    $orig = Get-Content $hba
    $temp = $orig | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -notmatch '^\s*(local|host)\s') { $_ }
        else { $_ -replace '(scram-sha-256|md5|password)\s*$', 'trust' }
    }
    Set-Content -Path $hba -Value $temp -Encoding ascii
    Write-Host "🔓 تحويل المصادقة المحلية مؤقتاً إلى trust" -ForegroundColor Yellow

    # ── 3) إعادة التشغيل + ضبط كلمة المرور ─────────────────────────────────
    Restart-Service $Service -Force
    Start-Sleep -Seconds 3
    # :'pw'  يقوم psql بتنصيصها كسلسلة نصية بأمان (يتعامل مع الرموز الخاصة)
    & $psql -h 127.0.0.1 -p $PgPort -U $PgUser -d postgres -w `
            -v pw="$p1" -c "ALTER USER $PgUser WITH PASSWORD :'pw';"
    if ($LASTEXITCODE -ne 0) { throw "فشل ضبط كلمة المرور عبر ALTER USER" }
    Write-Host "✅ ضُبطت كلمة المرور الجديدة" -ForegroundColor Green
}
finally {
    # ── 4) استرجاع pg_hba.conf الأصلي (إعادة الحماية) دائماً ────────────────
    if (Test-Path $backup) {
        Copy-Item $backup $hba -Force
        Restart-Service $Service -Force
        Start-Sleep -Seconds 3
        Write-Host "🔒 أُعيدت حماية pg_hba.conf الأصلية وأُعيد تشغيل الخدمة" -ForegroundColor Green
    }
}

# ── 5) كتابة pgpass + اختبار الاتصال ───────────────────────────────────────
$pgDir  = Join-Path $env:APPDATA "postgresql"
$pgpass = Join-Path $pgDir "pgpass.conf"
New-Item -ItemType Directory -Path $pgDir -Force | Out-Null
Set-Content -Path $pgpass -Encoding ascii -Value @(
    "127.0.0.1:${PgPort}:*:${PgUser}:${p1}",
    "localhost:${PgPort}:*:${PgUser}:${p1}"
)
try { icacls $pgpass /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null } catch {}

Write-Host "🔎 اختبار الاتصال بكلمة المرور الجديدة..." -ForegroundColor Cyan
& $psql -h 127.0.0.1 -p $PgPort -U $PgUser -d postgres -w -tAc "SELECT 'اتصال ناجح: ' || current_user;"
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ تم! كلمة المرور جاهزة ومحفوظة في pgpass." -ForegroundColor Green
    Write-Host "   التالي: powershell -ExecutionPolicy Bypass -File scripts\db_mirror_sync.ps1" -ForegroundColor Gray
} else {
    Write-Host "❌ فشل الاختبار — راجع المخرجات أعلاه." -ForegroundColor Red
    exit 1
}
