"""نماذج وحدة العقارات — مكتفية ذاتياً (لا تُعدَّل الجداول المشتركة).

الربط بالاشتراكات عبر جدول ربط `PremisesSubscriber` يملكه هذا المودول، فلا نلمس
نموذج `Subscriber` المشترك. عقار واحد → عدّة اشتراكات (subscriber_id فريد = اشتراك
واحد لعقار واحد على الأكثر).
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlmodel import SQLModel, Field


def utcnow() -> datetime:
    """توقيت UTC واعٍ بالمنطقة الزمنية (نسخة محلية للمودول — بلا اعتماد على المشترك)."""
    return datetime.now(timezone.utc)


class Premises(SQLModel, table=True):
    """عقار/موقع فعلي (دار سكني أو محل). طبقة محلية بحتة — لا تُكتب إلى SAS."""
    id: Optional[int] = Field(default=None, primary_key=True)
    # الملكية والعزل: شركة الوكيل + اسم الوكيل المُنشئ
    company_id: Optional[int] = Field(default=None, index=True)
    agent_username: str = Field(default="", index=True)

    # ── العنوان الوطني المولَّد (من محرّك العنونة NAS-IQ) ──
    npn: str = Field(default="", index=True)          # رقم العقار الوطني (11 خانة)
    npn_display: str = ""                             # صيغة العرض GG-NNNN-NNNN-C
    iqpin: str = Field(default="", index=True)        # رمز الموقع (10 رموز، من الإحداثيات)
    iqpin_display: str = ""                           # صيغة العرض 3-3-4
    gov_code: int = 0                                 # كتلة تخصيص المحافظة
    qr_payload: str = ""                              # الحمولة المشفَّرة في QR (تُرسَم بالواجهة)

    # ── الموقع الجغرافي ──
    lat: Optional[float] = None
    lon: Optional[float] = None

    # ── العنوان الوصفي ──
    governorate: str = Field(default="", index=True)
    district: str = ""                               # المنطقة/الحي
    landmark: str = ""                               # أقرب نقطة دالة
    address_details: str = ""                        # تفاصيل إضافية (زقاق/دار…)

    # ── الاتصال ──
    phone: str = ""
    phone_norm: str = Field(default="", index=True)  # مطبَّع 9647XXXXXXXXX

    # ── التصنيف ──
    ownership: str = Field(default="")               # owned (ملك) | rent (إيجار)
    property_type: str = Field(default="")           # residential (دار سكني) | commercial (محل)
    owner_name: str = ""
    notes: str = ""

    # ── الوسائط ──
    photo_path: str = ""                             # مسار نسبي لصورة الدار (تُخزَّن ملفّاً)

    # ── تدقيق ──
    created_by: str = ""
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class PremisesSubscriber(SQLModel, table=True):
    """جدول ربط عقار↔اشتراك (يملكه المودول). subscriber_id فريد: اشتراك ينتمي
    لعقار واحد على الأكثر؛ العقار قد يملك عدّة روابط (عدّة اشتراكات)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    premises_id: int = Field(index=True, foreign_key="premises.id")
    subscriber_id: int = Field(index=True, unique=True)  # id في جدول Subscriber المشترك
    created_at: datetime = Field(default_factory=utcnow)
