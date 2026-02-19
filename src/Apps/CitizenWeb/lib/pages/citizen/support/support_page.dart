import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة الدعم الفني والتذاكر
class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'all';

  // تذاكر تجريبية
  final List<Map<String, dynamic>> _tickets = [
    {
      'id': 'TKT-001',
      'title': 'مشكلة في سرعة الإنترنت',
      'status': 'open',
      'priority': 'high',
      'category': 'technical',
      'createdAt': '2026-01-30',
      'lastUpdate': '2026-01-30',
      'messages': 3,
    },
    {
      'id': 'TKT-002',
      'title': 'استفسار عن الفاتورة',
      'status': 'pending',
      'priority': 'medium',
      'category': 'billing',
      'createdAt': '2026-01-28',
      'lastUpdate': '2026-01-29',
      'messages': 5,
    },
    {
      'id': 'TKT-003',
      'title': 'طلب ترقية الباقة',
      'status': 'closed',
      'priority': 'low',
      'category': 'general',
      'createdAt': '2026-01-20',
      'lastUpdate': '2026-01-22',
      'messages': 4,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('الدعم الفني'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/home'),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'التذاكر', icon: Icon(Icons.confirmation_number)),
              Tab(text: 'المساعدة', icon: Icon(Icons.help)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showNewTicketDialog(),
          backgroundColor: AppTheme.primaryColor,
          icon: const Icon(Icons.add),
          label: const Text('تذكرة جديدة'),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // تبويب التذاكر
            _buildTicketsTab(isWide),
            // تبويب المساعدة
            _buildHelpTab(isWide),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketsTab(bool isWide) {
    final filteredTickets = _selectedFilter == 'all'
        ? _tickets
        : _tickets.where((t) => t['status'] == _selectedFilter).toList();

    return Column(
      children: [
        // فلاتر
        Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'الكل', Icons.list),
                const SizedBox(width: 8),
                _buildFilterChip('open', 'مفتوحة', Icons.radio_button_checked),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'pending',
                  'قيد المعالجة',
                  Icons.hourglass_empty,
                ),
                const SizedBox(width: 8),
                _buildFilterChip('closed', 'مغلقة', Icons.check_circle),
              ],
            ),
          ),
        ),

        // قائمة التذاكر
        Expanded(
          child: filteredTickets.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 32 : 16,
                    vertical: 8,
                  ),
                  itemCount: filteredTickets.length,
                  itemBuilder: (context, index) {
                    return _buildTicketCard(filteredTickets[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)],
      ),
      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryColor,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
      },
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTicketDetails(ticket),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatusBadge(ticket['status']),
                  const Spacer(),
                  Text(
                    ticket['id'],
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ticket['title'],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildPriorityBadge(ticket['priority']),
                  const SizedBox(width: 12),
                  _buildCategoryBadge(ticket['category']),
                  const Spacer(),
                  Row(
                    children: [
                      const Icon(
                        Icons.message,
                        size: 14,
                        color: AppTheme.textGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ticket['messages']}',
                        style: const TextStyle(
                          color: AppTheme.textGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'آخر تحديث: ${ticket['lastUpdate']}',
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'open':
        color = AppTheme.infoColor;
        label = 'مفتوحة';
        break;
      case 'pending':
        color = AppTheme.warningColor;
        label = 'قيد المعالجة';
        break;
      case 'closed':
        color = AppTheme.successColor;
        label = 'مغلقة';
        break;
      default:
        color = AppTheme.textGrey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color;
    String label;
    switch (priority) {
      case 'high':
        color = AppTheme.errorColor;
        label = 'عاجل';
        break;
      case 'medium':
        color = AppTheme.warningColor;
        label = 'متوسط';
        break;
      case 'low':
        color = AppTheme.successColor;
        label = 'منخفض';
        break;
      default:
        color = AppTheme.textGrey;
        label = priority;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flag, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildCategoryBadge(String category) {
    IconData icon;
    String label;
    switch (category) {
      case 'technical':
        icon = Icons.build;
        label = 'تقني';
        break;
      case 'billing':
        icon = Icons.receipt;
        label = 'مالي';
        break;
      case 'general':
        icon = Icons.info;
        label = 'عام';
        break;
      default:
        icon = Icons.help;
        label = category;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textGrey),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 80,
            color: AppTheme.textGrey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد تذاكر',
            style: TextStyle(fontSize: 18, color: AppTheme.textGrey),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _showNewTicketDialog(),
            icon: const Icon(Icons.add),
            label: const Text('إنشاء تذكرة جديدة'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpTab(bool isWide) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 32 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // البحث
              TextField(
                decoration: InputDecoration(
                  hintText: 'ابحث في مركز المساعدة...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // قنوات التواصل
              _buildContactCard(),
              const SizedBox(height: 24),

              // الأسئلة الشائعة
              _buildFaqSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تواصل معنا',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildContactItem(Icons.phone, 'اتصل بنا', '920012345'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactItem(Icons.chat, 'واتساب', '0512345678'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildContactItem(
                  Icons.email,
                  'البريد',
                  'support@sadara.sa',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactItem(
                  Icons.access_time,
                  'ساعات العمل',
                  '24/7',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFaqSection() {
    final faqs = [
      {
        'question': 'كيف يمكنني ترقية باقتي؟',
        'answer':
            'يمكنك ترقية باقتك من خلال الذهاب إلى خدمات الإنترنت > ترقية الباقة، واختيار الباقة المناسبة.',
      },
      {
        'question': 'كيف يمكنني دفع الفاتورة؟',
        'answer':
            'يمكنك الدفع من خلال التطبيق عبر البطاقة الائتمانية أو Apple Pay أو STC Pay.',
      },
      {
        'question': 'ما هي مدة تفعيل الخدمة؟',
        'answer': 'يتم تفعيل الخدمة خلال 24-48 ساعة من تقديم الطلب.',
      },
      {
        'question': 'كيف أتواصل مع الدعم الفني؟',
        'answer':
            'يمكنك التواصل معنا عبر الهاتف 920012345 أو من خلال فتح تذكرة دعم.',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'الأسئلة الشائعة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const Divider(height: 1),
          ...faqs.map(
            (faq) => ExpansionTile(
              title: Text(
                faq['question']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    faq['answer']!,
                    style: const TextStyle(color: AppTheme.textGrey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNewTicketDialog() {
    String selectedCategory = 'technical';
    String selectedPriority = 'medium';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تذكرة جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: 'عنوان التذكرة',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('التصنيف'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'technical',
                      child: Text('مشكلة تقنية'),
                    ),
                    DropdownMenuItem(
                      value: 'billing',
                      child: Text('استفسار مالي'),
                    ),
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('استفسار عام'),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedCategory = value!);
                  },
                ),
                const SizedBox(height: 16),
                const Text('الأولوية'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedPriority,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'high', child: Text('عاجل')),
                    DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                    DropdownMenuItem(value: 'low', child: Text('منخفض')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedPriority = value!);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'وصف المشكلة',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم إنشاء التذكرة بنجاح'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTicketDetails(Map<String, dynamic> ticket) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        ticket['id'],
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text(
                    ticket['title'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStatusBadge(ticket['status']),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _buildMessageBubble(
                    'أنا',
                    'مرحباً، أواجه مشكلة في سرعة الإنترنت منذ يومين.',
                    '10:30 ص',
                    isMe: true,
                  ),
                  _buildMessageBubble(
                    'الدعم الفني',
                    'مرحباً بك، يسعدنا خدمتك. هل يمكنك تزويدنا بمزيد من التفاصيل؟',
                    '11:00 ص',
                    isMe: false,
                  ),
                  _buildMessageBubble(
                    'أنا',
                    'السرعة أقل من المتوقع، الباقة 100 ميجا ولكن السرعة الفعلية 20 ميجا فقط.',
                    '11:15 ص',
                    isMe: true,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryColor,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    String sender,
    String message,
    String time, {
    required bool isMe,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sender,
              style: TextStyle(
                color: isMe ? Colors.white70 : AppTheme.textGrey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(color: isMe ? Colors.white : AppTheme.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                color: isMe ? Colors.white60 : AppTheme.textGrey,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
