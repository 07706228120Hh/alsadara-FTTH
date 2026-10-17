import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../services/whatsapp_bulk_sender_service.dart';
import '../services/whatsapp_business_service.dart';

/// صفحة إرسال جماعي من ملف Excel
class WhatsAppExcelSenderPage extends StatefulWidget {
  final bool embedded;
  const WhatsAppExcelSenderPage({super.key, this.embedded = false});

  @override
  State<WhatsAppExcelSenderPage> createState() =>
      _WhatsAppExcelSenderPageState();
}

class _WhatsAppExcelSenderPageState extends State<WhatsAppExcelSenderPage> {
  List<Map<String, String>> _rows = [];
  Set<int> _selectedRows = {};
  String _selectedTemplate = 'sadara_reminder';
  bool _isSending = false;
  String? _result;
  final _offerController = TextEditingController(text: 'باقة مميزة بسعر خاص!');

  final _templates = {
    'sadara_reminder': 'تذكير قبل الانتهاء',
    'sadara_renewed': 'تم التجديد بنجاح',
    'sadara_expired': 'اشتراك منتهي + عروض',
  };

  // ═══════════════════════════════════════
  // تحميل قالب Excel فارغ
  // ═══════════════════════════════════════

  Future<void> _downloadTemplate() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['المستلمين'];

      // العناوين
      sheet.appendRow([
        TextCellValue('الاسم'),
        TextCellValue('رقم الهاتف'),
        TextCellValue('تاريخ الانتهاء'),
        TextCellValue('اسم الباقة'),
        TextCellValue('السعر'),
      ]);

      // صف مثال
      sheet.appendRow([
        TextCellValue('أحمد محمد'),
        TextCellValue('07701234567'),
        TextCellValue('2026-04-30'),
        TextCellValue('TURBO'),
        TextCellValue('35000'),
      ]);

      // حذف Sheet1 الافتراضي
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/قالب_الإرسال_الجماعي.xlsx';
      final file = File(path);
      await file.writeAsBytes(excel.encode()!);

      await OpenFilex.open(path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء القالب — عبّئه ثم ارفعه'),
            backgroundColor: SdColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  // ═══════════════════════════════════════
  // رفع ملف Excel
  // ═══════════════════════════════════════

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes ??
          await File(result.files.first.path!).readAsBytes();

      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first;

      final rows = <Map<String, String>>[];
      final headers = <String>[];

      for (int i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (i == 0) {
          // استخراج العناوين
          for (final cell in row) {
            headers.add(cell?.value?.toString().trim() ?? '');
          }
          continue;
        }

        // استخراج البيانات
        final map = <String, String>{};
        for (int j = 0; j < row.length && j < headers.length; j++) {
          map[headers[j]] = row[j]?.value?.toString().trim() ?? '';
        }

        // تخطي الصفوف الفارغة
        final phone = map['رقم الهاتف'] ?? '';
        if (phone.isNotEmpty) {
          rows.add(map);
        }
      }

      setState(() {
        _rows = rows;
        _selectedRows = Set<int>.from(List.generate(rows.length, (i) => i));
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم استيراد ${rows.length} مستلم'),
            backgroundColor: SdColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في قراءة الملف: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  // ═══════════════════════════════════════
  // إرسال جماعي
  // ═══════════════════════════════════════

  Future<void> _send() async {
    if (_selectedRows.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإرسال'),
        content: Text(
          'سيتم إرسال ${_selectedRows.length} رسالة\n'
          'القالب: ${_templates[_selectedTemplate]}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: SdColors.success),
            child: const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);

    try {
      final phoneNumberId = await WhatsAppBusinessService.getPhoneNumberId() ?? '';
      final accessToken = await WhatsAppBusinessService.getUserToken() ?? '';

      final recipients = _selectedRows.map((i) {
        final row = _rows[i];
        var phone = row['رقم الهاتف'] ?? '';
        if (phone.startsWith('0')) phone = '964${phone.substring(1)}';
        return {
          'phoneNumber': phone,
          'name': row['الاسم'] ?? '',
          'expiryDate': row['تاريخ الانتهاء'] ?? '',
          'planName': row['اسم الباقة'] ?? '',
          'price': row['السعر'] ?? '',
        };
      }).toList();

      final result = await WhatsAppBulkSenderService.sendTemplateMessages(
        templateType: _selectedTemplate,
        recipients: recipients,
        phoneNumberId: phoneNumberId,
        accessToken: accessToken,
        contactNumbers: '07705210210',
        offerText: _selectedTemplate == 'sadara_expired' ? _offerController.text : null,
      );

      setState(() => _isSending = false);

      if (mounted) {
        final success = result['success'] == true;
        final count = result['data']?['totalRecipients'] ?? _selectedRows.length;
        _showResultDialog(success, success
            ? 'تم إرسال $count رسالة بنجاح!\n\nسيتم الإرسال في الخلفية عبر n8n.\nيمكنك متابعة النتائج في تقارير الإرسال.'
            : 'فشل الإرسال: ${result['message'] ?? 'خطأ غير معروف'}');
      }
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
        _showResultDialog(false, 'خطأ: $e');
      }
    }
  }

  void _showResultDialog(bool success, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle : Icons.error,
          size: 64,
          color: success ? SdColors.success : SdColors.danger,
        ),
        title: Text(success ? 'تم الإرسال' : 'فشل الإرسال'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: success ? SdColors.success : SdColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // واجهة المستخدم
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final content = _rows.isEmpty ? _buildEmptyState() : _buildDataView();

    if (widget.embedded) {
      return content;
    }

    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'إرسال جماعي من Excel',
          actions: [
            SdAppBarAction(
              icon: Icons.download,
              label: 'تحميل قالب Excel فارغ',
              onPressed: _downloadTemplate,
            ),
            SdAppBarAction(
              icon: Icons.upload_file,
              label: 'رفع ملف Excel',
              onPressed: _uploadFile,
            ),
          ],
        ),
        body: content,
      ),
    );
  }

