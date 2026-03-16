/// صفحة إضافة شركة جديدة
/// تتضمن بيانات الشركة والمدير الأول
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../multi_tenant.dart';

class AddCompanyPage extends StatefulWidget {
  const AddCompanyPage({super.key});

  @override
  State<AddCompanyPage> createState() => _AddCompanyPageState();
}

class _AddCompanyPageState extends State<AddCompanyPage> {
  final _formKey = GlobalKey<FormState>();
  final TenantService _tenantService = TenantService();

  // بيانات الشركة
  final _companyNameController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyAddressController = TextEditingController();

  // بيانات المدير
  final _adminUsernameController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _adminFullNameController = TextEditingController();
  final _adminPhoneController = TextEditingController();

  // بيانات الاشتراك
  DateTime _subscriptionEnd = DateTime.now().add(const Duration(days: 30));
  String _subscriptionPlan = 'monthly';
  int _maxUsers = 10;

  bool _isLoading = false;
  bool _obscurePassword = true;
  int _currentStep = 0;

  /// توليد كود تلقائي من اسم الشركة
  String _generateCompanyCode(String companyName) {
    // إزالة المسافات والأحرف الخاصة
    final cleanName = companyName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // تحويل الأحرف العربية إلى كود
    String code = '';
    final words = cleanName.split(' ');

    if (words.length >= 2) {
      // أخذ أول حرفين من أول كلمتين
      for (var i = 0; i < 2 && i < words.length; i++) {
        if (words[i].isNotEmpty) {
          code +=
              words[i].substring(0, words[i].length > 2 ? 2 : words[i].length);
        }
      }
    } else if (words.isNotEmpty) {
      // أخذ أول 4 أحرف من الكلمة الوحيدة
      code = words[0].substring(0, words[0].length > 4 ? 4 : words[0].length);
    }

    // إضافة رقم عشوائي لضمان الفرادة
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    code += timestamp.substring(timestamp.length - 4);

    return code.toUpperCase();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyPhoneController.dispose();
    _companyAddressController.dispose();
    _adminUsernameController.dispose();
    _adminPasswordController.dispose();
    _adminFullNameController.dispose();
    _adminPhoneController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _subscriptionEnd,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _subscriptionEnd = picked;
      });
    }
  }

  Future<void> _submit() async {
    // التحقق من جميع الحقول المطلوبة يدوياً
    String? error;

    // التحقق من بيانات الشركة
    if (_companyNameController.text.trim().isEmpty) {
      error = 'يرجى إدخال اسم الشركة';
      setState(() => _currentStep = 0);
    }
    // التحقق من بيانات المدير
    else if (_adminFullNameController.text.trim().isEmpty) {
      error = 'يرجى إدخال اسم المدير';
      setState(() => _currentStep = 2);
    } else if (_adminUsernameController.text.trim().isEmpty) {
      error = 'يرجى إدخال اسم المستخدم للمدير';
      setState(() => _currentStep = 2);
    } else if (_adminUsernameController.text.trim().length < 3) {
      error = 'اسم المستخدم يجب أن يكون 3 أحرف على الأقل';
      setState(() => _currentStep = 2);
    } else if (_adminPasswordController.text.isEmpty) {
      error = 'يرجى إدخال كلمة المرور';
      setState(() => _currentStep = 2);
    } else if (_adminPasswordController.text.length < 6) {
      error = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
      setState(() => _currentStep = 2);
    }

    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // توليد كود تلقائي من اسم الشركة
      final generatedCode =
          _generateCompanyCode(_companyNameController.text.trim());

      final result = await _tenantService.createTenantWithAdmin(
        tenantName: _companyNameController.text.trim(),
        tenantCode: generatedCode,
        tenantEmail: null,
        tenantPhone: _companyPhoneController.text.trim().isEmpty
            ? null
            : _companyPhoneController.text.trim(),
        tenantAddress: _companyAddressController.text.trim().isEmpty
            ? null
            : _companyAddressController.text.trim(),
        subscriptionEnd: _subscriptionEnd,
        subscriptionPlan: _subscriptionPlan,
        maxUsers: _maxUsers,
        adminUsername: _adminUsernameController.text.trim(),
        adminPassword: _adminPasswordController.text,
        adminFullName: _adminFullNameController.text.trim(),
        adminEmail: null,
        adminPhone: _adminPhoneController.text.trim().isEmpty
            ? null
            : _adminPhoneController.text.trim(),
      );

      setState(() {
        _isLoading = false;
      });

      if (result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة الشركة بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'حدث خطأ غير معروف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ'),
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
        title: const Text('إضافة شركة جديدة'),
        backgroundColor: const Color(0xFF1a237e),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() {
                _currentStep++;
              });
            } else {
              _submit();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() {
                _currentStep--;
              });
            }
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a237e),
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading && _currentStep == 2
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_currentStep == 2 ? 'إنشاء الشركة' : 'التالي'),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('السابق'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            // الخطوة 1: بيانات الشركة
            Step(
              title: const Text('بيانات الشركة'),
              subtitle: const Text('المعلومات الأساسية للشركة'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  TextFormField(
                    controller: _companyNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشركة *',
                      hintText: 'مثال: شركة الصدارة للاتصالات',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يرجى إدخال اسم الشركة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _companyPhoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      hintText: '+966xxxxxxxxx',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _companyAddressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'العنوان',
                      hintText: 'عنوان مقر الشركة',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // الخطوة 2: بيانات الاشتراك
            Step(
              title: const Text('بيانات الاشتراك'),
              subtitle: const Text('تحديد فترة ونوع الاشتراك'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // نوع الاشتراك
                  const Text('نوع الاشتراك'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'monthly',
                        label: Text('شهري'),
                        icon: Icon(Icons.calendar_today),
                      ),
                      ButtonSegment(
                        value: 'quarterly',
                        label: Text('ربع سنوي'),
                        icon: Icon(Icons.date_range),
                      ),
                      ButtonSegment(
                        value: 'yearly',
                        label: Text('سنوي'),
                        icon: Icon(Icons.event),
                      ),
                    ],
                    selected: {_subscriptionPlan},
                    onSelectionChanged: (value) {
                      setState(() {
                        _subscriptionPlan = value.first;
                        // تحديث تاريخ الانتهاء تلقائياً
                        switch (_subscriptionPlan) {
                          case 'monthly':
                            _subscriptionEnd = DateTime.now().add(
                              const Duration(days: 30),
                            );
                            break;
                          case 'quarterly':
                            _subscriptionEnd = DateTime.now().add(
                              const Duration(days: 90),
                            );
                            break;
                          case 'yearly':
                            _subscriptionEnd = DateTime.now().add(
                              const Duration(days: 365),
                            );
                            break;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // تاريخ انتهاء الاشتراك
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: const Text('تاريخ انتهاء الاشتراك'),
                    subtitle: Text(
                      DateFormat('yyyy/MM/dd', 'ar').format(_subscriptionEnd),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: ElevatedButton(
                      onPressed: _selectDate,
                      child: const Text('تغيير'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // عدد المستخدمين
                  const Text('الحد الأقصى للمستخدمين'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _maxUsers > 1
                            ? () {
                                setState(() {
                                  _maxUsers--;
                                });
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_maxUsers',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _maxUsers++;
                          });
                        },
                        icon: const Icon(Icons.add_circle),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // الخطوة 3: بيانات المدير
            Step(
              title: const Text('بيانات المدير'),
              subtitle: const Text('مدير الشركة الأول'),
              isActive: _currentStep >= 2,
              state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  TextFormField(
                    controller: _adminFullNameController,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل *',
                      hintText: 'اسم مدير الشركة',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يرجى إدخال اسم المدير';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _adminUsernameController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم *',
                      hintText: 'admin',
                      helperText: 'سيستخدم للدخول للنظام',
                      prefixIcon: Icon(Icons.account_circle),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يرجى إدخال اسم المستخدم';
                      }
                      if (value.trim().length < 3) {
                        return 'يجب أن يكون 3 أحرف على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _adminPasswordController,
                    obscureText: _obscurePassword,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور *',
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى إدخال كلمة المرور';
                      }
                      if (value.length < 6) {
                        return 'يجب أن تكون 6 أحرف على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _adminPhoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      hintText: '+966xxxxxxxxx',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
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
}
