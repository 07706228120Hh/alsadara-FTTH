// خادم واتساب المحلي لتطبيق الوكلاء — نقطة الدخول.
//
// يربط: الإعداد + مدير الجلسات + المُرسِل + مسارات HTTP.
// التشغيل: يُطلقه التطبيق تلقائياً (مخفيّاً عبر run_hidden.vbs)، أو يدوياً:
//   npm start  /  start_whatsapp_server.bat
'use strict';

const fs = require('fs');
const express = require('express');
const config = require('./src/config');
const { SessionManager } = require('./src/session');
const { Sender } = require('./src/sender');
const { buildRouter } = require('./src/routes');

// تأكّد من وجود مجلد البيانات القابل للكتابة، واكتب معرّف العملية (للإيقاف من التطبيق).
try {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.writeFileSync(config.pidFile, String(process.pid));
} catch (e) {
  console.error('[warn] could not write data dir/pid: ' + (e && e.message));
}

const app = express();
app.use(express.json({ limit: '2mb' }));

const sessions = new SessionManager();
const sender = new Sender(sessions);

app.use('/', buildRouter(sessions, sender));

const server = app.listen(config.port, config.host, () => {
  console.log('[aluklaa-whatsapp-server] listening on http://' + config.host + ':' + config.port);
  console.log('  data dir: ' + config.dataDir);
  console.log('  browser : ' + (config.chromePath || 'bundled Chromium'));
  console.log('  link a session: POST /session/default  then scan QR at GET /qr-image/default');
});

// تنظيف ملف الـ PID عند الإيقاف.
function shutdown() {
  try {
    fs.unlinkSync(config.pidFile);
  } catch (_) {
    /* ignore */
  }
  try {
    server.close();
  } catch (_) {
    /* ignore */
  }
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
