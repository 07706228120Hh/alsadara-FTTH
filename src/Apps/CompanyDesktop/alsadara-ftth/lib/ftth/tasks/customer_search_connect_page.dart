import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../services/ftth_connect_service.dart';
import '../../services/pending_subscribers_service.dart';
import '../../task/add_task_api_dialog.dart';

/// Wizard: بحث → بيانات المنطقة → معلومات الجهاز → كود التثبيت → إرسال
class CustomerSearchConnectPage extends StatefulWidget {
  const CustomerSearchConnectPage({super.key});

  @override
  State<CustomerSearchConnectPage> createState() => _State();
}

class _State extends State<CustomerSearchConnectPage> {
  final _service = FtthConnectService.instance;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();

  // 4 خطوات: 0=بحث  1=منطقة  2=جهاز  3=كود
  int _step = 0;

  // بحث
  bool _isSearching = false;
  String? _searchError;

  // مشترك
  Map<String, dynamic> _customer = {};
  List<Map<String, dynamic>> _subs = [];
  Map<String, dynamic> _taskDetails = {};
  String _taskId = '';

  // منطقة
  List<Map<String, dynamic>> _fdts = [];
  List<Map<String, dynamic>> _fats = [];
  bool _isLoadingFats = false;
  String? _selFdt;
  String? _selFat;
  final _pointCtl = TextEditingController();
  final _step1Key = GlobalKey<FormState>();

  // جهاز
  List<Map<String, dynamic>> _vendors = [];
  String? _selVendor;
  final _serialCtl = TextEditingController();
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _step2Key = GlobalKey<FormState>();
  bool? _userOk;
  String? _userHint;
  bool? _passOk;
  String? _passHint;
  Timer? _userT;
  Timer? _passT;

  // كود
  final _codeCtl = TextEditingController();
  final _step3Key = GlobalKey<FormState>();
  bool _submitting = false;

