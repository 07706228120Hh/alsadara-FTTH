import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web/web.dart' as web;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../config/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';

class DeliveryWithdrawalPage extends StatefulWidget {
  const DeliveryWithdrawalPage({super.key});

  @override
  State<DeliveryWithdrawalPage> createState() => _DeliveryWithdrawalPageState();
}

class _DeliveryWithdrawalPageState extends State<DeliveryWithdrawalPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _apiService = ApiService();
  final _storage = const FlutterSecureStorage();
  final _mapController = MapController();

  bool _isSubmitting = false;
  bool _submitted = false;
  bool _locating = false;
  String? _requestNumber;
  LatLng? _selectedLocation;
  static const _baghdadCenter = LatLng(33.315, 44.366);

  @override
  void initState() {
    super.initState();
    _loadSavedLocation();
  }

  Future<void> _getMyLocation() async {
    setState(() => _locating = true);
    try {
      final geo = web.window.navigator.geolocation;
      geo.getCurrentPosition(
        ((web.GeolocationPosition pos) {
          if (mounted) {
            final lat = pos.coords.latitude;
            final lng = pos.coords.longitude;
            setState(() {
              _selectedLocation = LatLng(lat.toDouble(), lng.toDouble());
              _locating = false;
            });
            _mapController.move(_selectedLocation!, 16);
          }
        }).toJS,
        ((web.GeolocationPositionError err) {
          if (mounted) {
            setState(() => _locating = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('تعذر تحديد الموقع — تأكد من تفعيل خدمة الموقع في المتصفح'),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }).toJS,
      );
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _loadSavedLocation() async {
    final lat = await _storage.read(key: 'citizen_saved_lat');
    final lng = await _storage.read(key: 'citizen_saved_lng');
    if (lat != null && lng != null) {
      final la = double.tryParse(lat);
      final ln = double.tryParse(lng);
      if (la != null && ln != null && mounted) {
        setState(() => _selectedLocation = LatLng(la, ln));
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الرجاء تحديد الموقع على الخريطة'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final citizen = context.read<AuthProvider>().citizen;
      final result = await _apiService.createDeliveryWithdrawal(
        citizenId: citizen?.id ?? '',
        amount: double.parse(_amountController.text.trim()),
        phone: citizen?.phoneNumber ?? '',
        address: citizen?.fullAddress ?? citizen?.city ?? '',
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
        notes: _notesController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitted = true;
          _requestNumber = result['requestNumber'] ?? 'DW-XXXX';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('طلب سحب ديلفري'),
          backgroundColor: Colors.orange[700],
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/master'),
          ),
        ),
        body: _submitted ? _buildSuccessView() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccessView() {
    final citizen = context.read<AuthProvider>().citizen;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
              child: Icon(Icons.check_circle, color: Colors.green[700], size: 64),
            ),
            const SizedBox(height: 24),
            const Text('تم إرسال طلبك بنجاح!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Text('رقم الطلب: $_requestNumber',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800])),
            ),
            const SizedBox(height: 16),
            // ملخص الطلب
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _summaryRow('المبلغ', '${_amountController.text} د.ع'),
                  const Divider(height: 16),
                  _summaryRow('الاسم', citizen?.fullName ?? ''),
                  const Divider(height: 16),
                  _summaryRow('الهاتف', citizen?.phoneNumber ?? ''),
                  if (_selectedLocation != null) ...[
                    const Divider(height: 16),
                    _summaryRow('الموقع', '${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('سيتم التواصل معك قريباً لتأكيد الطلب والتوصيل',
              style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () => context.go('/citizen/master'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700], foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('العودة للخدمات'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildForm() {
    final citizen = context.watch<AuthProvider>().citizen;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بيانات المواطن (تلقائية)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange[50],
                    child: Icon(Icons.person, color: Colors.orange[700]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(citizen?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(citizen?.phoneNumber ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        if (citizen?.city != null)
                          Text(citizen!.city!, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('تلقائي', style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // المبلغ
            const Text('المبلغ المطلوب (د.ع)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '0',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('د.ع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange[700]!, width: 2)),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'الرجاء إدخال المبلغ';
                final amount = double.tryParse(v.trim());
                if (amount == null || amount <= 0) return 'المبلغ غير صحيح';
                return null;
              },
            ),

            const SizedBox(height: 20),

            // الخريطة
            Row(
              children: [
                const Text('حدد موقع التوصيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                // زر تحديد الموقع التلقائي
                ElevatedButton.icon(
                  onPressed: _locating ? null : _getMyLocation,
                  icon: _locating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location, size: 16),
                  label: Text(_locating ? 'جاري التحديد...' : 'موقعي الحالي', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (_selectedLocation != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700], size: 14),
                        const SizedBox(width: 4),
                        Text('تم', style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedLocation != null ? Colors.green[400]! : Colors.grey[300]!,
                  width: _selectedLocation != null ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _selectedLocation ?? _baghdadCenter,
                        initialZoom: _selectedLocation != null ? 15 : 12,
                        onTap: (tapPos, latLng) => setState(() => _selectedLocation = latLng),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                        ),
                        if (_selectedLocation != null)
                          MarkerLayer(markers: [
                            Marker(
                              point: _selectedLocation!,
                              width: 40, height: 40,
                              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                            ),
                          ]),
                      ],
                    ),
                    if (_selectedLocation == null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('اضغط على الخريطة لتحديد موقعك',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_selectedLocation != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),

            const SizedBox(height: 20),

            // ملاحظات
            const Text('ملاحظات (اختياري)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'أي تفاصيل إضافية...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange[700]!, width: 2)),
              ),
            ),

            const SizedBox(height: 24),

            // زر الإرسال
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.delivery_dining, size: 22),
                label: Text(_isSubmitting ? 'جاري الإرسال...' : 'إرسال طلب السحب',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  disabledBackgroundColor: Colors.orange[300],
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
