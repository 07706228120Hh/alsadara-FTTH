/// نماذج بيانات قالب الوصل المرئي
/// يُعرّف الوصل كقائمة صفوف، كل صف يحتوي خلايا بخصائص قابلة للتعديل
library;

// ==================== Enums ====================

enum ReceiptRowType { cells, divider, spacer, centeredText, image }

enum ReceiptCellAlignment { right, center, left }

// ==================== ReceiptTextStyle ====================

class ReceiptTextStyle {
  final double
      fontSizeOffset; // offset من baseFontSize (مثلاً +6 للعنوان، -1 للتسميات)
  final bool bold;
  final bool italic;

  const ReceiptTextStyle({
    this.fontSizeOffset = 0,
    this.bold = false,
    this.italic = false,
  });

  Map<String, dynamic> toJson() => {
        'fontSizeOffset': fontSizeOffset,
        'bold': bold,
        'italic': italic,
      };

  factory ReceiptTextStyle.fromJson(Map<String, dynamic> json) {
    return ReceiptTextStyle(
      fontSizeOffset: (json['fontSizeOffset'] as num?)?.toDouble() ?? 0,
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
    );
  }

  ReceiptTextStyle copyWith({
    double? fontSizeOffset,
    bool? bold,
    bool? italic,
  }) {
    return ReceiptTextStyle(
      fontSizeOffset: fontSizeOffset ?? this.fontSizeOffset,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
    );
  }
}

// ==================== ReceiptBoxDecoration ====================

class ReceiptBoxDecoration {
  final double borderWidth; // 0 = بدون حدود
  final double borderRadius;
  final double paddingH; // حشو أفقي (px)
  final double paddingV; // حشو عمودي (px)
  final double marginBottom; // هامش سفلي (px)

  const ReceiptBoxDecoration({
    this.borderWidth = 0.8,
    this.borderRadius = 3,
    this.paddingH = 4,
    this.paddingV = 3,
    this.marginBottom = 3,
  });

  Map<String, dynamic> toJson() => {
        'borderWidth': borderWidth,
        'borderRadius': borderRadius,
        'paddingH': paddingH,
        'paddingV': paddingV,
        'marginBottom': marginBottom,
      };

  factory ReceiptBoxDecoration.fromJson(Map<String, dynamic> json) {
    return ReceiptBoxDecoration(
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0.8,
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 3,
      paddingH: (json['paddingH'] as num?)?.toDouble() ?? 4,
      paddingV: (json['paddingV'] as num?)?.toDouble() ?? 3,
      marginBottom: (json['marginBottom'] as num?)?.toDouble() ?? 3,
    );
  }

  ReceiptBoxDecoration copyWith({
    double? borderWidth,
    double? borderRadius,
    double? paddingH,
    double? paddingV,
    double? marginBottom,
  }) {
    return ReceiptBoxDecoration(
      borderWidth: borderWidth ?? this.borderWidth,
      borderRadius: borderRadius ?? this.borderRadius,
      paddingH: paddingH ?? this.paddingH,
      paddingV: paddingV ?? this.paddingV,
      marginBottom: marginBottom ?? this.marginBottom,
    );
  }
}

// ==================== ReceiptCell ====================

class ReceiptCell {
  final String id;
  final String content; // نص ثابت أو {{متغير}}
  final int flex;
  final ReceiptTextStyle textStyle;
  final ReceiptCellAlignment alignment;
  final bool isLabel; // تسمية (عادةً عريضة)

