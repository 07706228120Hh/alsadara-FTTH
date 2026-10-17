/// ألوان نظام تصميم الصدارة الموحّد (Sadara Design — sd)
///
/// المصدر الوحيد للألوان في الواجهات الجديدة/المرحَّلة. لا تكتب Color(0x…) داخل
/// الصفحات؛ أضف اللون هنا أولاً إن لزم.
///
/// الهوية «كحلي ملكي وذهبي» (17-10-2026): كحلي ملكي + ذهبي للفخامة + ألوان أحجار
/// كريمة للأقسام (زمرّد/ياقوت أزرق/ياقوت أحمر/جمشت) على خلفية رمادية مزرقّة باردة.
/// القاعدة: لون أساسي واحد (كحلي) + لون مرافق (سماوي بترولي #0E7490) للأزرار الثانوية؛
/// الذهبي للزخارف الرفيعة فقط (لا أزرار) — قرار المالك 17-10-2026 + 4 ألوان مجموعات
/// للأقسام + ألوان دلالية (نجاح/تحذير/خطر/معلومة) — كل لون معه درجة حافّة
/// داكنة (للبروز 3D) ودرجة فاتحة (خلفية) ودرجة حافّة فاتحة.
library;

import 'package:flutter/material.dart';

class SdColors {
  SdColors._();

  // ── الهوية ──
  static const primary = Color(0xFF132A5E); // كحلي ملكي
  static const primaryEdge = Color(0xFF0B1B3F); // حافّة البروز
  static const primaryMid = Color(0xFF1A3570);
  static const primaryLight = Color(0xFF1E3A8A);
  static const primarySoft = Color(0xFF3B5BA9);
  static const primaryTint = Color(0xFFE8EDF7);
  static const primaryTintEdge = Color(0xFFCFD9EC);

  static const accent = Color(0xFF0E7490); // تركوازي (الفايبر/الشبكة)
  static const accentEdge = Color(0xFF155E75);
  static const accentLight = Color(0xFF06B6D4);
  static const accentGlow = Color(0xFF22D3EE);
  static const accentTint = Color(0xFFE0F7FA);
  static const accentTintEdge = Color(0xFFA5F3FC);

  /// لمسة ذهبية للفخامة — للعناوين الفرعية وخطوط البطاقة العلوية فقط (لا للنص الطويل).
  static const gold = Color(0xFFC9A44C);

  /// ذهبي فاتح — للزخارف فقط (حلقات المكعّبات، خطوط رفيعة)، لا للأزرار.
  static const goldLight = Color(0xFFE6C67A);

  // ── المحايدات ──
  static const ground = Color(0xFFF1F4F9); // خلفية الصفحات
  static const groundAlt = Color(0xFFF6F8FB);
  static const surface = Color(0xFFFFFFFF); // البطاقات
  static const surfaceAlt = Color(0xFFF5F7FB); // صفوف داخل البطاقات
  static const ink = Color(0xFF0B1B3F); // النص الأساسي
  static const muted = Color(0xFF5E6577); // نص ثانوي (تباين ≥ 4.5:1 على الأبيض)
  static const faint = Color(0xFF9AA1B2); // نص معطّل/تلميح (للأيقونات لا للنص الطويل)
  static const divider = Color(0xFFE3E8F1);
  static const edge = Color(0xFFDCE3EE); // حافّة بروز العناصر الصغيرة
  static const cardEdge = Color(0xFFDCE3EE); // حافّة بروز البطاقات
  static const sideShade = Color(0xFFC8D2E3); // الوجه المظلّل للمجسّمات

  /// الإطار الموحّد حول الحقول والبطاقات والأزرار: كحلي رمادي داكن ناعم
  /// (بدل الأسود الصريح — 17-10-2026). غيّر هنا فقط ليتغيّر في كل التطبيق.
  static const outline = Color(0xFFE3E8F1);
  static const outlineDisabled = Color(0x80E3E8F1);

