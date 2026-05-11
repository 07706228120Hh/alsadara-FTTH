# خطة تحسين صفحة خارطة الزونات (kml_zones_map_page.dart)

## الحالة الحالية
- ملف واحد ~2583 سطر
- يعرض FAT points + FDT polygons + FBG hulls على OpenStreetMap
- فلترة Zone → FBG → FAT مع Autocomplete
- ملاحة GPS + OSRM routing بالعربي
- كاش مزدوج (JSON + static memory)

---

## التحسينات المطلوبة

### 1. ربط بيانات المشتركين (الأهم)
- [ ] عند الضغط على FAT → جلب عدد المشتركين الفعليين من API
- [ ] تلوين FAT حسب نسبة الإشغال (أخضر < 50%، أصفر < 80%، أحمر > 80%)
- [ ] عرض عدد المشتركين كـ badge فوق كل FAT عند zoom عالي

### 2. Marker Clustering
- [ ] استخدام `flutter_map_marker_cluster` لتجميع النقاط القريبة عند zoom منخفض
- [ ] عرض العدد الإجمالي داخل الـ cluster

### 3. ربط التذاكر والأعطال
- [ ] طبقة إضافية تُظهر التذاكر المفتوحة على الخريطة (أيقونة حمراء)
- [ ] عند الضغط → تفاصيل التذكرة مع إمكانية الانتقال لصفحة التذكرة

### 4. Polygon Tap (مناطق FDT)
- [ ] إضافة tap handler على مضلعات FDT لعرض تفاصيلها
- [ ] عرض بطاقة المنطقة عند الضغط على المضلع

### 5. GPS Tracking مستمر
- [ ] استخدام `Geolocator.getPositionStream()` لتحديث الموقع باستمرار
- [ ] تحديث خط المسار كلما تحرك المستخدم
- [ ] إشعار عند الاقتراب من الوجهة

### 6. بحث شامل
- [ ] بحث نصي يشمل: اسم FAT، رقم OLT، المحلة، الحي، Sub-ring
- [ ] عرض النتائج في قائمة مع زر "اذهب" لكل نتيجة

### 7. Heatmap Layer
- [ ] طبقة حرارية تُظهر كثافة المشتركين أو الأعطال حسب المنطقة

### 8. Export & Share
- [ ] نسخ إحداثيات FAT المحدد
- [ ] مشاركة رابط Google Maps مباشرة
- [ ] تصدير قائمة FAT المفلترة كـ CSV

### 9. Offline Tiles
- [ ] تحميل tiles مسبقاً للمناطق المحددة (flutter_map_tile_caching)
- [ ] دعم العمل الميداني بدون انترنت

### 10. تقسيم الكود (Refactoring)
- [ ] فصل Models إلى ملف مستقل
- [ ] فصل KML Parser إلى ملف مستقل
- [ ] فصل widgets (point_sheet, region_sheet, search_sheet, navigation_panel)
- [ ] فصل services (cache_service, routing_service)

```
lib/pages/kml_zones_map/
├── kml_zones_map_page.dart
├── models/
├── parser/kml_parser.dart
├── widgets/
│   ├── map_layers.dart
│   ├── point_sheet.dart
│   ├── region_sheet.dart
│   ├── search_sheet.dart
│   └── navigation_panel.dart
└── services/
    ├── cache_service.dart
    └── routing_service.dart
```

---

## الأولوية

| # | التحسين | الحالة |
|---|---------|--------|
| 1 | ربط بيانات المشتركين | ⏳ |
| 2 | Marker Clustering | ⏳ |
| 3 | Polygon Tap | ⏳ |
| 4 | GPS Tracking مستمر | ⏳ |
| 5 | بحث شامل | ⏳ |
| 6 | ربط التذاكر | ⏳ |
| 7 | Export & Share | ⏳ |
| 8 | Heatmap | ⏳ |
| 9 | Offline Tiles | ⏳ |
| 10 | تقسيم الكود | ⏳ |

---

*تاريخ الإنشاء: 2026-05-11*
