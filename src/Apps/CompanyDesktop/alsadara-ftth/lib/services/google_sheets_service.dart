import 'dart:convert';
import 'package:flutter/services.dart'; // لاستخدام rootBundle
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart'; // لاستخدام clientViaServiceAccount
import '../models/task.dart';
import '../models/filter_criteria.dart';

class GoogleSheetsService {
  static const String _spreadsheetId =
      '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc'; // معرف جدول Google Sheets
  static sheets.SheetsApi? _sheetsApi;
  static AuthClient? _client;

  /// تحقق من وجود ملف الخدمة
  static Future<bool> hasServiceFile() async {
    try {
      await rootBundle.loadString('assets/service_account.json');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// الحصول على معرف الجدول
  static Future<String> getSpreadsheetId() async {
    return _spreadsheetId;
  }

  /// تهيئة الاتصال بـ Google Sheets
  static Future<void> _initializeSheetsAPI() async {
    try {
      if (_sheetsApi != null) {
        return; // إذا كانت API موجودة فلا داعي للتهيئة مرة أخرى
      }
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      final scopes = [sheets.SheetsApi.spreadsheetsScope];
      _client = await clientViaServiceAccount(accountCredentials, scopes);
      _sheetsApi = sheets.SheetsApi(_client!);
    } catch (e) {
      throw Exception('خطأ أثناء تهيئة Google Sheets API: $e');
    }
  }

  /// جلب جميع المهام من جدول Google Sheets
  static Future<List<Task>> fetchTasks() async {
    await _initializeSheetsAPI(); // تأكد من تهيئة API

    try {
      const String range =
          'tasks!A2:T'; // تحديث النطاق ليشمل العمود T (رقم هاتف الفني)
      final response =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, range);
      final rows = response.values ?? [];

      print('📊 تم جلب ${rows.length} صف من Google Sheets');

      // تحويل الصفوف إلى كائنات مهام
      List<Task> tasks = [];

      for (int i = 0; i < rows.length; i++) {
        try {
          final row = rows[i];
          String status = row.length > 1 ? row[1].toString().trim() : '';
          DateTime? closedAt =
              row.length > 13 ? DateTime.tryParse(row[13].toString()) : null;

          // إذا كانت المهمة مكتملة أو ملغية ولم يتم تعيين closedAt، استخدم التاريخ الحالي
          if ((status == 'مكتملة' || status == 'ملغية') && closedAt == null) {
            closedAt =
                DateTime.now(); // تعيين التاريخ الحالي كتاريخ إغلاق افتراضي
            print(
                '⚠️ تم تعيين closedAt تلقائياً للمهمة ${row.isNotEmpty ? row[0] : 'غير معروف'} بحا��ة: $status');
          }

          final task = Task(
            id: row.isNotEmpty ? row[0].toString() : '',
            status: status,
            department: row.length > 2 ? row[2].toString() : '',
            title: row.length > 3 ? row[3].toString() : '',
            leader: row.length > 4 ? row[4].toString() : '',
            technician: row.length > 5 ? row[5].toString() : '',
            username: row.length > 6 ? row[6].toString() : '',
            phone: row.length > 7 ? row[7].toString() : '',
            fbg: row.length > 8 ? row[8].toString() : '',
            fat: row.length > 9 ? row[9].toString() : '',
            location: row.length > 10 ? row[10].toString() : '',
            notes: row.length > 11 ? row[11].toString() : '',
            createdAt: row.length > 12
                ? DateTime.tryParse(row[12].toString()) ?? DateTime.now()
                : DateTime.now(),
            closedAt: closedAt,
            summary: row.length > 14 ? row[14].toString() : '',
            priority: row.length > 15 ? row[15].toString() : '',
            agents: row.length > 16
                ? row[16]
                    .toString()
                    .split(',')
                    .where((agent) => agent.trim().isNotEmpty)
                    .toList()
                : [],
            createdBy: row.length > 16
                ? row[16].toString()
                : '', // Q - منشئ المهمة (العمود Q = الفهرس 16)
            amount: row.length > 17
                ? row[17].toString()
                : '', // R - المبلغ (العمود R = الفهرس 17)
            technicianPhone: row.length > 19
                ? row[19].toString()
                : '', // T - رقم هاتف الفني (العمود T = الفهرس 19)
            statusHistory: [],
          );

          tasks.add(task);
        } catch (e) {
          print('❌ خطأ في معالجة الصف ${i + 2}: $e');
          print('📋 محتوى الصف: ${rows[i]}');
          // ت��اهل الصف المعطل وأكمل مع الصفوف الأخرى
          continue;
        }
      }

      print('✅ تم تحويل ${tasks.length} مهمة بنجاح');
      return tasks;
    } catch (e) {
      print('❌ خطأ عام في جلب المهام: $e');
      throw Exception('حدث خطأ أثناء جلب المهام: $e');
    }
  }

  /// تحديث حالة مهمة موجودة
  static Future<void> updateTaskStatus(Task updatedTask) async {
    try {
      await _initializeSheetsAPI(); // تأكد من تهيئة API
    } catch (e) {
      print('❌ خطأ في تهيئة API: $e');
      throw Exception('فشل في الاتصال بـ Google Sheets: $e');
    }

    try {
      // قائمة بأسماء الأوراق المحتملة
      List<String> possibleSheetNames = [
        'المهام',
        'tasks',
        'Tasks',
        'TASKS',
        'مهام'
      ];

      bool taskUpdated = false;
      print('🔍 البحث عن المهمة بمعرف: ${updatedTask.id}');

      for (String sheetName in possibleSheetNames) {
        try {
          print('📋 البحث في ورقة: $sheetName');

          // جلب جميع البيانات للبحث عن المهمة
          final String searchRange =
              '$sheetName!A2:R'; // تحديث النطاق ليشمل الحقل R
          final response = await _sheetsApi!.spreadsheets.values
              .get(_spreadsheetId, searchRange);
          final rows = response.values ?? [];

          print('📊 عدد الصفوف في $sheetName: ${rows.length}');

          // البحث عن المهمة بناءً على معرفها مع معالجة أنواع البيانات المختلفة
          int? targetRowIndex;
          for (int i = 0; i < rows.length; i++) {
            if (rows[i].isNotEmpty) {
              // تحويل كلا القيمتين إلى نص وإزالة المسافات
              String rowId = rows[i][0].toString().trim();
              String taskId = updatedTask.id.toString().trim();

              print(
                  '🔍 مقارنة: صف $i -> "$rowId" (نوع: ${rows[i][0].runtimeType}) مع "$taskId" (نوع: ${updatedTask.id.runtimeType})');

              // مقارنة مباشرة كنصوص
              bool isMatch = rowId == taskId;

              // مقارنة إضافية كأرقام إذا كانت القيم رقمية
              if (!isMatch) {
                try {
                  double? rowIdNum = double.tryParse(rowId);
                  double? taskIdNum = double.tryParse(taskId);
                  if (rowIdNum != null && taskIdNum != null) {
                    isMatch = rowIdNum == taskIdNum;
                    print(
                        '🔢 مقارنة رقمية: $rowIdNum == $taskIdNum -> $isMatch');
                  }
                } catch (e) {
                  // تجاهل أخطاء التحويل الرقمي
                }
              }

              if (isMatch) {
                targetRowIndex = i +
                    2; // +2 لأن البيانات تبدأ من الصف الثاني والفهرس يبدأ من 0
                print('✅ تم العثور على المهمة في الصف: $targetRowIndex');
                break;
              }
            }
          }

          if (targetRowIndex != null) {
            print('🔄 تحديث المهمة في الصف: $targetRowIndex');

            // تحديث الصف الموجود مع التأكد من ترتيب البيانات الصحيح
            final String updateRange =
                'tasks!A$targetRowIndex:S$targetRowIndex'; // نطاق التحديث: tasks!A:S (بدون T)
            final values = [
              [
                updatedTask.id, // A - معرف المهمة
                updatedTask.status, // B - الحالة
                updatedTask.department, // C - القسم
                updatedTask.title, // D - العنوان
                updatedTask.leader, // E - الليدر
                updatedTask.technician, // F - الفني
                updatedTask.username, // G - اسم المستخدم
                updatedTask.phone, // H - الهاتف
                updatedTask.fbg, // I - FBG
                updatedTask.fat, // J - FAT
                updatedTask.location, // K - الموقع
                updatedTask.notes, // L - الملاحظات (بالعربية)
                updatedTask.createdAt.toIso8601String(), // M - تاريخ الإنشاء
                updatedTask.closedAt?.toIso8601String() ??
                    '', // N - تاريخ الإغلاق
                updatedTask.summary, // O - الملخص
                updatedTask.priority, // P - الأولوية
                updatedTask.createdBy, // Q - منشئ المهمة
                _formatAmountInEnglish(
                    updatedTask.amount), // R - المبلغ (بالأرقام الإنجليزية)
                '', // S - فارغ (محجوز)
                // ملاحظة: العمود T (رقم هاتف الفني) لا يتم تحديثه - يبقى كما هو
              ]
            ];

            print('📝 نطاق التحديث: $updateRange');
            print('📋 عدد الأعمدة: ${values[0].length}');
            print('👤 منشئ المهمة (Q): "${updatedTask.createdBy}"');
            print('💰 المبلغ المراد حفظه (R): "${values[0][17]}"');
            print('📝 الملاحظات المراد حفظها (L): "${updatedTask.notes}"');
            print(
                '📋 البيانات المراد تحديثها: المعرف=${values[0][0]}, الحالة=${values[0][1]}, منشئ المهمة=${values[0][16]}, المبلغ=${values[0][17]}');

            try {
              final valueRange = sheets.ValueRange(values: values);
              await _sheetsApi!.spreadsheets.values.update(
                valueRange,
                _spreadsheetId,
                updateRange,
                valueInputOption: 'USER_ENTERED',
              );

              print('✅ تم تحديث المهمة بنجاح في $sheetName');
              taskUpdated = true;
              break; // تم العثور على المهمة وتحديثها، توقف عن البحث
            } catch (updateError) {
              print('❌ خطأ في تحديث المهمة في $sheetName: $updateError');
              throw Exception('فشل في تحديث المهمة: $updateError');
            }
          } else {
            print('❌ لم يتم العثور على المهمة في $sheetName');
          }
        } catch (e) {
          print('⚠️ خطأ في معالجة ورقة $sheetName: $e');
          // تجاهل الأخطاء في هذه الورقة وجرب الورقة التالية
          continue;
        }
      }

      if (!taskUpdated) {
        print('❌ فشل في العثور على المهمة في جميع الأوراق');

        // إضافة تشخيص إضافي: طباعة جميع المعرفات الموجودة
        await _debugPrintAllTaskIds();

        throw Exception(
            'لم يتم العثور على المهمة بمعرف "${updatedTask.id}" في أي من أوراق Google Sheets');
      }
    } catch (e) {
      print('❌ خطأ عام في تحديث المهمة: $e');
      throw Exception('حدث خطأ أثناء تحديث المهمة: $e');
    }
  }

  /// وظيفة تشخيصية ��طباعة جميع معرفات المهام الموجودة
  static Future<void> _debugPrintAllTaskIds() async {
    try {
      print('🔍 تشخيص: جلب جميع معرفات المهام الموجودة...');

      List<String> possibleSheetNames = [
        'المهام',
        'tasks',
        'Tasks',
        'TASKS',
        'مهام'
      ];

      for (String sheetName in possibleSheetNames) {
        try {
          final String searchRange = '$sheetName!A2:A'; // العمود الأول فقط
          final response = await _sheetsApi!.spreadsheets.values
              .get(_spreadsheetId, searchRange);
          final rows = response.values ?? [];

          if (rows.isNotEmpty) {
            print('📋 معرفات المهام في $sheetName:');
            for (int i = 0; i < rows.length && i < 10; i++) {
              // أول 10 فقط
              if (rows[i].isNotEmpty) {
                print('   الصف ${i + 2}: "${rows[i][0].toString().trim()}"');
              }
            }
            if (rows.length > 10) {
              print('   ... و ${rows.length - 10} صف إضافي');
            }
          } else {
            print('📋 لا توجد بيانات في $sheetName');
          }
        } catch (e) {
          print('⚠️ خطأ في قراءة $sheetName: $e');
        }
      }
    } catch (e) {
      print('❌ خطأ في التشخيص: $e');
    }
  }

  /// ��ضافة مهمة جديدة إلى Google Sheets
  static Future<void> addTask(Task newTask) async {
    await _initializeSheetsAPI(); // تأكد من تهيئة API

    try {
      const String range = 'tasks!A2:Q';
      final values = [
        [
          newTask.id,
          newTask.status,
          newTask.department,
          newTask.title,
          newTask.leader,
          newTask.technician,
          newTask.username,
          newTask.phone,
          newTask.fbg,
          newTask.fat,
          newTask.location,
          newTask.notes,
          newTask.createdAt.toIso8601String(),
          newTask.closedAt?.toIso8601String() ?? '',
          newTask.summary,
          newTask.priority,
          newTask.agents.join(','),
        ]
      ];

      final valueRange = sheets.ValueRange(values: values);
      await _sheetsApi!.spreadsheets.values.append(
        valueRange,
        _spreadsheetId,
        range,
        insertDataOption: 'INSERT_ROWS',
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      throw Exception('حدث خطأ أثناء إضافة المهمة: $e');
    }
  }

  /// تحديث تفاصيل المشترك الموجود (البحث عن السجل وتحديثه بدلاً من إنشاء سجل جديد)
  static Future<void> updateExistingSubscriptionDetails({
    required String customerId,
    required String subscriptionId,
    String? partnerWalletBalanceBefore,
    String? customerWalletBalanceBefore,
    bool? isPrinted,
    bool? isWhatsAppSent,
    String? lastUpdateDate,
  }) async {
    await _initializeSheetsAPI();

    try {
      // البحث عن السجل الموجود بناءً على customerId و subscriptionId
      const String searchRange = 'Account!A:AL';
      final searchResponse = await _sheetsApi!.spreadsheets.values
          .get(_spreadsheetId, searchRange);
      final rows = searchResponse.values ?? [];

      int? targetRowNumber;

      // البحث عن الصف الذي يحتوي على نفس customerId و subscriptionId
      for (int i = 1; i < rows.length; i++) {
        // نبدأ من الصف الثاني (تجاهل العناوين)
        final row = rows[i];
        if (row.length >= 4 &&
            row[0]?.toString() == customerId &&
            row[3]?.toString() == subscriptionId) {
          targetRowNumber = i + 1; // +1 لأن الفهرسة في Google Sheets تبدأ من 1
          break;
        }
      }

      if (targetRowNumber == null) {
        print('⚠️ لم يتم العثور على السجل المطلوب تحديثه');
        // إذا لم يتم العثور على السجل، نستدعي الدالة العادية لإنشاء سجل جديد
        return;
      }

      print('🔍 تم العثور على السجل في الصف: $targetRowNumber');

      // الحصول على البيانات الحالية للصف
      final String currentRowRange =
          'Account!A$targetRowNumber:AL$targetRowNumber';
      final currentRowResponse = await _sheetsApi!.spreadsheets.values
          .get(_spreadsheetId, currentRowRange);
      final currentRowData = currentRowResponse.values?.isNotEmpty == true
          ? List<String>.from(
              currentRowResponse.values!.first.map((e) => e?.toString() ?? ''))
          : List.filled(38, ''); // 38 عمود من A إلى AL

      // تحديث الأعمدة المطلوبة فقط
      if (partnerWalletBalanceBefore != null &&
          partnerWalletBalanceBefore.isNotEmpty) {
        currentRowData[34] =
            partnerWalletBalanceBefore; // AI = العمود 35 (الفهرسة تبدأ من 0)
      }
      if (customerWalletBalanceBefore != null &&
          customerWalletBalanceBefore.isNotEmpty) {
        currentRowData[35] = customerWalletBalanceBefore; // AJ = العمود 36
      }
      if (isPrinted != null) {
        currentRowData[36] = isPrinted ? 'نعم' : 'لا'; // AK = العمود 37
      }
      if (isWhatsAppSent != null) {
        currentRowData[37] = isWhatsAppSent ? 'نعم' : 'لا'; // AL = العمود 38
      }
      if (lastUpdateDate != null) {
        currentRowData[32] = lastUpdateDate; // AG = العمود 33 (تاريخ آخر تحديث)
      }

      // تحديث الصف
      final valueRange = sheets.ValueRange(values: [currentRowData]);
      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        _spreadsheetId,
        currentRowRange,
        valueInputOption: 'USER_ENTERED',
      );

      print('✅ تم تحديث السجل بنجاح في الصف $targetRowNumber');
      print('💰 Partner Wallet Before: $partnerWalletBalanceBefore');
      print('👤 Customer Wallet Before: $customerWalletBalanceBefore');
      print('🖨️ Is Printed: ${isPrinted == true ? "نعم" : "لا"}');
      print('📱 WhatsApp Sent: ${isWhatsAppSent == true ? "نعم" : "لا"}');
    } catch (e) {
      print('❌ خطأ في تحديث تفاصيل الاشتراك: $e');
      throw Exception('حدث خطأ أثناء تحديث تفاصيل الاشتراك: $e');
    }
  }

  /// دالة موحدة لحفظ أو تحديث تفاصيل الاشتراك
  static Future<void> saveOrUpdateSubscriptionDetails({
    required String customerId,
    required String customerName,
    required String phoneNumber,
    required String subscriptionId,
    required String planName,
    required String planPrice,
    required int commitmentPeriod,
    required String operationType,
    required String activatedBy,
    required String activationDate,
    String? sessionId, // معرف فريد للجلسة/العملية الحالية
    // معلومات إضافية اختيارية
    String? zoneId,
    String? bundleId,
    String? currentStatus,
    String? deviceUsername,
    String? expirationDate,
    String? activationTime,
    String? deviceSerial,
    String? macAddress,
    String?
        fdtInfo, // (قد يُعاد استخدامه مستقبلاً في حال إعادة إدراج FDT في الشيت)
    String? fbgInfo, // القيمة المطلوبة الآن في العمود S
    String? fatInfo,
    String? walletBalanceBefore,
    String? walletBalanceAfter,
    String? currency,
    String? salesType,
    String? additionalServices,
    String? paymentMethod,
    String? gpsLatitude,
    String? gpsLongitude,
    String? partnerName,
    String? partnerId,
    String? deviceModel,
    String? subscriptionStartDate,
    String? lastUpdateDate,
    String? operatorNotes,
    String? subscriptionNotes, // ملاحظات الاشتراك للعمود AE
    // الأعمدة الجديدة AI-AL
    String? partnerWalletBalanceBefore,
    String? customerWalletBalanceBefore,
    bool? isPrinted,
    bool? isWhatsAppSent,
  }) async {
    await _initializeSheetsAPI();

    try {
      print('🔍 Searching with sessionId: $sessionId');
      print('🔍 hasGoogleSheetsPermission should be true for this to work');

      // البحث عن السجل الموجود أولاً
      const String searchRange = 'Account!A:AL';
      print('📊 جاري البحث في النطاق: $searchRange');
      final searchResponse = await _sheetsApi!.spreadsheets.values
          .get(_spreadsheetId, searchRange);
      final rows = searchResponse.values ?? [];

      print('📊 عدد الصفوف الموجودة: ${rows.length}');

      int? existingRowNumber;

      // البحث عن الصف الموجود بناءً على sessionId إذا تم توفيره
      // إذا لم يتم توفير sessionId، فسيتم البحث بالطريقة القديمة (customerId + subscriptionId)
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (sessionId != null && sessionId.isNotEmpty) {
          // البحث بناءً على sessionId في عمود AH (ملاحظات المشغل) - العمود 33 (zero-indexed)
          print(
              '🔍 فحص الصف ${i + 1}: ${row.length > 33 ? row[33] : "لا يوجد عمود 33"}');
          if (row.length > 33 &&
              row[33]?.toString().contains(sessionId) == true) {
            existingRowNumber = i + 1;
            print('✅ تم العثور على السجل في الصف: $existingRowNumber');
            break;
          }
        } else {
          print('⚠️ sessionId غير متوفر، البحث بالطريقة القديمة');
          // البحث بالطريقة القديمة (customerId + subscriptionId + نفس التاريخ)
          if (row.length >= 4 &&
              row[0]?.toString() == customerId &&
              row[3]?.toString() == subscriptionId &&
              row.length > 9 &&
              row[9]?.toString() == activationDate) {
            // نفس تاريخ التفعيل
            existingRowNumber = i + 1;
            print(
                '✅ تم العثور على السجل بالطريقة القديمة في الصف: $existingRowNumber');
            break;
          }
        }
      }

      if (existingRowNumber != null) {
        // تحديث السجل الموجود (الأعمدة AI-AL فقط)
        print('🔄 تحديث السجل الموجود في الصف: $existingRowNumber');

        final String updateRange =
            'Account!AI$existingRowNumber:AL$existingRowNumber';
        final updateValues = [
          [
            partnerWalletBalanceBefore ?? '', // AI
            customerWalletBalanceBefore ?? '', // AJ
            isPrinted == true ? 'نعم' : 'لا', // AK
            isWhatsAppSent == true ? 'نعم' : 'لا', // AL
          ]
        ];

        print('📊 تحديث القيم:');
        print(
            '  💼 Partner wallet before: ${partnerWalletBalanceBefore ?? "غير محدد"}');
        print(
            '  👤 Customer wallet before: ${customerWalletBalanceBefore ?? "غير محدد"}');
        print(
            '  🖨️ isPrinted: $isPrinted -> ${isPrinted == true ? "نعم" : "لا"}');
        print(
            '  📱 isWhatsAppSent: $isWhatsAppSent -> ${isWhatsAppSent == true ? "نعم" : "لا"}');

        final valueRange = sheets.ValueRange(values: updateValues);
        await _sheetsApi!.spreadsheets.values.update(
          valueRange,
          _spreadsheetId,
          updateRange,
          valueInputOption: 'USER_ENTERED',
        );

        // تحديث تاريخ آخر تحديث أيضاً
        if (lastUpdateDate != null) {
          final String dateRange = 'Account!AG$existingRowNumber';
          final dateValueRange = sheets.ValueRange(values: [
            [lastUpdateDate]
          ]);
          await _sheetsApi!.spreadsheets.values.update(
            dateValueRange,
            _spreadsheetId,
            dateRange,
            valueInputOption: 'USER_ENTERED',
          );
        }

        print('✅ تم تحديث السجل الموجود بنجاح');

        // محاولة تحديث أعمدة FBG (S) و FAT (T) إذا كانت فارغة مسبقاً ونملك قيم جديدة
        try {
          final existingRow = rows[existingRowNumber - 1];
          final bool shouldUpdateFBG =
              (fbgInfo != null && fbgInfo.trim().isNotEmpty) &&
                  (existingRow.length <= 18 ||
                      existingRow[18].toString().trim().isEmpty);
          final bool shouldUpdateFAT =
              (fatInfo != null && fatInfo.trim().isNotEmpty) &&
                  (existingRow.length <= 19 ||
                      existingRow[19].toString().trim().isEmpty);

          // نبني دفعة تحديث جزئية للأعمدة المطلوبة فقط للحفاظ على أقل عدد طلبات
          if (shouldUpdateFBG) {
            final rangeS = 'Account!S$existingRowNumber';
            final vrS = sheets.ValueRange(values: [
              [fbgInfo]
            ]);
            await _sheetsApi!.spreadsheets.values.update(
              vrS,
              _spreadsheetId,
              rangeS,
              valueInputOption: 'USER_ENTERED',
            );
            print(
                '✏️ تم تحديث FBG في العمود S للصف $existingRowNumber بالقيمة: $fbgInfo');
          }
          if (shouldUpdateFAT) {
            final rangeT = 'Account!T$existingRowNumber';
            final vrT = sheets.ValueRange(values: [
              [fatInfo]
            ]);
            await _sheetsApi!.spreadsheets.values.update(
              vrT,
              _spreadsheetId,
              rangeT,
              valueInputOption: 'USER_ENTERED',
            );
            print(
                '✏️ تم تحديث FAT في العمود T للصف $existingRowNumber بالقيمة: $fatInfo');
          }
        } catch (e) {
          print('⚠️ فشل تحديث الأعمدة S/T الشرطي: $e');
        }
      } else {
        // إنشاء سجل جديد
        print('📝 إنشاء سجل جديد');
        await recordSubscriptionDetails(
          customerId: customerId,
          customerName: customerName,
          phoneNumber: phoneNumber,
          subscriptionId: subscriptionId,
          planName: planName,
          planPrice: planPrice,
          commitmentPeriod: commitmentPeriod,
          operationType: operationType,
          activatedBy: activatedBy,
          activationDate: activationDate,
          zoneId: zoneId,
          bundleId: bundleId,
          currentStatus: currentStatus,
          deviceUsername: deviceUsername,
          expirationDate: expirationDate,
          activationTime: activationTime,
          deviceSerial: deviceSerial,
          macAddress: macAddress,
          // إعادة توجيه: العمود S أصبح الآن مخصصاً لـ FBG حسب طلب المستخدم
          fbgInfo: fbgInfo ?? fdtInfo,
          fatInfo: fatInfo,
          walletBalanceBefore: walletBalanceBefore,
          walletBalanceAfter: walletBalanceAfter,
          currency: currency,
          salesType: salesType,
          additionalServices: additionalServices,
          paymentMethod: paymentMethod,
          gpsLatitude: gpsLatitude,
          gpsLongitude: gpsLongitude,
          partnerName: partnerName,
          partnerId: partnerId,
          deviceModel: deviceModel,
          subscriptionStartDate: subscriptionStartDate,
          lastUpdateDate: lastUpdateDate,
          operatorNotes:
              sessionId != null ? 'SessionID:$sessionId' : operatorNotes,
          subscriptionNotes: subscriptionNotes,
          partnerWalletBalanceBefore: partnerWalletBalanceBefore,
          customerWalletBalanceBefore: customerWalletBalanceBefore,
          isPrinted: isPrinted,
          isWhatsAppSent: isWhatsAppSent,
        );
      }
    } catch (e) {
      print('❌ خطأ في حفظ/تحديث تفاصيل الاشتراك: $e');
      throw Exception('حدث خطأ أثناء حفظ/تحديث تفاصيل الاشتراك: $e');
    }
  }

