/// صفحة قائمة المواطنين
library;

import 'package:flutter/material.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';
import 'widgets/citizen_card.dart';
import 'citizen_details_page.dart';

class CitizensListPage extends StatefulWidget {
  const CitizensListPage({super.key});

  @override
  State<CitizensListPage> createState() => _CitizensListPageState();
}

class _CitizensListPageState extends State<CitizensListPage> {
  final CitizenPortalService _service = CitizenPortalService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CitizenModel> _citizens = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;
  bool? _filterActive;

  @override
  void initState() {
    super.initState();
    _loadCitizens();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadCitizens() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 1;
      _hasMore = true;
    });

    final response = await _service.getCitizens(
      page: 1,
      search: _searchController.text.isNotEmpty ? _searchController.text : null,
      isActive: _filterActive,
    );

    if (response.isSuccess && response.data != null) {
      setState(() {
        _citizens = response.data!;
        _isLoading = false;
        _hasMore = response.data!.length >= 20;
      });
    } else {
      setState(() {
        _error = response.message ?? 'فشل في تحميل المواطنين';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final response = await _service.getCitizens(
      page: _currentPage + 1,
      search: _searchController.text.isNotEmpty ? _searchController.text : null,
      isActive: _filterActive,
    );

    if (response.isSuccess && response.data != null) {
      setState(() {
        _citizens.addAll(response.data!);
        _currentPage++;
        _isLoadingMore = false;
        _hasMore = response.data!.length >= 20;
      });
    } else {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _toggleBan(CitizenModel citizen) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(citizen.isBanned ? 'إلغاء الحظر' : 'حظر المواطن'),
          content: Text(
            citizen.isBanned
                ? 'هل تريد إلغاء حظر "${citizen.fullName}"؟'
                : 'هل تريد حظر "${citizen.fullName}"؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: citizen.isBanned ? Colors.green : Colors.red,
              ),
              child: Text(citizen.isBanned ? 'إلغاء الحظر' : 'حظر'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final response = await _service.toggleCitizenBan(citizen.id);
      if (response.isSuccess) {
        _loadCitizens();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(citizen.isBanned ? 'تم إلغاء الحظر' : 'تم الحظر بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // شريط البحث والفلترة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // البحث
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'البحث بالاسم أو رقم الهاتف...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _loadCitizens();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _loadCitizens(),
                  ),
                ),
                const SizedBox(width: 16),

                // فلتر الحالة
                DropdownButton<bool?>(
                  value: _filterActive,
                  hint: const Text('جميع الحالات'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('جميع الحالات')),
                    DropdownMenuItem(value: true, child: Text('نشط فقط')),
                    DropdownMenuItem(value: false, child: Text('غير نشط')),
                  ],
                  onChanged: (value) {
                    setState(() => _filterActive = value);
                    _loadCitizens();
                  },
                ),
                const SizedBox(width: 16),

                // زر التحديث
                IconButton(
                  onPressed: _loadCitizens,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),

                // زر إضافة
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: فتح نافذة إضافة مواطن
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة مواطن'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // القائمة
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadCitizens,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_citizens.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'لا يوجد مواطنين',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'ابدأ بإضافة مواطن جديد',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCitizens,
      color: Colors.teal,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.4,
        ),
        itemCount: _citizens.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _citizens.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.teal),
              ),
            );
          }

          final citizen = _citizens[index];
          return CitizenCard(
            citizen: citizen,
            onTap: () => _openCitizenDetails(citizen),
            onBanToggle: () => _toggleBan(citizen),
          );
        },
      ),
    );
  }

  void _openCitizenDetails(CitizenModel citizen) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CitizenDetailsPage(citizen: citizen),
      ),
    );
  }
}
