/// 📐 Accounting Responsive Helper
/// أداة متخصصة لجعل صفحات المحاسبة متجاوبة مع أحجام الشاشات
/// تُستخدم مع ResponsiveHelper الأساسي لتوفير أحجام خاصة بالمحاسبة
library;

import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';

/// أداة التجاوب الخاصة بصفحات المحاسبة
/// تُستخدم عبر `context.accR` أو `AccR.of(context)`
class AccountingResponsive {
  final ResponsiveHelper r;

  const AccountingResponsive(this.r);

  // ═══════════════════════════════════════════════════════════════
  // 📝 أحجام النص الخاصة بالمحاسبة
  // ═══════════════════════════════════════════════════════════════

  /// عنوان كبير (22-26px) - لعناوين الأقسام الرئيسية
  double get headingLarge => r.scaled(18, 22, 26);

  /// عنوان متوسط (18-22px) - لعناوين البطاقات والأقسام
  double get headingMedium => r.scaled(16, 18, 22);

  /// عنوان صغير (16-18px) - لعناوين فرعية
  double get headingSmall => r.scaled(14, 16, 18);

  /// نص أساسي (14px) - للنصوص العادية
  double get body => r.scaled(12, 13, 14);

  /// نص صغير (12px) - للتفاصيل
  double get small => r.scaled(10, 11, 12);

  /// نص دقيق (10px) - للتسميات والحواشي
  double get caption => r.scaled(9, 10, 10);

  /// قيمة مالية كبيرة - لعرض الأرقام البارزة
  double get financialLarge => r.scaled(20, 24, 28);

  /// قيمة مالية متوسطة
  double get financialMedium => r.scaled(16, 18, 20);

  /// قيمة مالية صغيرة - في الجداول
  double get financialSmall => r.scaled(12, 13, 14);

  /// نص زر
  double get buttonText => r.scaled(11, 13, 14);

  /// نص حقل إدخال
  double get inputText => r.scaled(12, 13, 14);

  /// نص تلميح
  double get hintText => r.scaled(11, 12, 13);

  // ═══════════════════════════════════════════════════════════════
  // 🔲 أحجام الأيقونات
  // ═══════════════════════════════════════════════════════════════

  /// أيقونة صغيرة جداً (14-16px)
  double get iconXS => r.scaled(12, 14, 16);

  /// أيقونة صغيرة (16-20px)
  double get iconS => r.scaled(14, 16, 20);

  /// أيقونة متوسطة (20-24px)
  double get iconM => r.scaled(18, 20, 24);

  /// أيقونة كبيرة (24-30px)
  double get iconL => r.scaled(22, 26, 30);

  /// أيقونة كبيرة جداً (32-40px)
  double get iconXL => r.scaled(28, 34, 40);

  /// أيقونة الحالة الفارغة (48-64px)
  double get iconEmpty => r.scaled(40, 52, 64);

  /// أيقونة AppBar
  double get iconAppBar => r.scaled(20, 24, 28);

  // ═══════════════════════════════════════════════════════════════
  // 📏 المسافات والهوامش
  // ═══════════════════════════════════════════════════════════════

  /// مسافة صغيرة جداً (4px)
  double get spaceXS => r.scaled(3, 4, 4);

  /// مسافة صغيرة (8px)
  double get spaceS => r.scaled(6, 7, 8);

  /// مسافة متوسطة (12px)
  double get spaceM => r.scaled(8, 10, 12);

  /// مسافة كبيرة (16px)
  double get spaceL => r.scaled(12, 14, 16);

  /// مسافة كبيرة جداً (20-24px)
  double get spaceXL => r.scaled(16, 20, 24);

  /// مسافة ضخمة (24-32px)
  double get spaceXXL => r.scaled(20, 26, 32);

  /// هامش المحتوى الأفقي
  double get paddingH => r.scaled(10, 16, 24);

  /// هامش المحتوى العمودي
  double get paddingV => r.scaled(8, 12, 16);

  /// هامش البطاقة الداخلي
  double get cardPad => r.scaled(10, 14, 16);

  /// هامش الزر الأفقي
  double get btnPadH => r.scaled(12, 16, 20);

  /// هامش الزر العمودي
  double get btnPadV => r.scaled(8, 10, 12);

  /// هامش صغير (لعناصر الشريط)
  double get toolbarPad => r.scaled(6, 8, 12);

  // ═══════════════════════════════════════════════════════════════
  // 📊 أحجام الجداول
  // ═══════════════════════════════════════════════════════════════

  /// ارتفاع صف الجدول الأدنى
  double get tableRowMinH => r.scaled(36, 40, 48);

  /// ارتفاع صف الجدول الأقصى
  double get tableRowMaxH => r.scaled(48, 52, 60);

  /// ارتفاع رأس الجدول
  double get tableHeaderH => r.scaled(36, 40, 48);

  /// حجم نص رأس الجدول
  double get tableHeaderFont => r.scaled(11, 12, 13);

  /// حجم نص خلية الجدول
  double get tableCellFont => r.scaled(11, 12, 13);

  /// هامش خلية الجدول الأفقي
  double get tableCellPadH => r.scaled(6, 10, 14);

  /// هامش خلية الجدول العمودي
  double get tableCellPadV => r.scaled(4, 6, 8);

  /// عرض عمود الرقم (#)
  double get colNumW => r.scaled(30, 35, 40);

