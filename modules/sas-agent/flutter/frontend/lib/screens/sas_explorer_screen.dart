import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';
import 'package:webview_windows/webview_windows.dart';

/// مستكشف SAS — متصفّح مدمج (WebView2) يفتح لوحة SAS، وأنت تتنقّل وتسجّل الدخول
/// بشكل طبيعي، بينما يلتقط **كل طلب API** (المسار · الطريقة · الحمولة المشفّرة · الاستجابة)
/// عبر حقن JavaScript يعترض fetch/XHR. زرّ «نسخ/حفظ» يصدّر السجلّ كاملاً لتحليله.
///
/// الحمولة تبقى مشفّرة على السلك لكنها تُفكّ لاحقاً بمفتاح SAS المعروف — فتظهر
/// المسارات والمعاملات الحقيقية (صيغة DataTables للتقارير) والاستجابات.
class SasExplorerScreen extends StatefulWidget {
  final StaffApi api;
  const SasExplorerScreen({super.key, required this.api});
  @override
  State<SasExplorerScreen> createState() => _SasExplorerScreenState();
}

// JS يُحقَن قبل كل صفحة: يرقّع fetch و XMLHttpRequest ويرسل كل طلب إلى Dart.
const String _injectJs = r'''
(function(){
  if (window.__capInstalled) return; window.__capInstalled = true;
  function post(o){ try { window.chrome.webview.postMessage(JSON.stringify(o)); } catch(e){} }
  var of = window.fetch;
  if (of) window.fetch = function(input, init){
    var url = (typeof input === 'string') ? input : (input && input.url);
    var method = (init && init.method) || (typeof input==='object' && input.method) || 'GET';
    var body = (init && init.body) ? String(init.body) : '';
    return of.apply(this, arguments).then(function(res){
      try { res.clone().text().then(function(t){
        post({ts:Date.now(),type:'fetch',method:method,url:url,req:body,status:res.status,res:(t||'').slice(0,20000)});
      }); } catch(e){ post({ts:Date.now(),type:'fetch',method:method,url:url,req:body,status:res.status}); }
      return res;
    });
  };
  var oOpen = XMLHttpRequest.prototype.open, oSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m,u){ this.__m=m; this.__u=u; return oOpen.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(b){
    var x=this;
    x.addEventListener('loadend', function(){
      post({ts:Date.now(),type:'xhr',method:x.__m,url:x.__u,req:b?String(b):'',status:x.status,res:(x.responseText||'').slice(0,20000)});
    });
    return oSend.apply(this, arguments);
  };
})();
''';

