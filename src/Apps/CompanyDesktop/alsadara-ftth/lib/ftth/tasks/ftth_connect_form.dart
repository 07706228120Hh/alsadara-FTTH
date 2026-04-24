import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../services/ftth_connect_service.dart';

/// فورم تفاصيل المهمة + توصيل المشترك
class FtthConnectForm extends StatefulWidget {
  /// بيانات المهمة من قائمة المهام (تحتوي على self.id, zone, customer, etc.)
  final Map<String, dynamic> task;

  const FtthConnectForm({super.key, required this.task});

  @override
  State<FtthConnectForm> createState() => _FtthConnectFormState();
}

class _FtthConnectFormState extends State<FtthConnectForm> {
  final _service = FtthConnectService.instance;
  final _formKey = GlobalKey<FormState>();

  // ─── responsive helpers ───
  bool get _isPhone => MediaQuery.of(context).size.width < 500;
  double _fs(double base) => _isPhone ? base * 0.85 : base;

  // ─── بيانات المهمة التفصيلية ───
  Map<String, dynamic>? _taskDetails;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingDetails = true;

  // ─── بيانات dropdowns ───
  List<Map<String, dynamic>> _ontVendors = [];
  List<Map<String, dynamic>> _fdts = [];
  List<Map<String, dynamic>> _fats = [];
  bool _isLoadingFdts = false;
  bool _isLoadingFats = false;

  // ─── قيم الفورم ───
  String? _selectedFdtId;
  String? _selectedFatId;
  String? _selectedOntVendorId;
  final _serialController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pointSupplyController = TextEditingController();
  final _installCodeController = TextEditingController();

  // ─── التحقق من username/password ───
  bool? _usernameValid;
  String? _usernameHint;
  bool? _passwordValid;
  String? _passwordHint;
  Timer? _usernameDebounce;
  Timer? _passwordDebounce;

