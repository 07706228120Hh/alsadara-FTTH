import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/whatsapp_conversation.dart';
import 'firebase_availability.dart';

/// خدمة إدارة محادثات WhatsApp
class WhatsAppConversationService {
  /// تحميل كسول لتجنب خطأ [core/no-app] قبل اكتمال Firebase.initializeApp()
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// الحصول على جميع المحادثات (Real-time)
  static Stream<List<WhatsAppConversation>> getConversations() {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    return _firestore
        .collection('whatsapp_conversations')
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => WhatsAppConversation.fromFirestore(doc))
          .toList();
    });
  }

  /// جلب اسم المستخدم من رقم الهاتف
  static Future<String?> _getUserNameFromPhone(String phoneNumber) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      print('🔍 محاولة جلب اسم لـ: $phoneNumber');

      // قائمة صيغ مختلفة للبحث
      List<String> phoneVariants = [phoneNumber];

      // إزالة أي رموز وإبقاء الأرقام فقط
      final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

      // إضافة صيغ مختلفة
      if (cleanPhone.startsWith('964')) {
        phoneVariants.add('0${cleanPhone.substring(3)}'); // 07XXXXXXXXX
        phoneVariants.add('+$cleanPhone'); // +964XXXXXXXXX
        phoneVariants.add(cleanPhone); // 964XXXXXXXXX
      } else if (cleanPhone.startsWith('0')) {
        phoneVariants.add('964${cleanPhone.substring(1)}'); // 964XXXXXXXXX
        phoneVariants.add('+964${cleanPhone.substring(1)}'); // +964XXXXXXXXX
      }

      // إضافة الرقم النظيف
      phoneVariants.add(cleanPhone);

      print('🔍 صيغ البحث: $phoneVariants');

      // البحث في مجموعة ftth_subscriptions
      for (String variant in phoneVariants) {
        final snapshot = await _firestore
            .collection('ftth_subscriptions')
            .where('phone', isEqualTo: variant)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final data = snapshot.docs.first.data();
          final name = data['name'] as String?;
          if (name != null && name.isNotEmpty) {
            print('✅ تم العثور على الاسم: $name للرقم: $variant');
            return name;
          }
        }
      }

      print('⚠️ لم يتم العثور على اسم للرقم: $phoneNumber');
      return null;
    } catch (e) {
      print('❌ خطأ في جلب اسم المستخدم: $e');
      return null;
    }
  }

  /// تحديث اسم المستخدم في المحادثة
  static Future<void> _updateConversationUserName(
      String phoneNumber, String userName) async {
    if (!FirebaseAvailability.isAvailable) return;
    try {
      await _firestore
          .collection('whatsapp_conversations')
          .doc(phoneNumber)
          .update({
        'userName': userName,
        'contactName': userName,
      });
    } catch (e) {
      print('❌ خطأ في تحديث اسم المستخدم: $e');
    }
  }

  /// الحصول على رسائل محادثة معينة (Real-time) - من subcollection
  static Stream<List<WhatsAppMessage>> getMessages(String phoneNumber) {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    // قراءة الرسائل من subcollection messages تحت المحادثة
    return _firestore
        .collection('whatsapp_conversations')
        .doc(phoneNumber)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => WhatsAppMessage.fromFirestore(doc))
          .toList();
    });
  }

  /// إرسال رسالة (حفظها في Firestore)
  static Future<void> sendMessage({
    required String phoneNumber,
    required String message,
    String type = 'text',
  }) async {
    if (!FirebaseAvailability.isAvailable) return;
    final timestamp = DateTime.now();
    final timestampUnix = (timestamp.millisecondsSinceEpoch / 1000).floor();

    // محاولة جلب اسم المستخدم
    final userName = await _getUserNameFromPhone(phoneNumber);

    // حفظ الرسالة في subcollection messages تحت المحادثة
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    await _firestore
        .collection('whatsapp_conversations')
        .doc(phoneNumber)
        .collection('messages')
        .doc(messageId)
        .set({
      'messageId': messageId,
      'phoneNumber': phoneNumber,
      'text': message,
      'messageType': type,
      'timestamp': timestampUnix,
      'direction': 'outgoing',
      'status': 'sent',
      'contactName': userName ?? phoneNumber,
    });

    // تحديث المحادثة
    final conversationData = {
      'phoneNumber': phoneNumber,
      'lastMessage': message,
      'lastMessageTime': timestampUnix,
      'contactName': userName ?? phoneNumber,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'unreadCount': 0,
    };

    if (userName != null) {
      conversationData['userName'] = userName;
    }

    await _firestore
        .collection('whatsapp_conversations')
        .doc(phoneNumber)
        .set(conversationData, SetOptions(merge: true));
  }

  /// حفظ رسالة واردة (من WhatsApp)
  static Future<void> saveIncomingMessage({
    required String messageId,
    required String phoneNumber,
    required String message,
    required int timestamp,
    String? contactName,
    String type = 'text',
  }) async {
    if (!FirebaseAvailability.isAvailable) return;
    try {
      print('💬 حفظ رسالة واردة من: $phoneNumber - $contactName');

      // حفظ الرسالة في subcollection messages تحت المحادثة
      await _firestore
          .collection('whatsapp_conversations')
          .doc(phoneNumber)
          .collection('messages')
          .doc(messageId)
          .set({
        'messageId': messageId,
        'phoneNumber': phoneNumber,
        'text': message,
        'messageType': type,
        'timestamp': timestamp,
        'direction': 'incoming',
        'status': 'received',
        'contactName': contactName ?? phoneNumber,
      }, SetOptions(merge: true));

      // تحديث أو إنشاء المحادثة
      final conversationRef =
          _firestore.collection('whatsapp_conversations').doc(phoneNumber);

      // جلب المحادثة الحالية للحصول على عدد الرسائل غير المقروءة
      final conversationDoc = await conversationRef.get();
      final currentUnreadCount = conversationDoc.exists
          ? (conversationDoc.data()?['unreadCount'] ?? 0)
          : 0;

      final conversationData = {
        'phoneNumber': phoneNumber,
        'lastMessage': message,
        'lastMessageTime': timestamp,
        'lastMessageType': type,
        'contactName': contactName ?? phoneNumber,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'unreadCount': currentUnreadCount + 1,
        'isIncoming': true,
      };

      if (contactName != null && contactName.isNotEmpty) {
        conversationData['userName'] = contactName;
      }

      await conversationRef.set(conversationData, SetOptions(merge: true));

      print('✅ تم حفظ الرسالة الواردة والمحادثة بنجاح');
    } catch (e) {
      print('❌ خطأ في حفظ الرسالة الواردة: $e');
    }
  }

  /// تحديث حالة قراءة المحادثة
  static Future<void> markAsRead(String phoneNumber) async {
    if (!FirebaseAvailability.isAvailable) return;
    await _firestore
        .collection('whatsapp_conversations')
        .doc(phoneNumber)
        .update({'unreadCount': 0});
  }

  /// حذف محادثة
  static Future<void> deleteConversation(String phoneNumber) async {
    if (!FirebaseAvailability.isAvailable) return;
    try {
      print('🗑️ بدء حذف المحادثة: $phoneNumber');

      // 1. حذف الرسائل من subcollection messages (البنية الجديدة)
      final messagesSubcollection = await _firestore
          .collection('whatsapp_conversations')
          .doc(phoneNumber)
          .collection('messages')
          .get();

      print(
          '📝 عدد الرسائل في subcollection: ${messagesSubcollection.docs.length}');

      for (var doc in messagesSubcollection.docs) {
        await doc.reference.delete();
        print('🗑️ حذف رسالة من subcollection: ${doc.id}');
      }

      // 2. حذف الرسائل من collection whatsapp_messages (البنية القديمة)
      // جلب كل الرسائل والفلترة يدوياً لتجنب مشاكل الـ index
      final allMessagesSnapshot =
          await _firestore.collection('whatsapp_messages').get();

      print(
          '📝 إجمالي الرسائل في collection القديم: ${allMessagesSnapshot.docs.length}');

      // إنشاء قائمة بصيغ الرقم المختلفة للبحث
      final phoneVariants = _getPhoneVariants(phoneNumber);
      print('🔍 صيغ البحث: $phoneVariants');

      int deletedCount = 0;
      for (var doc in allMessagesSnapshot.docs) {
        final data = doc.data();
        final msgPhone = data['phoneNumber']?.toString() ?? '';
        final msgFrom = data['from']?.toString() ?? '';
        final msgTo = data['to']?.toString() ?? '';

        // تحقق إذا كان أي من الحقول يطابق أي صيغة من الرقم
        if (phoneVariants.contains(msgPhone) ||
            phoneVariants.contains(msgFrom) ||
            phoneVariants.contains(msgTo) ||
            phoneVariants.contains(_cleanPhone(msgPhone)) ||
            phoneVariants.contains(_cleanPhone(msgFrom)) ||
            phoneVariants.contains(_cleanPhone(msgTo))) {
          await doc.reference.delete();
          print('🗑️ حذف رسالة قديمة: ${doc.id} (phone: $msgPhone)');
          deletedCount++;
        }
      }

      print('📝 عدد الرسائل المحذوفة من collection القديم: $deletedCount');

      // 3. حذف المحادثة نفسها
      await _firestore
          .collection('whatsapp_conversations')
          .doc(phoneNumber)
          .delete();

      print('✅ تم حذف المحادثة والرسائل بنجاح: $phoneNumber');
    } catch (e) {
      print('❌ خطأ في حذف المحادثة: $e');
      rethrow;
    }
  }

  /// إنشاء قائمة بصيغ مختلفة لرقم الهاتف للبحث
  static Set<String> _getPhoneVariants(String phoneNumber) {
    final variants = <String>{phoneNumber};
    final clean = _cleanPhone(phoneNumber);
    variants.add(clean);

    // إضافة صيغ مختلفة
    if (clean.startsWith('964')) {
      variants.add('+$clean'); // +964...
      variants.add('00$clean'); // 00964...
      variants.add('0${clean.substring(3)}'); // 07...
    } else if (clean.startsWith('0')) {
      variants.add('964${clean.substring(1)}');
      variants.add('+964${clean.substring(1)}');
    }

    return variants;
  }

  /// تنظيف رقم الهاتف من الرموز
  static String _cleanPhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// البحث في المحادثات
  static Future<List<WhatsAppConversation>> searchConversations(
      String query) async {
    if (!FirebaseAvailability.isAvailable) return [];
    final snapshot =
        await _firestore.collection('whatsapp_conversations').get();

    return snapshot.docs
        .map((doc) => WhatsAppConversation.fromFirestore(doc))
        .where((conv) =>
            conv.phoneNumber.contains(query) ||
            conv.lastMessage.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  /// عدد الرسائل غير المقروءة
  static Stream<int> getUnreadCount() {
    if (!FirebaseAvailability.isAvailable) return Stream.value(0);
    return _firestore.collection('whatsapp_conversations').snapshots().map(
        (snapshot) => snapshot.docs.fold<int>(
            0, (sum, doc) => sum + ((doc.data()['unreadCount'] as int?) ?? 0)));
  }

  /// مراقبة الرسائل الواردة الجديدة وإنشاء المحادثات تلقائياً
  /// ملاحظة: n8n workflow يقوم بإنشاء المحادثات تلقائياً، هذه الدالة للتأكد فقط
  static void startIncomingMessagesListener() {
    // تم تعطيل الـ listener لأن n8n workflow يقوم بإنشاء المحادثات
    // إذا كنت تريد تفعيله، تأكد من عدم وجود duplicate writes
    print('⚠️ تم تعطيل الـ listener - n8n workflow يتولى إنشاء المحادثات');
  }

  /// استيراد الأسماء من الرسائل الموجودة إلى المحادثات
  static Future<void> syncNamesFromMessages() async {
    if (!FirebaseAvailability.isAvailable) return;
    try {
      print('🔄 بدء مزامنة الأسماء من الرسائل...');

      // جلب جميع المحادثات
      final conversationsSnapshot =
          await _firestore.collection('whatsapp_conversations').get();

      for (var convDoc in conversationsSnapshot.docs) {
        final phoneNumber = convDoc.id;
        final currentData = convDoc.data();

        // إذا كان هناك اسم بالفعل، تخطي
        if (currentData['userName'] != null &&
            currentData['userName'].toString().isNotEmpty) {
          continue;
        }

        // البحث عن أحدث رسالة واردة لهذا الرقم من subcollection
        final messagesSnapshot = await _firestore
            .collection('whatsapp_conversations')
            .doc(phoneNumber)
            .collection('messages')
            .where('direction', isEqualTo: 'incoming')
            .limit(1)
            .get();

        if (messagesSnapshot.docs.isNotEmpty) {
          final messageData = messagesSnapshot.docs.first.data();
          final contactName = messageData['contactName'] as String?;

          if (contactName != null && contactName.isNotEmpty) {
            // تحديث المحادثة بالاسم
            await convDoc.reference.update({
              'userName': contactName,
              'contactName': contactName,
            });
            print('✅ تم تحديث اسم $contactName للرقم $phoneNumber');
          }
        }
      }

      print('✅ تمت مزامنة الأسماء بنجاح');
    } catch (e) {
      print('❌ خطأ في مزامنة الأسماء: $e');
    }
  }

  /// مزامنة المحادثات - التحقق من عدد الرسائل لكل محادثة
  /// ملاحظة: مع البنية الجديدة (subcollections) الرسائل محفوظة تحت المحادثات
  static Future<void> syncConversationsFromMessages() async {
    if (!FirebaseAvailability.isAvailable) return;
    try {
      print('🔄 بدء مزامنة المحادثات...');
      print('ℹ️ البنية الجديدة: الرسائل محفوظة كـ subcollection تحت كل محادثة');

      // جلب جميع المحادثات الموجودة
      final conversationsSnapshot =
          await _firestore.collection('whatsapp_conversations').get();

      print('📊 وجدت ${conversationsSnapshot.docs.length} محادثة');

      // التحقق من كل محادثة
      for (var convDoc in conversationsSnapshot.docs) {
        final phoneNumber = convDoc.id;

        // جلب عدد الرسائل في هذه المحادثة
        final messagesSnapshot = await _firestore
            .collection('whatsapp_conversations')
            .doc(phoneNumber)
            .collection('messages')
            .get();

        print(
            '📱 المحادثة $phoneNumber: ${messagesSnapshot.docs.length} رسالة');
      }

      print('✅ تمت مزامنة المحادثات بنجاح');
    } catch (e) {
      print('❌ خطأ في مزامنة المحادثات: $e');
    }
  }
}
