// منطق الإرسال — رسالة واحدة + دفعة (مع تتبّع حالة وإلغاء).
'use strict';

const config = require('./config');
const { toChatId } = require('./phone');

class Sender {
  constructor(sessions) {
    this.sessions = sessions;
    /** @type {Map<string, object>} حالة الدفعة الجارية لكل مستأجر */
    this.bulk = new Map();
  }

  // يرسل رسالة واحدة. يُعيد { success, error? }.
  async sendOne(tenant, rawPhone, message) {
    const s = this.sessions.get(tenant);
    if (!s || s.state !== 'ready' || !s.client) {
      return { success: false, error: 'الجلسة غير جاهزة (امسح QR أولاً)' };
    }
    const chatId = toChatId(rawPhone);
    if (!chatId) return { success: false, error: 'رقم غير صالح' };
    try {
      await s.client.sendMessage(chatId, message);
      this.sessions.reportSuccess(tenant);
      return { success: true };
    } catch (e) {
      this.sessions.reportFailure(tenant);
      return { success: false, error: (e && e.message) || 'فشل الإرسال' };
    }
  }

  bulkStatus(tenant) {
    return this.bulk.get(tenant) || { inProgress: false };
  }

  cancelBulk(tenant) {
    const b = this.bulk.get(tenant);
    if (b && b.inProgress) b.cancel = true;
    return { cancelled: !!(b && b.inProgress) };
  }

  // يرسل دفعة على الخادم (throttle). التطبيق عادةً يستخدم sendOne لكل رسالة
  // ليحصل على تقدّم حيّ؛ هذه للاستخدام الخلفي/السكربتات.
  async sendBulk(tenant, messages, delaySeconds) {
    if (this.bulk.get(tenant)?.inProgress) {
      return { success: false, error: 'دفعة أخرى قيد التنفيذ' };
    }
    const delay = Math.max(config.minBulkDelaySec, delaySeconds || config.defaultBulkDelaySec) * 1000;
    const state = {
      inProgress: true,
      total: messages.length,
      sent: 0,
      failed: 0,
      current: 0,
      cancel: false,
      results: [],
    };
    this.bulk.set(tenant, state);

    for (let i = 0; i < messages.length; i++) {
      if (state.cancel) break;
      state.current = i + 1;
      const m = messages[i];
      const res = await this.sendOne(tenant, m.phone, m.message);
      if (res.success) state.sent++;
      else state.failed++;
      state.results.push({ phone: m.phone, name: m.name || '', success: res.success, error: res.error });
      if (i < messages.length - 1 && !state.cancel) {
        await sleep(delay);
      }
    }

    state.inProgress = false;
    return {
      success: true,
      total: state.total,
      sent: state.sent,
      failed: state.failed,
      cancelled: state.cancel,
      results: state.results,
    };
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

module.exports = { Sender };
