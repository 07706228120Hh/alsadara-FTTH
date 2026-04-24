/// صفحة تسجيل مشترك جديد — Customer Onboarding
/// 3 خطوات: المعلومات الشخصية → عنوان الاشتراك → المراجعة والتوقيع
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/auth_service.dart';
import '../../services/customer_onboarding_service.dart';
import '../../services/id_ocr_service.dart';
import '../auth/auth_error_handler.dart';

bool get _isOcrSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class CustomerOnboardingPage extends StatefulWidget {
  final String authToken;
  const CustomerOnboardingPage({super.key, required this.authToken});
  @override
  State<CustomerOnboardingPage> createState() => _CustomerOnboardingPageState();
}

class _CustomerOnboardingPageState extends State<CustomerOnboardingPage> {
  static const _primary = Color(0xFF1A237E);
  static const _accent = Color(0xFF667eea);
  static const _dark = Color(0xFF2C3E50);

  final _service = CustomerOnboardingService.instance;
  final _formKeys = List.generate(3, (_) => GlobalKey<FormState>());

  int _currentStep = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _scanning = false;

  // ═══ Lookups ═══
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _installationOptions = [];
  String? _contractHtml;

  // ═══ Step 1: المعلومات الشخصية + الهوية ═══
  final _firstName = TextEditingController();
  final _secondName = TextEditingController();
  final _thirdName = TextEditingController();
  final _fourthName = TextEditingController();
  final _familyName = TextEditingController();
  final _motherFirst = TextEditingController();
  final _motherSecond = TextEditingController();
  final _motherThird = TextEditingController(text: 'بلا');
  final _motherFourth = TextEditingController(text: 'بلا');
  final _phone = TextEditingController();
  final _idNumber = TextEditingController();
  final _familyNumber = TextEditingController();
  final _birthday = TextEditingController();
  final _placeOfIssue = TextEditingController(text: 'مديرية الجنسية والمعلومات المدنية');
  final _issuedAt = TextEditingController();
  String? _frontFileName, _backFileName, _frontFilePath, _backFilePath;
  String? _frontFileId, _backFileId, _signatureFileId;
  bool? _idValid;
  String? _idValidMsg;
  bool _validatingId = false;

  // ═══ Step 2: العنوان والاشتراك ═══
  String? _selectedZoneId;
  final _neighborhood = TextEditingController(text: '1');
  final _street = TextEditingController(text: '1');
  final _house = TextEditingController(text: '1');
  final _apartment = TextEditingController(text: '1');
  final _nearestPoint = TextEditingController(text: '1');
  final _zoneSearch = TextEditingController();
  LatLng _mapCenter = const LatLng(33.34, 44.40); // بغداد
  final _mapController = MapController();
  String? _selectedPlanName;
  String? _selectedInstallOptionId, _selectedInstallOptionName;

  // ═══ إظهار/إخفاء حقول العنوان التفصيلية ═══
  bool _showAddressDetails = false;

  // ═══ التوقيع ═══
  bool _signed = false;
  List<List<Offset>> _signatureStrokes = [];

  // ═══ OTP ═══
  bool _otpSent = false;
  String? _requestId;
  final _otpController = TextEditingController();
  bool _verifyingOtp = false;

  bool get _isPhone => MediaQuery.of(context).size.width < 500;

  bool get _isStep1Complete =>
      _idValid == true &&
      _firstName.text.trim().isNotEmpty &&
      _secondName.text.trim().isNotEmpty &&
      _thirdName.text.trim().isNotEmpty &&
      _familyName.text.trim().isNotEmpty &&
      _motherFirst.text.trim().isNotEmpty &&
      _motherSecond.text.trim().isNotEmpty &&
      _phone.text.trim().length == 11;

  void _onFieldChanged() => setState(() {}); // يُحدّث حالة زر التالي