  /// عرض عمود الحالة
  double get colStatusW => r.scaled(60, 80, 100);

  /// عرض عمود الإجراءات
  double get colActionsW => r.scaled(70, 100, 140);

  /// عرض عمود التاريخ
  double get colDateW => r.scaled(70, 90, 110);

  /// عرض عمود المبلغ
  double get colAmountW => r.scaled(70, 90, 120);

  // ═══════════════════════════════════════════════════════════════
  // 🔘 أحجام الأزرار
  // ═══════════════════════════════════════════════════════════════

  /// ارتفاع الزر
  double get btnHeight => r.scaled(32, 38, 42);

  /// حجم زر صغير (أيقونة فقط)
  double get btnSmallSize => r.scaled(28, 32, 36);

  /// نصف قطر الزر
  double get btnRadius => r.scaled(6, 8, 10);

  // ═══════════════════════════════════════════════════════════════
  // 🃏 أحجام البطاقات
  // ═══════════════════════════════════════════════════════════════

  /// نصف قطر البطاقة
  double get cardRadius => r.scaled(8, 10, 12);

  /// نصف قطر كبير (للحوارات والأقسام)
  double get radiusL => r.scaled(12, 14, 16);

  /// نصف قطر التلميح/الشارة
  double get badgeRadius => r.scaled(4, 5, 6);

  // ═══════════════════════════════════════════════════════════════
  // 📦 أحجام الحوارات والنوافذ
  // ═══════════════════════════════════════════════════════════════

  /// عرض الحوار الصغير
  double get dialogSmallW {
    final w = r.availableWidth;
    if (r.isMobile) return (w * 0.92).clamp(280, 380);
    if (r.isTablet) return (w * 0.6).clamp(350, 450);
    return (w * 0.35).clamp(380, 500);
  }

  /// عرض الحوار المتوسط
  double get dialogMediumW {
    final w = r.availableWidth;
    if (r.isMobile) return (w * 0.95).clamp(300, 420);
    if (r.isTablet) return (w * 0.7).clamp(400, 550);
    return (w * 0.45).clamp(450, 600);
  }

  /// عرض الحوار الكبير
  double get dialogLargeW {
    final w = r.availableWidth;
    if (r.isMobile) return (w * 0.97).clamp(320, 500);
    if (r.isTablet) return (w * 0.8).clamp(500, 700);
    return (w * 0.55).clamp(550, 800);
  }

  /// ارتفاع الحوار الأقصى
  double get dialogMaxH => r.safeHeight * 0.85;

  // ═══════════════════════════════════════════════════════════════
  // 🔧 أحجام عناصر الشريط (Toolbar)
  // ═══════════════════════════════════════════════════════════════

  /// ارتفاع شريط الأدوات
  double get toolbarH => r.scaled(42, 52, 60);

  /// ارتفاع شريط علوي مضغوط
  double get toolbarCompactH => r.scaled(36, 42, 48);

  /// ارتفاع شريط البحث
  double get searchBarH => r.scaled(32, 38, 42);

  /// عرض حقل البحث
  double get searchFieldW => r.scaled(140, 200, 280);

  // ═══════════════════════════════════════════════════════════════
  // 🏷️ أحجام الشارات والعلامات
  // ═══════════════════════════════════════════════════════════════

  /// ارتفاع شارة الحالة
  double get badgeH => r.scaled(20, 24, 28);

  /// حجم نص الشارة
  double get badgeFont => r.scaled(9, 10, 11);

  /// حجم دائرة الحالة
  double get statusDotSize => r.scaled(6, 8, 10);

  // ═══════════════════════════════════════════════════════════════
  // 📱 خصائص مساعدة
  // ═══════════════════════════════════════════════════════════════

  bool get isMobile => r.isMobile;
  bool get isTablet => r.isTablet;
  bool get isDesktop => r.isDesktop;
  double get screenW => r.availableWidth;
  double get screenH => r.availableHeight;

  /// عدد أعمدة الإحصائيات
  int get statColumns {
    if (r.availableWidth > 1200) return 4;
    if (r.availableWidth > 800) return 3;
    if (r.availableWidth > 500) return 2;
    return 1;
  }

  /// عدد أعمدة البطاقات
  int get cardColumns {
    if (r.availableWidth > 1000) return 3;
    if (r.availableWidth > 600) return 2;
    return 1;
  }

  /// EdgeInsets للبطاقة
  EdgeInsets get cardPadding => EdgeInsets.all(cardPad);

  /// EdgeInsets للمحتوى
  EdgeInsets get contentPadding =>
      EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV);

  /// EdgeInsets لعناصر الجدول
  EdgeInsets get tableCellPadding =>
      EdgeInsets.symmetric(horizontal: tableCellPadH, vertical: tableCellPadV);

  /// EdgeInsets للزر
  EdgeInsets get buttonPadding =>
      EdgeInsets.symmetric(horizontal: btnPadH, vertical: btnPadV);

  /// EdgeInsets شريط الأدوات
  EdgeInsets get toolbarPadding =>
      EdgeInsets.symmetric(horizontal: toolbarPad, vertical: toolbarPad * 0.6);
}

/// Extension لسهولة الوصول من أي BuildContext
extension AccountingResponsiveContext on BuildContext {
  AccountingResponsive get accR => AccountingResponsive(ResponsiveHelper(this));
}
