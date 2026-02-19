import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/agent_auth_provider.dart';

/// صفحة تفعيل مشترك جديد - تصميم احترافي متجاوب
class ActivateSubscriberPage extends StatefulWidget {
  const ActivateSubscriberPage({super.key});

  @override
  State<ActivateSubscriberPage> createState() => _ActivateSubscriberPageState();
}

class _ActivateSubscriberPageState extends State<ActivateSubscriberPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  bool _showResult = false;

  // بيانات الزبون
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final _notesController = TextEditingController();

  // الباقات من API
  List<Map<String, dynamic>> _plans = [];
  bool _isLoadingPlans = true;
  String? _plansError;
  Map<String, dynamic>? _selectedPlan;
  int? _selectedDuration;

  // خيارات المدة
  static const List<Map<String, dynamic>> _durations = [
    {'value': 1, 'label': 'شهر واحد'},
    {'value': 2, 'label': 'شهران'},
    {'value': 3, 'label': '3 أشهر'},
    {'value': 6, 'label': '6 أشهر'},
  ];

  // نتيجة الإنشاء
  Map<String, dynamic>? _createdRequest;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  /// مساعد لقراءة حقل من Map يدعم PascalCase و camelCase
  dynamic _get(Map<String, dynamic> m, String key) {
    return m[key] ?? m[key[0].toUpperCase() + key.substring(1)];
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
    _loadPlans();
  }

  /// تحميل الباقات من API
  Future<void> _loadPlans() async {
    try {
      final agentAuth = context.read<AgentAuthProvider>();
      final plans = await agentAuth.agentApi.getInternetPlans();
      if (mounted) {
        setState(() {
          _plans = plans;
          _isLoadingPlans = false;
          _plansError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPlans = false;
          _plansError = 'فشل تحميل الباقات: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isDesktop => MediaQuery.of(context).size.width >= 768;

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPlan == null || _selectedDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار الباقة والمدة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final agentAuth = context.read<AgentAuthProvider>();
      final planId = _get(_selectedPlan!, 'id') ?? _get(_selectedPlan!, 'Id');
      final result = await agentAuth.agentApi.createServiceRequest(
        serviceId: 9,
        operationTypeId: 8,
        internetPlanId: planId?.toString(),
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        address:
            '${_cityController.text.trim()} - ${_areaController.text.trim()}',
        city: _cityController.text.trim(),
        area: _areaController.text.trim(),
        subscriptionDuration: _selectedDuration,
        notes: _buildNotesWithDetails(),
      );

      setState(() {
        _createdRequest = result['data'] ?? result;
        _isSubmitting = false;
        _showResult = true;
      });
      _animController.reset();
      _animController.forward();
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _buildNotesWithDetails() {
    final durationLabel = _durations.firstWhere(
      (d) => d['value'] == _selectedDuration,
    )['label'];
    final planName =
        _get(_selectedPlan!, 'nameAr') ??
        _get(_selectedPlan!, 'name') ??
        'غير محدد';
    final parts = <String>['الباقة: $planName', 'مدة الاشتراك: $durationLabel'];
    if (_notesController.text.trim().isNotEmpty) {
      parts.add(_notesController.text.trim());
    }
    return parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _showResult
                    ? _isDesktop
                          ? _buildDesktopWrapper(
                              SingleChildScrollView(child: _buildResultStep()),
                            )
                          : _buildMobileWrapper(
                              SingleChildScrollView(child: _buildResultStep()),
                            )
                    : _isDesktop
                    ? _buildDesktopWrapper(_buildFormContent())
                    : _buildMobileWrapper(_buildFormContent()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================== الهيدر ========================

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        right: 16,
        left: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.go('/agent/home'),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفعيل مشترك جديد',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'إنشاء طلب اشتراك إنترنت',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_add_alt_1,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ======================== جسم الصفحة ========================

  Widget _buildDesktopWrapper(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: child,
        ),
      ),
    );
  }

  Widget _buildMobileWrapper(Widget child) {
    return Padding(padding: const EdgeInsets.all(12), child: child);
  }

  // ======================== النموذج الموحد ========================

  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: _buildCard(
                    icon: Icons.person_add_alt_1,
                    title: 'بيانات الطلب',
                    children: [
                      _buildTextField(
                        controller: _customerNameController,
                        label: 'اسم المشترك',
                        icon: Icons.person_outline,
                        hint: 'الاسم الثلاثي',
                        required: true,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'يرجى إدخال اسم المشترك'
                            : v.trim().length < 3
                            ? 'الاسم قصير جداً'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _customerPhoneController,
                        label: 'رقم الهاتف',
                        icon: Icons.phone_android,
                        hint: '07XXXXXXXXX',
                        required: true,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(locale: Locale('en')),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'يرجى إدخال رقم الهاتف';
                          }
                          final phone = v.trim();
                          if (!phone.startsWith('07')) {
                            return 'يجب أن يبدأ الرقم بـ 07';
                          }
                          if (phone.length != 11) {
                            return 'رقم الهاتف يجب أن يكون 11 رقم';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _cityController,
                              label: 'المدينة',
                              icon: Icons.location_city,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTextField(
                              controller: _areaController,
                              label: 'المنطقة',
                              icon: Icons.map_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // قائمة الباقات
                      if (_isLoadingPlans)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'جاري تحميل الباقات...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_plansError != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _plansError!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _isLoadingPlans = true;
                                    _plansError = null;
                                  });
                                  _loadPlans();
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPlan != null
                              ? (_get(_selectedPlan!, 'id') ??
                                        _get(_selectedPlan!, 'Id'))
                                    ?.toString()
                              : null,
                          decoration: InputDecoration(
                            labelText: 'الباقة *',
                            prefixIcon: const Icon(
                              Icons.wifi,
                              size: 20,
                              color: Color(0xFF666666),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FB),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF1565C0),
                                width: 1.5,
                              ),
                            ),
                          ),
                          hint: const Text(
                            'اختر الباقة',
                            style: TextStyle(fontSize: 13),
                          ),
                          isExpanded: true,
                          items: _plans.map((p) {
                            final id =
                                (_get(p, 'id') ?? _get(p, 'Id'))?.toString() ??
                                '';
                            final nameAr =
                                _get(p, 'nameAr') ?? _get(p, 'name') ?? '';
                            final speed = _get(p, 'speedMbps') ?? 0;
                            final price = _get(p, 'monthlyPrice') ?? 0;
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$nameAr ($speed Mbps)',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  Text(
                                    '${_formatPrice(price)} د.ع',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF2E7D32),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (id) {
                            final plan = _plans.firstWhere(
                              (p) =>
                                  ((_get(p, 'id') ?? _get(p, 'Id'))
                                      ?.toString()) ==
                                  id,
                              orElse: () => <String, dynamic>{},
                            );
                            setState(
                              () =>
                                  _selectedPlan = plan.isNotEmpty ? plan : null,
                            );
                          },
                        ),
                      // ملخص تكلفة الباقة المختارة
                      if (_selectedPlan != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF2E7D32).withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 18,
                                color: Color(0xFF2E7D32),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'الاشتراك الشهري: ${_formatPrice(_get(_selectedPlan!, 'monthlyPrice') ?? 0)} د.ع'
                                  '${(_get(_selectedPlan!, 'installationFee') ?? 0) > 0 ? "  |  رسم التركيب: ${_formatPrice(_get(_selectedPlan!, 'installationFee'))} د.ع" : ""}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // قائمة المدة
                      DropdownButtonFormField<int>(
                        initialValue: _selectedDuration,
                        decoration: InputDecoration(
                          labelText: 'مدة الاشتراك *',
                          prefixIcon: const Icon(
                            Icons.calendar_month,
                            size: 20,
                            color: Color(0xFF666666),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8F9FB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF1565C0),
                              width: 1.5,
                            ),
                          ),
                        ),
                        hint: const Text(
                          'اختر المدة',
                          style: TextStyle(fontSize: 13),
                        ),
                        isExpanded: true,
                        items: _durations
                            .map(
                              (d) => DropdownMenuItem<int>(
                                value: d['value'] as int,
                                child: Text(
                                  d['label'] as String,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedDuration = v),
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _notesController,
                        label: 'ملاحظات (اختياري)',
                        icon: Icons.edit_note,
                        hint: 'أي تفاصيل إضافية...',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // زر الإرسال
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _isSubmitting ||
                        _selectedPlan == null ||
                        _selectedDuration == null
                    ? null
                    : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  elevation: 2,
                  shadowColor: const Color(0xFF2E7D32).withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('جاري الإرسال...'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'تأكيد وإرسال الطلب',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ======================== النتيجة ========================

  Widget _buildResultStep() {
    if (_createdRequest == null) {
      return const Center(child: Text('خطأ في عرض النتيجة'));
    }

    final reqNum =
        _createdRequest!['requestNumber'] ??
        _createdRequest!['RequestNumber'] ??
        '';
    final status =
        (_createdRequest!['status'] ?? _createdRequest!['Status'] ?? 'Pending')
            .toString();
    final cost =
        _createdRequest!['estimatedCost'] ??
        _createdRequest!['EstimatedCost'] ??
        0;
    final serviceName =
        _createdRequest!['serviceName'] ??
        _createdRequest!['ServiceName'] ??
        '';
    final agentBalance =
        _createdRequest!['agentBalance'] ?? _createdRequest!['AgentBalance'];

    return Column(
      children: [
        const SizedBox(height: 24),

        // أيقونة النجاح
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.check, size: 50, color: Colors.white),
        ),
        const SizedBox(height: 20),

        const Text(
          'تم إنشاء الطلب بنجاح!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'سيتم مراجعة الطلب وجدولة التركيب',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 24),

        // تفاصيل الطلب
        _buildCard(
          icon: Icons.receipt_long,
          title: 'تفاصيل الطلب',
          children: [
            _detailRow('رقم الطلب', reqNum, highlight: true),
            _detailRow('الخدمة', serviceName),
            _detailRow('الحالة', _getStatusAr(status)),
            _detailRow('المشترك', _customerNameController.text),
            _detailRow('الهاتف', _customerPhoneController.text),
            if (cost != null && cost > 0)
              _detailRow('التكلفة', '${_formatPrice(cost)} د.ع'),
            if (agentBalance != null)
              _detailRow('رصيد الوكيل', '${_formatPrice(agentBalance)} د.ع'),
          ],
        ),
        const SizedBox(height: 24),

        // أزرار
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/agent/home'),
                  icon: const Icon(Icons.home_outlined, size: 20),
                  label: const Text(
                    'الرئيسية',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    foregroundColor: const Color(0xFF1565C0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showResult = false;
                      _selectedPlan = null;
                      _selectedDuration = null;
                      _createdRequest = null;
                      _customerNameController.clear();
                      _customerPhoneController.clear();
                      _cityController.clear();
                      _areaController.clear();
                      _notesController.clear();
                    });
                    _animController.reset();
                    _animController.forward();
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text(
                    'طلب جديد',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _detailRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          highlight
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey[800],
                  ),
                ),
        ],
      ),
    );
  }

  // ======================== العناصر المشتركة ========================

  Widget _buildCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: const Color(0xFF1565C0), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                Text(
                  '($subtitle)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextStyle? style,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: style,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey[600]),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        labelStyle: TextStyle(fontSize: 13, color: Colors.grey[600]),
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
      ),
    );
  }

  // ======================== مساعدات ========================

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    final v = (price is int)
        ? price.toDouble()
        : (price is double)
        ? price
        : double.tryParse(price.toString()) ?? 0.0;
    if (v >= 1000) {
      return v
          .toStringAsFixed(0)
          .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
    }
    return v.toStringAsFixed(0);
  }

  String _getStatusAr(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case '0':
        return 'قيد المراجعة';
      case 'reviewing':
      case '1':
        return 'قيد المراجعة';
      case 'approved':
      case '2':
        return 'تمت الموافقة';
      case 'assigned':
      case '3':
        return 'تم التعيين';
      case 'inprogress':
      case '4':
        return 'قيد التنفيذ';
      case 'completed':
      case '5':
        return 'مكتمل';
      case 'cancelled':
      case '6':
        return 'ملغي';
      case 'rejected':
      case '7':
        return 'مرفوض';
      default:
        return status;
    }
  }
}
