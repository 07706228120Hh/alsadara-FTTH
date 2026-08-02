# ═══════════════════════════════════════════════════════════════════════════
# setup_db_mirror_pgpass.ps1
# إعداد ملف pgpass لمرّة واحدة — يسمح لسكربت المزامنة بالاتصال بـ PostgreSQL
# المحلي بدون إدخال كلمة مرور في كل مرة (ودون أن تمرّ عبر المحادثة).
#
# شغّله مرّة واحدة في نافذة PowerShell عادية:
#   powershell -ExecutionPolicy Bypass -File scripts\setup_db_mirror_pgpass.ps1
#
# سيسألك عن كلمة مرور مستخدم postgres المحلي بشكل آمن (مخفية) ويكتبها في:
#   %APPDATA%\postgresql\pgpass.conf   (الموقع القياسي الذي يقرأه libpq)
# ═══════════════════════════════════════════════════════════════════════════

param(
    [string]$LocalPgUser = "postgres",
    [int]   $LocalPgPort = 5432,
    [string]$PgBin       = "C:\Program Files\PostgreSQL\16\bin"
)

$ErrorActionPreference = "Stop"

Write-Host "🔐 إعداد كلمة مرور PostgreSQL المحلي (postgres) لمزامنة النسخة المحلية" -ForegroundColor Cyan
Write-Host "   الموقع: %APPDATA%\postgresql\pgpass.conf" -ForegroundColor Gray
Write-Host ""

$secure = Read-Host -Prompt "أدخل كلمة مرور مستخدم '$LocalPgUser' المحلي" -AsSecureString
$bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrWhiteSpace($plain)) { Write-Host "❌ لم تُدخل كلمة مرور. أُلغي." -ForegroundColor Red; exit 1 }

$pgDir  = Join-Path $env:APPDATA "postgresql"
$pgpass = Join-Path $pgDir "pgpass.conf"
New-Item -ItemType Directory -Path $pgDir -Force | Out-Null

# صيغة pgpass:  hostname:port:database:username:password   (* = أي)
$lines = @(
    "127.0.0.1:${LocalPgPort}:*:${LocalPgUser}:${plain}",
    "localhost:${LocalPgPort}:*:${LocalPgUser}:${plain}"
)
Set-Content -Path $pgpass -Value $lines -Encoding ascii -NoNewline:$false

# صلاحيات مقيّدة: المستخدم الحالي فقط (libpq على Windows لا يشترط ذلك لكنه أأمن)
try {
    icacls $pgpass /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
} catch { Write-Host "⚠️ تعذّر ضبط ACL (غير حرج): $($_.Exception.Message)" -ForegroundColor Yellow }

$plain = $null  # مسح المتغيّر من الذاكرة

Write-Host "✅ كُتب pgpass.conf بنجاح." -ForegroundColor Green
Write-Host ""
Write-Host "🔎 اختبار الاتصال..." -ForegroundColor Cyan
$psql = Join-Path $PgBin "psql.exe"
& $psql -h 127.0.0.1 -p $LocalPgPort -U $LocalPgUser -d postgres -w -tAc "SELECT 'اتصال ناجح: ' || current_user;"
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ جاهز. يمكنك الآن تشغيل: scripts\db_mirror_sync.ps1" -ForegroundColor Green
} else {
    Write-Host "❌ فشل الاتصال — تأكّد أن كلمة المرور صحيحة وأعد تشغيل هذا السكربت." -ForegroundColor Red
    exit 1
}
