/// اسم الصفحة: إنشاء تذكرة جديدة
/// وصف الصفحة: صفحة إنشاء تذكرة دعم فني جديدة عبر API admin.ftth.iq
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2026
library;

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import '../../frontend/frontend.dart';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';

class CreateTicketPage extends StatefulWidget {
  final String authToken;
  const CreateTicketPage({super.key, required this.authToken});

  @override
  State<CreateTicketPage> createState() => _CreateTicketPageState();
}

class _CreateTicketPageState extends State<CreateTicketPage> {
  static const String _baseUrl = 'https://admin.ftth.iq/api';

  /// لون المجموعة (التبليغات = التواصل).
  SdTone get _tone => SdGroup.comms.tone;

  final _formKey = GlobalKey<FormState>();
  final _summaryController = TextEditingController();
  final _detailsController = TextEditingController();
  final _zoneSearchController = TextEditingController();
  final _customerSearchController = TextEditingController();

  // تبويب: مشاكلي / مشاكل المشتركين
  int _tabIndex = 0; // 0 = مشاكلي, 1 = مشاكل المشتركين

  // التصنيفات — {id, displayValue}
  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  bool _loadingCategories = true;

  // المناطق
  List<Map<String, dynamic>> _zones = [];
  String? _selectedZoneId;
  bool _loadingZones = false;
  bool _zonesLoaded = false;

  // بحث المشتركين
  List<Map<String, dynamic>> _customers = [];
  bool _loadingCustomers = false;
  Map<String, dynamic>? _selectedCustomer; // {id, displayValue}

  // اشتراكات المشترك
  List<Map<String, dynamic>> _subscriptions = [];
  bool _loadingSubscriptions = false;
  Map<String, dynamic>? _selectedSubscription;

  // المرفقات
  final List<_AttachmentInfo> _attachments = [];
  bool _uploadingFile = false;

  bool _submitting = false;

  Map<String, String> get _extraHeaders => {
        'Accept': 'application/json, text/plain, */*',
        'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        'X-User-Role': '0',
      };

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _detailsController.dispose();
    _zoneSearchController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  // ─── جلب التصنيفات ───
  Future<void> _fetchCategories() async {
    try {
      final resp = await AuthService.instance.authenticatedRequest(
        'GET',
        '$_baseUrl/support/tickets/categories',
        headers: _extraHeaders,
      );
      if (resp.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = data is List ? data : (data['items'] ?? []);
        if (mounted) {
          setState(() {
            _categories = List<Map<String, dynamic>>.from(items);
            _loadingCategories = false;
            if (_categories.isNotEmpty) {
              _selectedCategoryId = _categories.first['id']?.toString();
            }
          });
        }
      } else {
        _useFallbackCategories();
      }
    } catch (_) {
      _useFallbackCategories();
    }
  }

  void _useFallbackCategories() {
    if (!mounted) return;
    setState(() {
      _categories = [
        {'id': '1c0bc159-150a-e111-a31b-00155d04c01d', 'displayValue': 'Service request'},
        {'id': '975e1e02-9478-49f2-b399-aef842c29ce3', 'displayValue': 'Inquiry'},
        {'id': '1b0bc159-150a-e111-a31b-00155d04c01d', 'displayValue': 'Incident'},
      ];
      _selectedCategoryId = _categories.first['id'];
      _loadingCategories = false;
    });
  }

