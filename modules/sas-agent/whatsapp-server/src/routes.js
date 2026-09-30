// مسارات HTTP — واجهة الخادم التي يستهلكها التطبيق (ServerSender).
'use strict';

const express = require('express');
const QRCode = require('qrcode');

// يبني موجّهاً يربط الطلبات بمدير الجلسات والمُرسِل.
function buildRouter(sessions, sender) {
  const router = express.Router();

  // فحص حياة الخادم.
  router.get('/', (_req, res) => {
    res.json({ ok: true, name: 'aluklaa-whatsapp-server' });
  });

  // حالة الجلسة: { state, phone }. state ∈ ready|qr|connecting|disconnected
  router.get('/status/:tenant', (req, res) => {
    const st = sessions.status(req.params.tenant);
    // نطابق مفاتيح حالة التطبيق (initializing → connecting).
    const state = st.state === 'initializing' ? 'connecting' : st.state;
    res.json({ state, phone: st.phone });
  });

  // إنشاء/تهيئة الجلسة (يبدأ توليد QR إن لزم).
  router.post('/session/:tenant', (req, res) => {
    sessions.ensure(req.params.tenant);
    res.json({ ok: true });
  });

  // قطع الجلسة وحذفها.
  router.delete('/session/:tenant', async (req, res) => {
    await sessions.reset(req.params.tenant);
    res.json({ ok: true });
  });

  // رمز QR كنصّ خام.
  router.get('/qr/:tenant', (req, res) => {
    const s = sessions.get(req.params.tenant);
    if (!s || !s.qr) return res.status(404).json({ error: 'no qr' });
    res.json({ qr: s.qr });
  });

  // رمز QR كصورة PNG (تعرضها الواجهة مباشرة).
  router.get('/qr-image/:tenant', async (req, res) => {
    const s = sessions.get(req.params.tenant);
    if (!s || !s.qr) return res.status(404).send('no qr');
    try {
      const buf = await QRCode.toBuffer(s.qr, { type: 'png', width: 320, margin: 1 });
      res.set('Content-Type', 'image/png');
      res.set('Cache-Control', 'no-store');
      res.send(buf);
    } catch (e) {
      res.status(500).send('qr error');
    }
  });

  // إرسال رسالة واحدة.
  router.post('/send/:tenant', async (req, res) => {
    const { phone, message } = req.body || {};
    if (!phone || !message) return res.status(400).json({ success: false, error: 'phone و message مطلوبان' });
    const result = await sender.sendOne(req.params.tenant, phone, message);
    res.json(result);
  });

  // إرسال دفعة (خلفي). { messages:[{phone,message,name}], delaySeconds }
  router.post('/send-bulk/:tenant', async (req, res) => {
    const { messages, delaySeconds } = req.body || {};
    if (!Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({ success: false, error: 'messages مطلوبة' });
    }
    const result = await sender.sendBulk(req.params.tenant, messages, delaySeconds);
    res.json(result);
  });

  // حالة الدفعة الجارية.
  router.get('/send-bulk/:tenant/status', (req, res) => {
    res.json(sender.bulkStatus(req.params.tenant));
  });

  // إلغاء الدفعة.
  router.post('/send-bulk/:tenant/cancel', (req, res) => {
    res.json(sender.cancelBulk(req.params.tenant));
  });

  return router;
}

module.exports = { buildRouter };
