const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Token للتحقق من Webhook (يجب تغييره)
const VERIFY_TOKEN = "alsadara_webhook_secret_2025";

/**
 * Webhook للتحقق من صحة الإعداد (GET)
 */
exports.whatsappWebhook = onRequest({
  region: "us-central1",
  cors: true,
}, async (req, res) => {
  if (req.method === "GET") {
    // Facebook Webhook Verification
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    if (mode === "subscribe" && token === VERIFY_TOKEN) {
      console.log("✅ Webhook verified successfully");
      res.status(200).send(challenge);
    } else {
      console.log("❌ Webhook verification failed");
      res.sendStatus(403);
    }
    return;
  }

  if (req.method === "POST") {
    try {
      const body = req.body;
      console.log("📥 Received webhook:", JSON.stringify(body, null, 2));

      // تحقق من أن الطلب من WhatsApp Business
      if (body.object !== "whatsapp_business_account") {
        res.sendStatus(404);
        return;
      }

      // معالجة الرسائل الواردة
      for (const entry of body.entry || []) {
        for (const change of entry.changes || []) {
          const value = change.value;

          // معالجة الرسائل
          if (value.messages) {
            for (const message of value.messages) {
              await handleIncomingMessage(message, value.metadata);
            }
          }

          // معالجة حالات التسليم
          if (value.statuses) {
            for (const status of value.statuses) {
              await handleMessageStatus(status);
            }
          }
        }
      }

      res.sendStatus(200);
    } catch (error) {
      console.error("❌ Error processing webhook:", error);
      res.sendStatus(500);
    }
    return;
  }

  res.sendStatus(405);
});

/**
 * معالجة الرسالة الواردة
 */
async function handleIncomingMessage(message, metadata) {
  try {
    const from = message.from; // رقم المرسل
    const messageId = message.id;
    const timestamp = parseInt(message.timestamp) * 1000; // تحويل إلى milliseconds

    // استخراج نص الرسالة
    let messageText = "";
    let messageType = message.type;

    if (message.type === "text") {
      messageText = message.text.body;
    } else if (message.type === "image") {
      messageText = `[صورة] ${message.image.caption || ""}`;
    } else if (message.type === "document") {
      messageText = `[ملف] ${message.document.filename || ""}`;
    } else if (message.type === "audio") {
      messageText = "[رسالة صوتية]";
    } else if (message.type === "video") {
      messageText = `[فيديو] ${message.video.caption || ""}`;
    } else if (message.type === "location") {
      messageText = "[موقع جغرافي]";
    } else if (message.type === "contacts") {
      messageText = "[جهة اتصال]";
    } else {
      messageText = `[${message.type}]`;
    }

    console.log(`📨 Message from ${from}: ${messageText}`);

    // حفظ الرسالة في Firestore
    const conversationRef = db.collection("whatsapp_conversations").doc(from);
    const messageRef = conversationRef.collection("messages").doc(messageId);

    // تحديث أو إنشاء المحادثة
    await conversationRef.set({
      phoneNumber: from,
      lastMessage: messageText,
      lastMessageTime: admin.firestore.Timestamp.fromMillis(timestamp),
      lastMessageType: messageType,
      unreadCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isIncoming: true,
    }, {merge: true});

    // حفظ الرسالة
    await messageRef.set({
      messageId: messageId,
      from: from,
      text: messageText,
      type: messageType,
      timestamp: admin.firestore.Timestamp.fromMillis(timestamp),
      isIncoming: true,
      status: "delivered",
      rawData: message, // حفظ البيانات الكاملة للرجوع إليها
    });

    console.log(`✅ Message saved: ${messageId}`);
  } catch (error) {
    console.error("❌ Error handling incoming message:", error);
    throw error;
  }
}

/**
 * معالجة حالة الرسالة (تم التسليم / تم القراءة)
 */
async function handleMessageStatus(status) {
  try {
    const messageId = status.id;
    const statusValue = status.status; // sent, delivered, read, failed

    console.log(`📊 Status update for ${messageId}: ${statusValue}`);

    // البحث عن الرسالة في جميع المحادثات
    const conversationsSnapshot = await db.collection("whatsapp_conversations").get();

    for (const conversationDoc of conversationsSnapshot.docs) {
      const messageRef = conversationDoc.ref.collection("messages").doc(messageId);
      const messageDoc = await messageRef.get();

      if (messageDoc.exists) {
        // تحديث حالة الرسالة
        await messageRef.update({
          status: statusValue,
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Status updated: ${messageId} -> ${statusValue}`);
        break;
      }
    }
  } catch (error) {
    console.error("❌ Error handling message status:", error);
  }
}

/**
 * دالة لإرسال رسالة (يمكن استدعاؤها من التطبيق)
 */
exports.sendWhatsAppMessage = onRequest({
  region: "us-central1",
  cors: true,
}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  try {
    const {to, message, messageType = "text"} = req.body;

    if (!to || !message) {
      res.status(400).json({error: "Missing required fields"});
      return;
    }

    // حفظ الرسالة المرسلة في Firestore
    const conversationRef = db.collection("whatsapp_conversations").doc(to);
    const messageRef = conversationRef.collection("messages").doc();

    const timestamp = Date.now();

    await conversationRef.set({
      phoneNumber: to,
      lastMessage: message,
      lastMessageTime: admin.firestore.Timestamp.fromMillis(timestamp),
      lastMessageType: messageType,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isIncoming: false,
    }, {merge: true});

    await messageRef.set({
      messageId: messageRef.id,
      to: to,
      text: message,
      type: messageType,
      timestamp: admin.firestore.Timestamp.fromMillis(timestamp),
      isIncoming: false,
      status: "pending",
    });

    res.status(200).json({
      success: true,
      messageId: messageRef.id,
    });
  } catch (error) {
    console.error("❌ Error sending message:", error);
    res.status(500).json({error: error.message});
  }
});
