# -*- coding: utf-8 -*-
"""
ترقيم تلقائي للمنازل داخل QGIS — نظام العنونة الوطنية NAS-IQ
============================================================
سكربت PyQGIS مستقل: يُخصّص لكل مبنى في طبقة نشِطة:
  • NPN  — رقم العقار الوطني (11 خانة: GG + 8 تسلسل + Luhn)
  • IQ-Pin — رمز شبكي (10 رموز، دقّة ~1م) من مركز المبنى

مطابق حرفياً لمحرّك المنصّة (backend/app/core/addressing.py) ولمواصفة
الدراسة (الملحق أ): encode(33.3389, 44.4009) == "8L8L865FMT".

كيف تُشغّله:
  1) افتح QGIS، حمّل طبقة المباني (مضلّعات أو نقاط) واجعلها الطبقة النشِطة.
  2) القائمة: Plugins → Python Console → Show Editor → افتح هذا الملف → Run.
  3) عدّل GOV_CODE (كود المحافظة) وSTART_SEQ قبل التشغيل إن لزم.
تُضاف الحقول: npn, npn_disp, iqpin, iqpin_disp — ثم صدّر الطبقة GeoJSON
وارفعها إلى المنصّة (مجموعة الشركة/الباك بون)، أو استعملها في Atlas للّوحات.
"""

# ═══════════════ الإعداد (عدّله قبل التشغيل) ═══════════════
GOV_CODE = 10          # كود المحافظة (بغداد=10، البصرة=61، نينوى=41، أربيل=44…)
START_SEQ = 0          # أول تسلسل (تابِع من آخر رقم استُخدم لتفادي التكرار)
LAYER_NAME = None      # None = الطبقة النشِطة؛ أو اسم الطبقة صراحةً

# ═══════════════ خوارزمية العنونة (لا تُعدّل) ═══════════════
ALPHABET = "23456789CFJKLMPT"
LON_MIN, LON_MAX = 38.0, 50.0
LAT_MIN, LAT_MAX = 28.0, 38.0
LEVELS = 10


def iqpin_encode(lat, lon):
    if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
        return ""  # خارج صندوق العراق
    lat0, lat1, lon0, lon1 = LAT_MIN, LAT_MAX, LON_MIN, LON_MAX
    out = []
    for _ in range(LEVELS):
        dlat = (lat1 - lat0) / 4.0
        dlon = (lon1 - lon0) / 4.0
        row = min(3, int((lat1 - lat) / dlat))
        col = min(3, int((lon - lon0) / dlon))
        out.append(ALPHABET[row * 4 + col])
        lat1 -= row * dlat
        lat0 = lat1 - dlat
        lon0 += col * dlon
        lon1 = lon0 + dlon
    return "".join(out)


def luhn_check_digit(num):
    total = 0
    for i, d in enumerate(reversed(num)):
        n = int(d)
        if i % 2 == 0:
            n *= 2
            if n > 9:
                n -= 9
        total += n
    return str((10 - total % 10) % 10)


def build_npn(gov_code, seq):
    base = "%02d%08d" % (gov_code, seq)
    return base + luhn_check_digit(base)


def npn_display(npn):
    return "%s-%s-%s-%s" % (npn[:2], npn[2:6], npn[6:10], npn[10])


def iqpin_display(code):
    return "%s-%s-%s" % (code[:3], code[3:6], code[6:]) if len(code) >= 7 else code


# ═══════════════ التنفيذ داخل QGIS ═══════════════
def run():
    from qgis.core import (QgsProject, QgsField, QgsCoordinateReferenceSystem,
                           QgsCoordinateTransform)
    from qgis.PyQt.QtCore import QVariant
    try:
        from qgis.utils import iface
    except Exception:
        iface = None

    proj = QgsProject.instance()
    if LAYER_NAME:
        matches = proj.mapLayersByName(LAYER_NAME)
        layer = matches[0] if matches else None
    else:
        layer = iface.activeLayer() if iface else None
    if layer is None:
        print("لا طبقة نشِطة — حدّد LAYER_NAME أو فعّل طبقة المباني.")
        return

    dst = QgsCoordinateReferenceSystem("EPSG:4326")
    xform = QgsCoordinateTransform(layer.crs(), dst, proj)

    layer.startEditing()
    for fname in ("npn", "npn_disp", "iqpin", "iqpin_disp"):
        if layer.fields().indexFromName(fname) < 0:
            layer.addAttribute(QgsField(fname, QVariant.String))
    layer.updateFields()
    i_npn = layer.fields().indexFromName("npn")
    i_npd = layer.fields().indexFromName("npn_disp")
    i_pin = layer.fields().indexFromName("iqpin")
    i_pid = layer.fields().indexFromName("iqpin_disp")

    seq = START_SEQ
    numbered = skipped = 0
    for feat in layer.getFeatures():
        geom = feat.geometry()
        if geom is None or geom.isEmpty():
            skipped += 1
            continue
        p = xform.transform(geom.centroid().asPoint())
        lon, lat = p.x(), p.y()
        pin = iqpin_encode(lat, lon)
        if not pin:  # خارج العراق
            skipped += 1
            continue
        npn = build_npn(GOV_CODE, seq)
        seq += 1
        layer.changeAttributeValue(feat.id(), i_npn, npn)
        layer.changeAttributeValue(feat.id(), i_npd, npn_display(npn))
        layer.changeAttributeValue(feat.id(), i_pin, pin)
        layer.changeAttributeValue(feat.id(), i_pid, iqpin_display(pin))
        numbered += 1
    layer.commitChanges()
    print("تم الترقيم: %d مبنى | مُتخطّى: %d | آخر تسلسل: %d"
          % (numbered, skipped, seq - 1))


# فحص ذاتي عند التشغيل خارج QGIS (يُثبت مطابقة الخوارزمية)
if __name__ == "__main__":
    assert iqpin_encode(33.3389, 44.4009) == "8L8L865FMT"
    assert luhn_check_digit("1004839221") == "0"
    print("الخوارزمية مطابقة للدراسة ✓ (شغّل run() داخل QGIS للترقيم)")
else:
    try:
        run()
    except Exception as e:  # noqa
        print("خطأ:", e)
