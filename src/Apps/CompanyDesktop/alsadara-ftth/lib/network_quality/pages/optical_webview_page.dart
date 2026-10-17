/// قراءة الإشارة الضوئية عبر المتصفح المدمج (WebView) — Network Quality
///
/// الحلّ الموثوق لهواوي الحديثة (CSRF/SCRAM): ندع صفحة الراوتر نفسها تتولّى
/// تسجيل الدخول (SubmitForm) عبر حقن JS، ثم نقرأ صفحات البصريات عبر XHR من
/// داخل الصفحة (نفس الأصل، مُصادَق). يعمل على ويندوز (webview_windows).
///
/// يُعيد OpticalReading عبر Navigator.pop عند النجاح.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;

import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/optical_signal_service.dart';
import '../../frontend/tokens/sd_colors.dart' show SdColors;

class OpticalWebViewPage extends StatefulWidget {
  final String ip;
  final List<List<String>> credentials; // [[user, pass], ...]
  const OpticalWebViewPage({
    super.key,
    required this.ip,
    this.credentials = const [
      ['telecomadmin', 'admintelecom'],
      ['telecomadmin', 'nE7jA%5m'],
      ['root', 'adminHW'],
      ['admin', 'admin'],
    ],
  });

  @override
  State<OpticalWebViewPage> createState() => _OpticalWebViewPageState();
}

class _OpticalWebViewPageState extends State<OpticalWebViewPage> {
  static const _indigo = SdColors.primary;

