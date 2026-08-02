# ═══════════════════════════════════════════════════════════════════════════
# register_db_mirror_task.ps1
# يسجّل مهمة مجدولة تشغّل db_mirror_sync.ps1 كل 6 ساعات تلقائياً.
#
# شغّله مرّة واحدة (يفضّل PowerShell كـ Administrator لضمان التسجيل):
#   powershell -ExecutionPolicy Bypass -File scripts\register_db_mirror_task.ps1
#
# لإلغاء المهمة لاحقاً:
#   schtasks /Delete /TN "SadaraDbMirrorSync" /F
# ═══════════════════════════════════════════════════════════════════════════

param(
    [string]$TaskName    = "SadaraDbMirrorSync",
    [int]   $IntervalHrs = 6,
    [string]$StartTime   = "00:15",
    [string]$ScriptPath  = "C:\SadaraPlatform\scripts\db_mirror_sync.ps1"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ScriptPath)) { Write-Host "❌ لم يُعثر على سكربت المزامنة: $ScriptPath" -ForegroundColor Red; exit 1 }

$action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

Write-Host "🗓️  تسجيل مهمة '$TaskName' — كل $IntervalHrs ساعات، بدءاً من $StartTime" -ForegroundColor Cyan

# /SC HOURLY /MO N = كل N ساعة  |  /RL LIMITED = صلاحيات عادية (لا يحتاج admin للتشغيل)
schtasks /Create /TN $TaskName /TR $action /SC HOURLY /MO $IntervalHrs /ST $StartTime /RL LIMITED /F

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ سُجّلت المهمة بنجاح." -ForegroundColor Green
    Write-Host ""
    Write-Host "   • تشغيل فوري للاختبار:  schtasks /Run /TN $TaskName" -ForegroundColor Gray
    Write-Host "   • عرض الحالة:            schtasks /Query /TN $TaskName /V /FO LIST" -ForegroundColor Gray
    Write-Host "   • إلغاء المهمة:          schtasks /Delete /TN $TaskName /F" -ForegroundColor Gray
} else {
    Write-Host "❌ فشل تسجيل المهمة (جرّب تشغيل PowerShell كـ Administrator)." -ForegroundColor Red
    exit 1
}