  const ReceiptCell({
    required this.id,
    required this.content,
    this.flex = 1,
    this.textStyle = const ReceiptTextStyle(),
    this.alignment = ReceiptCellAlignment.right,
    this.isLabel = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'flex': flex,
        'textStyle': textStyle.toJson(),
        'alignment': alignment.name,
        'isLabel': isLabel,
      };

  factory ReceiptCell.fromJson(Map<String, dynamic> json) {
    return ReceiptCell(
      id: json['id'] as String? ?? _generateId(),
      content: json['content'] as String? ?? '',
      flex: json['flex'] as int? ?? 1,
      textStyle: json['textStyle'] != null
          ? ReceiptTextStyle.fromJson(json['textStyle'] as Map<String, dynamic>)
          : const ReceiptTextStyle(),
      alignment: ReceiptCellAlignment.values.firstWhere(
        (e) => e.name == json['alignment'],
        orElse: () => ReceiptCellAlignment.right,
      ),
      isLabel: json['isLabel'] as bool? ?? false,
    );
  }

  ReceiptCell copyWith({
    String? id,
    String? content,
    int? flex,
    ReceiptTextStyle? textStyle,
    ReceiptCellAlignment? alignment,
    bool? isLabel,
  }) {
    return ReceiptCell(
      id: id ?? this.id,
      content: content ?? this.content,
      flex: flex ?? this.flex,
      textStyle: textStyle ?? this.textStyle,
      alignment: alignment ?? this.alignment,
      isLabel: isLabel ?? this.isLabel,
    );
  }
}

// ==================== ReceiptRow ====================

class ReceiptRow {
  final String id;
  final ReceiptRowType type;
  final bool visible;
  final String? conditionVariable; // مثلاً "showCustomerInfo"
  final ReceiptBoxDecoration? decoration;
  final List<ReceiptCell> cells;
  final double? spacerHeight;
  final double? dividerThickness;
  final double? imageWidth; // عرض الصورة (px) — لصفوف image فقط
  final double? imageHeight; // ارتفاع الصورة (px) — لصفوف image فقط

  const ReceiptRow({
    required this.id,
    required this.type,
    this.visible = true,
    this.conditionVariable,
    this.decoration,
    this.cells = const [],
    this.spacerHeight,
    this.dividerThickness,
    this.imageWidth,
    this.imageHeight,
  });

  /// وصف مختصر للعرض في قائمة الصفوف
  String get displayLabel {
    switch (type) {
      case ReceiptRowType.divider:
        return 'خط فاصل';
      case ReceiptRowType.spacer:
        return 'مسافة';
      case ReceiptRowType.centeredText:
        if (cells.isNotEmpty) {
          final content = cells.first.content;
          if (content.startsWith('{{') && content.endsWith('}}')) {
            return content.substring(2, content.length - 2);
          }
          return content.length > 20
              ? '${content.substring(0, 20)}...'
              : content;
        }
        return 'نص';
      case ReceiptRowType.cells:
        if (cells.isEmpty) return 'صف فارغ';
        final labels = cells
            .where((c) => c.isLabel)
            .map((c) => c.content.replaceAll(':', ''));
        return labels.isNotEmpty ? labels.join(' / ') : 'صف خلايا';
      case ReceiptRowType.image:
        return 'شعار';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'visible': visible,
        'conditionVariable': conditionVariable,
        'decoration': decoration?.toJson(),
        'cells': cells.map((c) => c.toJson()).toList(),
        'spacerHeight': spacerHeight,
        'dividerThickness': dividerThickness,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      };

  factory ReceiptRow.fromJson(Map<String, dynamic> json) {
    return ReceiptRow(
      id: json['id'] as String? ?? _generateId(),
      type: ReceiptRowType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ReceiptRowType.cells,
      ),
      visible: json['visible'] as bool? ?? true,
      conditionVariable: json['conditionVariable'] as String?,
      decoration: json['decoration'] != null
          ? ReceiptBoxDecoration.fromJson(
              json['decoration'] as Map<String, dynamic>)
          : null,
      cells: (json['cells'] as List<dynamic>?)
              ?.map((c) => ReceiptCell.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      spacerHeight: (json['spacerHeight'] as num?)?.toDouble(),
      dividerThickness: (json['dividerThickness'] as num?)?.toDouble(),
      imageWidth: (json['imageWidth'] as num?)?.toDouble(),
      imageHeight: (json['imageHeight'] as num?)?.toDouble(),
    );
  }

  ReceiptRow copyWith({
    String? id,
    ReceiptRowType? type,
    bool? visible,
    String? Function()? conditionVariable,
    ReceiptBoxDecoration? Function()? decoration,
    List<ReceiptCell>? cells,
    double? Function()? spacerHeight,
    double? Function()? dividerThickness,
    double? Function()? imageWidth,
    double? Function()? imageHeight,
  }) {
    return ReceiptRow(
      id: id ?? this.id,
      type: type ?? this.type,
      visible: visible ?? this.visible,
      conditionVariable: conditionVariable != null
          ? conditionVariable()
          : this.conditionVariable,
      decoration: decoration != null ? decoration() : this.decoration,
      cells: cells ?? this.cells,
      spacerHeight: spacerHeight != null ? spacerHeight() : this.spacerHeight,
      dividerThickness:
          dividerThickness != null ? dividerThickness() : this.dividerThickness,
      imageWidth: imageWidth != null ? imageWidth() : this.imageWidth,
      imageHeight: imageHeight != null ? imageHeight() : this.imageHeight,
    );
  }
}

// ==================== ReceiptPageSettings ====================

class ReceiptPageSettings {
  final double paperWidthMm;
  final double marginMm;
  final double baseFontSize;
  final bool boldHeaders;

