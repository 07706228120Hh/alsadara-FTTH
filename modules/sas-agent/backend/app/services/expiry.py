"""حساب قُرب انتهاء اشتراكات SAS من نص التاريخ المخزَّن محلياً.

صيغة SAS الموحّدة: 'YYYY-MM-DD HH:MM:SS' (قابلة للفرز نصياً = زمنياً). نحسب الفارق
بالتقويم (بـ .date()) كي لا تتأثر النتيجة بساعة اليوم ولا بفارق المنطقة الزمنية للخادم.
يُستخدَم في تنبيهات لوحة الوكيل (بطاقات الانتهاء) ومرشّح «قائمة التجديد».
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Iterable, Optional

from ..models import utcnow


def parse_expiry(expiration: str) -> Optional[datetime]:
    """يحوّل نص انتهاء SAS إلى datetime، أو None إن تعذّر التحليل."""
    s = (expiration or "").strip()
    if len(s) < 10:
        return None
    try:
        return datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        try:
            return datetime.strptime(s[:10], "%Y-%m-%d")
        except ValueError:
            return None


def days_left(expiration: str, today: Optional[date] = None) -> Optional[int]:
    """عدد الأيام حتى الانتهاء بفارق تقويمي (سالب = منتهٍ). None إن تعذّر التحليل."""
    dt = parse_expiry(expiration)
    if dt is None:
        return None
    today = today or utcnow().date()
    return (dt.date() - today).days


# نوافذ التصفية المسموحة لمرشّح «قرب الانتهاء» (قيمة الطلب → نطاق أيام)
WINDOWS = ("overdue", "today", "soon3", "soon7")


def in_window(dl: Optional[int], window: str) -> bool:
    """هل يقع days_left ضمن النافذة المطلوبة؟ (soon3/soon7 تراكميّتان تشملان اليوم)."""
    if dl is None:
        return False
    if window == "overdue":
        return dl < 0
    if window == "today":
        return dl == 0
    if window == "soon3":
        return 0 <= dl <= 3
    if window == "soon7":
        return 0 <= dl <= 7
    return True                     # قيمة غير معروفة → لا تصفية


def expiry_counts(expirations: Iterable[str]) -> dict:
    """عدّاد نوافذ الانتهاء من قائمة نصوص (تراكميّ: soon3 يشمل today، soon7 يشمل soon3)."""
    today = utcnow().date()
    c = {"overdue": 0, "today": 0, "soon3": 0, "soon7": 0}
    for e in expirations:
        dl = days_left(e, today)
        if dl is None:
            continue
        if dl < 0:
            c["overdue"] += 1
        elif dl == 0:
            c["today"] += 1
            c["soon3"] += 1
            c["soon7"] += 1
        elif dl <= 3:
            c["soon3"] += 1
            c["soon7"] += 1
        elif dl <= 7:
            c["soon7"] += 1
    return c
