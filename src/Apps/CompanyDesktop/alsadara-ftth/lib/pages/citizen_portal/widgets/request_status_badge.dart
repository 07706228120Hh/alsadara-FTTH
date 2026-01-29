/// شارة حالة الطلب
library;

import 'package:flutter/material.dart';
import '../models/citizen_portal_models.dart';

class RequestStatusBadge extends StatelessWidget {
  final ServiceRequestStatus status;
  final bool showIcon;
  final double fontSize;

  const RequestStatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withAlpha((0.15 * 255).round()),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status.color.withAlpha((0.5 * 255).round()),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              status.icon,
              size: fontSize + 2,
              color: status.color,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            status.nameAr,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة أولوية الطلب
class RequestPriorityBadge extends StatelessWidget {
  final RequestPriority priority;
  final double fontSize;

  const RequestPriorityBadge({
    super.key,
    required this.priority,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: priority.color.withAlpha((0.15 * 255).round()),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        priority.nameAr,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: priority.color,
        ),
      ),
    );
  }
}

/// قائمة خيارات حالة الطلب
class StatusDropdown extends StatelessWidget {
  final ServiceRequestStatus currentStatus;
  final ValueChanged<ServiceRequestStatus> onChanged;

  const StatusDropdown({
    super.key,
    required this.currentStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ServiceRequestStatus>(
      value: currentStatus,
      decoration: const InputDecoration(
        labelText: 'حالة الطلب',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: ServiceRequestStatus.values
          .map((status) => DropdownMenuItem(
                value: status,
                child: Row(
                  children: [
                    Icon(status.icon, size: 18, color: status.color),
                    const SizedBox(width: 8),
                    Text(status.nameAr),
                  ],
                ),
              ))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

/// مخطط تقدم الطلب
class RequestProgressIndicator extends StatelessWidget {
  final ServiceRequestStatus status;

  const RequestProgressIndicator({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      ServiceRequestStatus.pending,
      ServiceRequestStatus.reviewing,
      ServiceRequestStatus.approved,
      ServiceRequestStatus.assigned,
      ServiceRequestStatus.inProgress,
      ServiceRequestStatus.completed,
    ];

    final currentIndex = steps.indexOf(status);
    final isCancelled = status == ServiceRequestStatus.cancelled ||
        status == ServiceRequestStatus.rejected;

    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isCompleted = currentIndex >= index;
        final isCurrent = currentIndex == index;
        final isLast = index == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCancelled
                            ? Colors.grey.shade300
                            : isCompleted
                                ? step.color
                                : Colors.grey.shade200,
                        border: isCurrent && !isCancelled
                            ? Border.all(color: step.color, width: 2)
                            : null,
                        boxShadow: isCurrent && !isCancelled
                            ? [
                                BoxShadow(
                                  color:
                                      step.color.withAlpha((0.3 * 255).round()),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : step.icon,
                        size: 16,
                        color: isCancelled
                            ? Colors.grey
                            : isCompleted
                                ? Colors.white
                                : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.nameAr,
                      style: TextStyle(
                        fontSize: 9,
                        color: isCancelled
                            ? Colors.grey
                            : isCompleted
                                ? step.color
                                : Colors.grey,
                        fontWeight: isCurrent ? FontWeight.bold : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(
                  height: 2,
                  width: 20,
                  color: isCancelled
                      ? Colors.grey.shade300
                      : isCompleted
                          ? step.color
                          : Colors.grey.shade200,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