  /// تسجيل تفاصيل المشترك في ورقة "Account" عند التجديد أو الشراء الجديد
  static Future<void> recordSubscriptionDetails({
    required String customerId,
    required String customerName,
    required String phoneNumber,
    required String subscriptionId,
    required String planName,
    required String planPrice,
    required int commitmentPeriod,
    required String operationType, // "تجديد" أو "اشتراك جديد"
    required String activatedBy, // اسم المستخدم الذي قام بالتفعيل
    required String activationDate,
    // معلومات إضافية اختيارية
    String? zoneId,
    String? bundleId,
    String? currentStatus,
    String? deviceUsername,
    String? expirationDate,
    String? activationTime,
    String? deviceSerial,
    String? macAddress,
    String? fdtInfo, // مهمل حالياً (تم استبداله بـ fbgInfo في العمود S)
    String? fbgInfo, // القيمة التي ستُحفظ في العمود S
    String? fatInfo,
    String? walletBalanceBefore,
    String? walletBalanceAfter,
    String? currency,
    String? salesType,
    String? additionalServices,
    String? paymentMethod,
    // معلومات جديدة إضافية
    String? gpsLatitude,
    String? gpsLongitude,
    String? partnerName,
    String? partnerId,
    String? deviceModel,
    String? subscriptionStartDate,
    String? lastUpdateDate,
    String? operatorNotes,
    String? subscriptionNotes, // ملاحظات الاشتراك للعمود AE
    // الأعمدة الجديدة AI-AL
    String? partnerWalletBalanceBefore, // AI
    String? customerWalletBalanceBefore, // AJ
    bool? isPrinted, // AK
    bool? isWhatsAppSent, // AL
  }) async {
    await _initializeSheetsAPI(); // تأكد من تهيئة API

    try {
      // أولاً، نحتاج لمعرفة آخر صف مُستخدم في الجدول
      const String checkRange =
          'Account!A:A'; // فحص العمود A فقط لمعرفة عدد الصفوف
      final checkResponse =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, checkRange);
      final existingRows = checkResponse.values ?? [];
      final nextRowNumber = existingRows.length + 1; // الصف التالي المتاح

      print('🔍 Current rows in Account sheet: ${existingRows.length}');
      print('📍 Next row number: $nextRowNumber');

      // تحديد النطاق المحدد للصف الجديد من A إلى AN (تم تمديده ليشمل عمود تكرار الطبع)
      final String specificRange = 'Account!A$nextRowNumber:AN$nextRowNumber';
      final values = [
        [
          customerId, // A - معرف العميل
          customerName, // B - اسم العميل
          phoneNumber, // C - رقم الهاتف
          subscriptionId, // D - معرف الاشتراك
          planName, // E - اسم الباقة
          planPrice, // F - سعر الباقة
          commitmentPeriod.toString(), // G - فترة الالتزام
          operationType, // H - نوع العملية
          activatedBy, // I - المُفعِّل
          activationDate, // J - تاريخ التفعيل
          // معلومات إضافية جديدة
          zoneId ?? '', // K - المنطقة
          bundleId ?? '', // L - معرف الحزمة
          currentStatus ?? '', // M - الحالة الحالية
          deviceUsername ?? '', // N - اسم المستخدم للجهاز
          expirationDate ?? '', // O - تاريخ انتهاء الاشتراك
          activationTime ?? '', // P - وقت التفعيل
          deviceSerial ?? '', // Q - السيريال
          macAddress ?? '', // R - عنوان MAC
          fbgInfo ?? '', // S - FBG (حسب التعديل المطلوب)
          fatInfo ?? '', // T - FAT (بدون تغيير)
          walletBalanceBefore ?? '', // U - رصيد المحفظة قبل العملية
          walletBalanceAfter ?? '', // V - رصيد المحفظة بعد العملية
          currency ?? '', // W - العملة
          salesType ?? '', // X - نوع البيع
          additionalServices ?? '', // Y - الخدمات الإضافية
          paymentMethod ?? 'Wallet', // Z - طريقة الدفع
          // معلومات GPS والشريك
          gpsLatitude ?? '', // AA - خط العرض GPS
          gpsLongitude ?? '', // AB - خط الطول GPS
          partnerName ?? '', // AC - اسم الشريك
          partnerId ?? '', // AD - معرف الشريك
          subscriptionNotes ?? '', // AE - ملاحظات الاشتراك
          subscriptionStartDate ?? '', // AF - تاريخ بداية الاشتراك
          lastUpdateDate ??
              DateTime.now().toIso8601String(), // AG - تاريخ آخر تحديث
          operatorNotes ?? '', // AH - ملاحظات المشغل
          // الأعمدة الجديدة AI-AN
          partnerWalletBalanceBefore ??
              '', // AI - رصيد محفظة الشريك قبل العملية
          customerWalletBalanceBefore ??
              '', // AJ - رصيد محفظة العميل قبل العملية
          isPrinted == true ? 'نعم' : 'لا', // AK - تم الطباعة
          isWhatsAppSent == true ? 'نعم' : 'لا', // AL - تم إرسال الواتساب
          '', // AM - فارغ (احتياطي)
          isPrinted == true
              ? '1'
              : '0', // AN - تكرار الطبع (يبدأ من 1 إذا تم الطباعة)
        ]
      ];

      print('📝 Recording subscription details to range: $specificRange');
      print('🆔 Customer ID: $customerId');
      print('📞 Phone: $phoneNumber');
      print('💳 Subscription ID: $subscriptionId');
      print('📦 Plan: $planName ($planPrice)');
      print('🔄 Operation: $operationType by $activatedBy');
      print('💰 Partner Wallet Before: $partnerWalletBalanceBefore');
      print('👤 Customer Wallet Before: $customerWalletBalanceBefore');
      print('🖨️ Is Printed: ${isPrinted == true ? "نعم" : "لا"}');
      print('📱 WhatsApp Sent: ${isWhatsAppSent == true ? "نعم" : "لا"}');

      final valueRange = sheets.ValueRange(values: values);
      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        _spreadsheetId,
        specificRange,
        valueInputOption: 'USER_ENTERED',
      );

