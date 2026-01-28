import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// بسيط: يرسل أوامر ESC/POS عبر TCP/IP لقص الورق بعد الطباعة.
class EscposCutterService {
  /// يرسل تغذية ثم أمر قطع. إذا كان [partial] true يستخدم القطع الجزئي.
  static Future<void> sendCut({
    required String host,
    required int port,
    int feedLines = 3,
    bool partial = true,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (host.trim().isEmpty) return;
    final bytesBuilder = BytesBuilder();

    // Initialize printer (optional but common)
    bytesBuilder.add([0x1B, 0x40]); // ESC @

    // Feed lines before cut
    if (feedLines > 0) {
      bytesBuilder.add([0x1B, 0x64, feedLines.clamp(0, 255)]); // ESC d n
    }

    // Cut command
    // GS V m (m = 0 full, 1 partial) — many printers support these
    bytesBuilder.add([0x1D, 0x56, partial ? 0x01 : 0x00]);

    final data = bytesBuilder.toBytes();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(data);
      await socket.flush();
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('ESC/POS cut send failed: $e\n$st');
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await socket?.close();
    }
  }
}
