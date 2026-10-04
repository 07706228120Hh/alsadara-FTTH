/// اسم الصفحة: إعدادات الطباعة
/// وصف الصفحة: اختيار طابعة الإيصالات (الحرارية) + تجربة الطباعة الصامتة
/// المؤلف: تطبيق السدارة
library;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/thermal_printer_service.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  bool _loading = true;
  bool _busy = false;
  List<Printer> _printers = const [];
  // null = الطابعة الافتراضية للنظام.
  String? _selectedName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final printers = await ThermalPrinterService.listSystemPrinters();
    final saved = await ThermalPrinterService.getReceiptPrinterName();
    if (!mounted) return;
    setState(() {
      _printers = printers;
      // أبقِ الاسم المحفوظ حتى لو لم يَعُد موجوداً (نعرضه كتحذير).
      _selectedName = saved;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ThermalPrinterService.setReceiptPrinterName(_selectedName);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
        _selectedName == null
            ? 'تم الحفظ: ستُطبع الإيصالات على الطابعة الافتراضية المتاحة'
            : 'تم حفظ طابعة الإيصالات: $_selectedName',
        ok: true);
  }

  Future<void> _test() async {
    Printer? target;
    if (_selectedName != null) {
      for (final p in _printers) {
        if (p.name == _selectedName) {
          target = p;
          break;
        }
      }
    } else {
      // الافتراضية المتاحة، وإلا أول متاحة.
      for (final p in _printers) {
        if (p.isDefault && p.isAvailable) {
          target = p;
          break;
        }
      }
      target ??= _printers.where((p) => p.isAvailable).cast<Printer?>().firstWhere(
            (_) => true,
            orElse: () => null,
          );
    }
    if (target == null) {
      _snack('لا توجد طابعة متاحة للتجربة', ok: false);
      return;
    }
    setState(() => _busy = true);
    final ok = await ThermalPrinterService.testPrintToPrinter(target);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
        ok ? 'أُرسلت صفحة التجربة إلى ${target.name}' : 'فشلت تجربة الطباعة',
        ok: ok);
  }

  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.right),
      backgroundColor: ok ? Colors.green[700] : Colors.red[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final savedMissing = _selectedName != null &&
        !_printers.any((p) => p.name == _selectedName);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات طابعة الإيصالات'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث القائمة',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.print, size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'اختر الطابعة التي تُطبع عليها الإيصالات. الطباعة صامتة '
                      'ومباشرة (بلا حوار ويندوز)، وتُتخطّى بأمان إن كانت الطابعة '
                      'غير متاحة.',
                      style: TextStyle(fontSize: 13.5, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    if (_printers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: const Text(
                            '❌ لا توجد طابعات مثبّتة على النظام. ثبّت طابعة ثم '
                            'اضغط تحديث.'),
                      )
                    else ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _printers.any((p) => p.name == _selectedName)
                            ? _selectedName
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'طابعة الإيصالات',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('الطابعة الافتراضية المتاحة (تلقائي)'),
                          ),
                          ..._printers.map((p) => DropdownMenuItem<String?>(
                                value: p.name,
                                child: Text(
                                  '${p.name}'
                                  '${p.isDefault ? ' (افتراضية)' : ''}'
                                  '${p.isAvailable ? '' : ' — غير متاحة'}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.isAvailable
                                        ? null
                                        : Colors.red[700],
                                  ),
                                ),
                              )),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _selectedName = v),
                      ),
                      if (savedMissing) ...[
                        const SizedBox(height: 10),
                        Text(
                          '⚠️ الطابعة المحفوظة «$_selectedName» غير موجودة حالياً — '
                          'اختر طابعة أخرى واحفظ.',
                          style: TextStyle(
                              color: Colors.orange[800],
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _save,
                              icon: const Icon(Icons.save),
                              label: const Text('حفظ'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _test,
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('تجربة طباعة'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.yellow[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ملاحظات:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text('• اختر طابعة الإيصالات الحرارية — لا طابعة A4.'),
                          Text('• «غير متاحة» تعني أن النظام يراها غير جاهزة؛ '
                              'لن تُرسَل لها الإيصالات تفادياً لتعليق الطباعة.'),
                          Text('• «تلقائي» يستخدم الطابعة الافتراضية إن كانت '
                              'متاحة، وإلا أول طابعة متاحة.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
