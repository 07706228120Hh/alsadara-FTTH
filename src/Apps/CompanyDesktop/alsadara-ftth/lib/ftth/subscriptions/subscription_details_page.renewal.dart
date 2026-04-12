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

    // منع الضغط المزدوج — إذا كانت عملية تفعيل جارية بالفعل
    if (_isActivating) {
      debugPrint('⚠️ عملية تفعيل جارية بالفعل - تجاهل الضغط');
      return;
    }

    // فاصل زمني إجباري (دقيقتان) بين كل تفعيلتين
    if (_lastActivationTime != null) {
      final elapsed = DateTime.now().difference(_lastActivationTime!);
      const cooldown = Duration(minutes: 2);
      if (elapsed < cooldown) {
        final remaining = cooldown - elapsed;
        final remainSec = remaining.inSeconds;
        final mins = remainSec ~/ 60;
        final secs = remainSec % 60;
        final timeText = mins > 0
            ? '$mins:${secs.toString().padLeft(2, '0')} دقيقة'
            : '$secs ثانية';
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.timer, color: Colors.orange.shade700, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('يرجى الانتظار', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top, size: 48, color: Colors.orange.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'يجب الانتظار دقيقتين بين كل عملية تفعيل وأخرى',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'المتبقي: $timeText',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
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
        return;
      }
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

    // التحقق من كفاية الرصيد (محفظة العضو إن وُجدت وإلا الرئيسية)
    final totalPrice = _asDouble(priceDetails!['totalPrice']);
    final availableBalance = _selectedWalletSource == 'customer'
        ? customerWalletBalance
        : _effectiveMainBalance;

    if (totalPrice > availableBalance) {
      safeSetState(() => errorMessage = 'الرصيد غير كافٍ لإتمام العملية');
      _showInsufficientBalanceDialog(totalPrice, availableBalance);
      return;
    }

    // ═══════ مقارنة بيانات المهمة مع الاختيارات الحالية ═══════
    if (widget.taskId != null) {
      final mismatches = <String>[];

      // مقارنة المدة
      if (widget.taskDuration != null && widget.taskDuration!.isNotEmpty) {
        final taskDur = int.tryParse(widget.taskDuration!);
        if (taskDur != null && selectedCommitmentPeriod != null && taskDur != selectedCommitmentPeriod) {
          mismatches.add('المدة: المهمة تطلب ${widget.taskDuration} شهر، لكنك اخترت $selectedCommitmentPeriod شهر');
        }
      }

      // مقارنة الخدمة (نوع الباقة)
      if (widget.taskServiceType != null && widget.taskServiceType!.isNotEmpty && selectedPlan != null) {
        final taskService = widget.taskServiceType!.replaceAll(RegExp(r'[^\d]'), '');
        final planDigits = selectedPlan!.replaceAll(RegExp(r'[^\d]'), '');
        if (taskService.isNotEmpty && planDigits.isNotEmpty && !planDigits.contains(taskService)) {
          mismatches.add('الخدمة: المهمة تطلب ${widget.taskServiceType} Mbps، لكنك اخترت $selectedPlan');
        }
      }

      // مقارنة المبلغ
      if (widget.taskAmount != null && widget.taskAmount!.isNotEmpty) {
        final taskAmt = double.tryParse(widget.taskAmount!.replaceAll(RegExp(r'[^\d.]'), ''));
        if (taskAmt != null && totalPrice > 0 && (taskAmt - totalPrice).abs() > 500) {
          mismatches.add('المبلغ: المهمة تطلب ${widget.taskAmount} د.ع، لكن السعر المحسوب ${totalPrice.toStringAsFixed(0)} د.ع');
        }
      }

      if (mismatches.isNotEmpty && mounted) {
        final continueAnyway = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.compare_arrows, color: Colors.orange.shade700, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('اختلاف عن بيانات المهمة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'يوجد اختلاف بين ما هو مطلوب في المهمة وما اخترته:',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                ...mismatches.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
                const SizedBox(height: 8),
                Text(
                  'هل تريد المتابعة رغم الاختلاف؟',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء، سأعدّل الاختيارات', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('متابعة رغم الاختلاف'),
              ),
            ],
          ),
        ) ?? false;
        if (!continueAnyway) return;
      }
    }

    // تحذير عند اختيار فترة التزام أكثر من شهر واحد
    if (selectedCommitmentPeriod != null && selectedCommitmentPeriod! > 1) {
      final confirmCommitment = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('تنبيه: فترة التزام طويلة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 48, color: Colors.amber.shade600),
              const SizedBox(height: 12),
              Text(
                'فترة الالتزام المحددة هي $selectedCommitmentPeriod شهر',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'هل أنت متأكد من أنك تريد التفعيل بفترة التزام أكثر من شهر واحد؟',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('نعم، تفعيل $selectedCommitmentPeriod شهر'),
            ),
          ],
        ),
      ) ?? false;
      if (!confirmCommitment) return;
    }

    // ═══════ سؤال التحصيل عند اختيار "فني" ═══════
    bool techCollectionLater = false;
    if (selectedPaymentMethod == 'فني' && _selectedLinkedTechnician != null && mounted) {
      final techName = _selectedLinkedTechnician!['FullName']?.toString().trim().isNotEmpty == true
          ? _selectedLinkedTechnician!['FullName'].toString().trim()
          : _selectedLinkedTechnician!['Name']?.toString().trim() ?? 'الفني';
      final customerName = subscriptionInfo?.customerName ?? widget.userName ?? '';
      final totalStr = totalPrice.toStringAsFixed(0);

      final screenW = MediaQuery.of(context).size.width;
      final isSmallScreen = screenW < 420;

      final collectionResult = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16)),
          insetPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 40, vertical: 24),
          title: Row(children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.account_balance_wallet, color: Colors.blue.shade700, size: isSmallScreen ? 22 : 28),
            ),
            SizedBox(width: isSmallScreen ? 8 : 12),
            Expanded(child: Text('هل تم تحصيل المبلغ؟', style: TextStyle(fontSize: isSmallScreen ? 15 : 17, fontWeight: FontWeight.bold))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('المشترك:', style: TextStyle(color: Colors.grey, fontSize: isSmallScreen ? 12 : 14)),
                  Flexible(child: Text(customerName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 12 : 14), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('المبلغ:', style: TextStyle(color: Colors.grey, fontSize: isSmallScreen ? 12 : 14)),
                  Text('$totalStr د.ع', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: isSmallScreen ? 12 : 14)),
                ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('الفني:', style: TextStyle(color: Colors.grey, fontSize: isSmallScreen ? 12 : 14)),
                  Flexible(child: Text(techName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 12 : 14), overflow: TextOverflow.ellipsis)),
                ]),
              ]),
            ),
            SizedBox(height: isSmallScreen ? 10 : 16),
            Text(
              'هل قام الفني "$techName" بتحصيل المبلغ من المشترك؟',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey.shade700),
            ),
          ]),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: EdgeInsets.fromLTRB(isSmallScreen ? 12 : 16, 0, isSmallScreen ? 12 : 16, isSmallScreen ? 10 : 16),
          actions: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: isSmallScreen ? double.infinity : null,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop('cancel'),
                      icon: Icon(Icons.cancel, size: isSmallScreen ? 16 : 18),
                      label: Text('إلغاء الاشتراك', style: TextStyle(fontSize: isSmallScreen ? 11 : 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isSmallScreen ? double.infinity : null,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop('later'),
                      icon: Icon(Icons.schedule, size: isSmallScreen ? 16 : 18),
                      label: Text('لا، حصّل لاحقاً', style: TextStyle(fontSize: isSmallScreen ? 11 : 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade700,
                        side: BorderSide(color: Colors.orange.shade300),
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isSmallScreen ? double.infinity : null,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop('collected'),
                      icon: Icon(Icons.check_circle, size: isSmallScreen ? 16 : 18),
                      label: Text('نعم، تم التحصيل', style: TextStyle(fontSize: isSmallScreen ? 11 : 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      if (collectionResult == null) return; // أُغلق بدون اختيار
      if (collectionResult == 'cancel') return; // إلغاء الاشتراك
      techCollectionLater = collectionResult == 'later';
    }

    // تأكيد العملية قبل التنفيذ
    final confirmed = await _showRenewalConfirmationDialog();
    if (!confirmed) return;

    // ========== بدء التنفيذ المتسلسل ==========
    safeSetState(() => _isActivating = true);

    // حفظ القيم المختارة قبل تحديث الصفحة (لأن fetchSubscriptionDetails تُعيد تعيينها)
    final activatedPlan = selectedPlan;
    final activatedPeriod = selectedCommitmentPeriod;
    final activatedPriceDetails = priceDetails != null
        ? Map<String, dynamic>.from(priceDetails!)
        : null;
    final activatedPaymentMethod = selectedPaymentMethod;
    final activatedAgent = _selectedLinkedAgent;
    final activatedTechnician = _selectedLinkedTechnician;

    try {
      // 1️⃣ تفعيل الاشتراك
      debugPrint('🚀 [1/5] بدء تفعيل الاشتراك...');
      final activationSuccess = await _executeChangeSubscription();
      if (!activationSuccess) {
        debugPrint('❌ فشل تفعيل الاشتراك - إيقاف العملية');
        return;
      }
      debugPrint('✅ [1/5] تم تفعيل الاشتراك بنجاح');

      // تسجيل التفعيل الناجح في القائمة + الفاصل الزمني
      _activatedSubscriptionsToday[subscriptionId] = DateTime.now();
      _lastActivationTime = DateTime.now();

      // 2️⃣ تحديث الصفحة للحصول على البيانات المحدثة
      debugPrint('🔄 [2/5] تحديث بيانات الصفحة...');
      try {
        await fetchSubscriptionDetails();
        debugPrint('✅ [2/5] تم تحديث الصفحة بنجاح');
      } catch (e) {
        debugPrint('⚠️ [2/5] فشل تحديث الصفحة: $e - المتابعة...');
      }

      // استعادة القيم المختارة للطباعة والحفظ (لأن API قد يرجع القيم القديمة)
      selectedPlan = activatedPlan;
      selectedCommitmentPeriod = activatedPeriod;
      priceDetails = activatedPriceDetails;
      selectedPaymentMethod = activatedPaymentMethod;
      _selectedLinkedAgent = activatedAgent;
      _selectedLinkedTechnician = activatedTechnician;

      // 🎉 عرض نافذة النجاح مع معلومات الاشتراك المحدثة
      if (mounted) {
        await _showActivationSuccessDialog();
      }

      // 🔄 إغلاق المهمة تلقائياً بعد نجاح التجديد
      if (widget.taskId != null && widget.taskId!.isNotEmpty) {
        debugPrint('🔄 إغلاق المهمة تلقائياً: ${widget.taskId}');
        try {
          await TaskApiService.instance.updateStatus(
            widget.taskId!,
            status: 'Completed',
            note: '[مفعّل] تم إكمال التجديد تلقائياً من صفحة التجديد',
          );
          debugPrint('✅ تم إغلاق المهمة بنجاح');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.task_alt, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('تم إكمال المهمة تلقائياً'),
                  ],
                ),
                backgroundColor: Colors.green.shade600,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          debugPrint('⚠️ فشل إغلاق المهمة تلقائياً: $e');
        }
      }

      // 📋 إنشاء مهمة تحصيل للفني إذا اختار "حصّل لاحقاً"
      if (techCollectionLater && _selectedLinkedTechnician != null) {
        debugPrint('📋 إنشاء مهمة تحصيل للفني...');
        try {
          final techName = _selectedLinkedTechnician!['FullName']?.toString().trim().isNotEmpty == true
              ? _selectedLinkedTechnician!['FullName'].toString().trim()
              : _selectedLinkedTechnician!['Name']?.toString().trim() ?? '';
          final techPhone = _selectedLinkedTechnician!['PhoneNumber']?.toString().trim() ?? '';
          final customerName = subscriptionInfo?.customerName ?? widget.userName ?? '';
          final customerPhone = widget.userPhone?.isNotEmpty == true
              ? widget.userPhone!
              : (_fetchedCustomerPhone?.isNotEmpty == true
                  ? _fetchedCustomerPhone!
                  : _resolveTargetPhone() ?? '');
          final totalStr = _asDouble(priceDetails?['totalPrice']).toStringAsFixed(0);

          final fbg = widget.fbgValue?.trim() ?? widget.fdtDisplayValue?.trim() ?? '';
          final fat = widget.fatValue?.trim() ?? widget.fatDisplayValue?.trim() ?? '';

          await TaskApiService.instance.createTask(
            taskType: 'تحصيل مبلغ تجديد',
            customerName: customerName,
            customerPhone: customerPhone,
            department: 'الحسابات',
            technician: techName,
            technicianPhone: techPhone,
            fbg: fbg,
            fat: fat,
            serviceType: selectedPlan,
            subscriptionDuration: '${selectedCommitmentPeriod ?? 1}',
            subscriptionAmount: _asDouble(priceDetails?['totalPrice']),
            notes: 'تحصيل $totalStr د.ع من $customerName\n'
                'الهاتف: $customerPhone\n'
                'الخدمة: ${selectedPlan ?? ""} - ${selectedCommitmentPeriod ?? 1} شهر\n'
                'المشغل: ${widget.activatedBy}\n'
                'تاريخ التجديد: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
            summary: 'تحصيل $totalStr د.ع من $customerName — فني: $techName',
            priority: 'عالي',
          );
          debugPrint('✅ تم إنشاء مهمة التحصيل بنجاح');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(children: [
                  const Icon(Icons.assignment_turned_in, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('تم إرسال أمر تحصيل $totalStr د.ع للفني $techName')),
                ]),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } catch (e) {
          debugPrint('⚠️ فشل إنشاء مهمة التحصيل: $e');
        }
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
          debugPrint('⚠️ [5/5] فشل إرسال الواتساب');
        }
      } else {
        debugPrint('⏭️ [5/5] تخطي واتساب - لا توجد صلاحية');
      }

      // ========== اكتمال العملية ==========
      debugPrint('🎉 اكتملت جميع العمليات بنجاح!');
    } finally {
      safeSetState(() => _isActivating = false);
    }
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

      // تحديد الـ endpoint وجسم الطلب حسب نوع الاشتراك
      final String apiUrl;
      final Map<String, dynamic> body;

      if (isNewSubscription) {
        // شراء اشتراك جديد (تحويل من تجريبي) — POST /api/subscriptions/purchase
        apiUrl = 'https://admin.ftth.iq/api/subscriptions/purchase';
        body = {
          'zoneId': subscriptionInfo!.zoneId,
          'bundleId': subscriptionInfo!.bundleId,
          'services': services,
          'commitmentPeriod': selectedCommitmentPeriod,
          'trialSubscriptionId': widget.subscriptionId,
          'simulatedPrice':
              simulatedPrice is double ? simulatedPrice.toInt() : simulatedPrice,
          'salesType': _getSalesTypeValue(),
          'paymentDetails': {
            'paymentMethod': 'Wallet',
            'walletSource': walletSource,
          },
        };
      } else {
        // تجديد أو تغيير اشتراك موجود — POST /api/subscriptions/{id}/change
        apiUrl = 'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/change';
        body = {
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
      }

      debugPrint('📤 إرسال طلب التفعيل: $apiUrl');
      debugPrint('📤 Body: ${jsonEncode(body)}');

      final resp = await AuthService.instance.authenticatedRequest(
          'POST',
          apiUrl,
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
            'x-user-role': '0',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 20));

      debugPrint('📥 الاستجابة: ${resp.statusCode}');
      debugPrint('📥 Headers: ${resp.headers}');
      debugPrint('📥 Body: ${resp.body}');

      // إغلاق مؤشر الانتظار
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }

      if (resp.statusCode == 200) {
        // النجاح - لا نعرض Dialog هنا لأنه سيظهر في النهاية
        return true;
      } else {
        String failMsg;
        if (resp.statusCode == 403) {
          failMsg = 'ممنوع (403): لا تملك صلاحية تجديد هذا الاشتراك.\n'
              'قد يكون المشترك تابع لمنطقة أو شريك آخر ليس لديك صلاحية عليه.';
        } else {
          failMsg = 'فشل تفعيل الاشتراك (HTTP ${resp.statusCode})';
        }
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

      debugPrint('❌ خطأ في التفعيل');
      safeSetState(() => errorMessage = 'خطأ في الاتصال');
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
      final vars = _buildReceiptVariableValues(copyNumber: _printCount + 1);
      final conds = _buildReceiptConditions();

      final bool success = await ThermalPrinterService.printFromReceiptTemplate(
        variableValues: vars,
        conditions: conds,
      );

      if (success && mounted) {
        safeSetState(() {
          _printCount++;
          isPrinted = true;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في الطباعة');
      rethrow;
    }
  }

  /// بناء خريطة قيم المتغيرات لنظام القالب الجديد V2
  Map<String, String> _buildReceiptVariableValues({int? copyNumber}) {
    final phone = _getCustomerPhoneNumber();
    final customerPhone = phone ?? 'غير متوفر';
    final operationText =
        isNewSubscription ? "تم شراء اشتراك جديد" : "تم تجديد الاشتراك";
    final now = DateTime.now();
    final activationDate = '${now.day}/${now.month}/${now.year}';
    final activationTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final printCurr = (priceDetails?['totalPrice'] is Map &&
            priceDetails?['totalPrice']['currency'] != null)
        ? priceDetails!['totalPrice']['currency'].toString()
        : (priceDetails?['currency']?.toString() ?? 'IQD');

    final oldTemplate = PrintTemplateStorage.defaultTemplate;

    // FDT/FAT مع fallback
    final fdtVal = (widget.fdtDisplayValue?.trim().isNotEmpty == true)
        ? widget.fdtDisplayValue!
        : (widget.fbgValue?.trim().isNotEmpty == true ? widget.fbgValue!.trim() : null);
    final fatVal = (widget.fatDisplayValue?.trim().isNotEmpty == true)
        ? widget.fatDisplayValue!
        : (widget.fatValue?.trim().isNotEmpty == true ? widget.fatValue!.trim() : null);

    // بيانات المشغّل من سيرفرنا
    final vpsUser = VpsAuthService.instance.currentUser;

    return ReceiptTemplateStorageV2.buildVariableValues(
      operationType: operationText,
      customerName: subscriptionInfo!.customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress ?? '',
      paymentMethod: selectedPaymentMethod, // فقط نوع الدفع (نقد/أجل/ماستر/وكيل/فني)
      totalPrice: _getFinalTotal().toStringAsFixed(0),
      currency: printCurr,
      endDate: _calculateEndDate(),
      activatedBy: widget.activatedBy,
      receiptNumber: (_printCount + 1).toString(),
      selectedPlan: selectedPlan ?? '',
      commitmentPeriod: (selectedCommitmentPeriod ?? 0).toString(),
      activationDate: activationDate,
      activationTime: activationTime,
      fdtInfo: fdtVal,
      fatInfo: fatVal,
      subscriptionNotes: (isNotesEnabled && subscriptionNotes.trim().isNotEmpty)
          ? subscriptionNotes.trim()
          : null,
      copyNumber: copyNumber,
      // الترويسة من القالب القديم
      companyName: oldTemplate.companyName,
      companySubtitle: oldTemplate.companySubtitle,
      contactInfo: oldTemplate.contactInfo,
      footerMessage: oldTemplate.footerMessage,
      // الفني / الوكيل (مفصولة)
      technicianName: _selectedLinkedTechnician?['Name']?.toString(),
      technicianUsername: _selectedLinkedTechnician?['Username']?.toString(),
      technicianPhone: _selectedLinkedTechnician?['PhoneNumber']?.toString(),
      agentName: _selectedLinkedAgent?['Name']?.toString(),
      agentCode: _selectedLinkedAgent?['AgentCode']?.toString(),
      agentPhone: _selectedLinkedAgent?['PhoneNumber']?.toString(),
      // الأسعار المفصّلة
      basePrice: _asDouble(priceDetails?['basePrice']).toStringAsFixed(0),
      discount: _asDouble(priceDetails?['discount']).toStringAsFixed(0),
      discountPercentage: (priceDetails?['discountPercentage']?.toString()) ?? '0',
      manualDiscount: manualDiscount.toStringAsFixed(0),
      salesType: subscriptionInfo?.salesType,
      walletBalance: walletBalance.toStringAsFixed(0),
      // بيانات الاشتراك الإضافية
      currentPlan: subscriptionInfo?.currentPlan,
      expiryDate: widget.expires,
      subscriptionStartDate: subscriptionInfo?.subscriptionStartDate,
      remainingDays: widget.remainingDays?.toString(),
      subscriptionStatus: subscriptionInfo?.status,
      customerId: subscriptionInfo?.customerId,
      partnerName: subscriptionInfo?.partnerName,
      // الشبكة والجهاز
      fbgInfo: widget.fbgValue ?? subscriptionInfo?.fbg,
      zoneDisplayValue: subscriptionInfo?.zoneDisplayValue,
      deviceUsername: subscriptionInfo?.deviceUsername,
      deviceSerial: subscriptionInfo?.deviceSerial,
      macAddress: subscriptionInfo?.macAddress,
      deviceModel: subscriptionInfo?.deviceModel,
      // المشغّل (سيرفرنا)
      operatorFullName: vpsUser?.fullName,
      operatorPhone: vpsUser?.phone,
      operatorDepartment: widget.firstSystemDepartment,
      operatorCenter: widget.firstSystemCenter,
      operatorRole: widget.userRoleHeader,
    );
  }

  /// بناء خريطة الشروط
  Map<String, bool> _buildReceiptConditions() {
    final oldTemplate = PrintTemplateStorage.defaultTemplate;
    return ReceiptTemplateStorageV2.buildConditions(
      showCustomerInfo: true,
      showServiceDetails: oldTemplate.showServiceDetails,
      showPaymentDetails: oldTemplate.showPaymentDetails,
      showAdditionalInfo: oldTemplate.showAdditionalInfo,
      showContactInfo: oldTemplate.showContactInfo,
      subscriptionNotes: (isNotesEnabled && subscriptionNotes.trim().isNotEmpty)
          ? subscriptionNotes.trim()
          : null,
    );
  }

  /// بناء نص طريقة الدفع للوصل (يشمل اسم الوكيل/الفني إن وُجد)
  String _getPaymentMethodForReceipt() {
    debugPrint('🧾 _getPaymentMethodForReceipt: method=$selectedPaymentMethod, agent=$_selectedLinkedAgent, tech=$_selectedLinkedTechnician');
    if (selectedPaymentMethod == 'وكيل' && _selectedLinkedAgent != null) {
      final name = _selectedLinkedAgent!['Name']?.toString() ?? '';
      final code = _selectedLinkedAgent!['AgentCode']?.toString() ?? '';
      return 'وكيل - $name${code.isNotEmpty ? " ($code)" : ""}';
    }
    if (selectedPaymentMethod == 'فني' && _selectedLinkedTechnician != null) {
      final name = _selectedLinkedTechnician!['Name']?.toString() ?? '';
      return 'فني - $name';
    }
    return selectedPaymentMethod;
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