  // ── الدلالية ──
  static const success = Color(0xFF2E7D32);
  static const successEdge = Color(0xFF1B5E20);
  static const successTint = Color(0xFFE8F5E9);
  static const successTintEdge = Color(0xFFC8E6C9);

  static const warning = Color(0xFFEF6C00);
  static const warningEdge = Color(0xFFA84300);
  static const warningTint = Color(0xFFFFF3E0);
  static const warningTintEdge = Color(0xFFFFE0B2);
  static const warningText = Color(0xFFB53D00); // نص برتقالي بتباين كافٍ

  static const danger = Color(0xFFC62828);
  static const dangerEdge = Color(0xFF7F0000);
  static const dangerTint = Color(0xFFFFEBEE);
  static const dangerTintEdge = Color(0xFFFFCDD2);

  static const info = Color(0xFF1E3A8A);
  static const infoEdge = Color(0xFF172554);
  static const infoTint = Color(0xFFE8EEFB);
  static const infoTintEdge = Color(0xFFC9D6F5);

  // ── بنفسجي المنصّات (مطابق لنبرة SdGroup.platform؛ للجداول/البطاقات الدلالية) ──
  static const platformBase = Color(0xFF5B21B6);
  static const platformLight = Color(0xFFC4B5FD);
  static const platformEdge = Color(0xFF3B1488);
  static const platformTint = Color(0xFFF1ECFD);
  static const platformTintEdge = Color(0xFFDCD0FA);

  // ── علامات تجارية خارجية (للأيقونة/الشعار فقط، لا للشريط أو الخلفية) ──
  // ── درجات وسيطة للتدرّجات والرسوم (مطابقة لنبرات SdGroup/SdStatus — إضافة فقط) ──
  static const successLight = Color(0xFF66BB6A);
  static const warningLight = Color(0xFFFFA726);
  static const dangerLight = Color(0xFFE57373);
  static const infoLight = Color(0xFF60A5FA);
  static const platformMid = Color(0xFF7C3AED);
  static const fieldBase = Color(0xFF047857);
  static const fieldLight = Color(0xFF34D399);
  static const commsBase = Color(0xFF9F1239);
  static const commsEdge = Color(0xFF6B0F2A);
  static const commsLight = Color(0xFFFB7185);
  static const neutralBase = Color(0xFF57534E);
  static const neutralLight = Color(0xFFA8A29E);

  static const whatsapp = Color(0xFF25D366);
  static const whatsappEdge = Color(0xFF128C7E); // الدرجة الداكنة لحافّة شعار واتساب

  // ── تدرّجات جاهزة (للشارات/الرؤوس المرحَّلة من الوحدات) ──
  /// تدرّج نيلي (هوية الصدارة) — بديل التدرّج الأزرق القديم.
  static const List<Color> blueGradient = [primaryMid, primaryLight, primarySoft];

  /// تدرّج نجاح أخضر.
  static const List<Color> greenGradient = [success, successEdge];

  /// تدرّج تحذير برتقالي.
  static const List<Color> orangeGradient = [warning, warningEdge];
}

/// مجموعات أقسام التطبيق — لون واحد لكل مجموعة بدل لون لكل زر.
enum SdGroup {
  /// العمليات الميدانية: الوكيل، المهام، الزونات، المشتركون، IPTV، الساس.
  field,

  /// الإدارة والموارد: HR، شاشتي، المتابعة، المخازن، الحسابات، الشركة.
  admin,

  /// التواصل: المحادثة، التبليغات، الواتساب.
  comms,

  /// المنصّات والبيانات: منصة الصدارة، العقارات، البحث الذكي، التقارير.
  platform,

  /// محايد: الإعدادات والأدوات.
  neutral,
}

/// درجات لون مجموعة واحدة.
class SdTone {
  const SdTone({
    required this.light,
    required this.base,
    required this.edge,
    required this.tint,
    required this.tintEdge,
    required this.text,
  });

  /// أعلى التدرّج (الوجه المضاء).
  final Color light;

  /// اللون الأساسي.
  final Color base;