      print(
          '✅ تم تسجيل تفاصيل الاشتراك بنجاح في الصف $nextRowNumber مع الأعمدة الإضافية AI-AL');
    } catch (e) {
      print('❌ خطأ في تسجيل تفاصيل الاشتراك: $e');
      throw Exception('حدث خطأ أثناء تسجيل تفاصيل الاشتراك: $e');
    }
  }

  /// وظيفة مساعدة لتنسيق المبلغ بالأرقام الإنجليزية
  static String _formatAmountInEnglish(String amount) {
    if (amount.isEmpty) return '';

    // تحويل الأرقام ��لعربية إلى إنجليزية
    String formattedAmount = amount
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');

    return formattedAmount;
  }

  /// جلب تفاصيل المشترك من ورقة Account
  static Future<Map<String, dynamic>?> getSubscriptionDetails(
      String customerId) async {
    await _initializeSheetsAPI();

    try {
      const String range = 'Account!A:AH'; // من A إلى AH
      final response =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, range);
      final rows = response.values ?? [];

      print('���� البحث عن العميل بمعرف: $customerId في ${rows.length} صف');

      // البحث عن العميل في الصفوف
      for (int i = 1; i < rows.length; i++) {
        // تجاهل الصف الأول (العناوين)
        final row = rows[i];
        if (row.isNotEmpty && row[0].toString().trim() == customerId.trim()) {
          print('✅ تم العثور على العميل في الصف ${i + 1}');

          return {
            'customerId': row.isNotEmpty ? row[0].toString() : '',
            'customerName': row.length > 1 ? row[1].toString() : '',
            'phoneNumber': row.length > 2 ? row[2].toString() : '',
            'subscriptionId': row.length > 3 ? row[3].toString() : '',
            'planName': row.length > 4 ? row[4].toString() : '',
            'planPrice': row.length > 5 ? row[5].toString() : '',
            'commitmentPeriod': row.length > 6 ? row[6].toString() : '',
            'operationType': row.length > 7 ? row[7].toString() : '',
            'activatedBy': row.length > 8 ? row[8].toString() : '',
            'activationDate': row.length > 9 ? row[9].toString() : '',
            'zoneId': row.length > 10 ? row[10].toString() : '',
            'bundleId': row.length > 11 ? row[11].toString() : '',
            'currentStatus': row.length > 12 ? row[12].toString() : '',
            'deviceUsername': row.length > 13 ? row[13].toString() : '',
            'expirationDate': row.length > 14 ? row[14].toString() : '',
            'activationTime': row.length > 15 ? row[15].toString() : '',
            'deviceSerial': row.length > 16 ? row[16].toString() : '',
            'macAddress': row.length > 17 ? row[17].toString() : '',
            // العمود S أصبح الآن يمثل FBG بعد التعديل (سابقاً FDT)
            'fbgInfo': row.length > 18 ? row[18].toString() : '',
            'fatInfo': row.length > 19 ? row[19].toString() : '',
            'walletBalanceBefore': row.length > 20 ? row[20].toString() : '',
            'walletBalanceAfter': row.length > 21 ? row[21].toString() : '',
            'currency': row.length > 22 ? row[22].toString() : '',
            'salesType': row.length > 23 ? row[23].toString() : '',
            'additionalServices': row.length > 24 ? row[24].toString() : '',
            'paymentMethod': row.length > 25 ? row[25].toString() : '',
            'gpsLatitude': row.length > 26 ? row[26].toString() : '',
            'gpsLongitude': row.length > 27 ? row[27].toString() : '',
            'partnerName': row.length > 28 ? row[28].toString() : '',
            'partnerId': row.length > 29 ? row[29].toString() : '',
            'deviceModel': row.length > 30 ? row[30].toString() : '',
            'subscriptionStartDate': row.length > 31 ? row[31].toString() : '',
            'lastUpdateDate': row.length > 32 ? row[32].toString() : '',
            'operatorNotes': row.length > 33 ? row[33].toString() : '',
          };
        }
      }

      print('❌ لم يتم العثور على العميل بمعرف: $customerId');
      return null;
    } catch (e) {
      print('❌ خطأ في جلب تفاصيل المشترك: $e');
      throw Exception('حدث خط�� أثناء جلب تفاصيل المشترك: $e');
    }
  }

  /// تحديث حالة المشترك في ورقة Account
  static Future<void> updateSubscriptionStatus(
      String customerId, String newStatus,
      {String? notes}) async {
    await _initializeSheetsAPI();

    try {
      const String range = 'Account!A:AH';
      final response =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, range);
      final rows = response.values ?? [];

      // البحث عن العميل
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isNotEmpty && row[0].toString().trim() == customerId.trim()) {
          final updateRange =
              'Account!M${i + 1}:AH${i + 1}'; // من M (الحالة) إلى AH

          // تحديث الحالة والملاحظات وتاريخ آخر تحديث
          final values = [
            [
              newStatus, // M - الحالة الحالية
              row.length > 13
                  ? row[13]
                  : '', // N - اسم المستخدم للجهاز (بدون تغيير)
              row.length > 14
                  ? row[14]
                  : '', // O - تاريخ انتهاء الاشتراك (بدون تغيير)
              row.length > 15 ? row[15] : '', // P - وقت التفعيل (بدون تغيير)
              row.length > 16 ? row[16] : '', // Q - السيريال (بدون تغيير)
              row.length > 17 ? row[17] : '', // R - عنوان MAC (بدون تغيير)
              row.length > 18 ? row[18] : '', // S - FBG (تم استبدال FDT)
              row.length > 19 ? row[19] : '', // T - FAT (بدون تغيير)
              row.length > 20
                  ? row[20]
                  : '', // U - رصيد المحفظة قبل (بدون تغيير)
              row.length > 21
                  ? row[21]
                  : '', // V - رصيد المحفظة بعد (بدون تغيير)
              row.length > 22 ? row[22] : '', // W - العملة (بدون تغيير)
              row.length > 23 ? row[23] : '', // X - نوع البيع (بدون تغيير)
              row.length > 24
                  ? row[24]
                  : '', // Y - الخدمات الإضافية (بدون تغيير)
              row.length > 25 ? row[25] : '', // Z - طريقة الدفع (بدون تغيير)
              row.length > 26 ? row[26] : '', // AA - خط العرض GPS (بدون تغيير)
              row.length > 27 ? row[27] : '', // AB - خط الطول GPS (بدون تغيير)
              row.length > 28 ? row[28] : '', // AC - اسم الشريك (بدون تغيير)
              row.length > 29 ? row[29] : '', // AD - معرف الشريك (بدون تغيير)
              row.length > 30 ? row[30] : '', // AE - موديل الجهاز (بدون تغيير)
              row.length > 31
                  ? row[31]
                  : '', // AF - تاريخ بداية الاشتراك (بدون تغيير)
              DateTime.now().toIso8601String(), // AG - تاريخ آخر تحديث (محدث)
              notes ?? (row.length > 33 ? row[33] : ''), // AH - ملاحظات المشغل
            ]
          ];

          final valueRange = sheets.ValueRange(values: values);
          await _sheetsApi!.spreadsheets.values.update(
            valueRange,
            _spreadsheetId,
            updateRange,
            valueInputOption: 'USER_ENTERED',
          );

          print('✅ تم تحديث حالة الم��ترك $customerId إلى: $newStatus');
          return;
        }
      }

      throw Exception('لم يتم العثور على المشترك بمعرف: $customerId');
    } catch (e) {
      print('❌ خطأ في تحديث حالة المشترك: $e');
      throw Exception('حدث خطأ أثناء تحديث حالة المشترك: $e');
    }
  }

  /// جلب جميع السجلات من ورقة Account
  static Future<List<Map<String, dynamic>>> getAllRecords() async {
    await _initializeSheetsAPI();

    try {
      const String range = 'Account!A:AN'; // من A إلى AN لتشمل عمود تكرار الطبع
      final response =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, range);
      final rows = response.values ?? [];

      print('📊 تم جلب ${rows.length} صف من ورقة Account');

      if (rows.isEmpty) {
        print('⚠️ لا توجد بيانات في ورقة Account');
        return [];
      }

      // أول صف يحتوي على العناوين
      final headers = rows[0].map((header) => header.toString()).toList();

      // إنشاء قائمة السجلات
      List<Map<String, dynamic>> records = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        Map<String, dynamic> record = {};

        // تحويل كل صف إلى Map باستخدام العناوين كمفاتيح
        for (int j = 0; j < headers.length && j < row.length; j++) {
          String headerKey = headers[j];
          String cellValue = row[j]?.toString() ?? '';

          // تحويل العناوين الإنجليزية إلى عربية للتوافق مع الواجهة
          switch (headerKey.toLowerCase()) {
            case 'customer_id':
            case 'customerid':
              record['معرف العميل'] = cellValue;
              break;
            case 'customer_name':
            case 'customername':
              record['اسم العميل'] = cellValue;
              break;
            case 'phone_number':
            case 'phonenumber':
              record['رقم الهاتف'] = cellValue;
              break;
            case 'subscription_id':
            case 'subscriptionid':
              record['معرف الاشتراك'] = cellValue;
              break;
            case 'plan_name':
            case 'planname':
              record['اسم الباقة'] = cellValue;
              break;
            case 'plan_price':
            case 'planprice':
              record['سعر الباقة'] = cellValue;
              break;
            case 'commitment_period':
            case 'commitmentperiod':
              record['فترة الالتزام'] = cellValue;
              break;
            case 'operation_type':
            case 'operationtype':
              record['نوع العملية'] = cellValue;
              break;
            case 'activated_by':
            case 'activatedby':
              record['المُفعِّل'] = cellValue;
              break;
            case 'activation_date':
            case 'activationdate':
              record['تاريخ التفعيل'] = cellValue;
              break;
            case 'zone_id':
            case 'zoneid':
              record['المنطقة'] = cellValue;
              break;
            case 'bundle_id':
            case 'bundleid':
              record['معرف الحزمة'] = cellValue;
              break;
            case 'current_status':
            case 'currentstatus':
              record['الحالة الحالية'] = cellValue;
              break;
            case 'device_username':
            case 'deviceusername':
              record['اسم المستخدم للجهاز'] = cellValue;
              break;
            case 'expiration_date':
            case 'expirationdate':
              record['تاريخ انتهاء الاشتراك'] = cellValue;
              break;
            case 'activation_time':
            case 'activationtime':
              record['وقت التفعيل'] = cellValue;
              break;
            case 'device_serial':
            case 'deviceserial':
              record['الس��ريال'] = cellValue;
              break;
            case 'mac_address':
            case 'macaddress':
              record['عنوان MAC'] = cellValue;
              break;
            case 'fdt_info':
            case 'fdtinfo':
              record['FDT'] = cellValue;
              break;
            case 'fat_info':
            case 'fatinfo':
              record['FAT'] = cellValue;
              break;
            case 'wallet_balance_before':
            case 'walletbalancebefore':
              record['رصيد المحفظة قبل العملية'] = cellValue;
              break;
            case 'wallet_balance_after':
            case 'walletbalanceafter':
              record['رصيد المحفظة بعد العملية'] = cellValue;
              break;
            case 'currency':
              record['العملة'] = cellValue;
              break;
            case 'sales_type':
            case 'salestype':
              record['نوع البيع'] = cellValue;
              break;
            case 'additional_services':
            case 'additionalservices':
              record['الخدمات الإضافية'] = cellValue;
              break;
            case 'payment_method':
            case 'paymentmethod':
              record['طريقة الدفع'] = cellValue;
              break;
            case 'gps_latitude':
            case 'gpslatitude':
              record['خط العرض GPS'] = cellValue;
              break;
            case 'gps_longitude':
            case 'gpslongitude':
              record['خط الطول GPS'] = cellValue;
              break;
            case 'partner_name':
            case 'partnername':
              record['اسم الشريك'] = cellValue;
              break;
            case 'partner_id':
            case 'partnerid':
              record['معرف الشريك'] = cellValue;
              break;
            case 'device_model':
            case 'devicemodel':
              record['موديل الجهاز'] = cellValue;
              break;
            case 'subscription_start_date':
            case 'subscriptionstartdate':
              record['تاريخ بداية الاشتراك'] = cellValue;
              break;
            case 'last_update_date':
            case 'lastupdatedate':
              record['تاريخ آخر تحديث'] = cellValue;
              break;
            case 'operator_notes':
            case 'operatornotes':
              record['ملاحظات المشغل'] = cellValue;
              break;
            case 'subscription_notes':
            case 'subscriptionnotes':
              record['ملاحظات الاشتراك'] = cellValue;
              break;
            case 'partner_wallet_balance_before':
            case 'partnerwalletbalancebefore':
              record['رصيد محفظة الشريك قبل العملية'] = cellValue;
              break;
            case 'customer_wallet_balance_before':
            case 'customerwalletbalancebefore':
              record['رصيد محفظة العميل قبل العملية'] = cellValue;
              break;
            case 'is_printed':
            case 'isprinted':
              record['تم الطباعة'] = cellValue;
              break;
            case 'whatsapp_sent':
            case 'whatsappsent':
              record['تم إرسال الواتساب'] = cellValue;
              break;
            case 'print_count':
            case 'printcount':
            case 'reprint_count':
            case 'reprintcount':
            case 'تكرار الطبع':
              record['تكرار الطبع'] = cellValue;
              break;
            default:
              // إذا كان العنوان باللغة العربية بالفعل، استخدمه كما هو
              record[headerKey] = cellValue;
              break;
          }
        }

        // تأكد من وجود المفاتيح الأساسية حتى لو كانت فارغة
        record['معرف العميل'] = record['معرف العميل'] ?? '';
        record['اسم العميل'] = record['اسم العميل'] ?? '';
        record['رقم الهاتف'] = record['رقم الهاتف'] ?? '';
        record['معرف الاشتراك'] = record['معرف الاشتراك'] ?? '';
        record['اسم الباقة'] = record['اسم الباقة'] ?? '';
        record['سعر الباقة'] = record['سعر الباقة'] ?? '';
        record['نوع العملية'] = record['نوع العملية'] ?? '';
        record['المُفعِّل'] = record['المُفعِّل'] ?? '';
        record['تاريخ التفعيل'] = record['تاريخ التفعيل'] ?? '';

        records.add(record);
      }

      print('✅ تم تحويل ${records.length} سجل بنجاح');
      return records;
    } catch (e) {
      print('❌ خطأ في جلب السجلات: $e');
      throw Exception('حدث خطأ أثناء جلب السجلات: $e');
    }
  }

  /// جلب السجلات مع تصفية حسب التاريخ (يتم التصفية قبل إرجاع البيانات)
  /// [fromDate] تاريخ البداية (شامل)
  /// [toDate] تاريخ النهاية (شامل)
  /// إذا كانت القيم null يتم جلب كل السجلات
  static Future<List<Map<String, dynamic>>> getRecordsByDateRange({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    // جلب كل السجلات أولاً
    final allRecords = await getAllRecords();

    // إذا لم يتم تحديد تاريخ، إرجاع الكل
    if (fromDate == null && toDate == null) {
      print('📊 لا يوجد فلتر تاريخ - إرجاع كل السجلات (${allRecords.length})');
      return allRecords;
    }

    // طباعة عينة من التواريخ للتشخيص
    if (allRecords.isNotEmpty) {
      final sample = allRecords.first;
      print('🔍 عينة سجل - التاريخ: ${sample['التاريخ']}');
    }

    // تصفية حسب التاريخ
    final filteredRecords = allRecords.where((record) {
      // البحث عن التاريخ - العامود J اسمه "التاريخ"
      String dateStr = record['التاريخ']?.toString() ?? '';
      if (dateStr.isEmpty) {
        dateStr = record['تاريخ التفعيل']?.toString() ?? '';
      }
      if (dateStr.isEmpty) {
        dateStr = record['activation_date']?.toString() ?? '';
      }
      if (dateStr.isEmpty) {
        dateStr = record['date']?.toString() ?? '';
      }

      if (dateStr.isEmpty) {
        return false; // تجاهل السجلات بدون تاريخ
      }

      // محاولة تحليل التاريخ بعدة صيغ
      DateTime? recordDate = _parseDateString(dateStr);

      if (recordDate == null) {
        print('⚠️ فشل تحليل التاريخ: $dateStr');
        return false;
      }

      // مقارنة التواريخ (فقط اليوم بدون الوقت)
      final recordDay =
          DateTime(recordDate.year, recordDate.month, recordDate.day);

      if (fromDate != null && toDate != null) {
        final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
        final to = DateTime(toDate.year, toDate.month, toDate.day);
        return !recordDay.isBefore(from) && !recordDay.isAfter(to);
      } else if (fromDate != null) {
        final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
        return !recordDay.isBefore(from);
      } else if (toDate != null) {
        final to = DateTime(toDate.year, toDate.month, toDate.day);
        return !recordDay.isAfter(to);
      }

      return true;
    }).toList();

    print(
        '📊 تصفية التاريخ: من ${fromDate?.toString().split(' ')[0] ?? 'غير محدد'} إلى ${toDate?.toString().split(' ')[0] ?? 'غير محدد'}');
    print(
        '📊 النتيجة: ${filteredRecords.length} سجل من أصل ${allRecords.length}');

    return filteredRecords;
  }

  /// تحليل نص التاريخ بعدة صيغ مختلفة
  static DateTime? _parseDateString(String dateStr) {
    if (dateStr.isEmpty) return null;

    try {
      // إزالة المسافات الزائدة
      dateStr = dateStr.trim();

      // صيغة: yyyy-MM-dd HH:mm:ss أو yyyy-MM-dd
      if (dateStr.contains('-')) {
        final datePart = dateStr.split(' ')[0]; // إزالة الوقت إن وجد
        final parts = datePart.split('-');
        if (parts.length >= 3) {
          final result = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          print('📅 تحليل تاريخ (yyyy-MM-dd): $dateStr -> $result');
          return result;
        }
      }

      // صيغة: d/M/yyyy أو dd/MM/yyyy أو yyyy/MM/dd (مثل 1/12/2025)
      if (dateStr.contains('/')) {
        final datePart = dateStr.split(' ')[0]; // إزالة الوقت إن وجد
        final parts = datePart.split('/');
        if (parts.length >= 3) {
          // التحقق من الصيغة
          if (parts[0].length == 4) {
            // yyyy/MM/dd
            final result = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
            print('📅 تحليل تاريخ (yyyy/MM/dd): $dateStr -> $result');
            return result;
          } else if (parts[2].length == 4) {
            // d/M/yyyy أو dd/MM/yyyy (مثل 1/12/2025 = 1 ديسمبر 2025)
            final result = DateTime(
              int.parse(parts[2]), // السنة
              int.parse(parts[1]), // الشهر
              int.parse(parts[0]), // اليوم
            );
            print('📅 تحليل تاريخ (d/M/yyyy): $dateStr -> $result');
            return result;
          } else if (parts[2].length == 2) {
            // dd/MM/yy - افتراض 2000+
            final result = DateTime(
              2000 + int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
            print('📅 تحليل تاريخ (d/M/yy): $dateStr -> $result');
            return result;
          }
        }
      }

      // صيغة: dd.MM.yyyy
      if (dateStr.contains('.')) {
        final datePart = dateStr.split(' ')[0];
        final parts = datePart.split('.');
        if (parts.length >= 3) {
          return DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      }
    } catch (e) {
      print('❌ خطأ في تحليل التاريخ "$dateStr": $e');
    }

    return null;
  }

  /// تحديث ملاحظات الاشتراك في العمود AE فقط للمشترك الموجود
  static Future<void> updateSubscriptionNotes({
    required String subscriptionId,
    required String subscriptionNotes,
    String? sessionId,
  }) async {
    try {
      print('🔄 جاري تحديث ملاحظات المشترك $subscriptionId...');
      print('📝 الملاحظات الجديدة: $subscriptionNotes');
      print('🆔 SessionID للبحث: $sessionId');

      await _initializeSheetsAPI();

      // البحث في العمود AH عن SessionID
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId,
        'Account!AH:AH', // العمود AH فقط
      );

      int targetRow = -1;

      if (response.values != null) {
        print('🔍 البحث في ${response.values!.length} صف في العمود AH...');

        // البحث عن SessionID في العمود AH
        if (sessionId != null && sessionId.isNotEmpty) {
          final searchPattern = 'SessionID:$sessionId';
          print('🎯 البحث عن: $searchPattern');

          for (int i = 0; i < response.values!.length; i++) {
            final row = response.values![i];
            if (row.isNotEmpty && row[0] != null) {
              final cellValue = row[0].toString().trim();
              if (cellValue.contains(searchPattern)) {
                targetRow = i + 1; // إضافة 1 لأن Google Sheets يبدأ من 1
                print('✅ تم العثور على SessionID في السطر $targetRow');
                break;
              }
            }
          }
        }
      }

      if (targetRow == -1) {
        print('❌ لم يتم العثور على SessionID: $sessionId');
        throw Exception(
            'لم يتم العثور على السطر المطابق للـ SessionID: $sessionId');
      }

      print('🎯 تحديث العمود AE في السطر $targetRow');

      // تحديث العمود AE (رقم 31) في السطر المحدد
      final updateRequest = sheets.ValueRange(
        values: [
          [subscriptionNotes.isNotEmpty ? subscriptionNotes : '']
        ],
      );

      await _sheetsApi!.spreadsheets.values.update(
        updateRequest,
        _spreadsheetId,
        'Account!AE$targetRow', // العمود AE في السطر المحدد
        valueInputOption: 'RAW',
      );

      print(
          '✅ تم تحديث ملاحظات السطر $targetRow بنجاح (SessionID: $sessionId)');
    } catch (e) {
      print('❌ خطأ في تحديث ملاحظات المشترك: $e');
      throw Exception('حدث خطأ أثناء تحديث ملاحظات المشترك: $e');
    }
  }

  /// زيادة عداد تكرار الطباعة في العمود AN
  static Future<int> incrementPrintCount({
    required String sessionId,
  }) async {
    try {
      print('🔄 جاري زيادة عداد تكرار الطباعة للجلسة: $sessionId');

      await _initializeSheetsAPI();

      // البحث في العمود AH عن SessionID
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId,
        'Account!AH:AN', // من العمود AH إلى AN
      );

      int targetRow = -1;
      int currentCount = 0;

      if (response.values != null) {
        print('🔍 البحث في ${response.values!.length} صف...');

        if (sessionId.isNotEmpty) {
          final searchPattern = 'SessionID:$sessionId';
          print('🎯 البحث عن: $searchPattern');

          for (int i = 0; i < response.values!.length; i++) {
            final row = response.values![i];
            if (row.isNotEmpty && row[0] != null) {
              final cellValue = row[0].toString().trim();
              if (cellValue.contains(searchPattern)) {
                targetRow = i + 1; // إضافة 1 لأن Google Sheets يبدأ من 1
                // قراءة القيمة الحالية من العمود AN (index 6 في النطاق المقروء)
                // AH=0, AI=1, AJ=2, AK=3, AL=4, AM=5, AN=6
                if (row.length > 6 && row[6] != null) {
                  final existingValue = row[6].toString().trim();
                  currentCount = int.tryParse(existingValue) ?? 0;
                }
                print(
                    '✅ تم العثور على السجل في السطر $targetRow، العداد الحالي: $currentCount');
                break;
              }
            }
          }
        }
      }

      if (targetRow == -1) {
        print('❌ لم يتم العثور على SessionID: $sessionId');
        return 0;
      }

      // زيادة العداد
      final newCount = currentCount + 1;
      print(
          '🎯 تحديث العمود AN في السطر $targetRow من $currentCount إلى $newCount');

      // تحديث العمود AN في السطر المحدد
      final updateRequest = sheets.ValueRange(
        values: [
          [newCount.toString()]
        ],
      );

      await _sheetsApi!.spreadsheets.values.update(
        updateRequest,
        _spreadsheetId,
        'Account!AN$targetRow', // العمود AN في السطر المحدد
        valueInputOption: 'RAW',
      );

      print('✅ تم تحديث عداد تكرار الطباعة إلى $newCount بنجاح');
      return newCount;
    } catch (e) {
      print('❌ خطأ في زيادة عداد الطباعة: $e');
      return 0;
    }
  }

  /// جلب عدد مرات الطباعة للسجل
  static Future<int> getPrintCount({
    required String sessionId,
  }) async {
    try {
      await _initializeSheetsAPI();

      // البحث في العمود AH عن SessionID
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId,
        'Account!AH:AN', // من العمود AH إلى AN
      );

      if (response.values != null && sessionId.isNotEmpty) {
        final searchPattern = 'SessionID:$sessionId';

        for (int i = 0; i < response.values!.length; i++) {
          final row = response.values![i];
          if (row.isNotEmpty && row[0] != null) {
            final cellValue = row[0].toString().trim();
            if (cellValue.contains(searchPattern)) {
              // قراءة القيمة من العمود AN (index 6)
              if (row.length > 6 && row[6] != null) {
                final existingValue = row[6].toString().trim();
                return int.tryParse(existingValue) ?? 0;
              }
              return 0;
            }
          }
        }
      }

      return 0;
    } catch (e) {
      print('❌ خطأ في جلب عداد الطباعة: $e');
      return 0;
    }
  }

  /// جلب جميع الوصولات التي تحتوي على موديل جهاز (عامود AE) مجمعة حسب المستخدم
  static Future<Map<String, List<Map<String, dynamic>>>>
      getConnectionsWithNotes() async {
    return await getFilteredConnectionsWithNotes(null);
  }

  /// جلب الوصولات مع تطبيق معايير التصفية
  static Future<Map<String, List<Map<String, dynamic>>>>
      getFilteredConnectionsWithNotes(FilterCriteria? filterCriteria) async {
    await _initializeSheetsAPI();

    print(
        '🔍 getFilteredConnectionsWithNotes called with filterCriteria: ${filterCriteria?.toString() ?? "null"}');

    try {
      const String range =
          'Account!A:AM'; // من A إلى AM (يشمل عامود AE - موديل الجهاز وعامود AM - حالة التسديد)
      final response =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, range);

      final rows = response.values ?? [];

      if (rows.isEmpty || rows.length < 2) {
        return {};
      }

      Map<String, List<Map<String, dynamic>>> groupedData = {};
      int totalRows = rows.length - 1; // عدد الصفوف عدا العنوان
      int filteredRows = 0; // عدد الصفوف بعد التصفية

      // تجاهل الصف الأول (العناوين) والبدء من الصف الثاني
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        // التحقق من وجود قيمة في عامود AE (موديل الجهاز - الفهرس 30)
        String deviceModel = '';
        if (row.length > 30 &&
            row[30] != null &&
            row[30].toString().trim().isNotEmpty) {
          deviceModel = row[30].toString().trim();
        }

        // إذا لم يوجد موديل الجهاز، تجاهل هذا الصف
        if (deviceModel.isEmpty) continue;

        // الحصول على اسم المستخدم من عامود I (المُفعل بواسطة - الفهرس 8)
        String userName = '';
        if (row.length > 8 &&
            row[8] != null &&
            row[8].toString().trim().isNotEmpty) {
          userName = row[8].toString().trim();
        } else {
          userName = 'غير محدد';
        }

        // إنشاء كائن البيانات
        Map<String, dynamic> connectionData = {
          'customerId': row.isNotEmpty ? row[0].toString() : '',
          'customerName': row.length > 1 ? row[1].toString() : '',
          'phoneNumber': row.length > 2 ? row[2].toString() : '',
          'subscriptionId': row.length > 3 ? row[3].toString() : '',
          'planName': row.length > 4 ? row[4].toString() : '',
          'planPrice': row.length > 5 ? row[5].toString() : '',
          'operationType': row.length > 7 ? row[7].toString() : '',
          'activatedBy': userName,
          'activationDate': row.length > 9 ? row[9].toString() : '',
          'zoneId': row.length > 10 ? row[10].toString() : '',
          'currentStatus': row.length > 12 ? row[12].toString() : '',
          'deviceModel': deviceModel, // استخدام موديل الجهاز من عامود AE
          'paymentMethod': row.length > 25 ? row[25].toString() : '',
          'currency': row.length > 22 ? row[22].toString() : '',
          'paymentStatus': row.length > 38
              ? row[38].toString()
              : '', // العامود AM (الفهرس 38)
        };

        // طباعة تشخيصية للتحقق من قراءة العامود AM
        if (i < 3) {
          // طباعة أول 3 صفوف فقط للتشخيص
          print('📋 الصف ${i + 2}: طول الصف = ${row.length}');
          if (row.length > 38) {
            print('   العامود AM (38): "${row[38]}"');
          } else {
            print('   العامود AM غير متوفر - الصف قصير جداً');
          }
          print(
              '   حالة التسديد النهائية: "${connectionData['paymentStatus']}"');
        }

        // تطبيق معايير التصفية إذا كانت متوفرة
        if (filterCriteria != null) {
          print('🎯 تطبيق التصفية على الصف $i: اسم المستخدم=$userName');

          // تصفية حسب نوع العملية
          if (filterCriteria.selectedOperationFilter != 'الكل') {
            String operationType = connectionData['operationType'] ?? '';
            print(
                '   - فحص نوع العملية: "$operationType" مقابل "${filterCriteria.selectedOperationFilter}"');

            if (filterCriteria.selectedOperationFilter == 'تجديد اشتراك') {
              if (!operationType.contains('تجديد') &&
                  !operationType.contains('تغيير')) {
                print('   ❌ تم رفض الصف: نوع العملية لا يطابق "تجديد اشتراك"');
                continue; // تجاهل هذا الصف
              }
            } else if (filterCriteria.selectedOperationFilter ==
                'شراء اشتراك جديد') {
              if (!operationType.contains('شراء') &&
                  !operationType.contains('جديد')) {
                print(
                    '   ❌ تم رفض الصف: نوع العملية لا يطابق "شراء اشتراك جديد"');
                continue; // تجاهل هذا الصف
              }
            } else if (!operationType
                .contains(filterCriteria.selectedOperationFilter)) {
              print(
                  '   ❌ تم رفض الصف: نوع العملية لا يطابق "${filterCriteria.selectedOperationFilter}"');
              continue; // تجاهل هذا الصف
            }
            print('   ✅ نوع العملية مطابق');
          }

          // تصفية حسب الزون
          if (filterCriteria.selectedZoneFilter != 'الكل') {
            String zoneId = connectionData['zoneId'] ?? '';
            print(
                '   - فحص الزون: "$zoneId" مقابل "${filterCriteria.selectedZoneFilter}"');
            if (!zoneId.contains(filterCriteria.selectedZoneFilter)) {
              print('   ❌ تم رفض الصف: الزون لا يطابق');
              continue; // تجاهل هذا الصف
            }
            print('   ✅ الزون مطابق');
          }

          // تصفية حسب منفذ العملية
          if (filterCriteria.selectedExecutorFilter != 'الكل') {
            String activatedBy = connectionData['activatedBy'] ?? '';
            print(
                '   - فحص منفذ العملية: "$activatedBy" مقابل "${filterCriteria.selectedExecutorFilter}"');
            if (!activatedBy.contains(filterCriteria.selectedExecutorFilter)) {
              print('   ❌ تم رفض الصف: منفذ العملية لا يطابق');
              continue; // تجاهل هذا الصف
            }
            print('   ✅ منفذ العملية مطابق');
          }

          // تصفية حسب طريقة الدفع
          if (filterCriteria.selectedPaymentTypeFilter != 'الكل') {
            String paymentMethod = connectionData['paymentMethod'] ?? '';
            if (filterCriteria.selectedPaymentTypeFilter == 'نقد' &&
                !paymentMethod.contains('نقد')) {
              continue;
            } else if (filterCriteria.selectedPaymentTypeFilter == 'آجل' &&
                !paymentMethod.contains('آجل')) {
              continue;
            }
          }

          // تصفية حسب التاريخ
          if (filterCriteria.fromDate != null ||
              filterCriteria.toDate != null) {
            String activationDateStr = connectionData['activationDate'] ?? '';
            print('   - فحص التاريخ: "$activationDateStr"');
            print('     من تاريخ: ${filterCriteria.fromDate}');
            print('     إلى تاريخ: ${filterCriteria.toDate}');

            if (activationDateStr.isNotEmpty) {
              try {
                DateTime? recordDate = DateTime.tryParse(activationDateStr);
                if (recordDate != null) {
                  print('     تاريخ السجل المحول: $recordDate');
                  DateTime? lowerBound;
                  DateTime? upperBound;

                  if (filterCriteria.fromDate != null) {
                    if (filterCriteria.fromTime != null) {
                      lowerBound = DateTime(
                          filterCriteria.fromDate!.year,
                          filterCriteria.fromDate!.month,
                          filterCriteria.fromDate!.day,
                          filterCriteria.fromTime!.hour,
                          filterCriteria.fromTime!.minute);
                    } else {
                      lowerBound = DateTime(
                          filterCriteria.fromDate!.year,
                          filterCriteria.fromDate!.month,
                          filterCriteria.fromDate!.day);
                    }
                    print('     الحد الأدنى: $lowerBound');
                  }

                  if (filterCriteria.toDate != null) {
                    if (filterCriteria.toTime != null) {
                      upperBound = DateTime(
                          filterCriteria.toDate!.year,
                          filterCriteria.toDate!.month,
                          filterCriteria.toDate!.day,
                          filterCriteria.toTime!.hour,
                          filterCriteria.toTime!.minute);
                    } else {
                      upperBound = DateTime(
                          filterCriteria.toDate!.year,
                          filterCriteria.toDate!.month,
                          filterCriteria.toDate!.day,
                          23,
                          59,
                          59);
                    }
                    print('     الحد الأعلى: $upperBound');
                  }

                  if (lowerBound != null && recordDate.isBefore(lowerBound)) {
                    print('   ❌ تم رفض الصف: التاريخ أقدم من الحد الأدنى');
                    continue; // تجاهل هذا الصف
                  }
                  if (upperBound != null && recordDate.isAfter(upperBound)) {
                    print('   ❌ تم رفض الصف: التاريخ أحدث من الحد الأعلى');
                    continue; // تجاهل هذا الصف
                  }
                  print('   ✅ التاريخ مطابق');
                }
              } catch (e) {
                print('   ❌ تم رفض الصف: فشل في تحليل التاريخ - $e');
                // في حالة فشل تحليل التاريخ، تجاهل هذا الصف
                continue;
              }
            } else {
              print('   ❌ تم رفض الصف: لا يوجد تاريخ');
              // إذا لم يوجد تاريخ وكانت التصفية بالتاريخ مفعلة، تجاهل هذا الصف
              continue;
            }
          }

          // تصفية حسب البحث النصي
          if (filterCriteria.searchQuery.isNotEmpty) {
            String searchQuery = filterCriteria.searchQuery.toLowerCase();
            bool matchFound = false;

            List<String> fieldsToSearch = [
              connectionData['customerName'] ?? '',
              connectionData['phoneNumber'] ?? '',
              connectionData['deviceModel'] ?? '',
              connectionData['customerId'] ?? '',
              connectionData['subscriptionId'] ?? '',
            ];

            for (String field in fieldsToSearch) {
              if (field.toLowerCase().contains(searchQuery)) {
                matchFound = true;
                break;
              }
            }

            if (!matchFound) {
              print('   ❌ تم رفض الصف: لا يطابق البحث النصي');
              continue; // تجاهل هذا الصف
            }
            print('   ✅ البحث النصي مطابق');
          }

          print('   🎉 تم قبول الصف: جميع معايير التصفية مطابقة');
        } else {
          print('   🔓 لا توجد معايير تصفية - تم قبول الصف');
        }

        // تجميع البيانات حسب المستخدم
        if (!groupedData.containsKey(userName)) {
          groupedData[userName] = [];
        }
        groupedData[userName]!.add(connectionData);
        filteredRows++; // زيادة عدد الصفوف المفلترة
      }

      print(
          '🔍 التصفية - المجموع: $totalRows، بعد التصفية: $filteredRows، المستخدمون: ${groupedData.length}');

      // طباعة تفاصيل FilterCriteria إذا كانت متوفرة
      if (filterCriteria != null && filterCriteria.hasActiveFilters) {
        print('📋 معايير التصفية النشطة:');
        print('   - نوع العملية: ${filterCriteria.selectedOperationFilter}');
        print('   - الزون: ${filterCriteria.selectedZoneFilter}');
        print('   - منفذ العملية: ${filterCriteria.selectedExecutorFilter}');
        print('   - طريقة الدفع: ${filterCriteria.selectedPaymentTypeFilter}');
        print('   - البحث: "${filterCriteria.searchQuery}"');
        if (filterCriteria.fromDate != null) {
          print('   - من تاريخ: ${filterCriteria.fromDate}');
        }
        if (filterCriteria.toDate != null) {
          print('   - إلى تاريخ: ${filterCriteria.toDate}');
        }
      } else {
        print('🔓 لا توجد معايير تصفية نشطة');
      }

      print(
          '✅ تم جلب ${groupedData.length} مستخدم مع وصولات تحتوي على موديل جهاز (عامود AE)');
      return groupedData;
    } catch (e) {
      print('❌ خطأ في جلب الوصولات مع موديل الجهاز: $e');
      throw Exception('خطأ في جلب البيانات من Google Sheets: $e');
    }
  }

  /// تحديث حالة التسديد في العامود AM
  static Future<void> updatePaymentStatus({
    required String subscriptionId,
    required String customerName,
    required String paymentStatus,
  }) async {
    await _initializeSheetsAPI();

    try {
      print('🔄 بدء تحديث حالة التسديد...');
      print('   - معرف الاشتراك: $subscriptionId');
      print('   - اسم العميل: $customerName');
      print('   - حالة التسديد: $paymentStatus');

      // قراءة جميع البيانات للعثور على السجل المطابق
      const String range = 'Account!A2:AM'; // من A2 إلى العامود AM
      final response =
          await _sheetsApi!.spreadsheets.values.get(_spreadsheetId, range);
      final rows = response.values ?? [];

      print('📊 تم جلب ${rows.length} صف للبحث عن السجل');

      // البحث عن السجل المطابق
      int targetRowIndex = -1;
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];

        // البحث حسب معرف الاشتراك (العامود I - الفهرس 8) أو اسم العميل (العامود B - الفهرس 1)
        final rowSubscriptionId =
            row.length > 8 ? row[8].toString().trim() : '';
        final rowCustomerName = row.length > 1 ? row[1].toString().trim() : '';

        if ((subscriptionId.isNotEmpty &&
                rowSubscriptionId == subscriptionId) ||
            (customerName.isNotEmpty && rowCustomerName == customerName)) {
          targetRowIndex = i +
              2; // +2 لأن البيانات تبدأ من الصف 2 ومصفوفة البيانات تبدأ من 0
          print('✅ تم العثور على السجل في الصف: $targetRowIndex');
          break;
        }
      }

      if (targetRowIndex == -1) {
        throw Exception('لم يتم العثور على السجل المطابق');
      }

      // تحديث العامود AM (الفهرس 38) في الصف المحدد
      final updateRange = 'Account!AM$targetRowIndex';
      final valueRange = sheets.ValueRange();
      valueRange.values = [
        [paymentStatus]
      ];

      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        _spreadsheetId,
        updateRange,
        valueInputOption: 'RAW',
      );

      print('✅ تم تحديث العامود AM بنجاح في الصف $targetRowIndex');
      print('   - القيمة الجديدة: $paymentStatus');
    } catch (e) {
      print('❌ خطأ في تحديث حالة التسديد: $e');
      throw Exception('خطأ في تحديث حالة التسديد: $e');
    }
  }

  /// إغلاق الاتصال
  static void dispose() {
    _client?.close();
    _sheetsApi = null;
    _client = null;
  }
}