  // ─── إرسال ───
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _passwordDebounce?.cancel();
    _serialController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pointSupplyController.dispose();
    _installCodeController.dispose();
    super.dispose();
  }

  String get _taskId => (widget.task['self'] as Map?)?['id'] ?? '';
  String get _zoneId =>
      (widget.task['zone'] as Map?)?['id'] ??
      (_taskDetails?['customerZone'] as Map?)?['id'] ??
      (_taskDetails?['zone'] as Map?)?['id'] ??
      '';

  Future<void> _loadAllData() async {
    // تحميل التفاصيل + ONT vendors بالتوازي
    final futures = await Future.wait([
      _service.getTaskDetails(_taskId).catchError((_) => <String, dynamic>{}),
      _service.getOntVendors().catchError((_) => <Map<String, dynamic>>[]),
      _service.getTaskComments(_taskId).catchError((_) => <Map<String, dynamic>>[]),
    ]);

    if (!mounted) return;

    setState(() {
      _taskDetails = futures[0] as Map<String, dynamic>?;
      _ontVendors = futures[1] as List<Map<String, dynamic>>;
      _comments = futures[2] as List<Map<String, dynamic>>;
      _isLoadingDetails = false;
    });

    // تحميل FDTs بعد معرفة الزون
    if (_zoneId.isNotEmpty) {
      _loadFdts();
    }
  }

  Future<void> _loadFdts() async {
    setState(() => _isLoadingFdts = true);
    try {
      final fdts = await _service.getFdts(_zoneId);
      if (!mounted) return;
      setState(() {
        _fdts = fdts;
        _isLoadingFdts = false;
        // اختيار تلقائي إذا FDT واحد فقط
        if (_fdts.length == 1) {
          _selectedFdtId = _fdts.first['id'] as String;
          _loadFats(_selectedFdtId!);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingFdts = false);
    }
  }

  Future<void> _loadFats(String fdtId) async {
    setState(() {
      _isLoadingFats = true;
      _fats = [];
      _selectedFatId = null;
    });
    try {
      final fats = await _service.getFats(fdtId);
      if (!mounted) return;
      setState(() {
        _fats = fats;
        _isLoadingFats = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingFats = false);
    }
  }

  void _onUsernameChanged(String val) {
    _usernameDebounce?.cancel();
    if (val.length < 3) {
      setState(() {
        _usernameValid = null;
        _usernameHint = null;
      });
      return;
    }
    _usernameDebounce = Timer(const Duration(milliseconds: 500), () async {
      final result = await _service.validateUsername(val);
      if (!mounted) return;
      setState(() {
        _usernameValid = result['isValid'] == true;
        final status = result['status'] as Map?;
        _usernameHint = _usernameValid == true
            ? null
            : (result['regexDescription'] as String? ??
                status?['displayValue'] as String? ??
                'صيغة غير صالحة');
      });
    });
  }

  void _onPasswordChanged(String val) {
    _passwordDebounce?.cancel();
    if (val.isEmpty) {
      setState(() {
        _passwordValid = null;
        _passwordHint = null;
      });
      return;
    }
    _passwordDebounce = Timer(const Duration(milliseconds: 500), () async {
      final result = await _service.validatePassword(val);
      if (!mounted) return;
      setState(() {
        _passwordValid = result['isValid'] == true;
        _passwordHint = _passwordValid == true
            ? null
            : (result['regexDescription'] as String? ?? 'صيغة غير صالحة');
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // تحقق إضافي
    if (_selectedFdtId == null ||
        _selectedFatId == null ||
        _selectedOntVendorId == null) {
      _showSnackBar('الرجاء اختيار FDT و FAT و نوع الجهاز', isError: true);
      return;
    }
    if (_usernameValid != true) {
      _showSnackBar('اسم المستخدم غير صالح', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await _service.connectCustomer(
      taskId: _taskId,
      deviceUsername: _usernameController.text.trim(),
      devicePassword: _passwordController.text,
      pointSupplyNumber: _pointSupplyController.text.trim(),
      deviceSerial: _serialController.text.trim(),
      fatId: _selectedFatId!,
      fdtId: _selectedFdtId!,
      ontVendorId: _selectedOntVendorId!,
      installationCode: _installCodeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      _showSnackBar('تم توصيل المشترك بنجاح!', isError: false);
      Navigator.of(context).pop(true);
    } else {
      final errorType = result['errorType'] ?? '';
      String msg = result['error'] ?? 'حدث خطأ';

      // ترجمة الأخطاء المعروفة
      if (errorType == 'InvalidInstallationCode') {
        msg = 'كود التثبيت لا يطابق كود الإعداد المسجل في النظام';
      }

      _showSnackBar(msg, isError: true);
    }
  }

  void _showSnackBar(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text('توصيل مشترك'),
          centerTitle: true,
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoadingDetails
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.all(_isPhone ? 10 : 16),
                child: Column(
                  children: [
                    _buildCustomerInfo(),
                    const SizedBox(height: 12),
                    if (_comments.isNotEmpty) ...[
                      _buildComments(),
                      const SizedBox(height: 12),
                    ],
                    _buildConnectionForm(),
                  ],
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 1: معلومات المشترك (للقراءة فقط)
  // ═══════════════════════════════════════════
  Widget _buildCustomerInfo() {
    final details = _taskDetails ?? {};
    final customer = details['customer'] as Map<String, dynamic>? ??
        widget.task['customer'] as Map<String, dynamic>? ??
        {};
    final address = customer['address'] as Map<String, dynamic>? ?? {};
    final gps = (address['gpsCoordinate'] ??
            (widget.task['gpsCoordinate'])) as Map<String, dynamic>? ??
        {};
    final zone = details['customerZone'] as Map<String, dynamic>? ??
        details['zone'] as Map<String, dynamic>? ??
        widget.task['zone'] as Map<String, dynamic>? ??
        {};

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(_isPhone ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: Colors.indigo.shade700, size: 20),
                const SizedBox(width: 8),
                Text('معلومات المشترك',
                    style:
                        TextStyle(fontSize: _fs(16), fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            _infoRow('الاسم', customer['displayValue'] ?? '-'),
            _infoRow('الهاتف', customer['primaryPhone'] ?? '-'),
            _infoRow('الزون', zone['displayValue'] ?? '-'),
            _infoRow('الحي', address['neighborhood'] ?? '-'),
            _infoRow('الشارع', '${address['street'] ?? '-'}'),
            _infoRow('المنزل', '${address['house'] ?? '-'}'),
            _infoRow('أقرب نقطة', address['nearestPoint'] ?? '-'),
            if (gps['latitude'] != null)
              _infoRow('الإحداثيات',
                  '${gps['latitude']}, ${gps['longitude']}'),
            _infoRow('الحالة', widget.task['status'] ?? '-'),
            _infoRow('تاريخ الإنشاء',
                _formatDateTime(widget.task['createdAt'] ?? '')),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: _isPhone ? 80 : 100,
            child: Text('$label:',
                style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: _fs(13),
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: _fs(13)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 2: التعليقات
  // ═══════════════════════════════════════════
  Widget _buildComments() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(_isPhone ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.comment, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Text('التعليقات (${_comments.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 16),
            ..._comments.map((c) {
              final by = c['createdBy'] as Map?;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (c['self'] as Map?)?['displayValue'] ?? '',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            '${by?['displayValue'] ?? ''} — ${_formatDateTime(c['createdAt'] ?? '')}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 3: فورم التوصيل
  // ═══════════════════════════════════════════
  Widget _buildConnectionForm() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(_isPhone ? 12 : 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cable, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text('بيانات التوصيل',
                      style:
                          TextStyle(fontSize: _fs(16), fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 20),

              // ─── FDT ───
              _buildDropdown(
                label: 'FDT',
                value: _selectedFdtId,
                items: _fdts,
                isLoading: _isLoadingFdts,
                onChanged: (val) {
                  setState(() {
                    _selectedFdtId = val;
                    _selectedFatId = null;
                    _fats = [];
                  });
                  if (val != null) _loadFats(val);
                },
              ),
              const SizedBox(height: 12),

              // ─── FAT ───
              _buildDropdown(
                label: 'FAT',
                value: _selectedFatId,
                items: _fats,
                isLoading: _isLoadingFats,
                onChanged: (val) => setState(() => _selectedFatId = val),
              ),
              const SizedBox(height: 12),

              // ─── ONT Vendor ───
              _buildDropdown(
                label: 'نوع الجهاز (ONT)',
                value: _selectedOntVendorId,
                items: _ontVendors,
                onChanged: (val) =>
                    setState(() => _selectedOntVendorId = val),
              ),
              const SizedBox(height: 12),

              // ─── Device Serial ───
              _buildTextField(
                controller: _serialController,
                label: 'سيريال الجهاز',
                icon: Icons.qr_code,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),

              // ─── Device Username ───
              _buildTextField(
                controller: _usernameController,
                label: 'اسم المستخدم (PPPoE)',
                icon: Icons.person_outline,
                onChanged: _onUsernameChanged,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                suffixIcon: _usernameValid == null
                    ? null
                    : Icon(
                        _usernameValid! ? Icons.check_circle : Icons.cancel,
                        color: _usernameValid! ? Colors.green : Colors.red,
                        size: 20,
                      ),
                helperText: _usernameHint,
                helperColor: Colors.red.shade700,
              ),
              const SizedBox(height: 12),

              // ─── Device Password ───
              _buildTextField(
                controller: _passwordController,
                label: 'كلمة المرور',
                icon: Icons.lock_outline,
                onChanged: _onPasswordChanged,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'مطلوب' : null,
                suffixIcon: _passwordValid == null
                    ? null
                    : Icon(
                        _passwordValid! ? Icons.check_circle : Icons.cancel,
                        color: _passwordValid! ? Colors.green : Colors.red,
                        size: 20,
                      ),
                helperText: _passwordHint,
                helperColor: Colors.red.shade700,
              ),
              const SizedBox(height: 12),

              // ─── Point Supply Number ───
              _buildTextField(
                controller: _pointSupplyController,
                label: 'رقم نقطة التوزيع',
                icon: Icons.electrical_services,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),

              // ─── Installation Code ───
              _buildTextField(
                controller: _installCodeController,
                label: 'كود التثبيت (Onboarding Code)',
                icon: Icons.pin,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 24),

              // ─── زر التوصيل ───
              SizedBox(
                width: double.infinity,
                height: _isPhone ? 40 : 48,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cable),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _isSubmitting ? 'جارٍ التوصيل...' : 'توصيل المشترك',
                      style: TextStyle(
                          fontSize: _fs(16), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Dropdown مشترك ───
  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        isLoading
            ? const LinearProgressIndicator()
            : DropdownButtonFormField<String>(
                value: value,
                isExpanded: true,
                decoration: InputDecoration(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                hint: Text('اختر $label'),
                items: items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item['id'] as String,
                    child: Text(item['displayValue'] as String? ?? '-',
                        style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: onChanged,
                validator: (v) => v == null ? 'مطلوب' : null,
              ),
      ],
    );
  }

  // ─── TextField مشترك ───
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? helperText,
    Color? helperColor,
  }) {
    return TextFormField(
      controller: controller,
      textDirection: TextDirection.ltr,
      keyboardType: keyboardType,
      inputFormatters: keyboardType == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
        helperText: helperText,
        helperStyle: TextStyle(color: helperColor ?? Colors.grey, fontSize: 11),
        helperMaxLines: 2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  // ─── مساعد تنسيق التاريخ ───
  String _formatDateTime(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
