// مدير الجلسات — عميل whatsapp-web.js لكل مستأجر، مع QR وإعادة اتصال تلقائية.
'use strict';

const { Client, LocalAuth } = require('whatsapp-web.js');
const config = require('./config');

// حالة جلسة واحدة في الذاكرة.
// state: 'initializing' | 'qr' | 'ready' | 'disconnected'
class Session {
  constructor(tenant) {
    this.tenant = tenant;
    this.client = null;
    this.state = 'initializing';
    this.qr = null; // آخر نصّ QR (للعرض كصورة)
    this.phone = null;
    this.consecutiveFailures = 0;
  }
}

class SessionManager {
  constructor() {
    /** @type {Map<string, Session>} */
    this.sessions = new Map();
  }

  get(tenant) {
    return this.sessions.get(tenant) || null;
  }

  status(tenant) {
    const s = this.sessions.get(tenant);
    if (!s) return { state: 'disconnected', phone: null };
    return { state: s.state, phone: s.phone };
  }

  // يُنشئ (أو يُعيد) جلسة ويبدأ التهيئة. آمن للاستدعاء المتكرّر.
  ensure(tenant) {
    let s = this.sessions.get(tenant);
    if (s && s.client) return s;
    s = s || new Session(tenant);
    this.sessions.set(tenant, s);
    this._boot(s);
    return s;
  }

  _boot(s) {
    s.state = 'initializing';
    s.qr = null;
    const puppeteer = {
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    };
    // استخدم متصفّح النظام (Edge/Chrome) إن وُجد بدل Chromium المضمَّن.
    if (config.chromePath) puppeteer.executablePath = config.chromePath;
    const client = new Client({
      authStrategy: new LocalAuth({ clientId: s.tenant, dataPath: config.sessionDir }),
      puppeteer,
    });

    client.on('qr', (qr) => {
      s.qr = qr;
      s.state = 'qr';
      log(s.tenant, 'QR ready — scan from WhatsApp linked devices');
    });

    client.on('authenticated', () => {
      s.state = 'initializing';
      log(s.tenant, 'authenticated');
    });

    client.on('ready', () => {
      s.state = 'ready';
      s.qr = null;
      s.consecutiveFailures = 0;
      try {
        s.phone = client.info && client.info.wid ? client.info.wid.user : null;
      } catch (_) {
        s.phone = null;
      }
      log(s.tenant, 'ready' + (s.phone ? ' (' + s.phone + ')' : ''));
    });

    client.on('disconnected', (reason) => {
      s.state = 'disconnected';
      log(s.tenant, 'disconnected: ' + reason + ' — reconnecting in 5s');
      safeDestroy(client);
      s.client = null;
      setTimeout(() => {
        if (this.sessions.get(s.tenant) === s) this._boot(s);
      }, 5000);
    });

    s.client = client;
    client.initialize().catch((e) => {
      s.state = 'disconnected';
      log(s.tenant, 'initialize failed: ' + (e && e.message));
    });
  }

  // يسجّل خروجاً ويحذف الجلسة (يتطلّب QR جديداً لاحقاً).
  async reset(tenant) {
    const s = this.sessions.get(tenant);
    if (!s) return;
    try {
      if (s.client) await s.client.logout().catch(() => {});
    } finally {
      if (s.client) safeDestroy(s.client);
      this.sessions.delete(tenant);
      log(tenant, 'session reset');
    }
  }

  // يُبلّغ بإخفاق إرسال — بعد حدٍّ يُعيد التشغيل.
  reportFailure(tenant) {
    const s = this.sessions.get(tenant);
    if (!s) return;
    s.consecutiveFailures += 1;
    if (s.consecutiveFailures >= config.maxConsecutiveFailures) {
      log(tenant, 'too many failures — restarting session');
      s.consecutiveFailures = 0;
      if (s.client) safeDestroy(s.client);
      s.client = null;
      this._boot(s);
    }
  }

  reportSuccess(tenant) {
    const s = this.sessions.get(tenant);
    if (s) s.consecutiveFailures = 0;
  }
}

function safeDestroy(client) {
  try {
    client.destroy();
  } catch (_) {
    /* ignore */
  }
}

function log(tenant, msg) {
  // ASCII-safe console (تجنّب مشاكل ترميز الطرفية على ويندوز).
  console.log('[' + new Date().toISOString() + '][' + tenant + '] ' + msg);
}

module.exports = { SessionManager };
