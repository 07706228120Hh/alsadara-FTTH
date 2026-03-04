// ملف منفصل لعمليات التجديد والتفعيل
// هذا الملف جزء من subscription_details_page.dart
part of 'subscription_details_page.dart';

/// قائمة لتتبع المشتركين الذين تم تفعيلهم اليوم (لمنع التفعيل المكرر)
/// Key: subscriptionId, Value: تاريخ التفعيل
final Map<String, DateTime> _activatedSubscriptionsToday = {};

/// Extension للدوال المتعلقة بالتجديد والتفعيل
extension SubscriptionRenewalActions on _SubscriptionDetailsPageState {
  /// زر موحد (تجديد أو تغيير أو شراء) حسب الحالة
  /// يتحقق من الرصيد ثم يستدعي API التغيير
  /// ثم يقوم بـ: تحديث الصفحة -> حفظ Sheets -> طباعة -> واتساب
  Future<void> executeRenewalOrPurchase() async {
    if (subscriptionInfo == null) {
      safeSetState(() => errorMessage = 'معلومات الاشتراك غير متوفرة');
      return;
    }

    // التحقق من التفعيل المكرر في نفس اليوم
    final subscriptionId = widget.subscriptionId;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // تنظيف القائمة من التفعيلات القديمة (غير اليوم)
    _activatedSubscriptionsToday.removeWhere((key, date) {
      final activationDate = DateTime(date.year, date.month, date.day);
      return activationDate != today;
    });

    // التحقق إذا تم تفعيل هذا المشترك اليوم
    if (_activatedSubscriptionsToday.containsKey(subscriptionId)) {
      final lastActivation = _activatedSubscriptionsToday[subscriptionId]!;
      final timeAgo = now.difference(lastActivation);
      final minutesAgo = timeAgo.inMinutes;

      final shouldContinue = await _showDuplicateActivationWarning(minutesAgo);
      if (!shouldContinue) return;
    }

    // تأكد من وجود خطة ومدة محددتين
    selectedPlan ??= subscriptionInfo!.currentPlan;
    selectedCommitmentPeriod ??= subscriptionInfo!.commitmentPeriod;

    // التحقق من حساب السعر
    if (priceDetails == null) {
      await fetchPriceDetails();
      if (priceDetails == null) {
        safeSetState(() => errorMessage = 'فشل حساب السعر');
        return;
      }
    }

    // التحقق من كفاية الرصيد
    final totalPrice = _asDouble(priceDetails!['totalPrice']);
    final availableBalance = _selectedWalletSource == 'customer'
        ? customerWalletBalance
        : walletBalance;

    if (totalPrice > availableBalance) {
      safeSetState(() => errorMessage = 'الرصيد غير كافٍ لإتمام العملية');
      _showInsufficientBalanceDialog(totalPrice, availableBalance);
      return;
    }

    // تأكيد العملية قبل التنفيذ
    final confirmed = await _showRenewalConfirmationDialog();
    if (!confirmed) return;

    // ========== بدء التنفيذ المتسلسل ==========

    // 1️⃣ تفعيل الاشتراك
    debugPrint('🚀 [1/5] بدء تفعيل الاشتراك...');
    final activationSuccess = await _executeChangeSubscription();
    if (!activationSuccess) {
      debugPrint('❌ فشل تفعيل الاشتراك - إيقاف العملية');
      return;
    }
    debugPrint('✅ [1/5] تم تفعيل الاشتراك بنجاح');

    // تسجيل التفعيل الناجح في القائمة
    _activatedSubscriptionsToday[subscriptionId] = DateTime.now();

    // 2️⃣ تحديث الصفحة للحصول على البيانات المحدثة
    debugPrint('🔄 [2/5] تحديث بيانات الصفحة...');
    try {
      await fetchSubscriptionDetails();
      debugPrint('✅ [2/5] تم تحديث الصفحة بنجاح');
    } catch (e) {
      debugPrint('⚠️ [2/5] فشل تحديث الصفحة: $e - المتابعة...');
    }

    // 🎉 عرض نافذة النجاح مع معلومات الاشتراك المحدثة
    if (mounted) {
      await _showActivationSuccessDialog();
    }

    // 3️⃣ حفظ البيانات في VPS (دائماً بغض النظر عن الصلاحيات)
    debugPrint('📊 [3/5] حفظ البيانات...');
    try {
      if (partnerWalletBalanceBefore == 0.0) {
        partnerWalletBalanceBefore = walletBalance;
      }
      if (customerWalletBalanceBefore == 0.0) {
        customerWalletBalanceBefore = customerWalletBalance;
      }
      await _saveToServer();
      safeSetState(() => _isSavedToSheets = true);
      debugPrint('✅ [3/5] تم الحفظ بنجاح');
    } catch (e) {
      debugPrint('⚠️ [3/5] فشل الحفظ: $e - المتابعة...');
    }

    // 4️⃣ طباعة الوصل
    debugPrint('🖨️ [4/5] طباعة الوصل...');
    try {
      await _executePrintReceipt();
      debugPrint('✅ [4/5] تم طباعة الوصل بنجاح');
    } catch (e) {
      debugPrint('⚠️ [4/5] فشل الطباعة: $e - المتابعة...');
    }

    // 5️⃣ إرسال واتساب (إن توفرت الصلاحية)
    if (widget.hasWhatsAppPermission) {
      debugPrint('📱 [5/5] إرسال رسالة واتساب...');
      try {
        await sendWhatsAppMessage();
        debugPrint('✅ [5/5] تم إرسال الواتساب بنجاح');
      } catch (e) {
        debugPrint('⚠️ [5/5] فشل إرسال الواتساب: $e');
      }
    } else {
      debugPrint('⏭️ [5/5] تخطي واتساب - لا توجد صلاحية');
    }

    // ========== اكتمال العملية ==========
    debugPrint('🎉 اكتملت جميع العمليات بنجاح!');
  }

