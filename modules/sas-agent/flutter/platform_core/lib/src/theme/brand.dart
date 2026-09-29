import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// هوية كل تطبيق داخل المنصّة — المصدر الوحيد للاسم واللكنة والأيقونة.
/// يُستخدم في: شاشة الدخول، شارة الهيكل، بطاقات البوّابة، الثيم.
enum AppBrand {
  portal(
    title: 'منصة العراق الرقمية',
    tagline: 'البوّابة الرئيسية',
    accent: Color(0xFF0E7490),
    accentDark: Color(0xFF22D3EE),
    icon: PhosphorIconsDuotone.globeHemisphereEast,
    iconFill: PhosphorIconsFill.globeHemisphereEast,
    slug: 'portal',
  ),
  ministry(
    title: 'منصّة الوزارة',
    tagline: 'الجهة الرقابية — الإشراف الوطني',
    accent: Color(0xFF1D4ED8),
    accentDark: Color(0xFF60A5FA),
    icon: PhosphorIconsDuotone.bank,
    iconFill: PhosphorIconsFill.bank,
    slug: 'ministry',
  ),
  companies(
    title: 'تطبيق الشركات',
    tagline: 'مزوّدو خدمة الإنترنت',
    accent: Color(0xFF059669),
    accentDark: Color(0xFF34D399),
    icon: PhosphorIconsDuotone.buildings,
    iconFill: PhosphorIconsFill.buildings,
    slug: 'companies',
  ),
  agents(
    title: 'تطبيق الوكلاء',
    tagline: 'وكلاء الشركات',
    accent: Color(0xFFB45309),
    accentDark: Color(0xFFFBBF24),
    icon: PhosphorIconsDuotone.briefcase,
    iconFill: PhosphorIconsFill.briefcase,
    slug: 'agents',
  ),
  subscribers(
    title: 'تطبيق المشتركين',
    tagline: 'المواطنون والمشتركون',
    accent: Color(0xFF0891B2),
    accentDark: Color(0xFF22D3EE),
    icon: PhosphorIconsDuotone.wifiHigh,
    iconFill: PhosphorIconsFill.wifiHigh,
    slug: 'subscribers',
  );

  final String title;
  final String tagline;
  final Color accent;
  final Color accentDark;
  final IconData icon;
  final IconData iconFill;
  final String slug;

  const AppBrand({
    required this.title,
    required this.tagline,
    required this.accent,
    required this.accentDark,
    required this.icon,
    required this.iconFill,
    required this.slug,
  });

  /// اللكنة المناسبة للوضع الحالي.
  Color accentFor(Brightness b) => b == Brightness.dark ? accentDark : accent;

  /// تدرّج اللكنة (للشعار والأزرار البارزة).
  List<Color> gradient(Brightness b) => this == AppBrand.agents
      ? const [Color(0xFFFBBF24), Color(0xFFD97706)]
      : [accentFor(b), Color.lerp(accentFor(b), Colors.black, 0.25)!];

  /// الأنظمة الأربعة التي تعرضها البوّابة (بلا البوّابة نفسها).
  static List<AppBrand> get systems => const [ministry, companies, agents, subscribers];
}