  Widget _buildEmptyState() {
    return SdEmptyState(
      title: 'ارفع ملف Excel للبدء',
      icon: Icons.table_chart_outlined,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SdButton(
            label: 'تحميل القالب',
            icon: Icons.download,
            kind: SdButtonKind.secondary,
            onPressed: _downloadTemplate,
          ),
          const SizedBox(width: 16),
          SdButton(
            label: 'رفع ملف Excel',
            icon: Icons.upload_file,
            onPressed: _uploadFile,
          ),
        ],
      ),
    );
  }

  Widget _buildDataView() {
    return Column(
      children: [
        // شريط التحكم
        Container(
          padding: const EdgeInsets.all(12),
          color: SdColors.surfaceAlt,
          child: Row(
            children: [
              // اختيار القالب
              const Text('القالب: ', style: SdText.label),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedTemplate,
                items: _templates.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedTemplate = v ?? 'sadara_reminder'),
              ),
              if (_selectedTemplate == 'sadara_expired') ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 350,
                  child: TextField(
                    controller: _offerController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'نص العرض الخاص',
                      hintText: 'مثال: باقة TURBO بسعر 30,000 فقط!',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: SdColors.warningTint,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // تحديد الكل
              TextButton.icon(
                onPressed: () => setState(() {
                  if (_selectedRows.length == _rows.length) {
                    _selectedRows.clear();
                  } else {
                    _selectedRows = Set<int>.from(List.generate(_rows.length, (i) => i));
                  }
                }),
                icon: Icon(
                  _selectedRows.length == _rows.length
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                label: Text(_selectedRows.length == _rows.length ? 'إلغاء الكل' : 'تحديد الكل'),
              ),
              const SizedBox(width: 8),
              // عداد
              Chip(
                backgroundColor: SdColors.successTint,
                label: Text('${_selectedRows.length} / ${_rows.length} محدد',
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontWeight: FontWeight.w800,
                        color: SdColors.successEdge)),
              ),
              const SizedBox(width: 12),
              // زر إرسال
              ElevatedButton.icon(
                onPressed: _isSending || _selectedRows.isEmpty ? null : _send,
                icon: _isSending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_isSending ? 'جاري الإرسال...' : 'إرسال (${_selectedRows.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        // (النتيجة تظهر كـ dialog)
        // الجدول
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(SdColors.successTint),
                columns: const [
                  DataColumn(label: Text('')),
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('الاسم')),
                  DataColumn(label: Text('رقم الهاتف')),
                  DataColumn(label: Text('تاريخ الانتهاء')),
                  DataColumn(label: Text('الباقة')),
                  DataColumn(label: Text('السعر')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final row = _rows[i];
                  return DataRow(
                    selected: _selectedRows.contains(i),
                    onSelectChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedRows.add(i);
                      } else {
                        _selectedRows.remove(i);
                      }
                    }),
                    cells: [
                      DataCell(Checkbox(
                        value: _selectedRows.contains(i),
                        onChanged: (v) => setState(() {
                          if (v == true) _selectedRows.add(i);
                          else _selectedRows.remove(i);
                        }),
                      )),
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(row['الاسم'] ?? '')),
                      DataCell(Text(row['رقم الهاتف'] ?? '')),
                      DataCell(Text(row['تاريخ الانتهاء'] ?? '')),
                      DataCell(Text(row['اسم الباقة'] ?? '')),
                      DataCell(Text(row['السعر'] ?? '')),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _offerController.dispose();
    super.dispose();
  }
}