  /// عرض تحذير التفعيل المكرر في نفس اليوم
  Future<bool> _showDuplicateActivationWarning(int minutesAgo) async {
    String timeText;
    if (minutesAgo < 1) {
      timeText = 'منذ أقل من دقيقة';
    } else if (minutesAgo < 60) {
      timeText = 'منذ $minutesAgo دقيقة';
    } else {
      final hours = minutesAgo ~/ 60;
      timeText = 'منذ $hours ساعة';
    }

    final customerName = subscriptionInfo?.customerName ?? 'هذا المشترك';

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade400, width: 2),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'تحذير: تفعيل مكرر!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Icon(
                    Icons.replay_circle_filled,
                    size: 48,
                    color: Colors.orange.shade600,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'تم الضغط على التفعيل التلقائي لـ',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'هل تريد المتابعة والتفعيل مرة أخرى؟',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'إلغاء',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('نعم، تابع التفعيل',
                    style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// عرض نافذة نجاح التفعيل مع معلومات الاشتراك
  Future<void> _showActivationSuccessDialog() async {
    final info = subscriptionInfo;
    final customerName = info?.customerName ?? 'غير معروف';
    final plan = info?.currentPlan ?? selectedPlan ?? 'غير محدد';
    final expiryDate = _calculateEndDate();
    final status = info?.status ?? 'غير معروف';
    final commitment =
        info?.commitmentPeriod ?? selectedCommitmentPeriod ?? 'غير محدد';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.teal.shade400],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'تم التفعيل بنجاح!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // معلومات الاشتراك
              _buildInfoRow(Icons.person, 'اسم المشترك', customerName),
              _buildInfoRow(Icons.wifi, 'الباقة', plan),
              _buildInfoRow(Icons.calendar_month, 'تاريخ الانتهاء', expiryDate),
              _buildInfoRow(Icons.timelapse, 'مدة الالتزام', '$commitment شهر'),
              _buildInfoRow(Icons.check_circle_outline, 'الحالة', status),
              const SizedBox(height: 12),
              // فاصل
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade200, Colors.teal.shade200],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'سيتم الآن: حفظ البيانات، طباعة الوصل، وإرسال الواتساب',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('موافق',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// بناء صف معلومات في Dialog
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.teal.shade700),
          ),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  /// تنفيذ تغيير الاشتراك (API) - يعيد true عند النجاح
  Future<bool> _executeChangeSubscription() async {
    if (subscriptionInfo == null || priceDetails == null) {
      safeSetState(
          () => errorMessage = 'معلومات الاشتراك أو الأسعار غير متوفرة');
      return false;
    }

    // حفظ رصيد المحفظة قبل العملية
    if (partnerWalletBalanceBefore == 0.0) {
      partnerWalletBalanceBefore = walletBalance;
    }
    if (customerWalletBalanceBefore == 0.0) {
      customerWalletBalanceBefore = customerWalletBalance;
    }

    // إظهار مؤشر انتظار
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: SizedBox(
            width: 220,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text('جاري تفعيل الاشتراك...')),
              ],
            ),
          ),
        ),
      );
    }

    try {
      // بناء جسم الطلب
      final services = [
        {'value': selectedPlan, 'type': 'Base'},
        {'value': 'IPTV', 'type': 'Vas'},
        {'value': 'PARENTAL_CONTROL', 'type': 'Vas'},
      ];

      final simulatedPrice = priceDetails?['finalPrice'] ??
          priceDetails?['totalAmountWithVat'] ??
          priceDetails?['totalAmount'] ??
          _getFinalTotal();

      final walletSource =
          _selectedWalletSource == 'customer' ? 'Customer' : 'Partner';

      final body = <String, dynamic>{
        'simulatedPrice':
            simulatedPrice is double ? simulatedPrice.toInt() : simulatedPrice,
        'bundleId': subscriptionInfo!.bundleId,
        'services': services,
        'commitmentPeriodValue': selectedCommitmentPeriod,
        'salesType': _getSalesTypeValue(),
        'paymentDetails': {
          'walletSource': walletSource,
          'paymentMethod': 'Wallet',
        },
        'changeType': 1,
      };

      debugPrint('📤 إرسال طلب التفعيل: ${jsonEncode(body)}');

      final resp = await http
          .post(
            Uri.parse(
                'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/change'),
            headers: {
              'Authorization': 'Bearer ${widget.authToken}',
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/plain, */*',
              'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
              'x-user-role': '0',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('📥 الاستجابة: ${resp.statusCode} - ${resp.body}');

      // إغلاق مؤشر الانتظار
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }

      if (resp.statusCode == 200) {
        // النجاح - لا نعرض Dialog هنا لأنه سيظهر في النهاية
        return true;
      } else {
        String failMsg = 'فشل تفعيل الاشتراك (HTTP ${resp.statusCode})';
        try {
          final data = jsonDecode(resp.body);
          final msg = data['message'] ?? data['error'];
          if (msg != null) failMsg += '\n$msg';
        } catch (_) {}

        safeSetState(() => errorMessage = failMsg);
        if (mounted) {
          _showResultDialog(
            isSuccess: false,
            title: 'فشل التفعيل',
            message: failMsg,
          );
        }
        return false;
      }
    } catch (e) {
      // إغلاق مؤشر الانتظار
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }

      debugPrint('❌ خطأ في التفعيل: $e');
      safeSetState(() => errorMessage = 'خطأ في الاتصال: $e');
      if (mounted) {
        _showResultDialog(
          isSuccess: false,
          title: 'خطأ في الاتصال',
          message: 'حدث خطأ أثناء الاتصال بالخادم:\n$e',
        );
      }
      return false;
    }
  }

  /// عرض نافذة منبثقة للنتيجة (نجاح/فشل)
  void _showResultDialog({
    required bool isSuccess,
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSuccess ? Colors.green.shade100 : Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color:
                      isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                ),
              ),
            ),
          ],
        ),
        content: Container(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Text(
            message,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuccess ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('موافق', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  /// تنفيذ الطباعة (بدون تحذير الطباعة المكررة)
  Future<void> _executePrintReceipt() async {
    if (subscriptionInfo == null) {
      debugPrint('⚠️ لا يمكن الطباعة - معلومات الاشتراك غير متوفرة');
      return;
    }

    try {
      final phone = _getCustomerPhoneNumber();
      final customerPhone = phone ?? 'غير متوفر';
      final operationText =
          isNewSubscription ? "تم شراء اشتراك جديد" : "تم تجديد الاشتراك";

      final template = await PrintTemplateStorage.loadTemplate();
      final adjustedTemplate = PrintTemplate(
        companyName: template.companyName,
        companySubtitle: template.companySubtitle,
        footerMessage: template.footerMessage,
        contactInfo: template.contactInfo,
        showCustomerInfo: true,
        showServiceDetails: template.showServiceDetails,
        showPaymentDetails: template.showPaymentDetails,
        showAdditionalInfo: template.showAdditionalInfo,
        showContactInfo: template.showContactInfo,
        fontSize: template.fontSize.clamp(8.0, 20.0),
        boldHeaders: template.boldHeaders,
      );

      final now = DateTime.now();
      final activationDate = '${now.day}/${now.month}/${now.year}';
      final activationTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final printCurr = (priceDetails?['totalPrice'] is Map &&
              priceDetails?['totalPrice']['currency'] != null)
          ? priceDetails!['totalPrice']['currency'].toString()
          : (priceDetails?['currency']?.toString() ?? 'IQD');

      final bool success =
          await ThermalPrinterService.printCustomSubscriptionReceipt(
        operationType: operationText,
        selectedPlan: selectedPlan ?? '',
        selectedCommitmentPeriod: (selectedCommitmentPeriod ?? 0).toString(),
        totalPrice: _getFinalTotal().toStringAsFixed(0),
        currency: printCurr,
        selectedPaymentMethod: selectedPaymentMethod,
        endDate: _calculateEndDate(),
        customerName: subscriptionInfo!.customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress ?? '',
        isNewSubscription: isNewSubscription,
        customTemplate: adjustedTemplate,
        activationDate: activationDate,
        activationTime: activationTime,
        fdtInfo: (widget.fdtDisplayValue != null &&
                widget.fdtDisplayValue!.trim().isNotEmpty)
            ? widget.fdtDisplayValue!
            : (widget.fbgValue != null && widget.fbgValue!.trim().isNotEmpty
                ? widget.fbgValue!.trim()
                : null),
        fatInfo: (widget.fatDisplayValue != null &&
                widget.fatDisplayValue!.trim().isNotEmpty)
            ? widget.fatDisplayValue!
            : (widget.fatValue != null && widget.fatValue!.trim().isNotEmpty
                ? widget.fatValue!.trim()
                : null),
        activatedBy: widget.activatedBy,
        subscriptionNotes:
            (isNotesEnabled && subscriptionNotes.trim().isNotEmpty)
                ? subscriptionNotes.trim()
                : null,
      );

      if (success && mounted) {
        safeSetState(() => isPrinted = true);
      }
    } catch (e) {
      debugPrint('❌ خطأ في الطباعة: $e');
      rethrow;
    }
  }

  /// عرض مربع حوار تأكيد قبل التجديد/الشراء
  Future<bool> _showRenewalConfirmationDialog() async {
    final operationType = _getOperationTypeText();
    final price = _formatNumber(_getFinalTotal().round());

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تأكيد $operationType',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildConfirmRow(
                          'العميل:', subscriptionInfo?.customerName ?? ''),
                      const SizedBox(height: 8),
                      _buildConfirmRow('الباقة:', selectedPlan ?? ''),
                      const SizedBox(height: 8),
                      _buildConfirmRow(
                          'المدة:', '$selectedCommitmentPeriod شهر'),
                      const SizedBox(height: 8),
                      _buildConfirmRow('المبلغ:', '$price IQD'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.amber.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'سيتم خصم المبلغ من المحفظة وتفعيل الاشتراك',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child:
                    const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.check, size: 18),
                label: Text('تأكيد $operationType'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// عرض مربع حوار عند عدم كفاية الرصيد
  void _showInsufficientBalanceDialog(double required, double available) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.red.shade700, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'الرصيد غير كافٍ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildConfirmRow('المبلغ المطلوب:',
                      '${_formatNumber(required.round())} IQD'),
                  const SizedBox(height: 8),
                  _buildConfirmRow('الرصيد المتاح:',
                      '${_formatNumber(available.round())} IQD'),
                  const Divider(height: 16),
                  _buildConfirmRow('النقص:',
                      '${_formatNumber((required - available).round())} IQD',
                      valueColor: Colors.red.shade700),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  /// بناء صف في مربع التأكيد
  Widget _buildConfirmRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  /// الحصول على نص نوع العملية
  String _getOperationTypeText() {
    if (isNewSubscription) return 'شراء الاشتراك';

    final isRenewal = subscriptionInfo != null &&
        selectedPlan == subscriptionInfo!.currentPlan &&
        selectedCommitmentPeriod == subscriptionInfo!.commitmentPeriod;

    return isRenewal ? 'تجديد الاشتراك' : 'تغيير الاشتراك';
  }

  /// بناء زر التجديد/الشراء للعرض في الواجهة
  Widget buildRenewalButton() {
    final operationType = _getOperationTypeText();
    final bool canExecute = priceDetails != null &&
        selectedPlan != null &&
        selectedCommitmentPeriod != null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton.icon(
        onPressed: canExecute ? executeRenewalOrPurchase : null,
        icon: Icon(
          isNewSubscription ? Icons.shopping_cart : Icons.refresh,
          size: 22,
        ),
        label: Text(
          operationType,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canExecute
              ? (isNewSubscription
                  ? Colors.green.shade600
                  : Colors.blue.shade600)
              : Colors.grey.shade400,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: canExecute ? Colors.green.shade800 : Colors.grey.shade500,
              width: 1.5,
            ),
          ),
          elevation: canExecute ? 4 : 0,
        ),
      ),
    );
  }
}
