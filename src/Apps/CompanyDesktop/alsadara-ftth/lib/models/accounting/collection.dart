/// موديل التحصيل
class Collection {
  final String id;
  final String technicianId;
  final String? technicianName;
  final String? citizenId;
  final String? serviceRequestId;
  final double amount;
  final String description;
  final String? paymentMethod;
  final String? receiptNumber;
  final String? receivedBy;
  final bool isDelivered;
  final String? notes;
  final String companyId;
  final String? customerName;
  final String? planName;
  final DateTime? createdAt;

  const Collection({
    required this.id,
    required this.technicianId,
    this.technicianName,
    this.citizenId,
    this.serviceRequestId,
    required this.amount,
    required this.description,
    this.paymentMethod,
    this.receiptNumber,
    this.receivedBy,
    this.isDelivered = false,
    this.notes,
    required this.companyId,
    this.customerName,
    this.planName,
    this.createdAt,
  });

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['Id']?.toString() ?? '',
        technicianId: j['TechnicianId']?.toString() ?? '',
        technicianName: j['TechnicianName']?.toString(),
        citizenId: j['CitizenId']?.toString(),
        serviceRequestId: j['ServiceRequestId']?.toString(),
        amount: _toDouble(j['Amount']),
        description: j['Description']?.toString() ?? '',
        paymentMethod: j['PaymentMethod']?.toString(),
        receiptNumber: j['ReceiptNumber']?.toString(),
        receivedBy: j['ReceivedBy']?.toString(),
        isDelivered: j['IsDelivered'] == true,
        notes: j['Notes']?.toString(),
        companyId: j['CompanyId']?.toString() ?? '',
        customerName: j['CustomerName']?.toString(),
        planName: j['PlanName']?.toString(),
        createdAt: _parseDate(j['CreatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'TechnicianId': technicianId,
        'Amount': amount,
        'Description': description,
        if (receiptNumber != null) 'ReceiptNumber': receiptNumber,
        if (receivedBy != null) 'ReceivedBy': receivedBy,
        if (notes != null) 'Notes': notes,
        'CompanyId': companyId,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
