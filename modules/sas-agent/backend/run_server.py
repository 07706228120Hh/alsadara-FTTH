"""
نقطة دخول الخادم للحزمة المستقلّة (PyInstaller) — backend.exe.

يعمل بلا حاجة لتثبيت بايثون على جهاز المستخدم. يشغّل FastAPI عبر uvicorn
(بلا reloader) على 127.0.0.1:8000، بعد ضبط مجلد العمل على مجلد الإعدادات
(حيث يوجد .env وقاعدة البيانات) كي يعمل حتى عند تشغيله بنقر مباشر.
"""
import os
import sys


def _locate_base() -> str:
    """يحدّد مجلد الإعدادات: يبحث صعوداً عن أوّل مجلد فيه .env بدءاً من مجلد الـ exe/السكربت."""
    start = os.path.dirname(sys.executable) if getattr(sys, "frozen", False) \
        else os.path.dirname(os.path.abspath(__file__))
    cur = start
    for _ in range(6):
        if os.path.exists(os.path.join(cur, ".env")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return start  # احتياطي: بلا .env → إعدادات افتراضية (وضع المحاكاة)


if __name__ == "__main__":
    import multiprocessing
    multiprocessing.freeze_support()   # ضروري للحزم المجمّدة على ويندوز
    os.chdir(_locate_base())           # قبل استيراد app كي تُقرأ .env من المكان الصحيح

    import uvicorn
    from app.main import app

    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