  final _webCtrl = wvwin.WebviewController();
  bool _ready = false;
  bool _running = false;
  String _status = 'تهيئة المتصفح المدمج...';
  final List<String> _log = [];
  OpticalSignalInfo? _result;
  String? _rawBody; // المحتوى الخام لصفحة البصريات (للتشخيص/الضبط)

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _webCtrl.initialize();
      await _webCtrl.setBackgroundColor(Colors.white);
      if (mounted) setState(() => _ready = true);
      await _run();
    } catch (e) {
      if (mounted) setState(() => _status = 'تعذّرت تهيئة المتصفح: $e');
    }
  }

  void _addLog(String s) {
    if (mounted) setState(() => _log.add(s));
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _result = null;
      _status = 'فتح واجهة الجهاز...';
    });

    try {
      await _webCtrl.loadUrl('http://${widget.ip}/');
      await Future.delayed(const Duration(seconds: 3));

      for (final c in widget.credentials) {
        _addLog('محاولة الدخول بـ ${c[0]}...');
        setState(() => _status = 'تسجيل الدخول بـ ${c[0]}...');

        // إعادة تحميل صفحة الدخول قبل كل محاولة.
        await _webCtrl.loadUrl('http://${widget.ip}/');
        await Future.delayed(const Duration(seconds: 2));

        // تعبئة الحقول.
        await _webCtrl.executeScript('''
          (function() {
            var u = document.getElementById('txt_Username')
                 || document.querySelector('input[name*="user" i]')
                 || document.querySelector('input[type="text"]');
            var p = document.getElementById('txt_Password')
                 || document.querySelector('input[name*="pass" i]')
                 || document.querySelector('input[type="password"]');
            if (u) { u.value = ${jsonEncode(c[0])}; u.disabled = false; }
            if (p) { p.value = ${jsonEncode(c[1])}; p.disabled = false; }
          })()
        ''');
        await Future.delayed(const Duration(milliseconds: 500));

        // استدعاء دالة الدخول الأصلية (تتكفّل بالتشفير/التوكن).
        await _webCtrl.executeScript('''
          (function() {
            if (typeof SubmitForm === 'function') { SubmitForm(); return; }
            if (typeof doLogin === 'function') { doLogin(); return; }
            var b = document.getElementById('loginbutton')
                 || document.getElementById('tripletbtn')
                 || document.querySelector('button.submit')
                 || document.querySelector('button')
                 || document.querySelector('input[type="submit"]');
            if (b) b.click();
          })()
        ''');
        await Future.delayed(const Duration(seconds: 4));

        // تحقّق من نجاح الدخول فعلياً.
        if (await _isLoggedIn()) {
          _addLog('✓ تم الدخول بـ ${c[0]}');
          setState(() => _status = 'الانتقال إلى معلومات البصريات...');
          final parsed = await _autoReadOptic();
          if (parsed != null && parsed.available) {
            setState(() {
              _result = parsed;
              _status = 'تم قراءة الإشارة الضوئية بنجاح';
              _running = false;
            });
            return;
          }
          // دخلنا لكن لم نصل للبصريات تلقائياً — اطلب تنقّلاً يدوياً.
          setState(() {
            _status =
                'تم الدخول ✓ — افتح في المتصفح أدناه: System Info ثم Optic Info، ثم اضغط «قراءة الآن».';
            _running = false;
          });
          return;
        }
        _addLog('✗ فشل الدخول بـ ${c[0]}');
      }

      setState(() {
        _status =
            'تعذّر الدخول تلقائياً — سجّل الدخول يدوياً في المتصفح أدناه (telecomadmin) ثم افتح Optic Info واضغط «قراءة الآن».';
        _running = false;
      });
    } catch (e) {
      setState(() {
        _status = 'خطأ: $e';
        _running = false;
      });
    }
  }

  /// يقرأ صفحات البصريات عبر XHR من داخل الصفحة المُصادَقة ويُعيد أطول محتوى.
  Future<String?> _readOpticViaXhr() async {
    final pagesJs = jsonEncode(OpticalSignalService.opticPagePaths);
    try {
      final res = await _webCtrl.executeScript('''
        (function() {
          function get(u){try{var x=new XMLHttpRequest();x.open('GET',u,false);x.send();return x.status===200?x.responseText:'';}catch(e){return '';}}
          var pages = $pagesJs;
          var best = '';
          for (var i=0;i<pages.length;i++){
            var t = get(pages[i]);
            if (!t) continue;
            var low = t.toLowerCase();
            if (low.indexOf('power') > -1 || low.indexOf('optic') > -1) return t;
            if (t.length > best.length) best = t;
          }
          return best;
        })()
      ''');
      return _decode(res);
    } catch (e) {
      return null;
    }
  }

  /// قراءة يدوية بعد أن يفتح المستخدم صفحة البصريات في المتصفح.
  Future<void> _readNow() async {
    setState(() => _status = 'قراءة الصفحة الظاهرة...');
    final parsed = await _grabAndParse();
    if (parsed != null && parsed.available) {
      setState(() {
        _result = parsed;
        _status = 'تم قراءة الإشارة الضوئية بنجاح';
      });
    } else {
      setState(() => _status =
          'لم تُقرأ البصريات من الصفحة الحالية — افتح صفحة Optic Info ثم أعد المحاولة (أو استخدم «عرض المصدر الخام»).');
    }
  }

  /// يتحقّق أن الجلسة مُصادَقة (ظهور logout/telecomadmin/قوائم لوحة التحكم).
  Future<bool> _isLoggedIn() async {
    try {
      final res = await _webCtrl.executeScript(r'''
        (function(){
          function chk(d){ try{ var b=(d.body?d.body.innerHTML:'').toLowerCase();
            return b.indexOf('logout')>-1 || b.indexOf('telecomadmin')>-1
              || b.indexOf('one-click')>-1 || b.indexOf('fast setting')>-1
              || b.indexOf('advanced configuration')>-1; }catch(e){ return false; } }
          if(chk(document)) return 'yes';
          try{ for(var i=0;i<window.frames.length;i++){ try{ if(chk(window.frames[i].document)) return 'yes'; }catch(e){} } }catch(e){}
          return 'no';
        })()
      ''');
      return (_decode(res) ?? '').contains('yes');
    } catch (_) {
      return false;
    }
  }

  /// يحاول قراءة البصريات تلقائياً: انتقال مباشر لمسارات معروفة ثم نقر القوائم.
  Future<OpticalSignalInfo?> _autoReadOptic() async {
    // 1) انتقال مباشر لمسارات صفحة البصريات المعروفة (الأسرع والأوثق).
    for (final path in OpticalSignalService.opticPagePaths) {
      try {
        setState(() => _status = 'فتح صفحة البصريات $path ...');
        await _webCtrl.loadUrl('http://${widget.ip}$path');
        await Future.delayed(const Duration(milliseconds: 2500));
        final p = await _grabAndParse();
        if (p != null && p.available) return p;
      } catch (_) {}
    }
    // 2) العودة للرئيسية ثم تصفّح القوائم (System Info ← Optic).
    try {
      setState(() => _status = 'محاولة عبر القوائم...');
      await _webCtrl.loadUrl('http://${widget.ip}/');
      await Future.delayed(const Duration(seconds: 2));
      await _tryAutoNavOptic();
      return await _grabAndParse();
    } catch (_) {
      return null;
    }
  }

  /// يحاول الوصول لصفحة البصريات بالضغط على القوائم (System Info ← Optic).
  Future<void> _tryAutoNavOptic() async {
    Future<void> clickKw(List<String> kws) async {
      final kwJson = jsonEncode(kws);
      await _webCtrl.executeScript('''
        (function(){
          var kws = $kwJson;
          function tryDoc(d){
            try{
              var els = d.querySelectorAll('a,div,span,li,td,p,label,button');
              for(var i=0;i<els.length;i++){
                var oc = (els[i].getAttribute && (els[i].getAttribute('onclick')||els[i].getAttribute('href')||'')) || '';
                var t = ((els[i].innerText||els[i].textContent||'')+' '+oc).toLowerCase();
                for(var k=0;k<kws.length;k++){ if(t.indexOf(kws[k])>-1){ try{els[i].click();}catch(e){} return true; } }
              }
            }catch(e){}
            return false;
          }
          function walk(w){ if(tryDoc(w.document)) return true;
            try{ for(var i=0;i<w.frames.length;i++){ try{ if(walk(w.frames[i])) return true; }catch(e){} } }catch(e){}
            return false; }
          return walk(window) ? 'ok' : 'no';
        })()
      ''');
    }

    await clickKw(['system info', 'status', 'device info']);
    await Future.delayed(const Duration(seconds: 2));
    await clickKw(['optic', 'pon info', 'بصري']);
    await Future.delayed(const Duration(seconds: 3));
  }

  /// يقرأ DOM الصفحة الحالية وكل الإطارات ثم يحلّلها.
  Future<OpticalSignalInfo?> _grabAndParse() async {
    final body = await _readCurrentDom();
    if (body != null && body.isNotEmpty) {
      _rawBody = body;
      final parsed = OpticalSignalService.parseBody(body,
          source: 'Huawei (WebView)', ip: widget.ip);
      if (parsed.available) return parsed;
    }
    // احتياطي: XHR على المسارات المعروفة.
    final x = await _readOpticViaXhr();
    if (x != null && x.isNotEmpty) {
      _rawBody = x;
      return OpticalSignalService.parseBody(x,
          source: 'Huawei (WebView)', ip: widget.ip);
    }
    return null;
  }

  /// يقرأ محتوى HTML للصفحة الحالية وكل الإطارات المتداخلة.
  Future<String?> _readCurrentDom() async {
    try {
      final res = await _webCtrl.executeScript(r'''
        (function(){
          function grab(d){ try{ return (d && d.documentElement) ? d.documentElement.outerHTML : ''; }catch(e){ return ''; } }
          var out = grab(document);
          function walk(w){ try{ for(var i=0;i<w.frames.length;i++){ try{ out += '\n<!--FRAME-->\n' + grab(w.frames[i].document); walk(w.frames[i]); }catch(e){} } }catch(e){} }
          walk(window);
          return out;
        })()
      ''');
      return _decode(res);
    } catch (_) {
      return null;
    }
  }

  String? _decode(Object? raw) {
    if (raw == null) return null;
    var s = raw.toString();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    s = s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').replaceAll(r'\/', '/');
    return s;
  }

  void _showRaw() {
    final raw = _rawBody ?? '';
    // ابحث عن المقطع حول كلمات القدرة لتسهيل العرض.
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: AlertDialog(
          title: const Text('مصدر صفحة البصريات (للتشخيص)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 600,
            height: 420,
            child: SingleChildScrollView(
              child: SelectableText(
                raw.length > 8000 ? raw.substring(0, 8000) : raw,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  void _finish() {
    final r = _result;
    Navigator.pop(
        context,
        r == null
            ? null
            : OpticalReading(
                rxPowerDbm: r.rxPowerDbm,
                txPowerDbm: r.txPowerDbm,
                voltage: r.voltage,
                biasCurrentMa: r.biasCurrentMa,
                temperatureC: r.temperatureC,
              ));
  }

  @override
  void dispose() {
    _webCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F8),
        appBar: AppBar(
          title: const Text('قراءة البصريات عبر المتصفح',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          actions: [
            if (_rawBody != null)
              IconButton(
                tooltip: 'عرض المصدر الخام',
                icon: const Icon(Icons.code_rounded),
                onPressed: _showRaw,
              ),
            if (_result != null)
              TextButton.icon(
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('تم', style: TextStyle(color: Colors.white)),
                onPressed: _finish,
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_running)
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(
                            _result != null
                                ? Icons.check_circle
                                : Icons.info_outline,
                            size: 18,
                            color: _result != null ? SdColors.success : _indigo),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_status,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13))),
                    ],
                  ),
                  if (_result != null) _resultChips(),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('إعادة المحاولة التلقائية'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8)),
                        onPressed: _running ? null : _run,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('قراءة الآن'),
                        onPressed: _running ? null : _readNow,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ready
                  ? wvwin.Webview(_webCtrl)
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultChips() {
    final r = _result!;
    final items = <String>[
      if (r.rxPowerDbm != null) 'Rx ${r.rxPowerDbm!.toStringAsFixed(2)} dBm',
      if (r.txPowerDbm != null) 'Tx ${r.txPowerDbm!.toStringAsFixed(2)} dBm',
      if (r.temperatureC != null) '${r.temperatureC!.toStringAsFixed(1)}°C',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: items
            .map((t) => Chip(
                  label: Text(t,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                  backgroundColor: const Color(0xFF00838F).withValues(alpha: 0.12),
                ))
            .toList(),
      ),
    );
  }
}