  // ─── بحث المشتركين ───
  Future<void> _searchCustomers(String query) async {
    if (query.trim().length < 2) {
      setState(() { _customers = []; _loadingCustomers = false; });
      return;
    }
    setState(() => _loadingCustomers = true);
    try {
      final url = '$_baseUrl/customers/summary?partnersAndLOBAgnostic=false&name=${Uri.encodeComponent(query.trim())}&pageSize=20&pageNumber=1';
      final resp = await AuthService.instance.authenticatedRequest('GET', url, headers: _extraHeaders);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final items = data['items'] ?? [];
        setState(() {
          _customers = List<Map<String, dynamic>>.from(items);
          _loadingCustomers = false;
        });
      } else {
        if (mounted) setState(() => _loadingCustomers = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  // ─── جلب اشتراكات المشترك ───
  Future<void> _fetchSubscriptions(String customerId) async {
    setState(() { _loadingSubscriptions = true; _subscriptions = []; _selectedSubscription = null; });
    try {
      final url = '$_baseUrl/customers/subscriptions?customerId=$customerId';
      final resp = await AuthService.instance.authenticatedRequest('GET', url, headers: _extraHeaders);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final items = data['items'] ?? [];
        setState(() {
          _subscriptions = List<Map<String, dynamic>>.from(items);
          _loadingSubscriptions = false;
          if (_subscriptions.isNotEmpty) {
            _selectedSubscription = _subscriptions.first;
            // تعبئة المنطقة تلقائياً من الاشتراك
            final zone = _selectedSubscription!['zone'];
            if (zone is Map) {
              _selectedZoneId = zone['id']?.toString();
            }
          }
        });
      } else {
        if (mounted) setState(() => _loadingSubscriptions = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSubscriptions = false);
    }
  }

  // ─── جلب المناطق ───
  Future<void> _fetchZones(String search) async {
    setState(() => _loadingZones = true);
    try {
      final url = '$_baseUrl/locations/zones?zoneIdOrName=${Uri.encodeComponent(search)}&pageSize=30&pageNumber=1';
      final resp = await AuthService.instance.authenticatedRequest('GET', url, headers: _extraHeaders);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final items = data['items'] ?? [];
        setState(() {
          _zones = List<Map<String, dynamic>>.from(items);
          _loadingZones = false;
          _zonesLoaded = true;
        });
      } else {
        if (mounted) setState(() => _loadingZones = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingZones = false);
    }
  }

  // ─── رفع ملف ───
  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() => _uploadingFile = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/files'));
      final uploadToken = await AuthService.instance.getAccessToken() ?? '';
      request.headers.addAll({
        'Authorization': 'Bearer $uploadToken',
        'Accept': 'application/json, text/plain, */*',
        'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        'X-User-Role': '0',
      });
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      final streamResp = await request.send();
      final respBody = await streamResp.stream.bytesToString();
      if (streamResp.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
      if ((streamResp.statusCode == 200 || streamResp.statusCode == 201) && mounted) {
        final data = jsonDecode(respBody);
        final fileId = data['id']?.toString() ?? '';
        if (fileId.isNotEmpty) {
          setState(() => _attachments.add(_AttachmentInfo(id: fileId, name: file.name, size: file.size)));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم رفع "${file.name}"'), backgroundColor: SdColors.success));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع الملف: ${streamResp.statusCode}'), backgroundColor: SdColors.danger));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ'), backgroundColor: SdColors.danger));
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  // ─── إنشاء التذكرة ───
  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر نوع المشكلة'), backgroundColor: SdColors.warning));
      return;
    }
    if (_tabIndex == 1 && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر مشترك أولاً'), backgroundColor: SdColors.warning));
      return;
    }

    setState(() => _submitting = true);
    try {
      final ticketId = _generateUuid();
      final body = {
        'ticketId': ticketId,
        'categoryId': _selectedCategoryId,
        'summary': _summaryController.text.trim(),
        'details': _detailsController.text.trim(),
        'zoneId': _selectedZoneId,
        'customerId': (_tabIndex == 1 && _selectedCustomer != null) ? _selectedCustomer!['id']?.toString() : null,
        'attachmentsIds': _attachments.map((a) => a.id).toList(),
      };

      final resp = await AuthService.instance.authenticatedRequest(
        'POST',
        '$_baseUrl/support/tickets',
        headers: _extraHeaders,
        body: jsonEncode(body),
      );

      if (resp.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
      if ((resp.statusCode == 200 || resp.statusCode == 201) && mounted) {
        // جلب تفاصيل التذكرة للحصول على displayId
        String displayId = ticketId;
        try {
          final detailResp = await AuthService.instance.authenticatedRequest(
            'GET',
            '$_baseUrl/support/tickets/$ticketId',
            headers: _extraHeaders,
          );
          if (detailResp.statusCode == 200) {
            final detail = jsonDecode(detailResp.body);
            final model = detail['model'] ?? detail;
            displayId = model['displayId']?.toString() ?? ticketId;
          }
        } catch (_) {}

        // بناء نص الملخص
        final catName = _categories.where((c) => c['id']?.toString() == _selectedCategoryId).isNotEmpty
            ? _catName(_categories.firstWhere((c) => c['id']?.toString() == _selectedCategoryId))
            : '';
        final buf = StringBuffer();
        buf.writeln('معرف التذكرة: $displayId');
        buf.writeln('النوع: $catName');
        buf.writeln('الملخص: ${_summaryController.text.trim()}');
        buf.writeln('الوصف: ${_detailsController.text.trim()}');
        if (_selectedZoneId != null) buf.writeln('المنطقة: $_selectedZoneId');
        if (_tabIndex == 1 && _selectedCustomer != null) {
          buf.writeln('المشترك: ${_selectedCustomer!['displayValue'] ?? ''}');
        }
        if (_selectedSubscription != null) {
          final subSelf = _selectedSubscription!['self'];
          if (subSelf is Map) buf.writeln('الاشتراك: ${subSelf['displayValue'] ?? ''} - ${subSelf['id'] ?? ''}');
        }
        if (_attachments.isNotEmpty) buf.writeln('المرفقات: ${_attachments.length}');

        final infoText = buf.toString().trim();
        await Clipboard.setData(ClipboardData(text: infoText));

        if (mounted) _showSuccessDialog(displayId, infoText);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: ${resp.statusCode}'), backgroundColor: SdColors.danger));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ'), backgroundColor: SdColors.danger));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccessDialog(String displayId, String infoText) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SdRadius.md)),
          title: Row(children: const [
            Icon(Icons.check_circle, color: SdColors.success, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('تم إنشاء التذكرة', style: SdText.titleSm)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SdColors.infoTint,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: Border.all(color: SdColors.infoTintEdge),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('معرف التذكرة', style: SdText.caption),
                const SizedBox(height: 4),
                SelectableText(displayId, style: SdText.title.copyWith(color: SdColors.info)),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: SdColors.surfaceAlt, borderRadius: BorderRadius.circular(SdRadius.xs), border: Border.all(color: SdColors.divider)),
              child: SelectableText(infoText, style: SdText.body),
            ),
            const SizedBox(height: 8),
            Text('تم نسخ المعلومات تلقائياً', style: SdText.caption.copyWith(color: SdColors.success)),
          ]),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('نسخ'),
              style: TextButton.styleFrom(foregroundColor: SdColors.primary),
              onPressed: () => Clipboard.setData(ClipboardData(text: infoText)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: SdColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SdRadius.xs))),
              onPressed: () { Navigator.pop(context); Navigator.pop(context, true); },
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
  }

  String _catName(Map<String, dynamic> c) {
    final v = c['displayValue']?.toString() ?? c['name']?.toString() ?? '';
    switch (v.toLowerCase()) {
      case 'service request': return 'طلب خدمة';
      case 'inquiry': return 'استفسار';
      case 'incident': return 'حادثة';
      default: return v;
    }
  }

  String _catEnglish(Map<String, dynamic> c) => c['displayValue']?.toString() ?? c['name']?.toString() ?? '';

  String _generateUuid() {
    final rng = math.Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  // ─── BUILD ───
  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: SdSpace.formMax,
      appBar: const SdAppBar(title: 'التبليغ عن مشكلة'),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── التبويبات ───
            _buildTabs(),
            const SizedBox(height: SdSpace.sm),

            // ─── بحث المشترك (تاب مشاكل المشتركين) ───
            if (_tabIndex == 1) ...[
              _label('اختر مشترك', IconsaxPlusBold.profile_2user),
              const SizedBox(height: 4),
              _buildCustomerSearch(),
              const SizedBox(height: SdSpace.xs),

              // اشتراكات المشترك
              if (_selectedCustomer != null) ...[
                _label('الاشتراك / بطاقة تعريف', IconsaxPlusBold.receipt_2),
                const SizedBox(height: 4),
                _buildSubscriptionSelector(),
                const SizedBox(height: SdSpace.xs),
              ],
            ],

            // ─── نوع المشكلة ───
            _label('نوع المشكلة', IconsaxPlusBold.category),
            const SizedBox(height: 4),
            _buildCategoryDropdown(),
            const SizedBox(height: SdSpace.xs),

            // ─── ملخص المشكلة ───
            _label('ملخص المشكلة', IconsaxPlusBold.text),
            const SizedBox(height: 4),
            _field(_summaryController, 'اكتب ملخص المشكلة...', 1, (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
            const SizedBox(height: SdSpace.xs),

            // ─── وصف المشكلة ───
            _label('وصف مشكلتك', IconsaxPlusBold.document_text),
            const SizedBox(height: 4),
            _field(_detailsController, 'اكتب وصف تفصيلي...', 3, (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
            const SizedBox(height: SdSpace.xs),

            // ─── المنطقة (فقط في مشاكلي) ───
            if (_tabIndex == 0) ...[
              _label('المنطقة (اختياري)', IconsaxPlusBold.location),
              const SizedBox(height: 4),
              _buildZoneSearch(),
              const SizedBox(height: SdSpace.xs),
            ],

            // ─── المرفقات ───
            _label('المرفقات (اختياري)', IconsaxPlusBold.attach_circle),
            const SizedBox(height: 4),
            _buildAttachments(),
            const SizedBox(height: SdSpace.md),

            // ─── إرسال ───
            _buildSubmitBtn(),
            const SizedBox(height: SdSpace.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return SdFilterChips<int>(
      options: const [
        SdFilterOption(0, 'مشاكلي'),
        SdFilterOption(1, 'مشاكل المشتركين'),
      ],
      selected: _tabIndex,
      onSelected: (idx) => setState(() {
        _tabIndex = idx;
        if (idx == 0) {
          _selectedCustomer = null;
          _selectedSubscription = null;
          _customers = [];
          _subscriptions = [];
          _customerSearchController.clear();
        }
      }),
    );
  }

  Widget _label(String t, IconData ic) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Icon(ic, size: 18, color: _tone.base),
        const SizedBox(width: 8),
        Text(t, style: SdText.label),
      ]),
    );
  }

  Widget _field(TextEditingController c, String hint, int lines, String? Function(String?)? v) {
    return TextFormField(
      controller: c, maxLines: lines, validator: v,
      style: SdText.body,
      decoration: _inputDec(hint),
    );
  }

  InputDecoration _inputDec(String hint, {Widget? prefix, Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint, hintStyle: SdText.body.copyWith(color: SdColors.faint),
      filled: true, fillColor: SdColors.surface,
      prefixIcon: prefix, suffixIcon: suffix,
      border: border(SdColors.divider),
      enabledBorder: border(SdColors.divider),
      focusedBorder: border(_tone.base, 2),
      errorBorder: border(SdColors.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  // ─── بحث المشترك ───
  Widget _buildCustomerSearch() {
    return Column(children: [
      TextFormField(
        controller: _customerSearchController,
        style: SdText.body,
        decoration: _inputDec(
          'ابحث باسم المشترك...',
          prefix: const Icon(IconsaxPlusBold.search_normal_1, color: SdColors.faint, size: 20),
          suffix: _loadingCustomers
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : _selectedCustomer != null
                  ? IconButton(icon: const Icon(Icons.close, size: 20, color: SdColors.faint), onPressed: () {
                      setState(() { _selectedCustomer = null; _selectedSubscription = null; _subscriptions = []; _selectedZoneId = null; _customerSearchController.clear(); _customers = []; });
                    })
                  : null,
        ),
        onChanged: (v) => _searchCustomers(v),
      ),
      // المشترك المختار
      if (_selectedCustomer != null) ...[
        const SizedBox(height: SdSpace.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _tone.tint,
            borderRadius: BorderRadius.circular(SdRadius.sm),
            border: Border.all(color: _tone.tintEdge),
          ),
          child: Row(children: [
            Icon(IconsaxPlusBold.profile_circle, size: 20, color: _tone.base),
            const SizedBox(width: 10),
            Expanded(child: Text(_selectedCustomer!['displayValue']?.toString() ?? '', style: SdText.label.copyWith(color: _tone.text))),
            InkWell(onTap: () => setState(() { _selectedCustomer = null; _selectedSubscription = null; _subscriptions = []; _selectedZoneId = null; }),
              child: const Icon(Icons.close, size: 18, color: SdColors.faint)),
          ]),
        ),
      ],
      // قائمة نتائج البحث
      if (_customers.isNotEmpty && _selectedCustomer == null) ...[
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: SdColors.surface, borderRadius: BorderRadius.circular(SdRadius.sm),
            border: Border.all(color: SdColors.divider),
            boxShadow: SdDepth.raised(),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _customers.length > 15 ? 15 : _customers.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: SdColors.divider),
            itemBuilder: (_, i) {
              final c = _customers[i];
              return ListTile(
                dense: true,
                leading: const Icon(IconsaxPlusBold.profile_circle, size: 18, color: SdColors.faint),
                title: Text(c['displayValue']?.toString() ?? '', style: SdText.bodySm.copyWith(color: SdColors.ink)),
                onTap: () {
                  setState(() { _selectedCustomer = c; _customers = []; _customerSearchController.text = c['displayValue']?.toString() ?? ''; });
                  _fetchSubscriptions(c['id'].toString());
                },
              );
            },
          ),
        ),
      ],
    ]);
  }

  // ─── اختيار الاشتراك ───
  Widget _buildSubscriptionSelector() {
    if (_loadingSubscriptions) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
    if (_subscriptions.isEmpty) return Text('لا توجد اشتراكات', style: SdText.bodySm);
    return Container(
      decoration: BoxDecoration(color: SdColors.surface, borderRadius: BorderRadius.circular(SdRadius.sm), border: Border.all(color: SdColors.divider)),
      child: Column(
        children: _subscriptions.map((sub) {
          final selfDv = (sub['self'] as Map?)?['displayValue']?.toString() ?? '';
          final selfId = (sub['self'] as Map?)?['id']?.toString() ?? '';
          final label = '$selfDv - $selfId';
          final isSel = _selectedSubscription == sub;
          return InkWell(
            onTap: () => setState(() {
              _selectedSubscription = sub;
              final zone = sub['zone'];
              if (zone is Map) _selectedZoneId = zone['id']?.toString();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSel ? _tone.tint : null,
                border: _subscriptions.last != sub ? const Border(bottom: BorderSide(color: SdColors.divider)) : null,
              ),
              child: Row(children: [
                Icon(isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSel ? _tone.base : SdColors.faint, size: 20),
                const SizedBox(width: 10),
                Icon(IconsaxPlusBold.receipt_2, size: 18, color: isSel ? _tone.base : SdColors.faint),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: SdText.bodySm.copyWith(color: isSel ? _tone.text : SdColors.ink, fontWeight: isSel ? FontWeight.w700 : FontWeight.w600))),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── قائمة نوع المشكلة ───
  Widget _buildCategoryDropdown() {
    if (_loadingCategories) return const Center(child: CircularProgressIndicator());
    return Container(
      decoration: BoxDecoration(color: SdColors.surface, borderRadius: BorderRadius.circular(SdRadius.sm), border: Border.all(color: SdColors.divider)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedCategoryId,
          dropdownColor: SdColors.surface,
          icon: const Icon(Icons.arrow_drop_down, color: SdColors.muted),
          style: SdText.body,
          items: _categories.map((c) {
            final id = c['id']?.toString() ?? '';
            return DropdownMenuItem(value: id, child: Text(_catName(c), style: SdText.body));
          }).toList(),
          onChanged: (v) => setState(() => _selectedCategoryId = v),
        ),
      ),
    );
  }

  // ─── بحث المنطقة ───
  Widget _buildZoneSearch() {
    return Column(children: [
      TextFormField(
        controller: _zoneSearchController,
        style: SdText.body,
        decoration: _inputDec(
          'ابحث عن المنطقة (مثال: 704)...',
          prefix: const Icon(IconsaxPlusBold.search_normal_1, color: SdColors.faint, size: 20),
          suffix: _selectedZoneId != null
              ? IconButton(icon: const Icon(Icons.close, size: 20, color: SdColors.faint), onPressed: () {
                  _zoneSearchController.clear();
                  setState(() { _selectedZoneId = null; _zones = []; _zonesLoaded = false; });
                })
              : null,
        ),
        onChanged: (v) {
          if (v.length >= 2) { _fetchZones(v); } else { setState(() { _zones = []; _zonesLoaded = false; }); }
        },
      ),
      if (_selectedZoneId != null) ...[
        const SizedBox(height: SdSpace.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: _tone.tint, borderRadius: BorderRadius.circular(SdRadius.sm), border: Border.all(color: _tone.tintEdge)),
          child: Row(children: [
            Icon(IconsaxPlusBold.location, size: 16, color: _tone.base),
            const SizedBox(width: 8),
            Expanded(child: Text(_selectedZoneId!, style: SdText.label.copyWith(color: _tone.text))),
            InkWell(onTap: () => setState(() => _selectedZoneId = null), child: const Icon(Icons.close, size: 18, color: SdColors.faint)),
          ]),
        ),
      ],
      if (_zonesLoaded && _zones.isNotEmpty && _selectedZoneId == null) ...[
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(
            color: SdColors.surface, borderRadius: BorderRadius.circular(SdRadius.sm),
            border: Border.all(color: SdColors.divider),
            boxShadow: SdDepth.raised(),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _zones.length > 20 ? 20 : _zones.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: SdColors.divider),
            itemBuilder: (_, i) {
              final z = _zones[i];
              final s = z['self'];
              final dv = (s is Map) ? (s['displayValue']?.toString() ?? s['id']?.toString() ?? '') : (z['id']?.toString() ?? '');
              final zid = (s is Map) ? (s['id']?.toString() ?? '') : (z['id']?.toString() ?? '');
              return ListTile(
                dense: true,
                leading: const Icon(IconsaxPlusBold.location, size: 18, color: SdColors.faint),
                title: Text(dv, style: SdText.body),
                onTap: () => setState(() { _selectedZoneId = zid; _zoneSearchController.text = dv; _zones = []; _zonesLoaded = false; }),
              );
            },
          ),
        ),
      ],
    ]);
  }

  // ─── المرفقات ───
  Widget _buildAttachments() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SdButton(
        label: _uploadingFile ? 'جاري الرفع...' : 'رفع ملف',
        icon: IconsaxPlusBold.document_upload,
        kind: SdButtonKind.secondary,
        onPressed: _uploadingFile ? null : _pickAndUploadFile,
      ),
      if (_attachments.isNotEmpty) ...[
        const SizedBox(height: SdSpace.sm),
        ..._attachments.asMap().entries.map((e) {
          final a = e.value;
          final s = SdStatus.success.tone;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: s.tint, borderRadius: BorderRadius.circular(SdRadius.sm), border: Border.all(color: s.tintEdge)),
            child: Row(children: [
              Icon(IconsaxPlusBold.document, size: 18, color: s.base),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: SdText.bodySm.copyWith(color: SdColors.ink, fontWeight: FontWeight.w700)),
                Text(_formatFileSize(a.size), style: SdText.caption),
              ])),
              InkWell(onTap: () => setState(() => _attachments.removeAt(e.key)), child: const Icon(Icons.close, size: 18, color: SdColors.danger)),
            ]),
          );
        }),
      ],
    ]);
  }

  Widget _buildSubmitBtn() {
    return SdButton(
      label: _submitting ? 'جاري الإرسال...' : 'إرسال التذكرة',
      icon: IconsaxPlusBold.send_1,
      expand: true,
      onPressed: _submitting ? null : _submitTicket,
    );
  }
}

class _AttachmentInfo {
  final String id;
  final String name;
  final int size;
  _AttachmentInfo({required this.id, required this.name, required this.size});
}
