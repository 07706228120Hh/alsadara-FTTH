# ═══════════════════════════════════════════════════════════════════════════
# node_backup.ps1
# النسخ الاحتياطي المحلي لعقدة شركة (المعمارية الموزّعة).
# بيانات الشركة تعيش محلياً فقط (ليست على المركز/هوستنكر) — لذا هذا النسخ حرج.
#
# ماذا يفعل:
#   1) pg_dump محلي (صيغة custom مضغوطة) لقاعدة الشركة.
#   2) يحفظ في مجلد أرشيف محلي + (اختياري) نسخة خارج الموقع (off-site).
#   3) يتحقق من سلامة النسخة، ويحتفظ بآخر N نسخة فقط.
#
# المصادقة: PostgreSQL محلي عبر %APPDATA%\postgresql\pgpass.conf
#           (شغّل setup_db_mirror_pgpass.ps1 مرّة واحدة أولاً).
#
# الاستخدام:
#   powershell -ExecutionPolicy Bypass -File scripts\node_backup.ps1 -NodeDb "<db>"
# للجدولة: أنشئ مهمة Task Scheduler مماثلة لـ register_db_mirror_task.ps1.
# ═══════════════════════════════════════════════════════════════════════════

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NodeDb,                                   # اسم قاعدة الشركة المحلية
    [string]$BackupDir     = "C:\SadaraNodeBackups",
    [string]$LogDir        = "C:\SadaraNodeBackups\logs",
    [string]$OffsiteDir    = "",                       # اختياري: مجلد/محرك خارجي لنسخة إضافية
    [string]$PgBin         = "C:\Program Files\PostgreSQL\16\bin",
    [string]$PgHost        = "127.0.0.1",
    [int]   $PgPort        = 5432,
    [string]$PgUser        = "postgres",
    [int]   $RetentionCount = 30                       # يومي × 30 = شهر
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$dumpName  = "${NodeDb}_$timestamp.dump"
$pgDump    = Join-Path $PgBin "pg_dump.exe"
$psql      = Join-Path $PgBin "psql.exe"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir    -Force | Out-Null
$localDump = Join-Path $BackupDir $dumpName
$logFile   = Join-Path $LogDir "node_backup_$timestamp.log"

function Log($msg, $color = "Gray") {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

Log "🔄 بدء النسخ الاحتياطي لعقدة الشركة: $NodeDb" "Cyan"

if (-not (Test-Path $pgDump)) { throw "pg_dump غير موجود في $PgBin" }
$pgpass = Join-Path $env:APPDATA "postgresql\pgpass.conf"
if (-not (Test-Path $pgpass)) { throw "ملف pgpass غير موجود ($pgpass). شغّل setup_db_mirror_pgpass.ps1 أولاً" }

try {
    # ── تأكد أن القاعدة موجودة ──
    $exists = & $psql -h $PgHost -p $PgPort -U $PgUser -d postgres -w -tAc `
        "SELECT 1 FROM pg_database WHERE datname='$NodeDb';"
    if ("$exists".Trim() -ne "1") { throw "القاعدة '$NodeDb' غير موجودة على PostgreSQL المحلي" }

    # ── 1) pg_dump محلي ──
    Log "📦 [1/4] pg_dump للقاعدة $NodeDb ..." "Yellow"
    & $pgDump -h $PgHost -p $PgPort -U $PgUser -w -Fc -Z6 -d $NodeDb -f $localDump
    if ($LASTEXITCODE -ne 0) { throw "pg_dump فشل" }
    $sizeMB = [math]::Round((Get-Item $localDump).Length / 1MB, 2)
    if ($sizeMB -le 0) { throw "ملف النسخة فارغ!" }
    Log "   ✅ نسخة محلية ($sizeMB MB): $dumpName" "Green"

    # ── 2) التحقق من سلامة النسخة (فهرس pg_restore يُقرأ بنجاح) ──
    Log "🔎 [2/4] التحقق من سلامة النسخة ..." "Yellow"
    & (Join-Path $PgBin "pg_restore.exe") --list $localDump | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "النسخة تالفة — pg_restore --list فشل" }
    Log "   ✅ النسخة سليمة وقابلة للاستعادة" "Green"

    # ── 3) نسخة خارج الموقع (اختياري) — 3-2-1 backup rule ──
    if ($OffsiteDir -ne "") {
        New-Item -ItemType Directory -Path $OffsiteDir -Force | Out-Null
        Copy-Item $localDump (Join-Path $OffsiteDir $dumpName) -Force
        Log "🌐 [3/4] نُسخت نسخة خارج الموقع إلى $OffsiteDir" "Green"
    } else {
        Log "⏭️  [3/4] لا مجلد off-site (مرّر -OffsiteDir لتفعيله) — يُنصح به بشدّة" "Yellow"
    }

    # ── 4) الاحتفاظ بآخر N نسخة ──
    $old = Get-ChildItem -Path $BackupDir -Filter "${NodeDb}_*.dump" |
           Sort-Object LastWriteTime -Descending | Select-Object -Skip $RetentionCount
    foreach ($f in $old) { Remove-Item $f.FullName -Force; Log "🗑️  حُذفت نسخة قديمة: $($f.Name)" }
    Log "📚 [4/4] يُحتفظ بآخر $RetentionCount نسخة" "Cyan"

    Log "✅ اكتمل النسخ الاحتياطي للعقدة بنجاح." "Green"
    exit 0
}
catch {
    Log "❌ فشل النسخ الاحتياطي: $($_.Exception.Message)" "Red"
    if (Test-Path $localDump) { Remove-Item $localDump -Force -ErrorAction SilentlyContinue }
    exit 1
}