  const ReceiptPageSettings({
    this.paperWidthMm = 72,
    this.marginMm = 1,
    this.baseFontSize = 10,
    this.boldHeaders = true,
  });

  Map<String, dynamic> toJson() => {
        'paperWidthMm': paperWidthMm,
        'marginMm': marginMm,
        'baseFontSize': baseFontSize,
        'boldHeaders': boldHeaders,
      };

  factory ReceiptPageSettings.fromJson(Map<String, dynamic> json) {
    return ReceiptPageSettings(
      paperWidthMm: (json['paperWidthMm'] as num?)?.toDouble() ?? 72,
      marginMm: (json['marginMm'] as num?)?.toDouble() ?? 1,
      baseFontSize: (json['baseFontSize'] as num?)?.toDouble() ?? 10,
      boldHeaders: json['boldHeaders'] as bool? ?? true,
    );
  }

  ReceiptPageSettings copyWith({
    double? paperWidthMm,
    double? marginMm,
    double? baseFontSize,
    bool? boldHeaders,
  }) {
    return ReceiptPageSettings(
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      marginMm: marginMm ?? this.marginMm,
      baseFontSize: baseFontSize ?? this.baseFontSize,
      boldHeaders: boldHeaders ?? this.boldHeaders,
    );
  }
}

// ==================== ReceiptTemplate ====================

class ReceiptTemplate {
  final String id;
  final String name;
  final int version;
  final ReceiptPageSettings pageSettings;
  final List<ReceiptRow> rows;

