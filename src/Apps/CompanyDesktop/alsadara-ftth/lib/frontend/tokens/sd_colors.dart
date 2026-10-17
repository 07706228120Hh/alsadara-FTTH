/// ألوان نظام تصميم الصدارة الموحّد (Sadara Design — sd)
///
/// المصدر الوحيد للألوان في الواجهات الجديدة/المرحَّلة. لا تكتب Color(0x…) داخل
/// الصفحات؛ أضف اللون هنا أولاً إن لزم.
///
/// القاعدة: لون أساسي واحد (نيلي) + لون مرافق (تركوازي) + 4 ألوان مجموعات
/// للأقسام + ألوان دلالية (نجاح/تحذير/خطر/معلومة) — كل لون معه درجة حافّة
/// داكنة (للبروز 3D) ودرجة فاتحة (خلفية) ودرجة حافّة فاتحة.
library;

import 'package:flutter/material.dart';

class SdColors {
  SdColors._();

  // ── الهوية ──
  static const primary = Color(0xFF1A237E); // نيلي الصدارة
  static const primaryEdge = Color(0xFF0F1660); // حافّة البروز
  static const primaryMid = Color(0xFF283593);
  static const primaryLight = Color(0xFF3949AB);
  static const primarySoft = Color(0xFF5C6BC0);
  static const primaryTint = Color(0xFFE8EAF6);
  static const primaryTintEdge = Color(0xFFC5CAE9);

  static const accent = Color(0xFF00838F); // تركوازي (الفايبر/الشبكة)
  static const accentEdge = Color(0xFF005662);
  static const accentLight = Color(0xFF26A69A);
  static const accentGlow = Color(0xFF00ACC1);
  static const accentTint = Color(0xFFE0F2F1);
  static const accentTintEdge = Color(0xFFB2DFDB);

  /// لمسة ذهبية للفخامة — للعناوين الفرعية وخطوط البطاقة العلوية فقط (لا للنص الطويل).
  static const gold = Color(0xFFE8C26A);

  // ── المحايدات ──
  static const ground = Color(0xFFEEF1F6); // خلفية الصفحات
  static const groundAlt = Color(0xFFF2F4F8);
  static const surface = Color(0xFFFFFFFF); // البطاقات
  static const surfaceAlt = Color(0xFFF5F7FB); // صفوف داخل البطاقات
  static const ink = Color(0xFF1B1E2B); // النص الأساسي
  static const muted = Color(0xFF5B6070); // نص ثانوي (تباين ≥ 4.5:1 على الأبيض)
  static const faint = Color(0xFF8A90A2); // نص معطّل/تلميح (للأيقونات لا للنص الطويل)
  static const divider = Color(0xFFE3E6F0);
  static const edge = Color(0xFFDCE0EC); // حافّة بروز العناصر الصغيرة
  static const cardEdge = Color(0xFFD6DBEA); // حافّة بروز البطاقات
  static const sideShade = Color(0xFFC5CBE0); // الوجه المظلّل للمجسّمات

  /// الإطار الموحّد حول الحقول والبطاقات والأزرار: كحلي رمادي داكن ناعم
  /// (بدل الأسود الصريح — 17-10-2026). غيّر هنا فقط ليتغيّر في كل التطبيق.
  static const outline = Color(0xFF3D4466);
  static const outlineDisabled = Color(0x403D4466);

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

  static const info = Color(0xFF1565C0);
  static const infoEdge = Color(0xFF0D47A1);
  static const infoTint = Color(0xFFE3F2FD);
  static const infoTintEdge = Color(0xFFBBDEFB);

  // ── بنفسجي المنصّات (مطابق لنبرة SdGroup.platform؛ للجداول/البطاقات الدلالية) ──
  static const platformBase = Color(0xFF7B1FA2);
  static const platformLight = Color(0xFFAB47BC);
  static const platformEdge = Color(0xFF4A148C);
  static const platformTint = Color(0xFFF3E5F5);
  static const platformTintEdge = Color(0xFFE1BEE7);

  // ── علامات تجارية خارجية (للأيقونة/الشعار فقط، لا للشريط أو الخلفية) ──
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
          light: Color(0xFF26A69A),
          base: Color(0xFF00838F),
          edge: Color(0xFF005662),
          tint: Color(0xFFE0F2F1),
          tintEdge: Color(0xFFB2DFDB),
          text: Color(0xFF00695C),
        );
      case SdGroup.admin:
        return const SdTone(
          light: Color(0xFF5C6BC0),
          base: Color(0xFF3949AB),
          edge: Color(0xFF1A237E),
          tint: Color(0xFFE8EAF6),
          tintEdge: Color(0xFFC5CAE9),
          text: Color(0xFF1A237E),
        );
      case SdGroup.comms:
        return const SdTone(
          light: Color(0xFFFFA726),
          base: Color(0xFFEF6C00),
          edge: Color(0xFFA84300),
          tint: Color(0xFFFFF3E0),
          tintEdge: Color(0xFFFFE0B2),
          text: Color(0xFFB53D00),
        );
      case SdGroup.platform:
        return const SdTone(
          light: Color(0xFFAB47BC),
          base: Color(0xFF7B1FA2),
          edge: Color(0xFF4A148C),
          tint: Color(0xFFF3E5F5),
          tintEdge: Color(0xFFE1BEE7),
          text: Color(0xFF6A1B9A),
        );
      case SdGroup.neutral:
        return const SdTone(
          light: Color(0xFF78909C),
          base: Color(0xFF546E7A),
          edge: Color(0xFF37474F),
          tint: Color(0xFFECEFF1),
          tintEdge: Color(0xFFCFD8DC),
          text: Color(0xFF37474F),
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
          light: Color(0xFF42A5F5),
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