  bool _lookupsLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _ensureTokenAndLoad();
    // استماع لتغيير كل الحقول المطلوبة
    final watched = [_firstName, _secondName, _thirdName, _familyName, _motherFirst, _motherSecond, _phone, _idNumber, _familyNumber, _placeOfIssue];
    for (final c in watched) c.addListener(_onFieldChanged);
  }

  /// تأكد من صلاحية التوكن قبل تحميل البيانات (كما في نظام FTTH)
  Future<void> _ensureTokenAndLoad() async {
    final token = await AuthService.instance.getAccessToken();
    if (token == null || token.isEmpty) {
      // فشل الحصول على توكن → معالجة 401
      if (mounted) {
        AuthErrorHandler.handle401Error(context);
      }
      return;
    }
    _loadLookups();
  }

  @override
  void dispose() {
    final watched = [_firstName, _secondName, _thirdName, _familyName, _motherFirst, _motherSecond, _phone, _idNumber, _familyNumber, _placeOfIssue];
    for (final c in watched) c.removeListener(_onFieldChanged);
    for (final c in [_firstName, _secondName, _thirdName, _fourthName, _familyName,
        _motherFirst, _motherSecond, _motherThird, _motherFourth,
        _phone, _idNumber, _familyNumber, _birthday, _placeOfIssue, _issuedAt,
        _neighborhood, _street, _house, _apartment, _nearestPoint, _zoneSearch, _otpController]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _safeFetch(Future<List<Map<String, dynamic>>> Function() f, String label) async {
    try { return await f().timeout(const Duration(seconds: 15)); }
    catch (e) { debugPrint('⚠️ $label: $e'); return []; }
  }

  Future<void> _loadLookups() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _lookupsLoadFailed = false; });

    final results = await Future.wait([
      _safeFetch(_service.getZones, 'المناطق'),
      _safeFetch(_service.getPlans, 'الخطط'),
      _safeFetch(_service.getInstallationOptions, 'خيارات التركيب'),
    ]);
    String? contract;
    try { contract = await _service.getContract().timeout(const Duration(seconds: 10)); } catch (_) {}
    if (!mounted) return;

    // إذا كل القوائم فارغة → فشل التحميل (غالباً مشكلة توكن أو شبكة)
    final allEmpty = results[0].isEmpty && results[1].isEmpty && results[2].isEmpty;

    setState(() {
      _zones = results[0]; _plans = results[1]; _installationOptions = results[2];
      _contractHtml = contract; _isLoading = false;
      _lookupsLoadFailed = allEmpty;
      if (_installationOptions.length == 1) {
        _selectedInstallOptionId = _installationOptions.first['id']?.toString();
        _selectedInstallOptionName = _installationOptions.first['displayValue']?.toString();
      }
    });
  }

  // ─── اختيار صورة هوية (أمامية/خلفية) ───
  Future<void> _pickIdPhoto({required bool isFront}) async {
    try {
      String? imagePath;
      String? fileName;

      if (_isOcrSupported) {
        // على الهاتف: نعرض خيارين (كاميرا أو معرض)
        final source = await _showImageSourceDialog();
        if (source == null) return;
        final image = await ImagePicker().pickImage(source: source, imageQuality: 90);
        if (image == null) return;
        imagePath = image.path;
        fileName = image.name;
      } else {
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png']);
        if (result == null || result.files.isEmpty || result.files.first.path == null) return;
        imagePath = result.files.first.path!;
        fileName = result.files.first.name;
      }

      setState(() {
        if (isFront) { _frontFileName = fileName; _frontFilePath = imagePath; }
        else { _backFileName = fileName; _backFilePath = imagePath; }
      });
    } catch (e) {
      if (mounted) _showSnackBar('خطأ: $e', isError: true);
    }
  }

  /// نافذة اختيار مصدر الصورة (كاميرا أو معرض)
  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Text('اختر مصدر الصورة', style: TextStyle(fontSize: _isPhone ? 15 : 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.camera_alt, color: Colors.blue.shade700)),
              title: const Text('الكاميرا', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('التقاط صورة جديدة', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.photo_library, color: Colors.green.shade700)),
              title: const Text('المعرض', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('اختيار صورة موجودة', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ])),
      )),
    );
  }

  // ─── OCR مسح الهوية — يرسل الصورتين معاً دفعة واحدة ───
  Future<void> _scanBothSides() async {
    try {
      setState(() => _scanning = true);
      final data = await IdOcrService.extractBothSides(
        frontPath: _frontFilePath,
        backPath: _backFilePath,
      );
      if (!mounted) return;
      if (data != null) {
        debugPrint('📷 OCR merged data: $data');
        int filled = 0;
        // بيانات الهوية
        if (data['idNumber'] != null) { _idNumber.text = data['idNumber']; filled++; }
        if (data['familyNumber'] != null) { _familyNumber.text = data['familyNumber']; filled++; }
        if (data['birthday'] != null) { _birthday.text = data['birthday']; filled++; }
        if (data['issuedAt'] != null) { _issuedAt.text = data['issuedAt']; filled++; }
        // مكان الإصدار: لا نستبدل القيمة الافتراضية
        // أسماء المشترك
        if (data['firstName'] != null) { _firstName.text = data['firstName']; filled++; }
        if (data['fatherName'] != null) { _secondName.text = data['fatherName']; filled++; }
        if (data['grandFatherName'] != null) { _thirdName.text = data['grandFatherName']; filled++; }
        if (data['familyName'] != null) { _familyName.text = data['familyName']; filled++; }
        // اسم الأم
        if (data['motherName'] != null) { _motherFirst.text = data['motherName']; filled++; }
        if (data['motherSecondName'] != null) { _motherSecond.text = data['motherSecondName']; filled++; }

        setState(() {});
        if (filled > 0) {
          _showSnackBar('تم قراءة $filled حقول من الهوية', isError: false);
          _tryAutoValidate();
        } else {
          debugPrint('📷 OCR raw: ${data['rawText']}');
          _showSnackBar('لم تُستخرج حقول — حاول بصور أوضح', isError: true);
        }
      } else {
        _showSnackBar('فشل قراءة الهوية — حاول بصور أوضح', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('خطأ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ─── GPS ───
  Future<void> _getGpsLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _mapCenter = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_mapCenter, 16);
    } catch (e) {
      if (mounted) _showSnackBar('فشل تحديد الموقع: $e', isError: true);
    }
  }

  // ─── التحقق من الهوية ───
  void _tryAutoValidate() {
    debugPrint('🔍 tryAutoValidate: id=${_idNumber.text.length}, fam=${_familyNumber.text.isNotEmpty}, bday=${_birthday.text.isNotEmpty}, issued=${_issuedAt.text.isNotEmpty}, place=${_placeOfIssue.text.isNotEmpty}, valid=$_idValid, validating=$_validatingId');
    if (_idNumber.text.trim().length >= 12 && _familyNumber.text.isNotEmpty && _birthday.text.isNotEmpty && _issuedAt.text.isNotEmpty && _placeOfIssue.text.isNotEmpty && _idValid != true && !_validatingId) {
      debugPrint('🔍 → التحقق التلقائي...');
      _validateNationalId();
    }
  }

  Future<void> _validateNationalId() async {
    if (_idNumber.text.trim().length < 12 || _familyNumber.text.isEmpty || _birthday.text.isEmpty || _issuedAt.text.isEmpty || _placeOfIssue.text.isEmpty) return;
    setState(() { _validatingId = true; _idValid = null; });
    _frontFileId ??= '85fb7b89-4bac-453b-b9f6-c55e21381ee7';
    _backFileId ??= '85fb7b89-4bac-453b-b9f6-c55e21381ee7';
    final result = await _service.validateNationalId(
      idNumber: _idNumber.text.trim(), familyNumber: _familyNumber.text.trim(),
      birthday: _birthday.text.trim(), placeOfIssue: _placeOfIssue.text.trim(),
      issuedAt: '${_issuedAt.text.trim()}T00:00:00.000Z',
      frontFileId: _frontFileId ?? '', backFileId: _backFileId ?? '',
    );
    if (!mounted) return;
    setState(() {
      _validatingId = false;
      _idValid = result['isValid'] == true;
      _idValidMsg = _idValid! ? 'رقم الهوية صالح' : _translateIdError(result['error'] ?? result['message'] ?? 'غير صالح');
    });
  }

  String _translateIdError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('already exists')) return 'رقم الهوية مسجل مسبقاً';
    if (m.contains('not found')) return 'رقم الهوية غير موجود';
    if (m.contains('invalid')) return 'رقم الهوية غير صالح';
    if (m.contains('validation failed')) return 'فشل التحقق — تأكد من البيانات';
    if (m.contains('must not be empty')) return 'حقول مطلوبة فارغة';
    if (m.contains('family number')) return 'رقم السجل العائلي غير صحيح';
    if (m.contains('birthday')) return 'تاريخ الميلاد غير صحيح';
    return msg;
  }

  String _formatPrice(dynamic price) {
    final n = double.tryParse(price.toString()) ?? 0;
    if (n == n.truncateToDouble()) return n.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return n.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
  }

  // ─── إنشاء file ID ───
  Future<String> _createFileId() async {
    try {
      final resp = await AuthService.instance.authenticatedRequest('POST', 'https://admin.ftth.iq/api/files',
        headers: {'Accept': 'application/json, text/plain, */*', 'Content-Type': 'application/json',
          'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f', 'X-User-Role': '0'}, body: '{}');
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = jsonDecode(resp.body);
        return data['id']?.toString() ?? '';
      }
    } catch (_) {}
    return '00000000-0000-0000-0000-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0')}';
  }

  // ─── إرسال الطلب ───
  Future<void> _submitRequest() async {
    setState(() => _isSubmitting = true);
    final fileIds = await Future.wait([_createFileId(), _createFileId(), _createFileId()]);
    _signatureFileId ??= fileIds[0]; _frontFileId = fileIds[1]; _backFileId = fileIds[2];

    final body = {
      'requestContactInfo': {
        'firstName': {'englishName': _firstName.text.trim()},
        'secondName': {'englishName': _secondName.text.trim()},
        'thirdName': {'englishName': _thirdName.text.trim()},
        'fourthName': {'englishName': _fourthName.text.trim().isEmpty ? 'بلا' : _fourthName.text.trim()},
        'familyName': {'englishName': _familyName.text.trim()},
        'motherFirstName': {'englishName': _motherFirst.text.trim()},
        'motherSecondName': {'englishName': _motherSecond.text.trim()},
        'motherThirdName': {'englishName': _motherThird.text.trim().isEmpty ? 'بلا' : _motherThird.text.trim()},
        'motherFourthName': {'englishName': _motherFourth.text.trim().isEmpty ? 'بلا' : _motherFourth.text.trim()},
        'contactInfo': [{'email': null, 'mobile': _phone.text.trim()}],
        'nationalId': {
          'officialDocument': {'frontFileId': _frontFileId, 'backFileId': _backFileId},
          'idNumber': _idNumber.text.trim(), 'placeOfIssue': _placeOfIssue.text.trim(),
          'issuedAt': '${_issuedAt.text.trim()}T00:00:00.000Z', 'idType': {'id': '0'},
          'familyNumber': _familyNumber.text.trim(), 'bookNumber': '', 'pageNumber': '',
          'birthday': _birthday.text.trim(),
        },
      },
      'subscription': {'id': null, 'planName': _selectedPlanName ?? 'FIBER 35', 'username': null, 'password': null},
      'requestAccountSiteInfo': {
        'gpsCoordinates': '${_mapCenter.latitude}, ${_mapCenter.longitude}',
        'address': _nearestPoint.text.trim(), 'appartmentNumber': _apartment.text.trim(),
        'houseNumber': _house.text.trim(), 'neighbourhoodNumber': _neighborhood.text.trim(),
        'streetNumber': _street.text.trim(), 'zoneId': _selectedZoneId ?? '',
      },
      'installationOption': {'id': _selectedInstallOptionId ?? '', 'displayValue': _selectedInstallOptionName ?? 'Option1'},
      'signatureFileId': _signatureFileId ?? '',
    };

    final result = await _service.submitOnboardingRequest(requestBody: body);
    if (!mounted) return;
    if (result['statusCode'] == 401) {
      setState(() => _isSubmitting = false);
      AuthErrorHandler.handle401Error(context);
      return;
    }
    if (result['success'] == true) {
      _requestId = result['data']?['id']?.toString();
      setState(() { _isSubmitting = false; _otpSent = true; });
      _showSnackBar('تم الإرسال! أدخل رمز OTP المرسل لـ ${_phone.text}', isError: false);
    } else {
      setState(() => _isSubmitting = false);
      _showSnackBar(result['error'] ?? 'فشل الإرسال', isError: true);
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length < 4) { _showSnackBar('أدخل رمز OTP', isError: true); return; }
    setState(() => _verifyingOtp = true);
    final result = await _service.validateOtp(phoneNumber: _phone.text.trim(), otp: _otpController.text.trim());
    if (!mounted) return;
    setState(() => _verifyingOtp = false);
    if (result['isValid'] == true) {
      _showSuccessDialog();
    } else {
      _showSnackBar('رمز OTP غير صحيح', isError: true);
    }
  }

  void _showSuccessDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 28), SizedBox(width: 10),
          Expanded(child: Text('تم تقديم الطلب بنجاح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))]),
        content: Text('تم التحقق من OTP وتقديم الطلب.\nسيتم مراجعته من قبل الإدارة.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.6)),
        actions: [ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
          onPressed: () { Navigator.pop(context); Navigator.pop(context, true); },
          child: const Text('تم'))],
      ),
    ));
  }

  void _showSnackBar(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, textDirection: TextDirection.rtl),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700, behavior: SnackBarBehavior.floating));
  }

  Future<void> _pickDate(TextEditingController c) async {
    final picked = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1920), lastDate: DateTime.now());
    if (picked != null && mounted) c.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  void _showSignatureDialog() {
    List<List<Offset>> tempStrokes = [];
    List<Offset>? currentStroke;
    final phone = _isPhone;
    final sigHeight = phone ? 150.0 : 200.0;
    showDialog(context: context, barrierDismissible: false, builder: (_) => StatefulBuilder(builder: (ctx, setDlg) {
      return Directionality(textDirection: TextDirection.rtl, child: Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: phone ? 12 : 40, vertical: phone ? 20 : 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: EdgeInsets.all(phone ? 12 : 16), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ارسم توقيعك أدناه', style: TextStyle(fontSize: phone ? 14 : 16, fontWeight: FontWeight.bold)),
          SizedBox(height: phone ? 8 : 12),
          Container(height: sigHeight, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade400)),
            child: GestureDetector(
              onPanStart: (d) { currentStroke = [d.localPosition]; setDlg(() {}); },
              onPanUpdate: (d) { currentStroke?.add(d.localPosition); setDlg(() {}); },
              onPanEnd: (_) { if (currentStroke != null && currentStroke!.length > 1) tempStrokes.add(List.from(currentStroke!)); currentStroke = null; setDlg(() {}); },
              child: CustomPaint(size: Size(double.infinity, sigHeight), painter: _SignaturePainter([...tempStrokes, if (currentStroke != null) currentStroke!])),
            )),
          SizedBox(height: phone ? 8 : 12),
          Row(children: [
            ElevatedButton(onPressed: tempStrokes.isEmpty ? null : () { setState(() { _signatureStrokes = tempStrokes; _signed = true; }); Navigator.pop(ctx); },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 16, vertical: phone ? 8 : 10)),
              child: Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: phone ? 13 : 14))),
            SizedBox(width: phone ? 6 : 8),
            OutlinedButton(onPressed: () => setDlg(() { tempStrokes.clear(); currentStroke = null; }),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: phone ? 10 : 16, vertical: phone ? 8 : 10)),
              child: Text('اعادة', style: TextStyle(fontSize: phone ? 13 : 14))),
            SizedBox(width: phone ? 6 : 8),
            OutlinedButton(onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: phone ? 10 : 16, vertical: phone ? 8 : 10)),
              child: Text('الغاء', style: TextStyle(fontSize: phone ? 13 : 14))),
          ]),
        ])),
      ));
    }));
  }

  // ═══ BUILD ═══
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final pad = w > 700 ? w * 0.12 : (_isPhone ? 10.0 : 16.0);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(title: Text('تسجيل مشترك جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _isPhone ? 16 : 20)),
        centerTitle: true, backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0),
      body: _isLoading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('جاري تحميل البيانات...')]))
          : _lookupsLoadFailed
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text('فشل تحميل البيانات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
              const SizedBox(height: 6),
              Text('تحقق من الاتصال أو أعد المحاولة', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _ensureTokenAndLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
                style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              ),
            ]))
          : _otpSent ? _buildOtpStep(pad) : Column(children: [
              _buildStepIndicator(),
              Expanded(child: SingleChildScrollView(padding: EdgeInsets.symmetric(horizontal: pad, vertical: _isPhone ? 6 : 12), child: _buildStep())),
              _buildNavButtons(pad),
            ]),
    ));
  }

  Widget _buildStepIndicator() {
    const steps = ['المعلومات الشخصية', 'عنوان الاشتراك', 'المراجعة والتوقيع'];
    const icons = [Icons.person, Icons.location_on, Icons.check_circle];
    final r = _isPhone ? 12.0 : 16.0;
    return Container(color: Colors.white, padding: EdgeInsets.symmetric(vertical: _isPhone ? 8 : 12, horizontal: _isPhone ? 4 : 8),
      child: Row(children: List.generate(3, (i) {
        final isActive = i == _currentStep; final isDone = i < _currentStep;
        final color = isDone ? Colors.green : (isActive ? _accent : Colors.grey.shade400);
        return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            if (i > 0) Expanded(child: Container(height: 2, color: i <= _currentStep ? _accent : Colors.grey.shade300)),
            CircleAvatar(radius: r, backgroundColor: color,
              child: isDone ? Icon(Icons.check, size: r, color: Colors.white) : Icon(icons[i], size: r, color: Colors.white)),
            if (i < 2) Expanded(child: Container(height: 2, color: i < _currentStep ? _accent : Colors.grey.shade300)),
          ]),
          const SizedBox(height: 3),
          Text(steps[i], style: TextStyle(fontSize: _isPhone ? 8 : 10, fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? _primary : Colors.grey.shade600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]));
      })));
  }

  Widget _buildStep() {
    switch (_currentStep) { case 0: return _buildStep1(); case 1: return _buildStep2(); case 2: return _buildStep3(); default: return const SizedBox.shrink(); }
  }

  // ═══ Step 1: المعلومات الشخصية + الهوية ═══
  Widget _buildStep1() {
    final g = _isPhone ? 8.0 : 10.0;
    return Form(key: _formKeys[0], child: Column(children: [
      // ─── صور الهوية + OCR (مدمجة) ───
      _card(icon: Icons.photo_camera, title: 'صور الهوية', children: [
        // الوجه الأمامي
        _fileBtnDel('الوجه الأمامي', _frontFileName, _scanning,
          onTap: () => _pickIdPhoto(isFront: true),
          onDelete: _frontFileName != null ? () => setState(() { _frontFileName = null; _frontFilePath = null; }) : null),
        const SizedBox(height: 8),
        // الوجه الخلفي
        _fileBtnDel('الوجه الخلفي', _backFileName, _scanning,
          onTap: () => _pickIdPhoto(isFront: false),
          onDelete: _backFileName != null ? () => setState(() { _backFileName = null; _backFilePath = null; }) : null),
        // ─── زر فحص الهوية ───
        if ((_frontFilePath != null || _backFilePath != null) && !_scanning)
          Padding(padding: const EdgeInsets.only(top: 10), child: SizedBox(
            width: double.infinity, height: _isPhone ? 36 : 42,
            child: ElevatedButton.icon(
              onPressed: _scanBothSides,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: Icon(Icons.document_scanner, size: _isPhone ? 16 : 18),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text('فحص الهوية واستخراج البيانات', style: TextStyle(fontSize: _isPhone ? 12 : 14, fontWeight: FontWeight.bold))),
            ),
          )),
        // حالة القراءة
        if (_scanning)
          Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8), Text('جاري فحص الهوية...', style: TextStyle(fontSize: _isPhone ? 11 : 12, color: Colors.teal)),
          ])),
      ]),
      SizedBox(height: g),

      // ─── بيانات الهوية ───
      _card(icon: Icons.badge, title: 'بيانات الهوية', children: [
        // رقم الهوية مع تحقق تلقائي عند 12 رقم
        TextFormField(controller: _idNumber, keyboardType: TextInputType.number, maxLength: 12,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : (v.trim().length < 12 ? 'يجب 12 رقم' : null),
          onChanged: (v) {
            if (_idValid != null && v.length != 12) setState(() => _idValid = null);
            _tryAutoValidate();
          },
          style: TextStyle(fontSize: _isPhone ? 12 : 14, color: _dark),
          decoration: InputDecoration(labelText: 'رقم الهوية (12 رقم)', labelStyle: TextStyle(fontSize: _isPhone ? 11 : 13), counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: _isPhone ? 10 : 12, vertical: _isPhone ? 8 : 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade800, width: 1.2)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2)),
            filled: true, fillColor: Colors.grey.shade50,
            suffixIcon: _validatingId
                ? Padding(padding: EdgeInsets.all(_isPhone ? 10 : 12), child: SizedBox(width: 16, height: 16, child: const CircularProgressIndicator(strokeWidth: 2)))
                : _idValid == true ? Icon(Icons.check_circle, color: Colors.green, size: _isPhone ? 18 : 22)
                : _idValid == false ? Icon(Icons.cancel, color: Colors.red, size: _isPhone ? 18 : 22)
                : null,
          ),
        ),
        if (_idValid != null) ...[
          const SizedBox(height: 4),
          Text(_idValidMsg ?? '', style: TextStyle(fontSize: _isPhone ? 10 : 11, color: _idValid! ? Colors.green.shade700 : Colors.red.shade700)),
        ],
        SizedBox(height: g),
        TextFormField(controller: _familyNumber, maxLength: 18,
          validator: (v) { if (v == null || v.trim().isEmpty) return 'مطلوب'; if (v.trim().length < 18) return 'يجب 18 خانة'; return null; },
          onChanged: (_) => _tryAutoValidate(),
          style: TextStyle(fontSize: _isPhone ? 12 : 14, color: _dark),
          decoration: InputDecoration(labelText: 'رقم السجل العائلي (18 خانة)', labelStyle: TextStyle(fontSize: _isPhone ? 11 : 13), counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: _isPhone ? 10 : 12, vertical: _isPhone ? 8 : 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade800, width: 1.2)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2)),
            filled: true, fillColor: Colors.grey.shade50)),
        SizedBox(height: g),
        _dateTf(_birthday, 'تاريخ الميلاد', req: true),
        SizedBox(height: g),
        _dateTf(_issuedAt, 'تاريخ الإصدار', req: true),
        SizedBox(height: g),
        TextFormField(controller: _placeOfIssue, validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          style: TextStyle(fontSize: _isPhone ? 12 : 14, color: _dark),
          decoration: InputDecoration(labelText: 'مكان الإصدار', labelStyle: TextStyle(fontSize: _isPhone ? 11 : 13),
            contentPadding: EdgeInsets.symmetric(horizontal: _isPhone ? 10 : 12, vertical: _isPhone ? 8 : 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade800, width: 1.2)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2)),
            filled: true, fillColor: Colors.grey.shade50,
            suffixIcon: _placeOfIssue.text.isNotEmpty ? IconButton(icon: Icon(Icons.clear, size: _isPhone ? 16 : 18), onPressed: () => setState(() => _placeOfIssue.clear())) : null,
          )),
        SizedBox(height: g),
        if (_idValid != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(
            color: _idValid! ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: _idValid! ? Colors.green : Colors.red)),
            child: Row(children: [Icon(_idValid! ? Icons.check_circle : Icons.cancel, color: _idValid! ? Colors.green : Colors.red, size: 18), const SizedBox(width: 6),
              Expanded(child: Text(_idValidMsg ?? '', style: TextStyle(fontSize: 12, color: _idValid! ? Colors.green.shade800 : Colors.red.shade800)))])),
        ],
      ]),
      SizedBox(height: g),

      // ─── الأسماء + الأم + الهاتف (تظهر فقط بعد نجاح التحقق) ───
      if (_idValid == true) ...[
        // ─── الأسماء ───
        _card(icon: Icons.person, title: 'اسم المشترك', children: [
          _isPhone
              ? Column(children: [_tf(_firstName, 'الاسم الأول', req: true), SizedBox(height: g), _tf(_secondName, 'اسم الأب', req: true), SizedBox(height: g),
                  _tf(_thirdName, 'اسم الجد', req: true), SizedBox(height: g), _tf(_fourthName, 'الاسم الرابع'), SizedBox(height: g)])
              : Column(children: [Row(children: [Expanded(child: _tf(_firstName, 'الاسم الأول', req: true)), const SizedBox(width: 12), Expanded(child: _tf(_secondName, 'اسم الأب', req: true))]),
                  SizedBox(height: g), Row(children: [Expanded(child: _tf(_thirdName, 'اسم الجد', req: true)), const SizedBox(width: 12), Expanded(child: _tf(_fourthName, 'الاسم الرابع'))]), SizedBox(height: g)]),
          _tf(_familyName, 'اسم العائلة / اللقب', req: true),
        ]),
        SizedBox(height: g),

        // ─── اسم الأم ───
        _card(icon: Icons.family_restroom, title: 'اسم الأم', children: [
          _isPhone
              ? Column(children: [_tf(_motherFirst, 'الاسم الأول', req: true), SizedBox(height: g), _tf(_motherSecond, 'اسم الأب', req: true), SizedBox(height: g),
                  _tf(_motherThird, 'اسم الجد'), SizedBox(height: g), _tf(_motherFourth, 'الاسم الرابع')])
              : Column(children: [Row(children: [Expanded(child: _tf(_motherFirst, 'الاسم الأول', req: true)), const SizedBox(width: 12), Expanded(child: _tf(_motherSecond, 'اسم الأب', req: true))]),
                  SizedBox(height: g), Row(children: [Expanded(child: _tf(_motherThird, 'اسم الجد')), const SizedBox(width: 12), Expanded(child: _tf(_motherFourth, 'الاسم الرابع'))])]),
        ]),
        SizedBox(height: g),

        // ─── الهاتف ───
        _card(icon: Icons.phone, title: 'رقم الهاتف', children: [_tfPhone(_phone, 'رقم الهاتف (07XXXXXXXXX)')]),
      ],
    ]));
  }

  // ═══ Step 2: عنوان الاشتراك ═══
  Widget _buildStep2() {
    final g = _isPhone ? 8.0 : 10.0;
    return Form(key: _formKeys[1], child: Column(children: [
      // ─── الموقع ───
      _card(icon: Icons.location_on, title: 'عنوان الاشتراك', children: [
        // خريطة
        Container(height: _isPhone ? 160 : 200, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade400)),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: _mapCenter, initialZoom: 14,
              onTap: (_, latlng) => setState(() => _mapCenter = latlng)),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.sadara.ftth'),
                MarkerLayer(markers: [Marker(point: _mapCenter, width: 40, height: 40,
                  child: const Icon(Icons.location_pin, color: Colors.red, size: 40))]),
              ]),
            Positioned(bottom: 10, left: 10, child: FloatingActionButton.small(
              onPressed: _getGpsLocation, backgroundColor: Colors.white, child: const Icon(Icons.my_location, color: Colors.blue))),
          ])),
        const SizedBox(height: 6),
        Text('موقع GPS: ${_mapCenter.latitude.toStringAsFixed(6)}, ${_mapCenter.longitude.toStringAsFixed(6)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        SizedBox(height: g),
        _zoneSearchDropdown(),
        SizedBox(height: g),
        // ─── زر إظهار/إخفاء تفاصيل العنوان ───
        InkWell(
          onTap: () => setState(() => _showAddressDetails = !_showAddressDetails),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: _isPhone ? 8 : 10),
            decoration: BoxDecoration(
              color: _showAddressDetails ? _accent.withValues(alpha: 0.08) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _showAddressDetails ? _accent.withValues(alpha: 0.4) : Colors.grey.shade300),
            ),
            child: Row(children: [
              Icon(_showAddressDetails ? Icons.expand_less : Icons.expand_more, size: _isPhone ? 18 : 20, color: _showAddressDetails ? _accent : Colors.grey.shade600),
              SizedBox(width: _isPhone ? 6 : 8),
              Expanded(child: Text(
                _showAddressDetails ? 'إخفاء تفاصيل العنوان' : 'تفاصيل العنوان (حي، شارع، دار، شقة)',
                style: TextStyle(fontSize: _isPhone ? 12 : 13, fontWeight: FontWeight.w500, color: _showAddressDetails ? _accent : Colors.grey.shade700),
              )),
              Text('${_neighborhood.text}/${_street.text}/${_house.text}',
                style: TextStyle(fontSize: _isPhone ? 10 : 11, color: Colors.grey.shade500)),
            ]),
          ),
        ),
        // ─── حقول العنوان التفصيلية (قابلة للطي) ───
        if (_showAddressDetails) ...[
          SizedBox(height: g),
          _tf(_nearestPoint, 'العنوان / أقرب نقطة دالة', req: true),
          SizedBox(height: g),
          _isPhone
              ? Column(children: [_tf(_neighborhood, 'حي #', req: true), SizedBox(height: g), _tf(_street, 'شارع #', req: true)])
              : Row(children: [Expanded(child: _tf(_neighborhood, 'حي #', req: true)), const SizedBox(width: 12), Expanded(child: _tf(_street, 'شارع #', req: true))]),
          SizedBox(height: g),
          _isPhone
              ? Column(children: [_tf(_house, 'رقم الدار #', req: true), SizedBox(height: g), _tf(_apartment, 'رقم الشقة (إن وجد)')])
              : Row(children: [Expanded(child: _tf(_house, 'رقم الدار #', req: true)), const SizedBox(width: 12), Expanded(child: _tf(_apartment, 'رقم الشقة (إن وجد)'))]),
        ],
      ]),
      SizedBox(height: g),

      // ─── الاشتراك ───
      _card(icon: Icons.wifi, title: 'اشتراك المشترك', children: [
        // اختيار الخطة — نستخدم planName كقيمة مع عرض السعر
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('اختر نوع الاشتراك', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedPlanName, isExpanded: true,
            validator: (v) => v == null ? 'مطلوب' : null,
            decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.grey.shade50,
              hintText: 'اختر الخطة', hintStyle: TextStyle(fontSize: _isPhone ? 11 : 13)),
            items: _plans.map((p) {
              final name = p['planName']?.toString() ?? p['displayValue']?.toString() ?? '-';
              final price = p['price'] ?? p['amount'] ?? p['planPrice'] ?? p['monthlyPrice'];
              final priceStr = price != null ? ' — ${_formatPrice(price)} دينار' : '';
              return DropdownMenuItem<String>(value: name, child: Text('$name$priceStr', style: TextStyle(fontSize: _isPhone ? 11 : 13)));
            }).toList(),
            onChanged: (v) => setState(() => _selectedPlanName = v),
          ),
        ]),
        SizedBox(height: g),
        // الإعداد والتثبيت — يظهر دائماً مثل البورتل
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الإعداد والتثبيت', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedInstallOptionId, isExpanded: true,
            decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.grey.shade50,
              hintText: 'اختر', hintStyle: TextStyle(fontSize: _isPhone ? 11 : 13)),
            items: _installationOptions.map((o) {
              final id = o['id']?.toString() ?? '';
              final name = o['displayValue']?.toString() ?? o['name']?.toString() ?? '-';
              final price = o['price'] ?? o['amount'] ?? o['cost'];
              final priceStr = price != null ? ' (${_formatPrice(price)} دينار)' : ' (0.00 دينار)';
              return DropdownMenuItem<String>(value: id, child: Text('$name$priceStr', style: TextStyle(fontSize: _isPhone ? 11 : 13)));
            }).toList(),
            onChanged: (v) { final opt = _installationOptions.firstWhere((o) => o['id']?.toString() == v, orElse: () => {});
              setState(() { _selectedInstallOptionId = v; _selectedInstallOptionName = opt['displayValue']?.toString(); }); },
          ),
        ]),
      ]),
    ]));
  }

  // ═══ Step 3: المراجعة والتوقيع ═══
  Widget _buildStep3() {
    final g = _isPhone ? 6.0 : 10.0;
    return Column(children: [
      _card(icon: Icons.person, title: 'المشترك', children: [
        _rv('الاسم', '${_firstName.text} ${_secondName.text} ${_thirdName.text} ${_fourthName.text} ${_familyName.text}'),
        _rv('اسم الأم', '${_motherFirst.text} ${_motherSecond.text}'), _rv('الهاتف', _phone.text),
      ]),
      SizedBox(height: g),
      _card(icon: Icons.badge, title: 'الهوية', children: [
        _rv('رقم الهوية', _idNumber.text), _rv('رقم العائلة', _familyNumber.text), _rv('الميلاد', _birthday.text),
      ]),
      SizedBox(height: g),
      _card(icon: Icons.location_on, title: 'العنوان', children: [
        _rv('المنطقة', _selectedZoneId ?? '-'), _rv('الحي/الشارع/الدار', '${_neighborhood.text}/${_street.text}/${_house.text}'),
        _rv('أقرب نقطة', _nearestPoint.text), _rv('GPS', '${_mapCenter.latitude.toStringAsFixed(4)}, ${_mapCenter.longitude.toStringAsFixed(4)}'),
      ]),
      SizedBox(height: g),
      _card(icon: Icons.wifi, title: 'الاشتراك', children: [_rv('الخطة', _selectedPlanName ?? '-'), _rv('الإعداد والتثبيت', _selectedInstallOptionName ?? '-')]),
      SizedBox(height: g),
      // ─── التوقيع ───
      _card(icon: Icons.draw, title: 'التوقيع على العقد', children: [
        if (_contractHtml != null) ...[
          Container(height: _isPhone ? 70 : 100, width: double.infinity, padding: EdgeInsets.all(_isPhone ? 6 : 8),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
            child: SingleChildScrollView(child: Text(_contractHtml!.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
              style: TextStyle(fontSize: _isPhone ? 8 : 9, color: Colors.grey.shade700, height: 1.4), textDirection: TextDirection.ltr))),
          const SizedBox(height: 8),
        ],
        if (_signed)
          Container(padding: EdgeInsets.all(_isPhone ? 8 : 10), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green)),
            child: Row(children: [Icon(Icons.check_circle, color: Colors.green, size: _isPhone ? 18 : 20), const SizedBox(width: 8),
              Expanded(child: Text('تم التوقيع', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: _isPhone ? 13 : 14))),
              TextButton(onPressed: () => setState(() { _signed = false; _signatureStrokes = []; }), child: Text('إعادة', style: TextStyle(fontSize: _isPhone ? 11 : 12)))]))
        else
          SizedBox(width: double.infinity, height: _isPhone ? 36 : 40, child: ElevatedButton.icon(
            onPressed: _showSignatureDialog,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            icon: Icon(Icons.draw, size: _isPhone ? 16 : 18), label: Text('انقر هنا للتوقيع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _isPhone ? 13 : 14)))),
        if (!_signed) Padding(padding: const EdgeInsets.only(top: 4), child: Text('يجب التوقيع قبل الإرسال', style: TextStyle(fontSize: _isPhone ? 10 : 11, color: Colors.red.shade400))),
      ]),
    ]);
  }

  // ═══ OTP ═══
  Widget _buildOtpStep(double pad) {
    return Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad, vertical: _isPhone ? 20 : 40),
      child: _card(icon: Icons.sms, title: 'التحقق من رقم الهاتف', children: [
        Text('تم إرسال رمز OTP إلى ${_phone.text}', style: TextStyle(fontSize: _isPhone ? 12 : 14, color: Colors.grey.shade600)),
        SizedBox(height: _isPhone ? 12 : 16), _tf(_otpController, 'رمز OTP', req: true, keyboard: TextInputType.number, dir: TextDirection.ltr),
        SizedBox(height: _isPhone ? 12 : 16),
        SizedBox(width: double.infinity, height: _isPhone ? 42 : 48, child: ElevatedButton.icon(
          onPressed: _verifyingOtp ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          icon: _verifyingOtp ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
          label: Text(_verifyingOtp ? 'جاري التحقق...' : 'تأكيد OTP', style: TextStyle(fontSize: _isPhone ? 14 : 16, fontWeight: FontWeight.bold)))),
      ])));
  }

  // ═══ Navigation ═══
  Widget _buildNavButtons(double pad) {
    final vPad = _isPhone ? 10.0 : 14.0;
    return Container(color: Colors.white, padding: EdgeInsets.symmetric(horizontal: pad, vertical: _isPhone ? 8 : 10),
      child: Row(children: [
        if (_currentStep > 0)
          Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _currentStep--),
            style: OutlinedButton.styleFrom(foregroundColor: _primary, side: const BorderSide(color: _primary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: EdgeInsets.symmetric(vertical: vPad)),
            icon: Icon(Icons.arrow_forward, size: _isPhone ? 16 : 18), label: Text('السابق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _isPhone ? 13 : 14)))),
        if (_currentStep > 0) SizedBox(width: _isPhone ? 8 : 12),
        Expanded(child: ElevatedButton.icon(onPressed: _isSubmitting || (_currentStep == 0 && !_isStep1Complete) ? null : _onNext,
          style: ElevatedButton.styleFrom(backgroundColor: _currentStep == 2 ? Colors.green.shade700 : _primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: EdgeInsets.symmetric(vertical: vPad), elevation: 2),
          icon: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_currentStep == 2 ? Icons.send : Icons.arrow_back, size: _isPhone ? 16 : 18),
          label: Text(_isSubmitting ? 'جاري الإرسال...' : (_currentStep == 2 ? 'تقديم الطلب' : 'التالي'), style: TextStyle(fontSize: _isPhone ? 13 : 15, fontWeight: FontWeight.bold)))),
      ]));
  }

  void _onNext() {
    if (_currentStep < 2) {
      if (!_formKeys[_currentStep].currentState!.validate()) return;
      // في الخطوة الأولى: يجب التحقق من الهوية
      if (_currentStep == 0 && _idValid != true) {
        _showSnackBar('يجب التحقق من رقم الهوية أولاً', isError: true);
        return;
      }
      setState(() => _currentStep++);
    } else {
      if (!_signed) { _showSnackBar('يجب التوقيع على العقد', isError: true); return; }
      _submitRequest();
    }
  }

  // ═══ Reusable Widgets ═══
  Widget _card({required IconData icon, required String title, required List<Widget> children}) {
    final p = _isPhone ? 12.0 : 16.0;
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_isPhone ? 10 : 14),
        side: BorderSide(color: Colors.grey.shade800, width: 1)), elevation: 1,
      child: Padding(padding: EdgeInsets.all(p), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: Colors.indigo.shade700, size: _isPhone ? 18 : 20), const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: _isPhone ? 14 : 16, fontWeight: FontWeight.bold)))]),
        Divider(height: _isPhone ? 16 : 20), ...children,
      ])));
  }

  Widget _tf(TextEditingController c, String label, {bool req = false, TextInputType? keyboard, TextDirection? dir, bool withBla = false}) {
    final fs = _isPhone ? 12.0 : 14.0;
    final lfs = _isPhone ? 11.0 : 13.0;
    final vp = _isPhone ? 8.0 : 10.0;
    return TextFormField(controller: c, keyboardType: keyboard, textDirection: dir,
      validator: req ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null : null,
      style: TextStyle(fontSize: fs, color: _dark),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(fontSize: lfs),
        contentPadding: EdgeInsets.symmetric(horizontal: _isPhone ? 10 : 12, vertical: vp),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade800, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2)),
        filled: true, fillColor: Colors.grey.shade50,
        suffixIcon: withBla ? InkWell(onTap: () => setState(() { c.text = c.text == 'بلا' ? '' : 'بلا'; }), borderRadius: BorderRadius.circular(8),
          child: Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: c.text == 'بلا' ? _accent.withValues(alpha: 0.15) : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
            child: Text('بلا', style: TextStyle(fontSize: _isPhone ? 10 : 11, fontWeight: FontWeight.bold, color: c.text == 'بلا' ? _accent : Colors.grey.shade600)))) : null));
  }

  Widget _tfPhone(TextEditingController c, String label) {
    final fs = _isPhone ? 12.0 : 14.0;
    final lfs = _isPhone ? 11.0 : 13.0;
    return TextFormField(controller: c, keyboardType: TextInputType.phone, maxLength: 11,
      validator: (v) { if (v == null || v.trim().isEmpty) return 'مطلوب'; if (!RegExp(r'^07\d{9}$').hasMatch(v.trim())) return 'يجب أن يبدأ بـ 07 ويتكون من 11 رقم'; return null; },
      style: TextStyle(fontSize: fs, color: _dark),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(fontSize: lfs), counterText: '',
        contentPadding: EdgeInsets.symmetric(horizontal: _isPhone ? 10 : 12, vertical: _isPhone ? 8 : 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade800, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2)),
        filled: true, fillColor: Colors.grey.shade50));
  }

  // حالة التواريخ — نحفظها في state بدل متغيرات محلية
  final Map<String, int?> _dateState = {};

  Widget _dateTf(TextEditingController c, String label, {bool req = false}) {
    final dfs = _isPhone ? 11.0 : 13.0;
    final key = c.hashCode.toString();
    int? selDay = _dateState['${key}_d'];
    int? selMonth = _dateState['${key}_m'];
    int? selYear = _dateState['${key}_y'];

    // مزامنة من c.text إذا فيه قيمة (مثلاً من OCR)
    if (c.text.isNotEmpty && selYear == null) {
      final parts = c.text.split('-');
      if (parts.length == 3) {
        selYear = int.tryParse(parts[0]); selMonth = int.tryParse(parts[1]); selDay = int.tryParse(parts[2]);
        _dateState['${key}_y'] = selYear; _dateState['${key}_m'] = selMonth; _dateState['${key}_d'] = selDay;
      }
    }

    void save(int? d, int? m, int? y) {
      _dateState['${key}_d'] = d; _dateState['${key}_m'] = m; _dateState['${key}_y'] = y;
      if (d != null && m != null && y != null) {
        c.text = '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
        Future.microtask(() => _tryAutoValidate());
      }
    }

    final currentYear = DateTime.now().year;
    final dec = InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400, width: 1)),
      filled: true, fillColor: Colors.grey.shade50, isDense: true,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: _isPhone ? 11 : 12, fontWeight: FontWeight.w600)),
        if (c.text.isNotEmpty) Text(c.text, style: TextStyle(fontSize: _isPhone ? 9 : 10, color: Colors.grey.shade500)),
        SizedBox(height: _isPhone ? 3 : 4),
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<int>(
            value: selDay, isDense: true, isExpanded: true,
            decoration: dec.copyWith(labelText: 'يوم', labelStyle: TextStyle(fontSize: _isPhone ? 9 : 11)),
            items: List.generate(31, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}', style: TextStyle(fontSize: dfs)))),
            onChanged: (v) => setState(() => save(v, _dateState['${key}_m'], _dateState['${key}_y'])),
          )),
          SizedBox(width: _isPhone ? 4 : 8),
          Expanded(flex: 2, child: DropdownButtonFormField<int>(
            value: selMonth, isDense: true, isExpanded: true,
            decoration: dec.copyWith(labelText: 'شهر', labelStyle: TextStyle(fontSize: _isPhone ? 9 : 11)),
            items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}', style: TextStyle(fontSize: dfs)))),
            onChanged: (v) => setState(() => save(_dateState['${key}_d'], v, _dateState['${key}_y'])),
          )),
          SizedBox(width: _isPhone ? 4 : 8),
          Expanded(flex: 3, child: DropdownButtonFormField<int>(
            value: selYear, isDense: true, isExpanded: true,
            decoration: dec.copyWith(labelText: 'سنة', labelStyle: TextStyle(fontSize: _isPhone ? 9 : 11)),
            items: List.generate(currentYear - 1920 + 1, (i) => currentYear - i)
                .map((y) => DropdownMenuItem(value: y, child: Text('$y', style: TextStyle(fontSize: dfs)))).toList(),
            onChanged: (v) => setState(() => save(_dateState['${key}_d'], _dateState['${key}_m'], v)),
          )),
        ]),
      ]);
  }

  Widget _rv(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final fs = _isPhone ? 11.0 : 12.0;
    return Padding(padding: EdgeInsets.symmetric(vertical: _isPhone ? 2 : 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: _isPhone ? 65 : 80, child: Text('$label:', style: TextStyle(color: Colors.grey.shade600, fontSize: fs, fontWeight: FontWeight.w500))),
      Expanded(child: Text(value.trim(), style: TextStyle(fontSize: fs, fontWeight: FontWeight.w500)))]));
  }

  Widget _dropdown({required String label, required String? value, required List<Map<String, dynamic>> items,
      required String hint, required ValueChanged<String?> onChanged, String? Function(String?)? validator, String displayKey = 'displayValue'}) {
    final seen = <String>{}; final uniqueItems = <DropdownMenuItem<String>>[];
    for (final item in items) { final id = item['id']?.toString(); if (id == null || seen.contains(id)) continue; seen.add(id);
      uniqueItems.add(DropdownMenuItem(value: id, child: Text(item[displayKey]?.toString() ?? item['planName']?.toString() ?? id, style: TextStyle(fontSize: _isPhone ? 11 : 13), overflow: TextOverflow.ellipsis))); }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: _isPhone ? 11 : 13, fontWeight: FontWeight.w600)), const SizedBox(height: 4),
      DropdownButtonFormField<String>(value: value, isExpanded: true, validator: validator,
        decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.grey.shade50, hintText: hint, hintStyle: TextStyle(fontSize: _isPhone ? 11 : 13)),
        items: uniqueItems, onChanged: onChanged)]);
  }

  // ─── بحث المنطقة ───
  Widget _zoneSearchDropdown() {
    final q = _zoneSearch.text.trim().toUpperCase();
    final filtered = q.isEmpty ? _zones
        : _zones.where((z) {
            final name = (z['displayValue']?.toString() ?? z['id']?.toString() ?? '').toUpperCase();
            return name.contains(q) || name.replaceAll('FBG', '').contains(q);
          }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('المنطقة (Zone)', style: TextStyle(fontSize: _isPhone ? 11 : 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextFormField(
        controller: _zoneSearch,
        validator: (_) => _selectedZoneId == null ? 'اختر منطقة' : null,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: _isPhone ? 12 : 14, color: _dark),
        decoration: InputDecoration(
          hintText: _selectedZoneId ?? 'ابحث عن المنطقة...',
          hintStyle: TextStyle(fontSize: _isPhone ? 11 : 13, color: _selectedZoneId != null ? _dark : Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _selectedZoneId != null ? Colors.green : Colors.grey.shade800, width: 1.2)),
          filled: true, fillColor: _selectedZoneId != null ? Colors.green.shade50 : Colors.grey.shade50,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _selectedZoneId != null ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() { _selectedZoneId = null; _zoneSearch.clear(); })) : null,
        ),
      ),
      if (q.isNotEmpty && _selectedZoneId == null && filtered.isNotEmpty)
        Container(
          constraints: BoxConstraints(maxHeight: _isPhone ? 120 : 150),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))]),
          child: ListView.builder(
            shrinkWrap: true, itemCount: filtered.length > 20 ? 20 : filtered.length,
            itemBuilder: (_, i) {
              final zone = filtered[i];
              final id = zone['id']?.toString() ?? '';
              return ListTile(
                dense: true, title: Text(id, style: TextStyle(fontSize: _isPhone ? 11 : 13)),
                onTap: () => setState(() { _selectedZoneId = id; _zoneSearch.text = id; }),
              );
            },
          ),
        ),
    ]);
  }

  Widget _fileBtn(String label, String? fileName, bool uploading, VoidCallback onTap) {
    return _fileBtnDel(label, fileName, uploading, onTap: onTap);
  }

  Widget _fileBtnDel(String label, String? fileName, bool uploading, {required VoidCallback onTap, VoidCallback? onDelete}) {
    final p = _isPhone ? 8.0 : 12.0;
    final fs = _isPhone ? 11.0 : 13.0;
    return InkWell(onTap: uploading ? null : onTap, borderRadius: BorderRadius.circular(10),
      child: Container(padding: EdgeInsets.all(p), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fileName != null ? Colors.green.shade300 : Colors.grey.shade300), color: fileName != null ? Colors.green.shade50 : Colors.grey.shade50),
        child: Row(children: [
          Icon(fileName != null ? Icons.check_circle : Icons.upload_file, color: fileName != null ? Colors.green : Colors.grey, size: _isPhone ? 18 : 22),
          SizedBox(width: _isPhone ? 6 : 10),
          Expanded(child: Text(fileName ?? label, style: TextStyle(fontSize: fs, color: fileName != null ? Colors.green.shade800 : Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
          if (fileName == null && !uploading) Text('اختيار', style: TextStyle(fontSize: _isPhone ? 10 : 12, color: _accent, fontWeight: FontWeight.w600)),
          if (onDelete != null && fileName != null) IconButton(icon: Icon(Icons.close, size: _isPhone ? 16 : 18, color: Colors.red.shade400), onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ])));
  }
}

// ═══ رسام التوقيع ═══
class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = ui.Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) path.lineTo(stroke[i].dx, stroke[i].dy);
      canvas.drawPath(path, paint);
    }
  }
  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
