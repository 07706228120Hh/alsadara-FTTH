import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api/api_client.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// صفحة عرض معاملات الفني المالية - ثيم فاتح (XONEPROO)
class TechnicianTransactionsPage extends StatefulWidget {
  final String username;

  const TechnicianTransactionsPage({
    super.key,
    required this.username,
  });

  @override
  State<TechnicianTransactionsPage> createState() =>
      _TechnicianTransactionsPageState();
}

class _TechnicianTransactionsPageState
    extends State<TechnicianTransactionsPage> {
  final _client = ApiClient.instance;

  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _transactions = [];
  Map<String, dynamic> _summary = {};
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;

  // ── ألوان الثيم الفاتح (XONEPROO Style) ──
  static const _bgPage = Color(0xFFF5F6FA);
  static const _bgCard = Colors.white;
  static const _bgToolbar = Color(0xFF2C3E50);
  static const _textDark = Color(0xFF333333);
  static const _textGray = Color(0xFF999999);
  static const _textSubtle = Color(0xFF666666);
  static const _shadowColor = Color(0x14000000);
  static const _accentBlue = Color(0xFF3498DB);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _client.get(
        '/techniciantransactions/my-transactions?page=$page&pageSize=50',
        (json) => json,
      );

      if (response.success && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          setState(() {
            _transactions = data['transactions'] as List<dynamic>? ?? [];
            _summary = data['summary'] as Map<String, dynamic>? ?? {};
            _currentPage = data['page'] ?? 1;
            _totalPages = data['totalPages'] ?? 1;
            _total = data['total'] ?? 0;
            _isLoading = false;
          });
        } else {
          setState(() {
            _transactions = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = response.message ?? 'فشل في تحميل المعاملات';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في الاتصال';
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd - HH:mm', 'ar').format(date.toLocal());
    } catch (_) {
      return dateStr;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final num val =
        amount is num ? amount : num.tryParse(amount.toString()) ?? 0;
    return NumberFormat('#,##0', 'ar').format(val);
  }

  Widget _infoChip(IconData icon, String text, Color iconColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 3),
        Text(
          text,
          style: GoogleFonts.cairo(color: _textSubtle, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _getCategoryName(String? category) {
    switch (category) {
      case 'Maintenance':
        return 'صيانة';
      case 'Installation':
        return 'تركيب';
      case 'Collection':
        return 'تحصيل';
      case 'CashPayment':
        return 'تسديد نقدي';
      case 'Subscription':
        return 'شراء اشتراك';
      case 'Other':
        return 'أخرى';
      default:
        return category ?? '-';
    }
  }

  String _getTypeName(String? type) {
    switch (type) {
      case 'Charge':
        return 'أجور';
      case 'Payment':
        return 'تسديد';
      case 'Discount':
        return 'خصم';
      case 'Adjustment':
        return 'تعديل';
      default:
        return type ?? '-';
    }
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'Charge':
        return const Color(0xFFE74C3C);
      case 'Payment':
        return const Color(0xFF2ECC71);
      case 'Discount':
        return const Color(0xFFF39C12);
      case 'Adjustment':
        return _accentBlue;
      default:
        return _textGray;
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type) {
      case 'Charge':
        return Icons.arrow_downward;
      case 'Payment':
        return Icons.arrow_upward;
      case 'Discount':
        return Icons.discount;
      case 'Adjustment':
        return Icons.tune;
      default:
        return Icons.receipt;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Maintenance':
        return Icons.build;
      case 'Installation':
        return Icons.construction;
      case 'Collection':
        return Icons.payments;
      case 'CashPayment':
        return Icons.money;
      case 'Subscription':
        return Icons.shopping_cart;
      case 'Other':
        return Icons.more_horiz;
      default:
        return Icons.receipt_long;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgPage,
        body: Column(
          children: [
            _buildPageToolbar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accentBlue))
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _bgToolbar,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('معاملاتي المالية',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const Spacer(),
          IconButton(
            onPressed: () => _loadTransactions(page: _currentPage),
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE74C3C), size: 64),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: GoogleFonts.cairo(color: _textGray, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadTransactions(),
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // بطاقات الملخص
          _buildSummaryCards(),
          const SizedBox(height: 20),
          // عنوان المعاملات
          Row(
            children: [
              Text(
                'المعاملات ($_total)',
                style: GoogleFonts.cairo(
                  color: _textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_totalPages > 1)
                Text(
                  'صفحة $_currentPage من $_totalPages',
                  style: GoogleFonts.cairo(color: _textGray, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // قائمة المعاملات
          if (_transactions.isEmpty)
            _buildEmptyView()
          else
            ..._transactions.map((tx) => _buildTransactionCard(tx)),
          if (_totalPages > 1) _buildPaginationBar(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final totalCharges = _summary['totalCharges'] ?? 0;
    final totalPayments = _summary['totalPayments'] ?? 0;
    final netBalance = _summary['netBalance'] ?? 0;
    final isNegative = (netBalance is num) && netBalance < 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW > 700 ? 3 : 2;
        final spacing = 16.0;
        final cardWidth = (maxW - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                title: 'إجمالي الأجور',
                value: '${_formatAmount(totalCharges)} د.ع',
                icon: Icons.trending_down,
                color: const Color(0xFFE74C3C),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                title: 'إجمالي التسديدات',
                value: '${_formatAmount(totalPayments)} د.ع',
                icon: Icons.trending_up,
                color: const Color(0xFF2ECC71),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                title: 'الرصيد الصافي',
                value:
                    '${_formatAmount((netBalance is num ? netBalance : 0).abs())} د.ع',
                icon: isNegative
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle,
                color: isNegative
                    ? const Color(0xFFE74C3C)
                    : const Color(0xFF2ECC71),
                subtitle: isNegative ? 'مدين' : 'لا يوجد مستحقات',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 3,
                  width: 60,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: GoogleFonts.cairo(fontSize: 12, color: _textGray),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(dynamic tx) {
    final type = tx['type']?.toString();
    final category = tx['category']?.toString();
    final amount = tx['amount'];
    final createdAt = tx['createdAt']?.toString();
    final typeColor = _getTypeColor(type);

    // تفاصيل المهمة
    final customerName = tx['customerName']?.toString();
    final taskType = tx['taskType']?.toString();
    final area = tx['area']?.toString();
    final address = tx['address']?.toString();
    final city = tx['city']?.toString();
    final contactPhone = tx['contactPhone']?.toString();

    // عنوان وصفي
    String title = _getCategoryName(category);
    if (taskType != null && taskType.isNotEmpty) {
      title = taskType;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // أيقونة دائرية ملونة
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: typeColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getTypeIcon(type),
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            // التفاصيل
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // نوع العملية + التصنيف
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getTypeName(type),
                          style: GoogleFonts.cairo(
                            color: typeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(_getCategoryIcon(category),
                          size: 14, color: _textGray),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.cairo(
                              color: _textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // معلومات المعاملة بشكل أفقي
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      if (customerName != null && customerName.isNotEmpty)
                        _infoChip(
                            Icons.person_outline, customerName, _accentBlue),
                      if ((area != null && area.isNotEmpty) ||
                          (city != null && city.isNotEmpty) ||
                          (address != null && address.isNotEmpty))
                        _infoChip(
                          Icons.location_on_outlined,
                          [
                            if (area != null && area.isNotEmpty) area,
                            if (city != null && city.isNotEmpty) city,
                            if (address != null && address.isNotEmpty) address,
                          ].join(' - '),
                          _textGray,
                        ),
                      if (contactPhone != null && contactPhone.isNotEmpty)
                        _infoChip(
                            Icons.phone_outlined, contactPhone, _textGray),
                      if (tx['journalEntryNumber'] != null)
                        _infoChip(Icons.receipt_long_outlined,
                            'قيد: ${tx['journalEntryNumber']}', _accentBlue),
                      _infoChip(
                          Icons.access_time, _formatDate(createdAt), _textGray),
                    ],
                  ),
                ],
              ),
            ),
            // المبلغ
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${type == 'Charge' ? '-' : '+'}${_formatAmount(amount)}',
                  style: GoogleFonts.cairo(
                    color: typeColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'د.ع',
                  style: GoogleFonts.cairo(color: _textGray, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: _textGray.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'لا توجد معاملات مالية حالياً',
            style: GoogleFonts.cairo(
              color: _textGray,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ستظهر هنا جميع الأجور والتسديدات',
            style: GoogleFonts.cairo(
                color: _textGray.withOpacity(0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_currentPage > 1)
            TextButton.icon(
              onPressed: () => _loadTransactions(page: _currentPage - 1),
              icon: const Icon(Icons.chevron_right, color: _accentBlue),
              label:
                  Text('السابق', style: GoogleFonts.cairo(color: _accentBlue)),
            ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: _shadowColor, blurRadius: 4),
              ],
            ),
            child: Text(
              '$_currentPage / $_totalPages',
              style: GoogleFonts.cairo(color: _textDark, fontSize: 14),
            ),
          ),
          const SizedBox(width: 16),
          if (_currentPage < _totalPages)
            TextButton.icon(
              onPressed: () => _loadTransactions(page: _currentPage + 1),
              icon: const Icon(Icons.chevron_left, color: _accentBlue),
              label:
                  Text('التالي', style: GoogleFonts.cairo(color: _accentBlue)),
            ),
        ],
      ),
    );
  }
}