  // style
  static const _bdr = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: Colors.black, width: 1.2),
  );
  static const _bdrF = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: Colors.black, width: 2),
  );

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _pointCtl.dispose();
    _serialCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    _codeCtl.dispose();
    _userT?.cancel();
    _passT?.cancel();
    super.dispose();
  }

  double _fs(double b) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return b * 0.85;
    if (w < 400) return b * 0.92;
    return b;
  }

  double get _pad {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 8;
    if (w < 400) return 10;
    return 16;
  }

  // ═══════════════════════════════════════════
  //  خطوة 0: بحث
  // ═══════════════════════════════════════════
  Future<void> _search() async {
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();
    if (phone.isEmpty && name.isEmpty) { setState(() => _searchError = 'أدخل رقم هاتف أو اسم للبحث'); return; }
    if (phone.isNotEmpty && phone.length < 5) { setState(() => _searchError = 'أدخل رقم هاتف صالح'); return; }
    if (name.isNotEmpty && name.length < 2) { setState(() => _searchError = 'أدخل حرفين على الأقل للبحث بالاسم'); return; }
    setState(() { _isSearching = true; _searchError = null; });

    try {
      final res = await _service.searchCustomers(
        phone: phone.isNotEmpty ? phone : null,
        name: name.isNotEmpty ? name : null,
      );
      if (!mounted) return;
      if (res.isEmpty) { setState(() { _isSearching = false; _searchError = 'لا يوجد مشترك بهذه البيانات'; }); return; }

      final cid = (res.first['self'] as Map?)?['id'] as String? ?? '';
      final f = await Future.wait([
        _service.getCustomerDetails(cid),
        _service.getCustomerSubscriptions(cid),
        _service.getCustomerTasks(cid),
      ]);
      if (!mounted) return;

      _customer = f[0] as Map<String, dynamic>;
      _subs = f[1] as List<Map<String, dynamic>>;
      final tasks = f[2] as List<Map<String, dynamic>>;

      if (tasks.isEmpty) { setState(() { _isSearching = false; _searchError = 'لا توجد عمليات مرتبطة بهذا المشترك'; }); return; }

      _taskId = tasks.first['id'] as String? ?? '';
      final tf = await Future.wait([_service.getTaskDetails(_taskId), _service.getOntVendors()]);
      if (!mounted) return;

      _taskDetails = tf[0] as Map<String, dynamic>;
      _vendors = tf[1] as List<Map<String, dynamic>>;

      final zid = (_taskDetails['customerZone'] as Map?)?['id'] ?? (_taskDetails['zone'] as Map?)?['id'] ?? '';
      if (zid.toString().isNotEmpty) {
        _fdts = await _service.getFdts(zid.toString());
        if (_fdts.length == 1) {
          _selFdt = _fdts.first['id'] as String;
          _fats = await _service.getFats(_selFdt!);
        }
      }

      if (!mounted) return;
      _selFat = null; _selVendor = null;
      _pointCtl.clear(); _serialCtl.clear(); _userCtl.clear(); _passCtl.clear(); _codeCtl.clear();
      _userOk = null; _passOk = null;

      // حفظ بيانات المشترك محلياً عند البحث الناجح
      final custName = _customer['fullName']?.toString() ?? _customer['name']?.toString() ?? '';
      final custPhone = _phoneController.text.trim();
      if (custPhone.isNotEmpty) {
        PendingSubscribersService.add(PendingSubscriber(
          name: custName,
          phone: custPhone,
        ));
      }

      setState(() { _isSearching = false; _step = 1; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isSearching = false; _searchError = 'فشل: $e'; });
    }
  }

  // ─── FATs ───
  Future<void> _loadFats(String id) async {
    setState(() { _isLoadingFats = true; _fats = []; _selFat = null; });
    try {
      _fats = await _service.getFats(id);
      if (!mounted) return;
      setState(() => _isLoadingFats = false);
    } catch (_) { if (mounted) setState(() => _isLoadingFats = false); }
  }

  // ─── validation ───
  void _onUserChanged(String v) {
    _userT?.cancel();
    if (v.length < 3) { setState(() { _userOk = null; _userHint = null; }); return; }
    _userT = Timer(const Duration(milliseconds: 500), () async {
      final r = await _service.validateUsername(v);
      if (!mounted) return;
      setState(() {
        _userOk = r['isValid'] == true;
        final s = r['status'] as Map?;
        _userHint = _userOk! ? null : (r['regexDescription'] as String? ?? s?['displayValue'] as String? ?? 'صيغة غير صالحة');
      });
    });
  }

  void _onPassChanged(String v) {
    _passT?.cancel();
    if (v.isEmpty) { setState(() { _passOk = null; _passHint = null; }); return; }
    _passT = Timer(const Duration(milliseconds: 500), () async {
      final r = await _service.validatePassword(v);
      if (!mounted) return;
      setState(() {
        _passOk = r['isValid'] == true;
        _passHint = _passOk! ? null : (r['regexDescription'] as String? ?? 'صيغة غير صالحة');
      });
    });
  }

  // ─── التالي ───
  void _next() {
    if (_step == 1) {
      if (!_step1Key.currentState!.validate()) return;
      if (_selFdt == null || _selFat == null) { _snack('اختر FDT و FAT', true); return; }
      setState(() => _step = 2);
    } else if (_step == 2) {
      if (!_step2Key.currentState!.validate()) return;
      if (_selVendor == null) { _snack('اختر نوع الجهاز', true); return; }
      if (_userOk != true) { _snack('اسم المستخدم غير صالح', true); return; }
      setState(() => _step = 3);
    }
  }

  // ─── إرسال ───
  Future<void> _submit() async {
    if (!_step3Key.currentState!.validate()) return;
    setState(() => _submitting = true);
    final r = await _service.connectCustomer(
      taskId: _taskId,
      deviceUsername: _userCtl.text.trim(),
      devicePassword: _passCtl.text,
      pointSupplyNumber: _pointCtl.text.trim(),
      deviceSerial: _serialCtl.text.trim(),
      fatId: _selFat!,
      fdtId: _selFdt!,
      ontVendorId: _selVendor!,
      installationCode: _codeCtl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (r['success'] == true) {
      // حفظ المشترك محلياً للاستخدام أوفلاين
      final custName = _customer['fullName']?.toString() ?? _customer['name']?.toString() ?? '';
      final custPhone = _phoneController.text.trim();
      PendingSubscribersService.add(PendingSubscriber(
        name: custName,
        phone: custPhone,
        pppoeUser: _userCtl.text.trim(),
        pppoePass: _passCtl.text,
        fbg: _selFdt ?? '',
        fat: _selFat ?? '',
      ));
      _snack('تم توصيل المشترك بنجاح!', false);

      // فتح مهمة "شراء اشتراك" تلقائياً مع كل بيانات المشترك
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final currentUser = prefs.getString('savedUsername') ?? '';

        // جلب اسم الباقة من الاشتراك إن وجد
        final subPlan = _subs.isNotEmpty
            ? (_subs.first['planName']?.toString() ?? '')
            : '';
        // استخراج رقم السرعة (35, 50, 75, 150)
        final speedMatch = RegExp(r'(\d+)').firstMatch(subPlan);
        final serviceType = speedMatch?.group(1) ?? '';

        // جمع الملاحظات من بيانات التوصيل
        final notes = StringBuffer();
        notes.writeln('PPPoE User: ${_userCtl.text.trim()}');
        notes.writeln('PPPoE Pass: ${_passCtl.text}');
        if (_serialCtl.text.trim().isNotEmpty) notes.writeln('Serial: ${_serialCtl.text.trim()}');
        if (_pointCtl.text.trim().isNotEmpty) notes.writeln('Point: ${_pointCtl.text.trim()}');

        // جلب اسم FDT و FAT الفعلي
        final fdtName = _fdts.where((f) => f['id'] == _selFdt).map((f) => f['displayValue']?.toString() ?? f['name']?.toString() ?? _selFdt).firstOrNull ?? _selFdt ?? '';
        final fatName = _fats.where((f) => f['id'] == _selFat).map((f) => f['displayValue']?.toString() ?? f['name']?.toString() ?? _selFat).firstOrNull ?? _selFat ?? '';

        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AddTaskApiDialog(
              currentUsername: currentUser,
              currentUserRole: '',
              currentUserDepartment: 'الحسابات',
              initialTaskType: 'شراء اشتراك',
              initialCustomerName: custName,
              initialCustomerPhone: custPhone,
              initialFBG: fdtName,
              initialFAT: fatName,
              initialServiceType: serviceType,
              initialNotes: notes.toString().trim(),
            ),
          );
        }
      }

      setState(() { _step = 0; _phoneController.clear(); });
    } else {
      String msg = r['error'] ?? 'حدث خطأ';
      if (r['errorType'] == 'InvalidInstallationCode') msg = 'كود التثبيت لا يطابق كود الإعداد';
      _snack(msg, true);
    }
  }

  void _snack(String m, bool e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, textDirection: TextDirection.rtl),
      backgroundColor: e ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating, duration: Duration(seconds: e ? 5 : 3),
    ));
  }

  // ═══════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final labels = ['بحث', 'المنطقة', 'الجهاز', 'التثبيت'];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text(labels[_step], style: TextStyle(fontSize: _fs(17))),
          centerTitle: true,
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_step > 0) setState(() => _step--);
              else Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (ctx, c) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(_pad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - _pad * 2),
                child: Column(
                  children: [
                    _buildSteps(labels),
                    SizedBox(height: _pad),
                    // بطاقة المشترك (تظهر في خطوات 1-3)
                    if (_step >= 1) ...[_customerBar(), SizedBox(height: _pad * 0.75)],
                    // المحتوى
                    if (_step == 0) _searchCard(),
                    if (_step == 1) _zoneCard(),
                    if (_step == 2) _deviceCard(),
                    if (_step == 3) _codeCard(),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─── Steps ───
  Widget _buildSteps(List<String> labels) {
    final fs = _fs(10);
    return Row(
      children: List.generate(4, (i) {
        final active = _step >= i;
        final cur = _step == i;
        return Expanded(child: Column(children: [
          Row(children: [
            if (i > 0) Expanded(child: Container(height: 2.5, color: active ? Colors.indigo : Colors.grey.shade300)),
            CircleAvatar(
              radius: _fs(14),
              backgroundColor: cur ? Colors.indigo : active ? Colors.indigo.shade200 : Colors.grey.shade300,
              child: Text('${i + 1}', style: TextStyle(fontSize: fs, color: active ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold)),
            ),
            if (i < 3) Expanded(child: Container(height: 2.5, color: _step > i ? Colors.indigo : Colors.grey.shade300)),
          ]),
          const SizedBox(height: 4),
          Text(labels[i], style: TextStyle(fontSize: fs, color: cur ? Colors.indigo : Colors.grey.shade500, fontWeight: cur ? FontWeight.bold : FontWeight.normal)),
        ]));
      }),
    );
  }

  // ─── بطاقة المشترك المختصرة ───
  Widget _customerBar() {
    final self = _customer['self'] as Map? ?? {};
    final contact = _customer['primaryContact'] as Map? ?? {};
    final name = self['displayValue'] ?? '-';
    final phone = contact['mobile'] as String? ?? '';
    String zone = '-'; String sub = '-';
    if (_subs.isNotEmpty) {
      zone = (_subs.first['zone'] as Map?)?['displayValue'] ?? '-';
      sub = (_subs.first['self'] as Map?)?['displayValue'] ?? '-';
    }
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.black, width: 0.5)),
      child: Padding(
        padding: EdgeInsets.all(_pad),
        child: Row(children: [
          CircleAvatar(radius: _fs(18), backgroundColor: Colors.indigo.shade50, child: Icon(Icons.person, size: _fs(20), color: Colors.indigo.shade700)),
          SizedBox(width: _pad * 0.6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: _fs(13), fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$phone  •  $zone  •  $sub', style: TextStyle(fontSize: _fs(11), color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  خطوة 0: بحث
  // ═══════════════════════════════════════════
  Widget _searchCard() {
    return _card(child: Column(children: [
      Icon(Icons.person_search, size: _fs(48), color: Colors.indigo.shade200),
      SizedBox(height: _pad * 0.75),
      Text('بحث عن مشترك', style: TextStyle(fontSize: _fs(15), fontWeight: FontWeight.bold)),
      SizedBox(height: _pad),
      TextField(
        controller: _phoneController,
        textDirection: TextDirection.ltr, textAlign: TextAlign.center,
        keyboardType: TextInputType.phone,
        style: TextStyle(fontSize: _fs(17), letterSpacing: 1.5),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
        onSubmitted: (_) => _search(),
        decoration: _inputDeco(hint: '07XXXXXXXXX', icon: Icons.phone),
      ),
      SizedBox(height: _pad * 0.75),
      TextField(
        controller: _nameController,
        textDirection: TextDirection.rtl, textAlign: TextAlign.center,
        keyboardType: TextInputType.name,
        style: TextStyle(fontSize: _fs(15)),
        onSubmitted: (_) => _search(),
        decoration: _inputDeco(hint: 'اسم المشترك', icon: Icons.person),
      ),
      if (_searchError != null) ...[
        const SizedBox(height: 8),
        Text(_searchError!, style: TextStyle(color: Colors.red.shade700, fontSize: _fs(12))),
      ],
      SizedBox(height: _pad),
      _actionBtn(
        label: _isSearching ? 'جارٍ البحث...' : 'بحث',
        icon: Icons.search,
        loading: _isSearching,
        onPressed: _isSearching ? null : _search,
      ),
    ]));
  }

  // ═══════════════════════════════════════════
  //  خطوة 1: بيانات المنطقة
  // ═══════════════════════════════════════════
  Widget _zoneCard() {
    final fs = _fs(13);
    final gap = SizedBox(height: _pad * 0.75);
    return _card(child: Form(key: _step1Key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(Icons.location_on, 'بيانات المنطقة', Colors.teal.shade700),
      gap,
      _dd('FDT', _selFdt, _fdts, fs, (v) { setState(() { _selFdt = v; _selFat = null; _fats = []; }); if (v != null) _loadFats(v); }),
      gap,
      _searchableFat(fs),
      gap,
      _tf(_pointCtl, 'رقم نقطة التوزيع', Icons.electrical_services, fs, isNum: true),
      SizedBox(height: _pad * 1.5),
      _actionBtn(label: 'التالي', icon: Icons.arrow_back, onPressed: _next),
    ])));
  }

  // ═══════════════════════════════════════════
  //  خطوة 2: معلومات الجهاز
  // ═══════════════════════════════════════════
  Widget _deviceCard() {
    final fs = _fs(13);
    final gap = SizedBox(height: _pad * 0.75);
    return _card(child: Form(key: _step2Key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(Icons.router, 'معلومات الجهاز', Colors.indigo.shade700),
      gap,
      _dd('نوع الجهاز (ONT)', _selVendor, _vendors, fs, (v) => setState(() => _selVendor = v)),
      gap,
      _tf(_serialCtl, 'سيريال الجهاز', Icons.qr_code, fs),
      gap,
      _tf(_userCtl, 'اسم المستخدم (PPPoE)', Icons.person_outline, fs,
        onChanged: _onUserChanged,
        suffix: _userOk == null ? null : Icon(_userOk! ? Icons.check_circle : Icons.cancel, color: _userOk! ? Colors.green : Colors.red, size: 18),
        helper: _userHint),
      gap,
      _tf(_passCtl, 'كلمة المرور', Icons.lock_outline, fs,
        onChanged: _onPassChanged,
        suffix: _passOk == null ? null : Icon(_passOk! ? Icons.check_circle : Icons.cancel, color: _passOk! ? Colors.green : Colors.red, size: 18),
        helper: _passHint),
      SizedBox(height: _pad * 1.5),
      _actionBtn(label: 'التالي', icon: Icons.arrow_back, onPressed: _next),
    ])));
  }

  // ═══════════════════════════════════════════
  //  خطوة 3: كود التثبيت + إرسال
  // ═══════════════════════════════════════════
  Widget _codeCard() {
    final fs = _fs(13);
    return _card(child: Form(key: _step3Key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(Icons.vpn_key, 'كود التثبيت', Colors.orange.shade800),
      SizedBox(height: _pad * 0.75),
      _tf(_codeCtl, 'كود التثبيت (Onboarding Code)', Icons.pin, fs, isNum: true),
      SizedBox(height: _pad * 2),
      _actionBtn(
        label: _submitting ? 'جارٍ التوصيل...' : 'توصيل المشترك',
        icon: Icons.cable,
        loading: _submitting,
        onPressed: _submitting ? null : _submit,
        color: Colors.green.shade700,
      ),
    ])));
  }

  // ═══════════════════════════════════════════
  //  مكونات مشتركة
  // ═══════════════════════════════════════════

  Widget _card({required Widget child}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Colors.black, width: 0.5)),
      elevation: 2,
      child: Padding(padding: EdgeInsets.all(_pad + 2), child: child),
    );
  }

  Widget _header(IconData icon, String title, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: _fs(18)),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: _fs(15), fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _actionBtn({required String label, required IconData icon, VoidCallback? onPressed, bool loading = false, Color? color}) {
    return SizedBox(
      width: double.infinity,
      height: _fs(48),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        icon: loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: _fs(20)),
        label: Text(label, style: TextStyle(fontSize: _fs(15), fontWeight: FontWeight.bold)),
      ),
    );
  }

  InputDecoration _inputDeco({String? hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      contentPadding: EdgeInsets.symmetric(horizontal: _pad, vertical: 12),
      border: _bdr, enabledBorder: _bdr, focusedBorder: _bdrF,
      filled: true, fillColor: Colors.white,
    );
  }

  Widget _dd(String label, String? value, List<Map<String, dynamic>> items, double fs, ValueChanged<String?> onChanged, {bool loading = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      loading
          ? const LinearProgressIndicator()
          : DropdownButtonFormField<String>(
              value: value, isExpanded: true,
              style: TextStyle(fontSize: fs, color: Colors.black),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: _bdr, enabledBorder: _bdr, focusedBorder: _bdrF,
                filled: true, fillColor: Colors.white,
              ),
              hint: Text('اختر $label', style: TextStyle(fontSize: fs)),
              items: items.map((m) => DropdownMenuItem(value: m['id'] as String, child: Text(m['displayValue'] as String? ?? '-', style: TextStyle(fontSize: fs)))).toList(),
              onChanged: onChanged,
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
    ]);
  }

  Widget _searchableFat(double fs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('FAT', style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      _isLoadingFats
          ? const LinearProgressIndicator()
          : Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (text) {
                if (_fats.isEmpty) return const Iterable.empty();
                if (text.text.isEmpty) return _fats;
                final q = text.text.toLowerCase();
                return _fats.where((f) => (f['displayValue'] as String? ?? '').toLowerCase().contains(q));
              },
              displayStringForOption: (o) => o['displayValue'] as String? ?? '',
              initialValue: _selFat != null
                  ? TextEditingValue(text: _fats.where((f) => f['id'] == _selFat).map((f) => f['displayValue'] as String? ?? '').firstOrNull ?? '')
                  : TextEditingValue.empty,
              onSelected: (o) => setState(() => _selFat = o['id'] as String),
              fieldViewBuilder: (ctx, ctl, fn, onSubmit) {
                return TextFormField(
                  controller: ctl, focusNode: fn, textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: fs),
                  decoration: InputDecoration(
                    hintText: 'ابحث أو اختر FAT...',
                    hintStyle: TextStyle(fontSize: fs),
                    prefixIcon: Icon(Icons.search, size: fs + 4),
                    suffixIcon: ctl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { ctl.clear(); setState(() => _selFat = null); })
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: _bdr, enabledBorder: _bdr, focusedBorder: _bdrF,
                    filled: true, fillColor: Colors.white,
                  ),
                  validator: (_) => _selFat == null ? 'مطلوب' : null,
                );
              },
              optionsViewBuilder: (ctx, onSelect, options) {
                return Align(
                  alignment: Alignment.topRight,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 200, maxWidth: MediaQuery.of(ctx).size.width - _pad * 4),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (_, i) {
                          final o = options.elementAt(i);
                          final name = o['displayValue'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            title: Text(name, style: TextStyle(fontSize: fs)),
                            onTap: () => onSelect(o),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
    ]);
  }

  Widget _tf(TextEditingController ctl, String label, IconData icon, double fs, {bool isNum = false, ValueChanged<String>? onChanged, Widget? suffix, String? helper}) {
    return TextFormField(
      controller: ctl, textDirection: TextDirection.ltr,
      keyboardType: isNum ? TextInputType.number : null,
      inputFormatters: isNum ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: TextStyle(fontSize: fs),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(fontSize: fs),
        prefixIcon: Icon(icon, size: fs + 4), suffixIcon: suffix,
        helperText: helper, helperStyle: TextStyle(color: Colors.red.shade700, fontSize: fs - 2), helperMaxLines: 2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _bdr, enabledBorder: _bdr, focusedBorder: _bdrF,
        filled: true, fillColor: Colors.white,
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
      onChanged: onChanged,
    );
  }
}
