// تطبيع أرقام الهاتف العراقية إلى معرّف محادثة واتساب (9647XXXXXXXXX@c.us).
'use strict';

// يعالج: 07XXXXXXXXX · +964... · 00964... · أرقاماً متعددة (يأخذ أوّل صالح).
// يُعيد الرقم المطبّع (9647XXXXXXXXX) أو null.
function normalizeIraqi(raw) {
  if (!raw || !String(raw).trim()) return null;
  const parts = String(raw).split(/[\s,/]+/);
  let pick = String(raw);
  for (const p of parts) {
    if (p.replace(/\D/g, '').length >= 10) {
      pick = p;
      break;
    }
  }
  let d = pick.replace(/\D/g, '');
  if (d.startsWith('00964')) d = d.slice(5);
  if (d.startsWith('964')) d = d.slice(3);
  if (d.startsWith('0')) d = d.slice(1);
  if (d.length === 10 && d.startsWith('7')) return '964' + d;
  return null;
}

// معرّف محادثة واتساب من رقم خام، أو null إن تعذّر.
function toChatId(raw) {
  const n = normalizeIraqi(raw);
  return n ? n + '@c.us' : null;
}

module.exports = { normalizeIraqi, toChatId };
