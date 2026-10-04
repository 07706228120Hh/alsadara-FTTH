/// تفاصيل العقار — بطاقة QR (العنوان الوطني) + صورة الدار + الوسائط +
/// الاشتراكات المرتبطة (ربط/فكّ ربط) + طباعة اللصاقة + فتح الموقع في الخرائط.
///
/// بثيم منصّة الصدارة. الكتابة (تعديل/حذف/صورة/ربط) محكومة بـ `canAdd('sas_agent')`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../permissions/permission_manager.dart';
import '../../../theme/app_theme.dart';
import '../../services/sas_agent_api_service.dart';
import '../../widgets/sas_state_views.dart';
import '../models/premises.dart';
import '../print/premises_label.dart';
import 'premises_form_screen.dart';

class PremisesDetailScreen extends StatefulWidget {
  final int premisesId;
  const PremisesDetailScreen({super.key, required this.premisesId});

  @override
  State<PremisesDetailScreen> createState() => _PremisesDetailScreenState();
}

class _PremisesDetailScreenState extends State<PremisesDetailScreen> {
  final _api = SasAgentApiService.instance;

  Premises? _p;
  bool _loading = true;
  String? _error;
  Uint8List? _photo;
  bool _photoLoading = false;

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _api.getPremise(widget.premisesId);
      if (!mounted) return;
      setState(() {
        _p = p;
        _loading = false;
      });
      if (p.hasPhoto) _loadPhoto();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadPhoto() async {
    setState(() => _photoLoading = true);
    try {
      final bytes = await _api.getPremisePhoto(widget.premisesId);
      if (!mounted) return;
      setState(() {
        _photo = bytes == null ? null : Uint8List.fromList(bytes);
        _photoLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  void _msg(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: err ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => PremisesFormScreen(existing: _p)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف العقار؟',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text(
            'سيُحذف العقار وصورته ويُفكّ ربط اشتراكاته (لا تُحذف الاشتراكات).',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
              child: Text('حذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deletePremise(widget.premisesId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _msg('تعذّر الحذف: $e', err: true);
    }
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppTheme.primaryColor),
              title: Text('كاميرا', style: GoogleFonts.cairo()),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppTheme.primaryColor),
              title: Text('من الملفات', style: GoogleFonts.cairo()),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ]),
        ),
      ),
    );
    if (src == null) return;
    try {
      final XFile? x =
          await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 82);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final ok = await _api.uploadPremisePhoto(
        widget.premisesId,
        bytes,
        contentType: x.mimeType ?? 'image/jpeg',
      );
      if (!ok) {
        _msg('تعذّر رفع الصورة', err: true);
        return;
      }
      _msg('حُفظت صورة الدار');
      // نُحدّث محلياً فوراً ثم نعيد جلب العقار (has_photo).
      if (mounted) setState(() => _photo = Uint8List.fromList(bytes));
      _load();
    } catch (e) {
      _msg('تعذّر رفع الصورة: $e', err: true);
    }
  }

  Future<void> _openMap() async {
    final p = _p;
    if (p?.lat == null || p?.lon == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${p!.lat},${p.lon}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _msg('تعذّر فتح الخرائط', err: true);
    }
  }

  Future<void> _linkDialog() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: _LinkSheet(premisesId: widget.premisesId),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _unlink(PremisesSub s) async {
    try {
      await _api.unlinkPremiseSubscribers(widget.premisesId, [s.username]);
      _load();
    } catch (e) {
      _msg('تعذّر فكّ الربط: $e', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: _appBar(),
        body: _loading
            ? const SasLoadingView(message: 'جارٍ تحميل العقار…')
            : _error != null
                ? SasErrorView(message: _error!, onRetry: _load)
                : _body(_p!),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: AppTheme.primaryColor,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.blueGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Text('تفاصيل العقار',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
      actions: [
        if (_canManage) ...[
          IconButton(
            tooltip: 'تعديل',
            onPressed: _edit,
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: _delete,
            icon:
                const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _body(Premises p) {
    return SasContentWrap(
      maxWidth: 960,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _qrCard(p),
          const SizedBox(height: 12),
          _photoCard(p),
          const SizedBox(height: 12),
          _detailsCard(p),
          const SizedBox(height: 12),
          _subscribersCard(p),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _qrCard(Premises p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: SasUi.card(),
      child: Column(
        children: [
          Text('العنوان الوطني',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.grey[700])),
          const SizedBox(height: 12),
          if (p.qrPayload.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    width: 1.5),
                boxShadow: SasUi.cardShadow(),
              ),
              child: QrImageView(
                data: p.qrPayload,
                size: 190,
                version: QrVersions.auto,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppTheme.primaryColor),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1A1A2E)),
              ),
            ),
          const SizedBox(height: 14),
          SelectableText(
            p.npnDisplay.isEmpty ? 'عقار #${p.id}' : p.npnDisplay,
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1,
                color: const Color(0xFF1A1A2E)),
          ),
          if (p.iqpinDisplay.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('IQ-Pin: ${p.iqpinDisplay}',
                  style: GoogleFonts.cairo(
                      color: Colors.grey[700], fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => printPremisesLabel(p),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.4)),
            ),
            icon: const Icon(Icons.print_rounded),
            label: Text('طباعة اللصاقة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _photoCard(Premises p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppTheme.blueGradient),
                  ),
                  child: Icon(Icons.home_outlined,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('صورة الدار',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: const Color(0xFF1A1A2E))),
              ),
              if (_canManage)
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                  label: Text(p.hasPhoto ? 'تغيير' : 'إضافة',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _photoContent(p),
        ],
      ),
    );
  }

  Widget _photoContent(Premises p) {
    if (_photoLoading) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
            child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    if (_photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_photo!,
            height: 210, width: double.infinity, fit: BoxFit.cover),
      );
    }
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 40, color: Colors.grey.withValues(alpha: 0.6)),
            const SizedBox(height: 6),
            Text('لا توجد صورة',
                style: GoogleFonts.cairo(
                    color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(Premises p) {
    final commercial = p.propertyType == 'commercial';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              SasStatusBadge(
                  label: propertyLabel(p.propertyType),
                  color: commercial
                      ? AppTheme.warningColor
                      : AppTheme.primaryColor,
                  icon: commercial
                      ? Icons.storefront_rounded
                      : Icons.home_rounded),
              SasStatusBadge(
                  label: ownershipLabel(p.ownership),
                  color: AppTheme.successColor,
                  icon: Icons.vpn_key_rounded),
              SasStatusBadge(
                  label: '${p.subscriberCount} اشتراك',
                  color: AppTheme.secondaryColor,
                  icon: Icons.people_rounded),
            ],
          ),
          const Divider(height: 24),
          _kv('المحافظة', p.governorate),
          _kv('المنطقة', p.district),
          _kv('أقرب نقطة', p.landmark),
          _kv('التفاصيل', p.addressDetails),
          _kv('الهاتف', p.phone),
          _kv('المالك/المستأجر', p.ownerName),
          if (p.notes.trim().isNotEmpty) _kv('ملاحظات', p.notes),
          if (p.lat != null && p.lon != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openMap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.successColor,
                side:
                    BorderSide(color: AppTheme.successColor.withValues(alpha: 0.4)),
              ),
              icon: const Icon(Icons.map_rounded),
              label: Text(
                  'الموقع: ${p.lat!.toStringAsFixed(5)}, ${p.lon!.toStringAsFixed(5)}',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subscribersCard(Premises p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SasSectionHeader(
            title: 'الاشتراكات المرتبطة',
            icon: Icons.people_outline_rounded,
            trailingText: '${p.subscriberCount}',
            action: _canManage
                ? TextButton.icon(
                    onPressed: _linkDialog,
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: Text('ربط اشتراك',
                        style:
                            GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (p.subscribers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا اشتراكات مرتبطة بعد — اربط اشتراكاً واحداً أو أكثر بهذا العقار.',
                style: GoogleFonts.cairo(
                    color: Colors.grey[600], fontWeight: FontWeight.w600),
              ),
            )
          else
            for (int i = 0; i < p.subscribers.length; i++) ...[
              if (i > 0) const Divider(height: 14),
              _subRow(p.subscribers[i]),
            ],
        ],
      ),
    );
  }

  Widget _subRow(PremisesSub s) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.online ? AppTheme.successColor : Colors.grey,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.username,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E))),
              if ([s.name, s.profile].any((x) => x.trim().isNotEmpty))
                Text(
                  [s.name, s.profile]
                      .where((x) => x.trim().isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
        if (_canManage)
          IconButton(
            tooltip: 'فكّ الربط',
            onPressed: () => _unlink(s),
            icon: const Icon(Icons.link_off_rounded,
                size: 20, color: AppTheme.errorColor),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: GoogleFonts.cairo(
                    color: Colors.grey[600], fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(v,
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }
}

/// ورقة بحث وربط الاشتراكات بالعقار (عبر link-candidates).
class _LinkSheet extends StatefulWidget {
  final int premisesId;
  const _LinkSheet({required this.premisesId});

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _api = SasAgentApiService.instance;
  final _q = TextEditingController();

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await _api.premiseLinkCandidates(search: _q.text.trim());
      if (mounted) {
        setState(() {
          _rows = r;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// مرجع الاشتراك المستخدم للربط (username المفضّل، أو ref/id).
  String _refOf(Map<String, dynamic> r) =>
      (r['username'] ?? r['ref'] ?? r['id'] ?? '').toString();

  Future<void> _link(Map<String, dynamic> r) async {
    final ref = _refOf(r);
    if (ref.isEmpty) return;
    try {
      await _api.linkPremiseSubscribers(widget.premisesId, [ref]);
      _changed = true;
      _search();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('تمّ الربط', style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذّر الربط: $e', style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SasUi.pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('ربط اشتراك بالعقار',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, _changed),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              onSubmitted: (_) => _search(),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المستخدم / الاسم / الهاتف',
                hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.primaryColor),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: AppTheme.primaryColor),
                  onPressed: _search,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const SasLoadingView()
                : _rows.isEmpty
                    ? const SasEmptyView(
                        message: 'لا نتائج — جرّب كلمة بحث أخرى',
                        icon: Icons.person_search_rounded)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _candidateCard(_rows[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _candidateCard(Map<String, dynamic> r) {
    final linkedHere = _asInt(r['premises_id'] ?? r['premisesId']) ==
            widget.premisesId &&
        (r['premises_id'] ?? r['premisesId']) != null;
    final linkedElse =
        (r['premises_id'] ?? r['premisesId']) != null && !linkedHere;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: SasUi.card(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${r['username'] ?? _refOf(r)}',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E))),
                if ([r['name'], r['phone']]
                    .any((x) => (x ?? '').toString().trim().isNotEmpty))
                  Text(
                    [r['name'], r['phone']]
                        .where((x) => (x ?? '').toString().trim().isNotEmpty)
                        .join(' · '),
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (linkedHere)
            const SasStatusBadge(
                label: 'مربوط هنا',
                color: AppTheme.successColor,
                icon: Icons.check_rounded)
          else
            FilledButton(
              onPressed: () => _link(r),
              style: FilledButton.styleFrom(
                backgroundColor: linkedElse
                    ? AppTheme.warningColor
                    : AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(linkedElse ? 'نقل هنا' : 'ربط',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? -1;
  }
}
