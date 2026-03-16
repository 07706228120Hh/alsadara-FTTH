import 'package:flutter/material.dart';
import '../models/company_model.dart';
import '../services/company_api_service.dart';

/// شاشة إدارة الشركات - لمدير النظام فقط
class CompaniesManagementPage extends StatefulWidget {
  const CompaniesManagementPage({super.key});

  @override
  State<CompaniesManagementPage> createState() =>
      _CompaniesManagementPageState();
}

class _CompaniesManagementPageState extends State<CompaniesManagementPage> {
  List<CompanyModel> companies = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loadedCompanies = await CompanyApiService.getAllCompanies();
      setState(() {
        companies = loadedCompanies;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ';
        isLoading = false;
      });
    }
  }

  Future<void> _linkCompanyToCitizenPortal(CompanyModel company) async {
    // تأكيد من المستخدم
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الربط'),
        content: Text(
          'هل أنت متأكد من ربط الشركة "${company.name}" بنظام المواطن؟\n\n'
          'سيتم إلغاء ربط أي شركة أخرى تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await CompanyApiService.linkToCitizenPortal(company.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('تم ربط الشركة "${company.name}" بنظام المواطن بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadCompanies(); // إعادة تحميل القائمة
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الربط'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unlinkCompanyFromCitizenPortal(CompanyModel company) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إلغاء الربط'),
        content: Text(
            'هل أنت متأكد من إلغاء ربط الشركة "${company.name}" من نظام المواطن?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إلغاء الربط'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await CompanyApiService.unlinkFromCitizenPortal(company.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء الربط بنجاح'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _loadCompanies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إلغاء الربط'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الشركات'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCompanies,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddCompanyDialog,
            tooltip: 'إضافة شركة',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadCompanies,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : companies.isEmpty
                  ? const Center(
                      child:
                          Text('لا توجد شركات', style: TextStyle(fontSize: 18)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: companies.length,
                      itemBuilder: (context, index) {
                        final company = companies[index];
                        return _buildCompanyCard(company);
                      },
                    ),
    );
  }

  Widget _buildCompanyCard(CompanyModel company) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: اسم الشركة + الحالة
            Row(
              children: [
                // Logo
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      company.isActive ? Colors.indigo : Colors.grey,
                  child: Text(
                    company.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                // Name & Code
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الكود: ${company.code}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: company.isActive ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    company.isActive ? 'نشط' : 'معلق',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(Icons.email, company.email ?? 'غير محدد'),
                      _buildInfoRow(Icons.phone, company.phone ?? 'غير محدد'),
                      _buildInfoRow(
                          Icons.location_on, company.address ?? 'غير محدد'),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(Icons.calendar_today,
                          'الاشتراك: ${company.daysRemaining} يوم متبقي'),
                      _buildInfoRow(
                          Icons.people, 'المستخدمين: ${company.maxUsers}'),
                      _buildInfoRow(Icons.card_membership,
                          'الخطة: ${company.subscriptionPlan}'),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Citizen Portal Status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: company.isLinkedToCitizenPortal
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: company.isLinkedToCitizenPortal
                      ? Colors.green
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    company.isLinkedToCitizenPortal
                        ? Icons.link
                        : Icons.link_off,
                    color: company.isLinkedToCitizenPortal
                        ? Colors.green
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      company.isLinkedToCitizenPortal
                          ? '✅ مرتبطة بنظام المواطن'
                          : 'غير مرتبطة بنظام المواطن',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: company.isLinkedToCitizenPortal
                            ? Colors.green.shade900
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  if (company.isActive)
                    ElevatedButton.icon(
                      onPressed: () {
                        if (company.isLinkedToCitizenPortal) {
                          _unlinkCompanyFromCitizenPortal(company);
                        } else {
                          _linkCompanyToCitizenPortal(company);
                        }
                      },
                      icon: Icon(
                        company.isLinkedToCitizenPortal
                            ? Icons.link_off
                            : Icons.link,
                      ),
                      label: Text(
                        company.isLinkedToCitizenPortal
                            ? 'إلغاء الربط'
                            : 'ربط بنظام المواطن',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: company.isLinkedToCitizenPortal
                            ? Colors.orange
                            : Colors.green,
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

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[800]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCompanyDialog() {
    // TODO: إضافة نافذة لإنشاء شركة جديدة
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('سيتم إضافة نافذة إنشاء الشركة قريباً')),
    );
  }
}
