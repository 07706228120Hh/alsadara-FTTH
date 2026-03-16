import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/whatsapp_templates_service.dart';

/// صفحة إدارة قوالب الواتساب - تصميم فخم وعصري
class WhatsAppTemplatesPage extends StatefulWidget {
  const WhatsAppTemplatesPage({super.key});

  @override
  State<WhatsAppTemplatesPage> createState() => _WhatsAppTemplatesPageState();
}

class _WhatsAppTemplatesPageState extends State<WhatsAppTemplatesPage>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  Map<WhatsAppTemplateType, String> _templates = {};
  WhatsAppTemplateType? _editingType;
  final _editController = TextEditingController();
  late AnimationController _animController;
  TabController? _editorTabController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadTemplates();
  }

  @override
  void dispose() {
    _editController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      _templates = await WhatsAppTemplatesService.getAllTemplates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل القوالب')),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
      _animController.forward();
    }
  }

  Future<void> _saveTemplate(WhatsAppTemplateType type, String template) async {
    final success = await WhatsAppTemplatesService.saveTemplate(
      type: type,
      template: template,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'تم حفظ ${WhatsAppTemplatesService.templateNames[type]}',
                  style: GoogleFonts.cairo(),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _loadTemplates();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Text('فشل حفظ القالب', style: GoogleFonts.cairo()),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _resetTemplate(WhatsAppTemplateType type) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.restore_rounded,
                    color: Colors.orange.shade600, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                'إعادة تعيين القالب',
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'هل تريد إعادة تعيين "${WhatsAppTemplatesService.templateNames[type]}" للقالب الافتراضي؟',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text('إلغاء', style: GoogleFonts.cairo()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text('إعادة تعيين', style: GoogleFonts.cairo()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await WhatsAppTemplatesService.resetToDefault(type: type);
      _loadTemplates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('تم إعادة تعيين القالب', style: GoogleFonts.cairo()),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _openTemplateEditor(WhatsAppTemplateType type) {
    _editController.text = _templates[type] ?? '';
    setState(() => _editingType = type);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TemplateEditorSheet(
        type: type,
        initialText: _templates[type] ?? '',
        color: _getTemplateColor(type),
        icon: _getTemplateIcon(type),
        onSave: (text) async {
          await _saveTemplate(type, text);
        },
      ),
    ).then((_) {
      setState(() => _editingType = null);
    });
  }

  Color _getTemplateColor(WhatsAppTemplateType type) {
    switch (type) {
      case WhatsAppTemplateType.renewal:
        return const Color(0xFF22C55E);
      case WhatsAppTemplateType.expiringSoon:
        return const Color(0xFFF97316);
      case WhatsAppTemplateType.expired:
        return const Color(0xFFEF4444);
      case WhatsAppTemplateType.notification:
        return const Color(0xFF3B82F6);
    }
  }

  List<Color> _getTemplateGradient(WhatsAppTemplateType type) {
    switch (type) {
      case WhatsAppTemplateType.renewal:
        return [const Color(0xFF22C55E), const Color(0xFF16A34A)];
      case WhatsAppTemplateType.expiringSoon:
        return [const Color(0xFFF97316), const Color(0xFFEA580C)];
      case WhatsAppTemplateType.expired:
        return [const Color(0xFFEF4444), const Color(0xFFDC2626)];
      case WhatsAppTemplateType.notification:
        return [const Color(0xFF3B82F6), const Color(0xFF2563EB)];
    }
  }

  IconData _getTemplateIcon(WhatsAppTemplateType type) {
    switch (type) {
      case WhatsAppTemplateType.renewal:
        return Icons.check_circle_rounded;
      case WhatsAppTemplateType.expiringSoon:
        return Icons.schedule_rounded;
      case WhatsAppTemplateType.expired:
        return Icons.warning_rounded;
      case WhatsAppTemplateType.notification:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: _isLoading
            ? _buildLoadingState()
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildInfoCard(),
                          const SizedBox(height: 24),
                          ...WhatsAppTemplateType.values
                              .asMap()
                              .entries
                              .map((entry) {
                            return _buildTemplateCard(entry.value, entry.key);
                          }),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'جاري تحميل القوالب...',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF7C3AED),
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7C3AED),
                Color(0xFF9333EA),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BackgroundPatternPainter(),
                ),
              ),
              Positioned(
                bottom: 35,
                right: 20,
                left: 20,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'قوالب الرسائل',
                            style: GoogleFonts.cairo(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'تخصيص رسائل التجديد والإشعارات',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      leading: IconButton(
        icon:
            const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: const Icon(Icons.more_vert, color: Colors.white, size: 22),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) async {
              if (value == 'reset_all') {
                final confirm = await _showResetAllDialog();
                if (confirm == true) {
                  await WhatsAppTemplatesService.resetAllToDefault();
                  _loadTemplates();
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'reset_all',
                child: Row(
                  children: [
                    Icon(Icons.restore_rounded, color: Colors.red.shade600),
                    const SizedBox(width: 12),
                    Text('إعادة تعيين الكل', style: GoogleFonts.cairo()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _showResetAllDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.warning_rounded,
                    color: Colors.red.shade600, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                'إعادة تعيين الكل',
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'هل تريد إعادة تعيين جميع القوالب للقيم الافتراضية؟\nلا يمكن التراجع عن هذا الإجراء.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text('إلغاء', style: GoogleFonts.cairo()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child:
                          Text('إعادة تعيين الكل', style: GoogleFonts.cairo()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تُستخدم هذه القوالب في الإرسال الجماعي وإشعارات المشتركين',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(WhatsAppTemplateType type, int index) {
    final template = _templates[type] ?? '';
    final color = _getTemplateColor(type);
    final gradient = _getTemplateGradient(type);
    final icon = _getTemplateIcon(type);
    final name = WhatsAppTemplatesService.templateNames[type]!;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 80)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: () => _openTemplateEditor(type),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        template.length > 60
                            ? '${template.substring(0, 60)}...'
                            : template,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_rounded,
                  color: color,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// رسام الخلفية المزخرفة
class _BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      100,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.75),
      70,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.65, size.height * 0.85),
      50,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ورقة تحرير القالب مع المعاينة
class _TemplateEditorSheet extends StatefulWidget {
  final WhatsAppTemplateType type;
  final String initialText;
  final Color color;
  final IconData icon;
  final Future<void> Function(String) onSave;

  const _TemplateEditorSheet({
    required this.type,
    required this.initialText,
    required this.color,
    required this.icon,
    required this.onSave,
  });

  @override
  State<_TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends State<_TemplateEditorSheet>
    with SingleTickerProviderStateMixin {
  late TextEditingController _editController;
  late TabController _tabController;
  bool _isSaving = false;

  // بيانات عينة للمعاينة
  final Map<String, String> _sampleData = {
    '{customerName}': 'أحمد محمد',
    '{customerPhone}': '07701234567',
    '{planName}': 'باقة 50 ميجا',
    '{endDate}': '2025-04-01',
    '{days_left}': '7',
    '{operation}': 'تجديد',
    '{commitmentPeriod}': '1',
    '{totalPrice}': '25,000',
    '{currency}': 'د.ع',
    '{paymentMethod}': 'نقداً',
    '{activatedBy}': 'علي حسن',
    '{fbg}': 'FBG-001',
    '{fat}': 'FAT-002',
    '{todayDate}': '2025-03-01',
    '{todayTime}': '10:30',
    '{offer}': 'باقة 50 ميجا بسعر 20,000 د.ع فقط!',
    '{message}': 'سيكون هناك صيانة مجدولة غداً من الساعة 2 إلى 4 صباحاً.',
  };

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.initialText);
    _tabController = TabController(length: 2, vsync: this);
    _editController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _editController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _getPreviewText() {
    String text = _editController.text;
    _sampleData.forEach((key, value) {
      text = text.replaceAll(key, value);
    });
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final variables = WhatsAppTemplatesService.templateVariables[widget.type]!;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 45,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [widget.color, widget.color.withOpacity(0.8)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تعديل ${WhatsAppTemplatesService.templateNames[widget.type]}',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        WhatsAppTemplatesService
                                .templateDescriptions[widget.type] ??
                            '',
                        style: GoogleFonts.cairo(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // التبويبات
          Container(
            color: Colors.grey.shade100,
            child: TabBar(
              controller: _tabController,
              indicatorColor: widget.color,
              indicatorWeight: 3,
              labelColor: widget.color,
              unselectedLabelColor: Colors.grey.shade600,
              labelStyle:
                  GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.cairo(fontSize: 14),
              tabs: const [
                Tab(
                  icon: Icon(Icons.edit_rounded, size: 20),
                  text: 'تعديل',
                ),
                Tab(
                  icon: Icon(Icons.phone_android_rounded, size: 20),
                  text: 'معاينة',
                ),
              ],
            ),
          ),

          // المحتوى
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEditTab(variables),
                _buildPreviewTab(),
              ],
            ),
          ),

          // أزرار التحكم
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _editController.text = WhatsAppTemplatesService
                          .defaultTemplates[widget.type]!;
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('الافتراضي',
                        style: GoogleFonts.cairo(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: widget.color.withOpacity(0.5)),
                      foregroundColor: widget.color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() => _isSaving = true);
                            await widget.onSave(_editController.text);
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          },
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'جاري الحفظ...' : 'حفظ القالب',
                      style: GoogleFonts.cairo(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditTab(List<String> variables) {
    return Column(
      children: [
        // المتغيرات المتاحة
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.color.withOpacity(0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.code_rounded, color: widget.color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'المتغيرات (اضغط للإضافة):',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: variables.map((v) {
                  final description =
                      WhatsAppTemplatesService.variableDescriptions[v] ?? v;
                  return InkWell(
                    onTap: () {
                      final cursorPos = _editController.selection.baseOffset;
                      final text = _editController.text;
                      final newText = cursorPos >= 0
                          ? text.substring(0, cursorPos) +
                              v +
                              text.substring(cursorPos)
                          : text + v;
                      _editController.text = newText;
                      _editController.selection = TextSelection.collapsed(
                        offset: cursorPos >= 0
                            ? cursorPos + v.length
                            : newText.length,
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.color.withOpacity(0.15),
                            widget.color.withOpacity(0.08)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: widget.color.withOpacity(0.4)),
                      ),
                      child: Text(
                        description,
                        style: GoogleFonts.cairo(
                          color: widget.color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // محرر النص
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _editController,
              maxLines: null,
              expands: true,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'اكتب نص القالب هنا...',
                hintStyle: GoogleFonts.cairo(color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
              style: GoogleFonts.cairo(fontSize: 14, height: 1.7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTab() {
    final previewText = _getPreviewText();
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Container(
      color: const Color(0xFFECE5DD),
      child: Column(
        children: [
          // شريط واتساب العلوي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: const Color(0xFF075E54),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.person, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sampleData['{customerName}']!,
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'متصل الآن',
                        style: GoogleFonts.roboto(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.videocam,
                    color: Colors.white.withOpacity(0.9), size: 22),
                const SizedBox(width: 16),
                Icon(Icons.call,
                    color: Colors.white.withOpacity(0.9), size: 20),
                const SizedBox(width: 16),
                Icon(Icons.more_vert,
                    color: Colors.white.withOpacity(0.9), size: 22),
              ],
            ),
          ),

          // منطقة الرسائل
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'اليوم',
                        style: GoogleFonts.roboto(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // فقاعة الرسالة الخضراء
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(width: 50),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            top: 8,
                            bottom: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCF8C6),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(4),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                previewText,
                                textDirection: TextDirection.rtl,
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    timeStr,
                                    style: GoogleFonts.roboto(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.done_all,
                                    size: 14,
                                    color: Color(0xFF34B7F1),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // شريط الإدخال السفلي (للمظهر فقط)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: const Color(0xFFF0F0F0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.emoji_emotions_outlined,
                      color: Colors.grey.shade500, size: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      'اكتب رسالة',
                      style: GoogleFonts.roboto(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00A884),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
