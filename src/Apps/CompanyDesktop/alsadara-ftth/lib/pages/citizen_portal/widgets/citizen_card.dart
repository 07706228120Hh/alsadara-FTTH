/// بطاقة عرض المواطن
library;

import 'package:flutter/material.dart';
import '../models/citizen_portal_models.dart';

class CitizenCard extends StatelessWidget {
  final CitizenModel citizen;
  final VoidCallback? onTap;
  final VoidCallback? onBanToggle;
  final bool showActions;

  const CitizenCard({
    super.key,
    required this.citizen,
    this.onTap,
    this.onBanToggle,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: citizen.isBanned ? Colors.red.shade200 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // صورة المواطن
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.blue.shade100,
                    backgroundImage: citizen.profileImageUrl != null
                        ? NetworkImage(citizen.profileImageUrl!)
                        : null,
                    child: citizen.profileImageUrl == null
                        ? Text(
                            citizen.fullName.isNotEmpty
                                ? citizen.fullName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // معلومات المواطن
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                citizen.fullName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (citizen.isBanned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'محظور',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (!citizen.isActive && !citizen.isBanned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'غير نشط',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.phone,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              citizen.phoneNumber,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (citizen.isPhoneVerified)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: Colors.green.shade600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // أيقونة السهم
                  if (onTap != null)
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // الإحصائيات
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(
                    icon: Icons.list_alt,
                    label: 'الطلبات',
                    value: '${citizen.totalRequests}',
                    color: Colors.blue,
                  ),
                  _buildStat(
                    icon: Icons.payments,
                    label: 'المدفوعات',
                    value: '${citizen.totalPaid.toStringAsFixed(0)} د.ع',
                    color: Colors.green,
                  ),
                  _buildStat(
                    icon: Icons.stars,
                    label: 'النقاط',
                    value: '${citizen.loyaltyPoints}',
                    color: Colors.amber,
                  ),
                ],
              ),

              // العنوان إذا موجود
              if (citizen.fullAddress != null &&
                  citizen.fullAddress!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        citizen.fullAddress!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // أزرار الإجراءات
              if (showActions) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: onBanToggle,
                      icon: Icon(
                        citizen.isBanned ? Icons.lock_open : Icons.block,
                        size: 18,
                      ),
                      label: Text(
                        citizen.isBanned ? 'إلغاء الحظر' : 'حظر',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor:
                            citizen.isBanned ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
