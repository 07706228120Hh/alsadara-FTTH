# ═══════════════════════════════════════════════════════════════════════════
# db_mirror_sync.ps1
# مزامنة نسخة محلية مطابقة من قاعدة الإنتاج sadara_db (على 72.61.183.61)
# إلى PostgreSQL محلي — نسخة مجمّدة (snapshot) كل تشغيل.
#
# ماذا يفعل:
#   1) pg_dump على السيرفر (قراءة فقط، لا يمسّ الإنتاج) بصيغة custom مضغوطة.
#   2) ينزّل ملف .dump إلى C:\SadaraBackups\db  (أرشيف تاريخي).
#   3) يحذف الملف المؤقت من السيرفر.
#   4) يستعيد النسخة في قاعدة محلية staging ثم يبدّلها ذرّياً باسم sadara_db_mirror
#      (يبقى الـ mirror القديم سليماً لو فشلت الاستعادة).
#   5) يحتفظ بآخر N نسخة فقط ويحذف الأقدم.
#
# المصادقة: SSH بمفاتيح (لا كلمة مرور) + PostgreSQL محلي عبر %APPDATA%\postgresql\pgpass.conf
#           (شغّل setup_db_mirror_pgpass.ps1 مرّة واحدة أولاً).
#
# الاستخدام اليدوي:
#   powershell -ExecutionPolicy Bypass -File scripts\db_mirror_sync.ps1
# ═══════════════════════════════════════════════════════════════════════════

[CmdletBinding()]
param(
    [string]$ServerHost   = "72.61.183.61",
    [string]$ServerUser   = "root",
    [string]$SourceDb     = "sadara_db",
    [string]$MirrorDb     = "sadara_db_mirror",
    [string]$BackupDir    = "C:\SadaraBackups\db",
    [string]$LogDir       = "C:\SadaraBackups\logs",
    [string]$PgBin        = "C:\Program Files\PostgreSQL\16\bin",
    [string]$LocalPgHost  = "127.0.0.1",
    [int]   $LocalPgPort  = 5432,
    [string]$LocalPgUser  = "postgres",
    [int]   $RetentionCount = 28   # 28 نسخة × كل 6 ساعات = 7 أيام أرشيف
)

$ErrorActionPreference = "Stop"
$timestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm"
$dumpName    = "${SourceDb}_$timestamp.dump"
$remoteDump  = "/tmp/$dumpName"
$localDump   = Join-Path $BackupDir $dumpName
$stagingDb   = "${MirrorDb}_staging"
$psql        = Join-Path $PgBin "psql.exe"
$pgRestore   = Join-Path $PgBin "pg_restore.exe"

# ── أدوات مساعدة ──────────────────────────────────────────────────────────
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir    -Force | Out-Null
$logFile = Join-Path $LogDir "db_mirror_$timestamp.log"

