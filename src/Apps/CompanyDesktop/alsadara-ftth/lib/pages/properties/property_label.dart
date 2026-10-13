/// ملصق العنوان الوطني للعقار — الشكل العام الموحّد (QR + رقم الهاتف وحده).
///
/// يستخدم باني الملصق المشترك [buildStickerCell] ليطابق تماماً شكل دفعات QR
/// وأي طباعة ملصق في التطبيق. (التصميم القديم: عنوان + NPN + IQ-Pin + موقع
/// استُبدل بالشكل العام المعتمد.)
library;

import '../../models/property.dart';
import 'property_sticker.dart';

/// يفتح معاينة طباعة ملصق العقار بالشكل العام الموحّد (QR + هاتف).
Future<void> printPropertyLabel(Property p) async {
  final payload = p.qrPayload.isNotEmpty
      ? p.qrPayload
      : (p.qrToken.isNotEmpty ? 'SADARA|P:${p.qrToken}' : '');
  if (payload.isEmpty) return;
  await printSinglePropertySticker(payload);
}
