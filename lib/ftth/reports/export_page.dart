/// اسم الصفحة: التصدير
/// وصف الصفحة: صفحة تصدير البيانات والتقارير
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:gsheets/gsheets.dart';
import '../../services/permissions_service.dart';

// تم تحديث الواجهة لتصبح أكثر عصرية وحداثة بدون إضافة حزم خارجية
// ركزنا على: ألوان متدرجة، بطاقات تفاعلية، حركات انتقالية، وتحسين عرض التقدم والرسائل

class ExportButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final Color? iconColor; // لون مخصص للأيقونة (اختياري)
  final List<Color>? iconGradientColors; // تدرج مخصص للأيقونة
  const ExportButton({
    super.key,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.color,
    this.iconColor,
    this.iconGradientColors,
  });

  @override
  State<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<ExportButton> {
  bool _pressed = false;
  void _handleTapDown(_) => setState(() => _pressed = true);
  void _handleTapUp(_) => setState(() => _pressed = false);
  void _handleTapCancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baseColor = widget.color ?? scheme.primary;
    // تحسين حساب التباين: إذا كان اللون فاتح جداً (>0.6) نستخدم أسود، إذا متوسط نستخدم أسود مع شفافية أقل، إذا غامق جداً أبيض صافي
    final luminance = baseColor.computeLuminance();
    final bool isDarkBase = luminance <
        0.52; // رفع العتبة قليلاً لتقليل الحالات البيضاء غير الواضحة
    final Color contrast = luminance > 0.70
        ? Colors.black
        : (isDarkBase
            ? Colors.white
            : Colors.black87); // قاعدة وسطية للألوان المتوسطة
    final Color darker = _darken(baseColor, 0.18);
    // إلغاء التدرج واستخدام لون أساسي واحد للخلفية
    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      scale: _pressed ? 0.95 : 1,
      curve: Curves.easeOutBack,
      child: InkWell(
        onTap: widget.onPressed,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 110),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: baseColor,
            boxShadow: [
              BoxShadow(
                color: darker.withValues(alpha: 0.40),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: Colors.black,
              width: 1.2,
            ),
          ),
          child: Stack(
            children: [
              // لمعان ثابت خفيف
              Positioned(
                top: -25,
                right: -25,
                child: IgnorePointer(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ColoredIconCircle(
                      base: baseColor,
                      contrast: contrast,
                      icon: widget.icon,
                      customIconColor: widget.iconColor,
                      gradientColors: widget.iconGradientColors,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: contrast,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (rect) => LinearGradient(
                            colors: [
                              _lighten(baseColor, 0.35),
                              _darken(baseColor, 0.1),
                            ],
                          ).createShader(rect),
                          blendMode: BlendMode.srcIn,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'بدء التصدير',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: contrast.withValues(alpha: 0.80),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    )
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

class ExportPage extends StatefulWidget {
  final String authToken;
  const ExportPage({
    super.key,
    required this.authToken,
  });

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage>
    with SingleTickerProviderStateMixin {
  bool isExporting = false;
  bool isCancelled = false;
  double exportTotalProgress = 0.0;
  String exportMessage = "";
  bool isAuthenticated = false;
  bool _passwordDialogShown =
      false; // حارس لمنع تكرار إظهار مربع كلمة المرور وبالتالي بقاء حاجز شفاف
  final TextEditingController passwordController = TextEditingController();
  final String spreadsheetId = '1Vc9Syd7D0mo6EGnIsdMA-sVCpvWsAQ7NGnvZf8knXKE';
  final Duration timeout = const Duration(minutes: 5);
  late final AnimationController _bgController; // متحكم لتحريك الخلفية الملونة

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_passwordDialogShown) {
        _passwordDialogShown = true;
        _showPasswordDialog();
      }
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  // توليد قائمة ألوان متحركة للخلفية عبر تدوير درجة اللون (Hue)
  List<Color> _animatedBgColors(ColorScheme scheme, double t) {
    // t بين 0 و 1
    Color shift(Color base, double delta) {
      final hsl = HSLColor.fromColor(base);
      final h = (hsl.hue + delta) % 360;
      final lWave = 0.04 * math.sin(2 * math.pi * (t + delta / 360));
      return hsl
          .withHue(h)
          .withLightness((hsl.lightness + lWave).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
          .toColor();
    }

    // نعتمد على primary / secondary / tertiary وإن لم تتوفر tertiary نشتقها من primary
    final c1 = shift(scheme.primary, t * 120); // تدوير تدريجي
    final c2 = shift(scheme.secondary, 60 + t * 160);
    final c3 = shift(scheme.tertiary, 120 + t * 200);
    return [c1, c2, c3];
  }

  Future<void> _showPasswordDialog() async {
    // جلب كلمة المرور الافتراضية المخزنة من خدمة الصلاحيات (يمكن تعديلها من صفحة الصلاحيات)
    final storedPassword =
        await PermissionsService.getSecondSystemDefaultPassword();
    final expectedPassword = storedPassword?.trim() ?? '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // منع الإغلاق بالضغط خارجاً
      builder: (BuildContext ctx) {
        return WillPopScope(
          onWillPop: () async => false, // تعطيل زر الرجوع أثناء الحوار
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('أدخل كلمة المرور'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    hintText: 'كلمة المرور',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) {
                    if (value.trim() == expectedPassword) {
                      Navigator.of(ctx).pop(true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('كلمة المرور غير صحيحة!')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'الدخول مخصص للأدمن فقط',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton.icon(
                icon: const Icon(Icons.exit_to_app_rounded),
                label: const Text('خروج'),
                onPressed: () => SystemNavigator.pop(),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('تأكيد'),
                onPressed: () {
                  if (passwordController.text.trim() == expectedPassword) {
                    Navigator.of(ctx).pop(true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('كلمة المرور غير صحيحة!')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() {
      isAuthenticated = result ?? false;
      // لا نغلق التطبيق مباشرة إذا فشل - نسمح بإعادة المحاولة
      if (!isAuthenticated) {
        // إعادة إظهار الحوار للمحاولة مرة أخرى بدون ترك حاجز عالق
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_passwordDialogShown) {
            _passwordDialogShown = true;
            _showPasswordDialog();
          } else if (mounted && _passwordDialogShown) {
            // السماح للمستخدم بالمحاولة: نعيد التفعيل
            _passwordDialogShown = false;
            _showPasswordDialog();
          }
        });
      }
    });
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final response = await http.get(Uri.parse('https://www.google.com'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _optimizeMemory() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('Memory optimization failed: $e');
    }
  }

  Future<void> _retryOperation(Function operation, int retries) async {
    for (int i = 0; i < retries; i++) {
      try {
        await operation();
        break;
      } catch (e) {
        if (i == retries - 1) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2));
      }
    }
  }

  Future<void> _clearSheetData(Worksheet sheet) async {
    try {
      final rowCount = sheet.rowCount;
      if (rowCount > 1) {
        final headerRow = await sheet.values.row(1);
        final columnCount = headerRow.length;

        final lastColumnLetter = String.fromCharCode(65 + columnCount - 1);
        final range = 'A2:$lastColumnLetter$rowCount';

        setState(() {
          exportMessage = "جاري مسح البيانات...";
        });

        await sheet.values.clear(range);

        final secondRow = await sheet.values.row(2);
        debugPrint("محتويات السطر الثاني بعد المسح: $secondRow");

        if (rowCount > 2) {
          await sheet.deleteRow(2, count: rowCount - 1);
        }

        setState(() {
          exportMessage = "تم مسح البيانات بنجاح";
        });

        debugPrint("تم مسح البيانات السابقة بنجاح");
      } else {
        debugPrint("لا توجد بيانات لمسحها.");
      }
    } catch (e) {
      debugPrint("خطأ في مسح البيانات السابقة: $e");
      throw Exception("فشل في مسح البيانات السابقة: $e");
    }
  }

  Future<Worksheet> _getOrCreateSheet(Spreadsheet ss, String sheetName) async {
    var sheet = ss.worksheetByTitle(sheetName);
    sheet ??= await ss.addWorksheet(sheetName);
    return sheet;
  }

  Future<void> _exportToGoogleSheets(String apiUrl, List<String> headers,
      {required String sheetName}) async {
    if (!isAuthenticated) return;

    if (!await _checkInternetConnection()) {
      setState(() {
        exportMessage = "لا يوجد اتصال بالإنترنت!";
      });
      return;
    }

    setState(() {
      isExporting = true;
      isCancelled = false;
      exportMessage = "جاري تحضير عملية التصدير...";
      exportTotalProgress = 0.0;
    });

    try {
      final credentials =
          await rootBundle.loadString('assets/service_account.json');
      final gsheets = GSheets(credentials);
      final ss = await gsheets.spreadsheet(spreadsheetId);
      final sheet = await _getOrCreateSheet(ss, sheetName);

      setState(() {
        exportMessage = "جاري مسح البيانات القديمة...";
      });

      await _retryOperation(() => _clearSheetData(sheet), 3);
      await sheet.values.insertRow(1, headers);

      int currentPage = 1;
      final pageSize = 150;
      int totalProcessed = 0;
      List<List<dynamic>> batchRows = [];

      while (true) {
        if (isCancelled) {
          setState(() {
            exportMessage = "تم إلغاء عملية التصدير.";
            isExporting = false;
          });
          return;
        }

        final url = Uri.parse(apiUrl.contains('subscriptions')
            ? '$apiUrl?pageNumber=$currentPage&pageSize=$pageSize&sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0'
            : apiUrl.contains('addresses')
                ? apiUrl
                : '$apiUrl?pageNumber=$currentPage&pageSize=$pageSize');

        final response = await http.get(
          url,
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        ).timeout(timeout);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = data['items'] as List? ?? [];
          if (items.isEmpty) break;

          for (final item in items) {
            final List<dynamic> row;

            if (apiUrl.contains('addresses')) {
              row = [
                totalProcessed + 1,
                item['customer']?['id'] ?? 'غير معروف',
                item['deviceDetails']?['username'] ?? 'غير معروف',
                item['customer']?['displayValue'] ?? 'غير معروف',
                item['deviceDetails']?['serial'] ?? 'غير معروف',
                item['zone']?['displayValue'] ?? 'غير معروف',
                item['deviceDetails']?['fat']?['displayValue'] ?? 'غير معروف',
                '${item['gpsCoordinate']?['latitude'] ?? ''}, ${item['gpsCoordinate']?['longitude'] ?? ''}'
              ];
            } else if (apiUrl.contains('subscriptions')) {
              row = [
                totalProcessed + 1,
                item['customer']?['displayValue'] ?? 'غير معروف',
                item['customer']?['id'] ?? 'غير معروف',
                item['self']?['id'] ?? 'غير معروف', // إضافة self.id
                item['username'] ?? 'غير معروف',
                item['services']?.first?['displayValue'] ?? 'غير معروف',
                item['status'] ?? 'غير معروف',
                item['zone']?['displayValue'] ?? 'غير معروف',
                item['expires'] ?? 'غير معروف',
                item['salesType']?['displayValue'] ?? 'غير معروف',
                item['bundle']?['displayValue'] ?? 'غير معروف',
                item['commitmentPeriod']?.toString() ?? 'غير معروف',
              ];
            } else {
              final customerId = item['self']?['id']?.toString() ?? 'غير معروف';
              final customerName = item['self']?['displayValue'] ?? 'غير معروف';
              final phone = item['primaryContact']?['mobile'] ?? 'غير متوفر';
              row = [totalProcessed + 1, customerId, customerName, phone];
            }

            batchRows.add(row);
            totalProcessed++;
          }

          if (batchRows.length >= 450 || items.length < pageSize) {
            setState(() {
              exportMessage = "جاري كتابة البيانات... ($totalProcessed سجل)";
            });
            await sheet.values.appendRows(batchRows);
            batchRows.clear();
            await _optimizeMemory();
          }

          setState(() {
            exportTotalProgress = totalProcessed / (data['totalCount'] as num);
            exportMessage = "تم تجهيز $totalProcessed سجل";
          });

          if (!apiUrl.contains('addresses')) {
            currentPage++;
          } else {
            break;
          }
        } else {
          throw Exception("فشل جلب البيانات: ${response.statusCode}");
        }
      }

      if (batchRows.isNotEmpty) {
        await sheet.values.appendRows(batchRows);
      }

      setState(() {
        exportMessage = "تم تصدير $totalProcessed سجل بنجاح!";
        exportTotalProgress = 1.0;
      });
    } catch (e) {
      setState(() {
        exportMessage = "فشل تصدير البيانات: $e";
      });
      debugPrint("تفاصيل الخطأ: $e");
    } finally {
      setState(() {
        isExporting = false;
      });
    }
  }

  Future<void> _exportCustomerDetails() async {
    if (!isAuthenticated) return;

    if (!await _checkInternetConnection()) {
      setState(() {
        exportMessage = "لا يوجد اتصال بالإنترنت!";
      });
      return;
    }

    setState(() {
      isExporting = true;
      isCancelled = false;
      exportMessage = "جاري تحضير عملية التصدير...";
      exportTotalProgress = 0.0;
    });

    try {
      final credentials =
          await rootBundle.loadString('assets/service_account.json');
      final gsheets = GSheets(credentials);
      final ss = await gsheets.spreadsheet(spreadsheetId);
      final sheet = await _getOrCreateSheet(ss, 'SUP details');

      setState(() {
        exportMessage = "جاري مسح البيانات القديمة...";
      });

      await _retryOperation(() => _clearSheetData(sheet), 3);
      await sheet.values.insertRow(1, [
        'N',
        'ID',
        'اسم المستخدم',
        'اسم المشترك',
        'السيريال',
        'المنطقة',
        'FAT',
        'GPS'
      ]);

      int currentPage = 1;
      final pageSize = 100;
      int totalProcessed = 0;
      List<List<dynamic>> batchRows = [];

      while (true) {
        if (isCancelled) {
          setState(() {
            exportMessage = "تم إلغاء عملية التصدير.";
            isExporting = false;
          });
          return;
        }

        setState(() {
          exportMessage = "جاري جلب معرفات المشتركين (الصفحة $currentPage)...";
        });

        final customersUrl = Uri.parse(
            'https://api.ftth.iq/api/customers?pageNumber=$currentPage&pageSize=$pageSize&sortCriteria.property=self.displayValue&sortCriteria.direction=asc');

        final customersResponse = await http.get(
          customersUrl,
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        ).timeout(timeout);

        if (customersResponse.statusCode == 200) {
          final customersData = jsonDecode(customersResponse.body);
          final customersItems = customersData['items'] as List? ?? [];

          if (customersItems.isEmpty) break;

          List<String> customerIds = [];
          for (final customer in customersItems) {
            final customerId =
                customer['self']?['id']?.toString() ?? 'غير معروف';
            customerIds.add(customerId);
          }

          setState(() {
            exportMessage =
                "تم جلب ${customerIds.length} معرف مشترك من الصفحة $currentPage.";
          });

          const batchSize = 100;
          for (int i = 0; i < customerIds.length; i += batchSize) {
            if (isCancelled) {
              setState(() {
                exportMessage = "تم إلغاء عملية التصدير.";
                isExporting = false;
              });
              return;
            }

            final batchIds = customerIds.sublist(
                i,
                i + batchSize > customerIds.length
                    ? customerIds.length
                    : i + batchSize);

            setState(() {
              exportMessage =
                  "جاري جلب تفاصيل المشتركين (الدفعة ${i ~/ batchSize + 1})...";
            });

            final detailsUrl = Uri.parse(
                'https://api.ftth.iq/api/addresses?accountIds=${batchIds.join('&accountIds=')}');

            final detailsResponse = await http.get(
              detailsUrl,
              headers: {
                'Authorization': 'Bearer ${widget.authToken}',
                'Accept': 'application/json',
              },
            ).timeout(timeout);

            if (detailsResponse.statusCode == 200) {
              final detailsData = jsonDecode(detailsResponse.body);
              final detailsItems = detailsData['items'] as List? ?? [];

              for (final item in detailsItems) {
                final List<dynamic> row = [
                  totalProcessed + 1,
                  item['customer']?['id'] ?? 'غير معروف',
                  item['deviceDetails']?['username'] ?? 'غير معروف',
                  item['customer']?['displayValue'] ?? 'غير معروف',
                  item['deviceDetails']?['serial'] ?? 'غير معروف',
                  item['zone']?['displayValue'] ?? 'غير معروف',
                  item['deviceDetails']?['fat']?['displayValue'] ?? 'غير معروف',
                  '${item['gpsCoordinate']?['latitude'] ?? ''}, ${item['gpsCoordinate']?['longitude'] ?? ''}'
                ];

                batchRows.add(row);
                totalProcessed++;

                if (batchRows.length >= 1000) {
                  setState(() {
                    exportMessage =
                        "جاري كتابة البيانات... ($totalProcessed سجل)";
                  });
                  await sheet.values.appendRows(batchRows);
                  batchRows.clear();
                  await _optimizeMemory();
                }
              }
            } else {
              throw Exception(
                  "فشل جلب تفاصيل المشتركين: ${detailsResponse.statusCode}");
            }
          }

          if (batchRows.isNotEmpty) {
            setState(() {
              exportMessage = "جاري كتابة البيانات... ($totalProcessed سجل)";
            });
            await sheet.values.appendRows(batchRows);
            batchRows.clear();
          }

          if (customersItems.length < pageSize) break;
          currentPage++;
        } else {
          throw Exception(
              "فشل جلب بيانات المشتركين: ${customersResponse.statusCode}");
        }
      }

      setState(() {
        exportTotalProgress = 1.0;
        exportMessage = "تم تصدير $totalProcessed سجل بنجاح!";
      });
    } catch (e) {
      setState(() {
        exportMessage = "فشل تصدير البيانات: $e";
      });
      debugPrint("تفاصيل الخطأ: $e");
    } finally {
      setState(() {
        isExporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 50,
          iconTheme: const IconThemeData(size: 20),
          title: const Text('تصدير البيانات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        body: const Center(child: Text('أدخل كلمة المرور للوصول إلى الصفحة')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, _) {
        final t = _bgController.value; // تقدم الحركة
        final bgColors = _animatedBgColors(scheme, t);
        return Scaffold(
          extendBody: true,
          appBar: AppBar(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            iconTheme: IconThemeData(color: scheme.onPrimary),
            toolbarHeight: 60,
            elevation: 8,
            shadowColor: scheme.primary.withValues(alpha: 0.35),
            centerTitle: true,
            title: ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                colors: [scheme.onPrimary, scheme.onPrimary.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(rect),
              blendMode: BlendMode.srcIn,
              child: const Text(
                'تصدير البيانات',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            actions: [
              if (isExporting)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: exportTotalProgress),
                      duration: const Duration(milliseconds: 400),
                      builder: (context, value, _) => Text(
                        '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Container(
            // خلفية متعددة الألوان متحركة
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bgColors[0].withValues(alpha: 0.85),
                  bgColors[1].withValues(alpha: 0.80),
                  bgColors[2].withValues(alpha: 0.85),
                ],
              ),
            ),
            // طبقة شفافة خفيفة لتحسين التباين
            foregroundDecoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 650),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount: 3,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 18),
                            itemBuilder: (context, index) {
                              switch (index) {
                                case 0:
                                  return Align(
                                    alignment: Alignment.center,
                                    child: ExportButton(
                                      title: 'المشتركين',
                                      icon: Icons.people_alt_rounded,
                                      color: const Color.fromARGB(
                                          255, 36, 117, 43),
                                      iconGradientColors: const [
                                        Color(0xFFFFC107),
                                        Color(0xFFFF9800),
                                      ],
                                      onPressed: () => _exportToGoogleSheets(
                                        'https://api.ftth.iq/api/customers',
                                        [
                                          'N',
                                          'ID',
                                          'اسم المستخدم',
                                          'رقم الهاتف'
                                        ],
                                        sheetName: 'users',
                                      ),
                                    ),
                                  );
                                case 1:
                                  return Align(
                                    alignment: Alignment.center,
                                    child: ExportButton(
                                      title: 'الاشتراكات',
                                      icon: Icons.subscriptions_rounded,
                                      color: const Color.fromARGB(
                                          255, 170, 69, 38),
                                      iconGradientColors: const [
                                        Color(0xFFFF7043), // deepOrange lighten
                                        Color(0xFFFF5722), // deepOrange base
                                      ],
                                      onPressed: () => _exportToGoogleSheets(
                                        'https://api.ftth.iq/api/subscriptions',
                                        [
                                          'N',
                                          'اسم الزبون',
                                          'Customer ID',
                                          'Self ID',
                                          'اسم المستخدم',
                                          'الخدمة',
                                          'الحالة',
                                          'المنطقة',
                                          'تاريخ الانتهاء',
                                          'نوع البيع',
                                          'الباقة',
                                          'فترة الالتزام',
                                        ],
                                        sheetName: 'SUP Total',
                                      ),
                                    ),
                                  );
                                default:
                                  return Align(
                                    alignment: Alignment.center,
                                    child: ExportButton(
                                      title: 'تفاصيل المشترك',
                                      icon: Icons.manage_search_rounded,
                                      color: Colors.deepPurple,
                                      iconGradientColors: const [
                                        Color(0xFFE040FB),
                                        Color(0xFF7C4DFF),
                                      ],
                                      onPressed: _exportCustomerDetails,
                                    ),
                                  );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: isExporting
                          ? Column(
                              key: const ValueKey('progress'),
                              children: [
                                _ModernProgressBar(
                                  progress: exportTotalProgress,
                                  label: exportMessage.isEmpty
                                      ? 'جاري التصدير...'
                                      : exportMessage,
                                  onCancel: () =>
                                      setState(() => isCancelled = true),
                                ),
                              ],
                            )
                          : (exportMessage.isNotEmpty
                              ? _MessageCard(
                                  key: const ValueKey('message'),
                                  message: exportMessage,
                                  isSuccess: exportTotalProgress == 1.0,
                                  onClear: () =>
                                      setState(() => exportMessage = ''),
                                )
                              : const SizedBox.shrink()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// بطاقة تقدم حديثة
class _ModernProgressBar extends StatelessWidget {
  final double progress; // 0..1
  final String label;
  final VoidCallback onCancel;
  const _ModernProgressBar({
    required this.progress,
    required this.label,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: scheme.surface.withValues(alpha: 0.55),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primaryContainer],
                  ),
                ),
                child: const Icon(Icons.sync_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.87),
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final barWidth = c.maxWidth;
              final pct = progress.clamp(0, 1);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    width: pct == 0 ? 60 : barWidth * pct,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary,
                          scheme.primary.withValues(alpha: 0.85),
                          scheme.secondary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: pct > 0
                        ? Center(
                            child: Text(
                              '${(pct * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
              label: const Text('إلغاء'),
            ),
          )
        ],
      ),
    );
  }
}

// بطاقة رسالة نهائية
class _MessageCard extends StatelessWidget {
  final String message;
  final bool isSuccess;
  final VoidCallback onClear;
  const _MessageCard({
    super.key,
    required this.message,
    required this.isSuccess,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isSuccess ? scheme.primaryContainer : scheme.errorContainer;
    final fg = isSuccess ? scheme.primary : scheme.error;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [bg.withValues(alpha: 0.85), bg.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: fg.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [fg, fg.withValues(alpha: 0.6)],
              ),
            ),
            child: Icon(
              isSuccess ? Icons.check_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              message,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                height: 1.35,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Tooltip(
            message: 'إغلاق',
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.all(6.0),
                child: Icon(Icons.close_rounded, size: 20),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// دائرة تحتوي أيقونة ملوّنة بتدرج لوني
class _ColoredIconCircle extends StatelessWidget {
  final Color base;
  final Color contrast;
  final IconData icon;
  final Color? customIconColor;
  final List<Color>? gradientColors;
  const _ColoredIconCircle({
    required this.base,
    required this.contrast,
    required this.icon,
    this.customIconColor,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = customIconColor ?? _lighten(base, 0.35);
    final Color iconColor2 =
        gradientColors != null ? gradientColors!.last : _darken(base, 0.05);
    final bool useLightBorder = base.computeLuminance() < 0.5;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (contrast == Colors.white ? Colors.black : Colors.white)
            .withValues(alpha: 0.14),
        border: Border.all(
          color:
              (useLightBorder ? Colors.white : Colors.black).withValues(alpha: 0.30),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor2.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(11),
      child: LayoutBuilder(
        builder: (context, rect) {
          final gradient = gradientColors ?? [iconColor, iconColor2];
          final String glyph = String.fromCharCode(icon.codePoint);
          final TextStyle baseStyle = TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 27,
            height: 1.0,
            letterSpacing: 0,
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              // طبقة الحد (Stroke)
              Text(
                glyph,
                textDirection: TextDirection.ltr,
                style: baseStyle.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2.1
                    ..color = Colors.white.withValues(alpha: 0.90),
                ),
              ),
              // تعبئة متدرجة فوق الحد
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ).createShader(r),
                blendMode: BlendMode.srcIn,
                child: Text(
                  glyph,
                  textDirection: TextDirection.ltr,
                  style: baseStyle.copyWith(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension on WorksheetAsValues {
  clear(String range) {}
}

// تفتيح/تغميق بسيط للّون لإنشاء تدرج واضح بدون شفافية
Color _darken(Color c, [double amount = 0.1]) {
  final hsl = HSLColor.fromColor(c);
  final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return hslDark.toColor();
}

Color _lighten(Color c, [double amount = 0.1]) {
  final hsl = HSLColor.fromColor(c);
  final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
  return hslLight.toColor();
}
