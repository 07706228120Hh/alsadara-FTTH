// إعدادات الخادم — كلها قابلة للضبط عبر متغيّرات البيئة.
'use strict';

const path = require('path');
const { detectBrowser } = require('./browser');

// مجلد بيانات المستخدم القابل للكتابة (خارج مجلد التثبيت في Program Files):
//   %LOCALAPPDATA%\Aluklaa\whatsapp  ← يُحذف مع إلغاء تثبيت التطبيق.
// يسقط إلى مجلد محلي بجانب الكود في التطوير.
function dataDir() {
  if (process.env.WA_DATA_DIR) return process.env.WA_DATA_DIR;
  const local = process.env['LOCALAPPDATA'];
  if (local) return path.join(local, 'Aluklaa', 'whatsapp');
  return path.join(__dirname, '..', '.data');
}

const base = dataDir();

module.exports = {
  // المنفذ الذي يستمع عليه الخادم (يطابق الافتراضي في التطبيق: 3100).
  port: parseInt(process.env.WA_PORT || '3100', 10),

  // يُستمع محلياً فقط افتراضياً (أمان) — التطبيق على نفس الجهاز.
  host: process.env.WA_HOST || '127.0.0.1',

  // مجلد البيانات القابل للكتابة، وجلسات واتساب بداخله (تدوم بين الإقلاعات).
  dataDir: base,
  sessionDir: path.join(base, '.wwebjs_auth'),
  pidFile: path.join(base, 'server.pid'),

  // متصفّح النظام (Edge/Chrome) — يتجنّب تنزيل Chromium الضخم. null → Chromium المضمَّن.
  chromePath: detectBrowser(),

  // الفاصل الافتراضي بين رسائل الدفعة (ثوانٍ) — حدّ أدنى للحماية من الحظر.
  defaultBulkDelaySec: parseFloat(process.env.WA_BULK_DELAY || '5'),
  minBulkDelaySec: 3,

  // عدد الإخفاقات المتتالية قبل محاولة إعادة تشغيل الجلسة.
  maxConsecutiveFailures: 3,
};
