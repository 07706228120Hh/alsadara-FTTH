// اكتشاف متصفّح النظام (Edge/Chrome) لاستخدامه مع puppeteer بدل تنزيل Chromium.
// هذا يوفّر ~300MB ويجعل الخادم جاهزاً بلا تنزيل وقت التشغيل — Edge موجود على كل ويندوز 11.
'use strict';

const fs = require('fs');

// مرشّحات مسارات Edge وChrome الشائعة على ويندوز (Edge أوّلاً — مضمَّن دائماً).
function candidates() {
  const pf = process.env['ProgramFiles'] || 'C:\\Program Files';
  const pf86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
  const local = process.env['LOCALAPPDATA'] || '';
  return [
    pf86 + '\\Microsoft\\Edge\\Application\\msedge.exe',
    pf + '\\Microsoft\\Edge\\Application\\msedge.exe',
    pf + '\\Google\\Chrome\\Application\\chrome.exe',
    pf86 + '\\Google\\Chrome\\Application\\chrome.exe',
    local + '\\Google\\Chrome\\Application\\chrome.exe',
  ];
}

// يُعيد مسار أوّل متصفّح موجود، أو null (فيسقط puppeteer إلى Chromium المضمَّن إن وُجد).
function detectBrowser() {
  // أولوية للمتغيّر البيئي (يضبطه المشغّل عند اللزوم).
  if (process.env.WA_CHROME && fs.existsSync(process.env.WA_CHROME)) {
    return process.env.WA_CHROME;
  }
  for (const p of candidates()) {
    try {
      if (p && fs.existsSync(p)) return p;
    } catch (_) {
      /* ignore */
    }
  }
  return null;
}

module.exports = { detectBrowser };
