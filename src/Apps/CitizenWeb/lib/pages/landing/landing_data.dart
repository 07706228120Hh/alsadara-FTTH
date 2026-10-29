import 'package:flutter/material.dart';
import 'landing_style.dart';

/// خدمة تُعرض في الواجهة الرئيسية: فيديو + وصف + مسار الصفحة الحقيقية في التطبيق.
class LService {
  final String key; // اسم ملف الفيديو في assets/videos
  final String title;
  final String short;
  final String desc;
  final IconData icon;
  final Color bg;
  final Color fg;
  final String route; // مسار go_router

  const LService({
    required this.key,
    required this.title,
    required this.short,
    required this.desc,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.route,
  });

  String get video => 'assets/videos/$key.mp4';
  String get poster => 'assets/videos/$key.jpg';
}

const kServices = <LService>[
  LService(
    key: 'internet',
    title: 'إنترنت فايبر',
    short: 'اشتراك • تجديد • ترقية',
    desc: 'اشترك بباقة جديدة، جدّد أو رقِّ سرعتك بخطوات قليلة، وتابع طلبك مباشرة.',
    icon: Icons.wifi_rounded,
    bg: LColors.tealSoft,
    fg: LColors.teal,
    route: '/citizen/internet',
  ),
  LService(
    key: 'master',
    title: 'ماستر كارد',
    short: 'طلب بطاقة • شحن رصيد',
    desc: 'اطلب بطاقة ماستر كارد جديدة واشحن رصيدها من حسابك، وتصلك البطاقة للبيت.',
    icon: Icons.credit_card_rounded,
    bg: LColors.goldSoft,
    fg: LColors.goldText,
    route: '/citizen/master',
  ),
  LService(
    key: 'delivery',
    title: 'سحب ديلفري',
    short: 'النقد يصلك للبيت',
    desc: 'اطلب سحب مبلغ من بطاقتك، ويأتيك المندوب بجهاز الدفع ويسلّمك المبلغ مع الوصل.',
    icon: Icons.payments_outlined,
    bg: LColors.greenSoft,
    fg: LColors.greenInk,
    route: '/citizen/master/delivery-withdraw',
  ),
  LService(
    key: 'store',
    title: 'المتجر الإلكتروني',
    short: 'راوترات • ملحقات',
    desc: 'راوترات وكابلات وملحقات شبكات أصلية، مع سلة ودفع إلكتروني وتوصيل.',
    icon: Icons.shopping_bag_outlined,
    bg: LColors.indigoSoft,
    fg: LColors.navySoft,
    route: '/citizen/store',
  ),
  LService(
    key: 'maintenance',
    title: 'الدعم والصيانة',
    short: 'طلب فنّي',
    desc: 'افتح طلب صيانة لخطّك وتابع الفريق الفني حتى إغلاق المشكلة.',
    icon: Icons.build_outlined,
    bg: LColors.tealSoft,
    fg: LColors.teal,
    route: '/citizen/internet/maintenance',
  ),
  LService(
    key: 'coverage',
    title: 'خريطة التغطية',
    short: 'مناطق الشبكة',
    desc: 'تصفّح خريطة الشبكة التفاعلية لمعرفة المناطق المغطاة قبل طلب الاشتراك.',
    icon: Icons.location_on_outlined,
    bg: LColors.goldSoft,
    fg: LColors.goldText,
    route: '/citizen/kml-map',
  ),
];

const kMarquee = [
  'اشتراك إنترنت جديد', 'تجديد فوري', 'ترقية الباقة', 'طلب صيانة', 'بطاقة ماستر كارد',
  'شحن رصيد', 'سحب ديلفري', 'متجر الأجهزة', 'خريطة التغطية', 'بوابة الوكلاء',
];

class LStep {
  final String title;
  final String text;
  const LStep(this.title, this.text);
}

const kDeliverySteps = [
  LStep('أدخل المبلغ', 'اكتب المبلغ الذي تريد سحبه من بطاقة الماستر.'),
  LStep('حدّد موقعك', 'اختر موقع التوصيل على الخريطة أو استخدم موقعك الحالي.'),
  LStep('أرسل الطلب', 'تحصل فوراً على رقم طلب، ونتواصل معك لتأكيده.'),
  LStep('استلم المبلغ', 'يمرّر المندوب بطاقتك على جهاز الدفع ويسلّمك النقد مع الوصل.'),
];

/// بيانات التواصل الرسمية.
class LContact {
  LContact._();
  static const phone = '07717727720';
  static const email = 'info@ramzalsadara.tech';
  static const company = 'شركة رمز الصدارة للتجارة العامة والمقاولات العامة المحدودة';
}

/// تحويل الأرقام إلى أرقام عربية (١٢٣).
String arDigits(int n, {int pad = 2}) =>
    n.toString().padLeft(pad, '0').split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();