  const ReceiptTemplate({
    required this.id,
    required this.name,
    this.version = 3,
    this.pageSettings = const ReceiptPageSettings(),
    this.rows = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'pageSettings': pageSettings.toJson(),
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  factory ReceiptTemplate.fromJson(Map<String, dynamic> json) {
    return ReceiptTemplate(
      id: json['id'] as String? ?? 'default',
      name: json['name'] as String? ?? 'افتراضي',
      version: json['version'] as int? ?? 2,
      pageSettings: json['pageSettings'] != null
          ? ReceiptPageSettings.fromJson(
              json['pageSettings'] as Map<String, dynamic>)
          : const ReceiptPageSettings(),
      rows: (json['rows'] as List<dynamic>?)
              ?.map((r) => ReceiptRow.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  ReceiptTemplate copyWith({
    String? id,
    String? name,
    int? version,
    ReceiptPageSettings? pageSettings,
    List<ReceiptRow>? rows,
  }) {
    return ReceiptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      pageSettings: pageSettings ?? this.pageSettings,
      rows: rows ?? this.rows,
    );
  }

  /// القالب الافتراضي — يُطابق تخطيط الوصل المطلوب
  factory ReceiptTemplate.defaultTemplate() {
    const bordered = ReceiptBoxDecoration(
      borderWidth: 0.8,
      borderRadius: 3,
      paddingH: 4,
      paddingV: 3,
      marginBottom: 3,
    );

    return ReceiptTemplate(
      id: 'default',
      name: 'افتراضي',
      version: 8,
      pageSettings: const ReceiptPageSettings(),
      rows: [
        // 0. شعار الشركة (مخفي افتراضياً)
        const ReceiptRow(
          id: 'r0',
          type: ReceiptRowType.image,
          visible: false,
          imageWidth: 60,
          imageHeight: 60,
        ),
        // 1. اسم الشركة
        ReceiptRow(
          id: 'r1',
          type: ReceiptRowType.centeredText,
          cells: [
            ReceiptCell(
              id: 'r1c1',
              content: '{{companyName}}',
              alignment: ReceiptCellAlignment.center,
              textStyle: const ReceiptTextStyle(fontSizeOffset: 6, bold: true),
            ),
          ],
        ),
        // 2. السطر الفرعي
        ReceiptRow(
          id: 'r2',
          type: ReceiptRowType.centeredText,
          cells: [
            ReceiptCell(
              id: 'r2c1',
              content: '{{companySubtitle}}',
              alignment: ReceiptCellAlignment.center,
            ),
          ],
        ),
        // 3. الوصل + المبلغ
        ReceiptRow(
          id: 'r3',
          type: ReceiptRowType.cells,
          decoration: bordered,
          cells: [
            ReceiptCell(
              id: 'r3c1',
              content: 'الوصل:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r3c2',
              content: '{{receiptNumber}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r3c3',
              content: 'المبلغ:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r3c4',
              content: '{{totalPrice}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
          ],
        ),
        // 4. محاسب + FBG-FAT
        ReceiptRow(
          id: 'r4',
          type: ReceiptRowType.cells,
          decoration: bordered,
          cells: [
            ReceiptCell(
              id: 'r4c1',
              content: 'محاسب:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1.5),
            ),
            ReceiptCell(
              id: 'r4c2',
              content: '{{operatorFullName}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1.5),
            ),
            ReceiptCell(
              id: 'r4c3',
              content: '-',
              flex: 1,
              alignment: ReceiptCellAlignment.center,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r4c4',
              content: '{{fatInfo}}-{{fbgInfo}}',
              flex: 7,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
          ],
        ),
        // 5. الاسم + الرقم
        ReceiptRow(
          id: 'r5',
          type: ReceiptRowType.cells,
          conditionVariable: 'showCustomerInfo',
          decoration: bordered,
          cells: [
            ReceiptCell(
              id: 'r5c1',
              content: 'الاسم:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1.5),
            ),
            ReceiptCell(
              id: 'r5c2',
              content: '{{customerName}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1.5),
            ),
            ReceiptCell(
              id: 'r5c3',
              content: 'الرقم:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r5c4',
              content: '{{customerPhone}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
          ],
        ),
        // 6. الدفع + المحصّل
        ReceiptRow(
          id: 'r6',
          type: ReceiptRowType.cells,
          conditionVariable: 'showPaymentDetails',
          decoration: bordered,
          cells: [
            ReceiptCell(
              id: 'r6c1',
              content: 'الدفع:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r6c2',
              content: '{{paymentMethod}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r6c3',
              content: 'المحصّل:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1.5),
            ),
            ReceiptCell(
              id: 'r6c4',
              content: '{{collectorName}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1.5),
            ),
          ],
        ),
        // 7. التفعيل + الوقت
        ReceiptRow(
          id: 'r7',
          type: ReceiptRowType.cells,
          decoration: bordered,
          cells: [
            ReceiptCell(
              id: 'r7c1',
              content: 'التفعيل:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r7c2',
              content: '{{activationDate}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r7c3',
              content: 'الوقت:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r7c4',
              content: '{{activationTime}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
          ],
        ),
        // 8. الخدمة + المدة
        ReceiptRow(
          id: 'r8',
          type: ReceiptRowType.cells,
          conditionVariable: 'showServiceDetails',
          decoration: bordered,
          cells: [
            ReceiptCell(
              id: 'r8c1',
              content: 'الخدمة:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r8c2',
              content: '{{selectedPlan}}',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r8c3',
              content: 'المدة:',
              flex: 3,
              alignment: ReceiptCellAlignment.right,
              isLabel: true,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
            ReceiptCell(
              id: 'r8c4',
              content: '{{commitmentPeriod}} شهر',
              flex: 4,
              alignment: ReceiptCellAlignment.right,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
            ),
          ],
        ),
        // 9. معلومات الاتصال (فوتر)
        ReceiptRow(
          id: 'r9',
          type: ReceiptRowType.centeredText,
          cells: [
            ReceiptCell(
              id: 'r9c1',
              content: '{{contactInfo}}',
              alignment: ReceiptCellAlignment.center,
              textStyle: const ReceiptTextStyle(fontSizeOffset: -1),
            ),
          ],
        ),
      ],
    );
  }
}

// ==================== Template Variables ====================

class TemplateVariable {
  final String key;
  final String displayName;
  final String sampleValue;
  final String category;

  const TemplateVariable({
    required this.key,
    required this.displayName,
    required this.sampleValue,
    required this.category,
  });
}

class TemplateVariableRegistry {
  static const List<TemplateVariable> allVariables = [
    // ── الترويسة ──
    TemplateVariable(
        key: 'companyName',
        displayName: 'اسم الشركة',
        sampleValue: 'شركة رمز الاتصالات',
        category: 'header'),
    TemplateVariable(
        key: 'companySubtitle',
        displayName: 'السطر الفرعي',
        sampleValue: 'المشغل الرسمي للمشروع الوطني',
        category: 'header'),
    TemplateVariable(
        key: 'contactInfo',
        displayName: 'معلومات الاتصال',
        sampleValue: 'للاستفسار: 0123456789',
        category: 'header'),
    TemplateVariable(
        key: 'footerMessage',
        displayName: 'رسالة التذييل',
        sampleValue: 'شكراً لاختياركم شركة رمز الاتصالات',
        category: 'header'),

    // ── العميل ──
    TemplateVariable(
        key: 'customerName',
        displayName: 'اسم العميل',
        sampleValue: 'أحمد محمد علي',
        category: 'customer'),
    TemplateVariable(
        key: 'customerPhone',
        displayName: 'رقم الهاتف',
        sampleValue: '07801234567',
        category: 'customer'),
    TemplateVariable(
        key: 'customerAddress',
        displayName: 'العنوان',
        sampleValue: 'بغداد - المنصور',
        category: 'customer'),
    TemplateVariable(
        key: 'customerId',
        displayName: 'معرف العميل',
        sampleValue: 'C-1234',
        category: 'customer'),
    TemplateVariable(
        key: 'partnerName',
        displayName: 'اسم الشريك',
        sampleValue: 'شريك 1',
        category: 'customer'),

    // ── الدفع ──
    TemplateVariable(
        key: 'paymentMethod',
        displayName: 'طريقة الدفع',
        sampleValue: 'فني',
        category: 'payment'),
    TemplateVariable(
        key: 'totalPrice',
        displayName: 'المبلغ الإجمالي',
        sampleValue: '35000',
        category: 'payment'),
    TemplateVariable(
        key: 'currency',
        displayName: 'العملة',
        sampleValue: 'IQD',
        category: 'payment'),
    TemplateVariable(
        key: 'basePrice',
        displayName: 'السعر الأساسي',
        sampleValue: '40000',
        category: 'payment'),
    TemplateVariable(
        key: 'discount',
        displayName: 'الخصم',
        sampleValue: '5000',
        category: 'payment'),
    TemplateVariable(
        key: 'discountPercentage',
        displayName: 'نسبة الخصم %',
        sampleValue: '12',
        category: 'payment'),
    TemplateVariable(
        key: 'manualDiscount',
        displayName: 'الخصم اليدوي',
        sampleValue: '0',
        category: 'payment'),
    TemplateVariable(
        key: 'salesType',
        displayName: 'نوع البيع',
        sampleValue: 'نقد',
        category: 'payment'),
    TemplateVariable(
        key: 'walletBalance',
        displayName: 'رصيد المحفظة',
        sampleValue: '150000',
        category: 'payment'),

    // ── الفني / الوكيل ──
    TemplateVariable(
        key: 'collectorName',
        displayName: 'اسم المحصّل',
        sampleValue: 'علي حسين',
        category: 'collector'),
    TemplateVariable(
        key: 'technicianName',
        displayName: 'اسم الفني',
        sampleValue: 'علي حسين',
        category: 'collector'),
    TemplateVariable(
        key: 'technicianUsername',
        displayName: 'يوزر الفني',
        sampleValue: 'ali_tech',
        category: 'collector'),
    TemplateVariable(
        key: 'technicianPhone',
        displayName: 'رقم الفني',
        sampleValue: '07701234567',
        category: 'collector'),
    TemplateVariable(
        key: 'agentName',
        displayName: 'اسم الوكيل',
        sampleValue: 'أحمد وكيل',
        category: 'collector'),
    TemplateVariable(
        key: 'agentCode',
        displayName: 'كود الوكيل',
        sampleValue: '1001',
        category: 'collector'),
    TemplateVariable(
        key: 'agentPhone',
        displayName: 'رقم الوكيل',
        sampleValue: '07809876543',
        category: 'collector'),

    // ── الخدمة والاشتراك ──
    TemplateVariable(
        key: 'selectedPlan',
        displayName: 'الخطة المختارة',
        sampleValue: 'FIBER 35',
        category: 'service'),
    TemplateVariable(
        key: 'currentPlan',
        displayName: 'الخطة الحالية',
        sampleValue: 'FIBER 75',
        category: 'service'),
    TemplateVariable(
        key: 'commitmentPeriod',
        displayName: 'فترة الالتزام',
        sampleValue: '1',
        category: 'service'),
    TemplateVariable(
        key: 'endDate',
        displayName: 'تاريخ الانتهاء',
        sampleValue: '8/4/2026',
        category: 'service'),
    TemplateVariable(
        key: 'expiryDate',
        displayName: 'انتهاء الاشتراك الحالي',
        sampleValue: '9/3/2026',
        category: 'service'),
    TemplateVariable(
        key: 'subscriptionStartDate',
        displayName: 'تاريخ بدء الاشتراك',
        sampleValue: '9/2/2026',
        category: 'service'),
    TemplateVariable(
        key: 'remainingDays',
        displayName: 'الأيام المتبقية',
        sampleValue: '5',
        category: 'service'),
    TemplateVariable(
        key: 'subscriptionStatus',
        displayName: 'حالة الاشتراك',
        sampleValue: 'Active',
        category: 'service'),
    TemplateVariable(
        key: 'subscriptionNotes',
        displayName: 'الملاحظات',
        sampleValue: 'ملاحظة خاصة',
        category: 'service'),

    // ── الشبكة والجهاز ──
    TemplateVariable(
        key: 'fdtInfo',
        displayName: 'FDT',
        sampleValue: 'FBG1044',
        category: 'network'),
    TemplateVariable(
        key: 'fatInfo',
        displayName: 'FAT',
        sampleValue: 'FAT3',
        category: 'network'),
    TemplateVariable(
        key: 'fbgInfo',
        displayName: 'FBG',
        sampleValue: 'FBG1044',
        category: 'network'),
    TemplateVariable(
        key: 'zoneDisplayValue',
        displayName: 'المنطقة',
        sampleValue: 'Zone A',
        category: 'network'),
    TemplateVariable(
        key: 'deviceUsername',
        displayName: 'يوزر الجهاز',
        sampleValue: 'user_device1',
        category: 'network'),
    TemplateVariable(
        key: 'deviceSerial',
        displayName: 'سيريال الجهاز',
        sampleValue: 'SN123456',
        category: 'network'),
    TemplateVariable(
        key: 'macAddress',
        displayName: 'MAC عنوان',
        sampleValue: 'AA:BB:CC:DD:EE:FF',
        category: 'network'),
    TemplateVariable(
        key: 'deviceModel',
        displayName: 'موديل الجهاز',
        sampleValue: 'HG8245H',
        category: 'network'),

    // ── المشغّل (سيرفرنا) ──
    TemplateVariable(
        key: 'operatorFullName',
        displayName: 'اسم المشغّل (سيرفرنا)',
        sampleValue: 'حيدر كريم',
        category: 'operator'),
    TemplateVariable(
        key: 'operatorPhone',
        displayName: 'رقم المشغّل',
        sampleValue: '07701112233',
        category: 'operator'),
    TemplateVariable(
        key: 'operatorDepartment',
        displayName: 'قسم المشغّل',
        sampleValue: 'المبيعات',
        category: 'operator'),
    TemplateVariable(
        key: 'operatorCenter',
        displayName: 'مركز المشغّل',
        sampleValue: 'بغداد',
        category: 'operator'),
    TemplateVariable(
        key: 'operatorRole',
        displayName: 'دور المشغّل',
        sampleValue: 'مشغل',
        category: 'operator'),

    // ── النظام ──
    TemplateVariable(
        key: 'operationType',
        displayName: 'نوع العملية',
        sampleValue: 'تم تجديد الاشتراك',
        category: 'system'),
    TemplateVariable(
        key: 'activatedBy',
        displayName: 'المنشط (FTTH)',
        sampleValue: 'hai',
        category: 'system'),
    TemplateVariable(
        key: 'receiptNumber',
        displayName: 'رقم الوصل',
        sampleValue: '2',
        category: 'system'),
    TemplateVariable(
        key: 'activationDate',
        displayName: 'تاريخ التفعيل',
        sampleValue: '9/3/2026',
        category: 'system'),
    TemplateVariable(
        key: 'activationTime',
        displayName: 'وقت التفعيل',
        sampleValue: '03:54',
        category: 'system'),
    TemplateVariable(
        key: 'copyNumber',
        displayName: 'رقم النسخة',
        sampleValue: '1',
        category: 'system'),
    TemplateVariable(
        key: 'currentDate',
        displayName: 'التاريخ الحالي',
        sampleValue: '09/03/2026',
        category: 'system'),
  ];

  static Map<String, String> get sampleValues => {
        for (final v in allVariables) v.key: v.sampleValue,
      };

  static List<String> get categories => [
        'header',
        'customer',
        'payment',
        'collector',
        'service',
        'network',
        'operator',
        'system'
      ];

  static String categoryDisplayName(String category) {
    switch (category) {
      case 'header':
        return 'الترويسة';
      case 'customer':
        return 'العميل';
      case 'payment':
        return 'الدفع';
      case 'collector':
        return 'الفني / الوكيل';
      case 'service':
        return 'الخدمة';
      case 'network':
        return 'الشبكة والجهاز';
      case 'operator':
        return 'المشغّل (سيرفرنا)';
      case 'system':
        return 'النظام';
      default:
        return category;
    }
  }
}

// ==================== Helpers ====================

int _idCounter = 0;
String _generateId() =>
    'id_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

/// توليد معرف فريد للاستخدام الخارجي
String generateReceiptId() => _generateId();