  /// الحافّة الداكنة (سماكة المجسّم/الزر).
  final Color edge;

  /// خلفية فاتحة (شارات/صفوف).
  final Color tint;

  /// حافّة الخلفية الفاتحة.
  final Color tintEdge;

  /// لون نص مقروء فوق tint.
  final Color text;
}

extension SdGroupTone on SdGroup {
  SdTone get tone {
    switch (this) {
      case SdGroup.field:
        return const SdTone(
          light: Color(0xFF34D399),
          base: Color(0xFF047857),
          edge: Color(0xFF064E3B),
          tint: Color(0xFFE7F6EF),
          tintEdge: Color(0xFFBFE8D4),
          text: Color(0xFF065F46),
        );
      case SdGroup.admin:
        return const SdTone(
          light: Color(0xFF60A5FA),
          base: Color(0xFF1E3A8A),
          edge: Color(0xFF172554),
          tint: Color(0xFFE8EEFB),
          tintEdge: Color(0xFFC9D6F5),
          text: Color(0xFF1E3A8A),
        );
      case SdGroup.comms:
        return const SdTone(
          light: Color(0xFFFB7185),
          base: Color(0xFF9F1239),
          edge: Color(0xFF6B0F2A),
          tint: Color(0xFFFDECEF),
          tintEdge: Color(0xFFF8C9D2),
          text: Color(0xFF9F1239),
        );
      case SdGroup.platform:
        return const SdTone(
          light: Color(0xFFC4B5FD),
          base: Color(0xFF5B21B6),
          edge: Color(0xFF3B1488),
          tint: Color(0xFFF1ECFD),
          tintEdge: Color(0xFFDCD0FA),
          text: Color(0xFF5B21B6),
        );
      case SdGroup.neutral:
        return const SdTone(
          light: Color(0xFFA8A29E),
          base: Color(0xFF57534E),
          edge: Color(0xFF3F3B37),
          tint: Color(0xFFF3F2F0),
          tintEdge: Color(0xFFE2DFDB),
          text: Color(0xFF44403C),
        );
    }
  }

  String get arabicLabel {
    switch (this) {
      case SdGroup.field:
        return 'العمليات الميدانية';
      case SdGroup.admin:
        return 'الإدارة والموارد';
      case SdGroup.comms:
        return 'التواصل';
      case SdGroup.platform:
        return 'المنصّات والبيانات';
      case SdGroup.neutral:
        return 'الأدوات';
    }
  }
}

/// نبرة دلالية للحالات (شارات، رسائل، أعمدة).
enum SdStatus { success, warning, danger, info, neutral }

extension SdStatusTone on SdStatus {
  SdTone get tone {
    switch (this) {
      case SdStatus.success:
        return const SdTone(
          light: Color(0xFF66BB6A),
          base: SdColors.success,
          edge: SdColors.successEdge,
          tint: SdColors.successTint,
          tintEdge: SdColors.successTintEdge,
          text: SdColors.successEdge,
        );
      case SdStatus.warning:
        return const SdTone(
          light: Color(0xFFFFA726),
          base: SdColors.warning,
          edge: SdColors.warningEdge,
          tint: SdColors.warningTint,
          tintEdge: SdColors.warningTintEdge,
          text: SdColors.warningText,
        );
      case SdStatus.danger:
        return const SdTone(
          light: Color(0xFFE57373),
          base: SdColors.danger,
          edge: SdColors.dangerEdge,
          tint: SdColors.dangerTint,
          tintEdge: SdColors.dangerTintEdge,
          text: Color(0xFFB71C1C),
        );
      case SdStatus.info:
        return const SdTone(
          light: Color(0xFF60A5FA),
          base: SdColors.info,
          edge: SdColors.infoEdge,
          tint: SdColors.infoTint,
          tintEdge: SdColors.infoTintEdge,
          text: SdColors.infoEdge,
        );
      case SdStatus.neutral:
        return SdGroup.neutral.tone;
    }
  }
}
