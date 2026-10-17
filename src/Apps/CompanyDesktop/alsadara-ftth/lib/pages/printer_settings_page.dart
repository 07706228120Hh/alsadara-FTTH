/// اسم الصفحة: إعدادات الطباعة
/// وصف الصفحة: اختيار طابعة الإيصالات (الحرارية) + تجربة الطباعة الصامتة
/// المؤلف: تطبيق السدارة
library;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/thermal_printer_service.dart';
import '../frontend/frontend.dart';

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
      backgroundColor: ok ? SdColors.success : SdColors.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final savedMissing = _selectedName != null &&
        !_printers.any((p) => p.name == _selectedName);
    return SdPage(
      maxWidth: SdSpace.formMax,
      scrollable: !_loading,
      appBar: SdAppBar(
        title: 'إعدادات طابعة الإيصالات',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh,
            label: 'تحديث القائمة',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.print, size: 64, color: SdColors.warning),
                const SizedBox(height: SdSpace.md),
                const Text(
                  'اختر الطابعة التي تُطبع عليها الإيصالات. الطباعة صامتة '
                  'ومباشرة (بلا حوار ويندوز)، وتُتخطّى بأمان إن كانت الطابعة '
                  'غير متاحة.',
                  style: SdText.body,
                ),
                const SizedBox(height: SdSpace.lg),
                if (_printers.isEmpty)
                  const SdEmptyState(
                    title: 'لا توجد طابعات مثبّتة',
                    message: 'لا توجد طابعات مثبّتة على النظام. ثبّت طابعة ثم اضغط تحديث.',
                    icon: Icons.print_disabled_rounded,
                    status: SdStatus.danger,
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
                                color: p.isAvailable ? null : SdColors.danger,
                              ),
                            ),
                          )),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _selectedName = v),
                  ),
                  if (savedMissing) ...[
                    const SizedBox(height: SdSpace.sm),
                    Text(
                      '⚠️ الطابعة المحفوظة «$_selectedName» غير موجودة حالياً — '
                      'اختر طابعة أخرى واحفظ.',
                      style: SdText.caption.copyWith(color: SdColors.warningText),
                    ),
                  ],
                  const SizedBox(height: SdSpace.lg),
                  Row(
                    children: [
                      Expanded(
                        child: SdButton(
                          label: 'حفظ',
                          icon: Icons.save,
                          expand: true,
                          onPressed: _busy ? null : _save,
                        ),
                      ),
                      const SizedBox(width: SdSpace.sm),
                      Expanded(
                        child: SdButton(
                          label: 'تجربة طباعة',
                          icon: Icons.print_outlined,
                          kind: SdButtonKind.secondary,
                          expand: true,
                          onPressed: _busy ? null : _test,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: SdSpace.lg),
                SdCard(
                  title: 'ملاحظات',
                  icon: Icons.info_outline_rounded,
                  tone: SdStatus.warning.tone,
                  padding: const EdgeInsets.all(SdSpace.sm),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• اختر طابعة الإيصالات الحرارية — لا طابعة A4.',
                          style: SdText.body),
                      Text('• «غير متاحة» تعني أن النظام يراها غير جاهزة؛ '
                          'لن تُرسَل لها الإيصالات تفادياً لتعليق الطباعة.',
                          style: SdText.body),
                      Text('• «تلقائي» يستخدم الطابعة الافتراضية إن كانت '
                          'متاحة، وإلا أول طابعة متاحة.',
                          style: SdText.body),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
