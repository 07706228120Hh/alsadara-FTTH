/// قارئ البصريات الخفيّ عبر WebView (ويندوز) — Network Quality
///
/// يشغّل WebView2 بلا واجهة مرئية ليسجّل الدخول لصفحة هواوي (تتولّى الصفحة
/// التشفير/CSRF) ثم ينتقل لصفحة البصريات ويقرأ Rx/Tx — يُستخدم تلقائياً أثناء
/// الفحص الرئيسي ليظهر الناتج في الواجهة دون تدخّل المستخدم.
///
/// ويندوز فقط (webview_windows). على غيره يُعيد null بلا ضرر.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;

import '../models/device_models.dart';
import 'optical_signal_service.dart';

class WebViewOpticalReader {
  static const _defaultCreds = [
    ['telecomadmin', 'admintelecom'],
    ['telecomadmin', 'nE7jA%5m'],
    ['root', 'adminHW'],
    ['admin', 'admin'],
  ];

  /// يقرأ البصريات بإنشاء متحكّم WebView خاص (قد يفشل بلا واجهة مرئية).
  static Future<OpticalReading?> read(String ip,
      {List<List<String>> creds = const []}) async {
    if (!Platform.isWindows) return null;
    final ctrl = wvwin.WebviewController();
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 15));
      return await readWith(ctrl, ip, creds: creds);
    } catch (e) {
      debugPrint('[WebViewOptical] init error: $e');
      return null;
    } finally {
      try {
        ctrl.dispose();
      } catch (_) {}
    }
  }

  /// يقرأ البصريات باستخدام متحكّم WebView **مُهيّأ ومُركَّب في الشجرة** مسبقاً
  /// (الطريقة الموثوقة — WebView2 يحتاج عرضاً فعلياً ولو خفيّاً).
  static Future<OpticalReading?> readWith(
      wvwin.WebviewController ctrl, String ip,
      {List<List<String>> creds = const []}) async {
    final attempts = creds.isNotEmpty ? creds : _defaultCreds;
    try {
      await ctrl.loadUrl('http://$ip/');
      await Future.delayed(const Duration(milliseconds: 2500));

      bool logged = await _isLoggedIn(ctrl);
      if (!logged) {
        for (final c in attempts) {
          await ctrl.loadUrl('http://$ip/');
          await Future.delayed(const Duration(milliseconds: 1500));
          await _fill(ctrl, c[0], c[1]);
          await Future.delayed(const Duration(milliseconds: 400));
          await _submit(ctrl);
          await Future.delayed(const Duration(milliseconds: 3500));
          if (await _isLoggedIn(ctrl)) {
            logged = true;
            break;
          }
        }
      }
      if (!logged) return null;

      // انتقال مباشر لمسارات البصريات المعروفة.
      for (final path in OpticalSignalService.opticPagePaths) {
        try {
          await ctrl.loadUrl('http://$ip$path');
          await Future.delayed(const Duration(milliseconds: 2200));
          final dom = await _readDom(ctrl);
          if (dom != null && dom.isNotEmpty) {
            final p = OpticalSignalService.parseBody(dom,
                source: 'Huawei (WebView)', ip: ip);
            if (p.available) {
              return OpticalReading(
                rxPowerDbm: p.rxPowerDbm,
                txPowerDbm: p.txPowerDbm,
                voltage: p.voltage,
                biasCurrentMa: p.biasCurrentMa,
                temperatureC: p.temperatureC,
              );
            }
          }
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('[WebViewOptical] read error: $e');
      return null;
    }
  }

  static Future<bool> _isLoggedIn(wvwin.WebviewController ctrl) async {
    try {
      final res = await ctrl.executeScript(r'''
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

  static Future<void> _fill(
      wvwin.WebviewController ctrl, String user, String pass) async {
    await ctrl.executeScript('''
      (function() {
        var u = document.getElementById('txt_Username')
             || document.querySelector('input[name*="user" i]')
             || document.querySelector('input[type="text"]');
        var p = document.getElementById('txt_Password')
             || document.querySelector('input[name*="pass" i]')
             || document.querySelector('input[type="password"]');
        if (u) { u.value = ${_js(user)}; u.disabled = false; }
        if (p) { p.value = ${_js(pass)}; p.disabled = false; }
      })()
    ''');
  }

  static Future<void> _submit(wvwin.WebviewController ctrl) async {
    await ctrl.executeScript('''
      (function() {
        if (typeof SubmitForm === 'function') { SubmitForm(); return; }
        if (typeof doLogin === 'function') { doLogin(); return; }
        var b = document.getElementById('loginbutton')
             || document.getElementById('tripletbtn')
             || document.querySelector('button')
             || document.querySelector('input[type="submit"]');
        if (b) b.click();
      })()
    ''');
  }

  static Future<String?> _readDom(wvwin.WebviewController ctrl) async {
    try {
      final res = await ctrl.executeScript(r'''
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

  static String _js(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  static String? _decode(Object? raw) {
    if (raw == null) return null;
    var s = raw.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').replaceAll(r'\/', '/');
  }
}