class _SasExplorerScreenState extends State<SasExplorerScreen> {
  final _controller = WebviewController();
  final _addr = TextEditingController();
  final List<Map<String, dynamic>> _caps = [];
  bool _ready = false;
  String? _error;
  bool _onlyApi = true;     // اعرض طلبات API فقط (index/ · report/ · api/)

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // العنوان الابتدائي = جذر خادم الوكيل (صفحة الدخول عادةً) — قابل للتعديل بالكامل.
    try {
      final cfg = await widget.api.agentSasConfig();
      final host = (cfg['sas_host'] ?? '').toString().trim();
      if (host.isNotEmpty) {
        final base = host.startsWith('http') ? host : 'https://$host';
        _addr.text = base.replaceAll(RegExp(r'/+$'), '');   // الجذر بلا /admin
      }
    } catch (_) {}
    if (_addr.text.isEmpty) _addr.text = 'https://';
    try {
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.allow);
      await _controller.addScriptToExecuteOnDocumentCreated(_injectJs);
      _controller.webMessage.listen(_onMessage);
      if (_addr.text != 'https://') await _controller.loadUrl(_addr.text);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final m = raw is String ? jsonDecode(raw) : raw;
      if (m is Map) {
        final url = (m['url'] ?? '').toString();
        if (_onlyApi && !_looksApi(url)) return;
        setState(() => _caps.add(Map<String, dynamic>.from(m)));
      }
    } catch (_) {}
  }

  // طلبات البيانات الحقيقية فقط — نستبعد الترجمة/الموارد والأصول الساكنة (ضجيج ضخم).
  static const _noise = [
    'resources/language', 'resources/forms', 'resources/menu', 'resources/login',
    'maps.google', 'gen_204', 'firebase', '.js', '.css', '.png', '.jpg', '.jpeg',
    '.svg', '.woff', '.ico', '/assets/',
  ];
  bool _looksApi(String url) {
    if (!url.contains('/api/')) return false;
    final u = url.toLowerCase();
    for (final n in _noise) {
      if (u.contains(n)) return false;
    }
    return true;
  }

  Future<void> _go() async {
    var u = _addr.text.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http')) u = 'https://$u';
    await _controller.loadUrl(u);
  }

  String _export() => const JsonEncoder.withIndent('  ').convert({
        'captured_at_count': _caps.length,
        'requests': _caps,
      });

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _export()));
    if (mounted) showMsg(context, 'نُسخ ${_caps.length} طلباً إلى الحافظة');
  }

  Future<void> _saveFile() async {
    try {
      final dir = Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
      final path = '$dir\\Desktop\\sas_capture.json';
      final f = File(path);
      await f.writeAsString(_export());
      if (mounted) showMsg(context, 'حُفظ ${_caps.length} طلباً في: $path');
    } catch (e) {
      if (mounted) showMsg(context, 'تعذّر الحفظ: $e', error: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _addr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مستكشف SAS — التقاط الطلبات'),
          actions: [
            IconButton(tooltip: 'مسح السجلّ', onPressed: () => setState(_caps.clear),
                icon: const Icon(PhosphorIconsBold.trash)),
          ],
        ),
        body: _error != null
            ? _ErrorBox(error: _error!)
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    // شريط العنوان
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _addr,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              isDense: true, prefixIcon: Icon(PhosphorIconsBold.globe),
                              hintText: 'ضع رابط لوحة SAS ثم اضغط «اذهب»',
                              border: OutlineInputBorder(),
                            ),
                            onTap: () => _addr.selection = TextSelection(
                                baseOffset: 0, extentOffset: _addr.text.length),
                            onSubmitted: (_) => _go(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: _go, child: const Text('اذهب')),
                      ]),
                    ),
                    // المتصفّح
                    Expanded(child: Webview(_controller)),
                    // شريط الالتقاط
                    Material(
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Row(children: [
                          const Icon(PhosphorIconsBold.pulse, size: 18, color: BrandColors.green),
                          const SizedBox(width: 6),
                          Text('التُقط ${_caps.length} طلباً', style: tt.titleSmall),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'طلبات API فقط',
                            child: Row(children: [
                              Switch(value: _onlyApi, onChanged: (v) => setState(() => _onlyApi = v)),
                              const Text('API فقط'),
                            ]),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(onPressed: _caps.isEmpty ? null : _saveFile,
                              icon: const Icon(PhosphorIconsBold.floppyDisk, size: 18),
                              label: const Text('حفظ ملف')),
                          const SizedBox(width: 8),
                          FilledButton.icon(onPressed: _caps.isEmpty ? null : _copyAll,
                              icon: const Icon(PhosphorIconsBold.copy, size: 18),
                              label: const Text('نسخ كل شيء')),
                        ]),
                      ),
                    ),
                  ]),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(PhosphorIconsDuotone.warning, size: 48, color: Colors.orange),
          const SizedBox(height: 12),
          const Text('تعذّر تشغيل المتصفّح المدمج (WebView2)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'يتطلّب هذا «WebView2 Runtime» (مثبّت افتراضياً على ويندوز 11). '
            'إن ظهر هذا الخطأ فثبّته من موقع مايكروسوفت ثم أعد فتح الصفحة.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SelectableText(error, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}