function Log($msg, $color = "Gray") {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Invoke-LocalPsql($db, $sql) {
    & $psql -h $LocalPgHost -p $LocalPgPort -U $LocalPgUser -d $db -v ON_ERROR_STOP=1 -qtAc $sql
    if ($LASTEXITCODE -ne 0) { throw "psql فشل على القاعدة '$db' عند تنفيذ: $sql" }
}

Log "🔄 بدء مزامنة النسخة المحلية من $SourceDb" "Cyan"

# ── تحقق من المتطلبات ─────────────────────────────────────────────────────
if (-not (Test-Path $psql))      { throw "psql غير موجود في $PgBin" }
if (-not (Test-Path $pgRestore)) { throw "pg_restore غير موجود في $PgBin" }
$pgpass = Join-Path $env:APPDATA "postgresql\pgpass.conf"
if (-not (Test-Path $pgpass)) {
    throw "ملف pgpass غير موجود ($pgpass). شغّل أولاً: scripts\setup_db_mirror_pgpass.ps1"
}

try {
    # ── 1) pg_dump على السيرفر (قراءة فقط) ────────────────────────────────
    Log "📤 [1/5] تنفيذ pg_dump على السيرفر ($SourceDb)..." "Yellow"
    $dumpCmd = "sudo -u postgres pg_dump -Fc -Z6 -d $SourceDb -f $remoteDump && ls -l $remoteDump"
    $dumpOut = ssh -o ConnectTimeout=20 -o BatchMode=yes "$ServerUser@$ServerHost" $dumpCmd
    if ($LASTEXITCODE -ne 0) { throw "pg_dump على السيرفر فشل" }
    Log "   $dumpOut"

    # ── 2) تنزيل الملف ────────────────────────────────────────────────────
    Log "📥 [2/5] تنزيل $dumpName إلى $BackupDir ..." "Yellow"
    scp -o ConnectTimeout=20 -o BatchMode=yes "${ServerUser}@${ServerHost}:$remoteDump" $localDump
    if ($LASTEXITCODE -ne 0) { throw "scp (تنزيل النسخة) فشل" }
    $sizeMB = [math]::Round((Get-Item $localDump).Length / 1MB, 2)
    if ($sizeMB -le 0) { throw "الملف المنزَّل فارغ!" }
    Log "   ✅ نُزّل بنجاح ($sizeMB MB)" "Green"

    # ── 3) حذف الملف المؤقت من السيرفر ────────────────────────────────────
    ssh -o ConnectTimeout=20 -o BatchMode=yes "$ServerUser@$ServerHost" "rm -f $remoteDump" | Out-Null
    Log "🧹 [3/5] حُذف الملف المؤقت من السيرفر"

    # ── 4) الاستعادة في قاعدة staging ثم التبديل الذرّي ───────────────────
    Log "♻️  [4/5] استعادة في $stagingDb ..." "Yellow"
    # أنهِ أي اتصالات على staging ثم أعِد إنشاءها نظيفة
    $killStaging = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$stagingDb' AND pid<>pg_backend_pid();"
    Invoke-LocalPsql "postgres" $killStaging | Out-Null
    Invoke-LocalPsql "postgres" "DROP DATABASE IF EXISTS `"$stagingDb`";" | Out-Null
    Invoke-LocalPsql "postgres" "CREATE DATABASE `"$stagingDb`";" | Out-Null

    & $pgRestore -h $LocalPgHost -p $LocalPgPort -U $LocalPgUser `
                 --no-owner --no-privileges --exit-on-error `
                 -d $stagingDb $localDump
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore فشل — الـ mirror القديم لم يُمَس (ما زال سليماً)"
    }
    Log "   ✅ الاستعادة في staging نجحت" "Green"

    # التبديل الذرّي: أنهِ اتصالات الـ mirror، احذفه، أعد تسمية staging
    Log "🔀 تبديل $stagingDb → $MirrorDb ..." "Yellow"
    $killMirror = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$MirrorDb' AND pid<>pg_backend_pid();"
    Invoke-LocalPsql "postgres" $killMirror | Out-Null
    Invoke-LocalPsql "postgres" "DROP DATABASE IF EXISTS `"$MirrorDb`";" | Out-Null
    Invoke-LocalPsql "postgres" "ALTER DATABASE `"$stagingDb`" RENAME TO `"$MirrorDb`";" | Out-Null
    Log "   ✅ الـ mirror المحلي محدَّث: $MirrorDb" "Green"

    # ── 5) الاحتفاظ بآخر N نسخة فقط ───────────────────────────────────────
    $old = Get-ChildItem -Path $BackupDir -Filter "${SourceDb}_*.dump" |
           Sort-Object LastWriteTime -Descending | Select-Object -Skip $RetentionCount
    foreach ($f in $old) {
        Remove-Item $f.FullName -Force
        Log "🗑️  حُذفت نسخة قديمة: $($f.Name)"
    }
    Log "📦 [5/5] الأرشيف: يُحتفظ بآخر $RetentionCount نسخة" "Cyan"

    Log "✅ اكتملت المزامنة بنجاح." "Green"
    exit 0
}
catch {
    Log "❌ فشلت المزامنة: $($_.Exception.Message)" "Red"
    # حاول تنظيف staging المعطّل و/أو الملف المؤقت على السيرفر
    try { Invoke-LocalPsql "postgres" "DROP DATABASE IF EXISTS `"$stagingDb`";" | Out-Null } catch {}
    try { ssh -o ConnectTimeout=10 -o BatchMode=yes "$ServerUser@$ServerHost" "rm -f $remoteDump" | Out-Null } catch {}
    exit 1
}
