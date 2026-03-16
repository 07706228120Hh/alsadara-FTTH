/// موديل الاستجابة المرقّمة (Paginated Response)
class PaginatedResponse<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const PaginatedResponse({
    required this.items,
    this.page = 1,
    this.pageSize = 50,
    this.totalPages = 1,
    this.total = 0,
  });

  bool get hasNext => page < totalPages;
  bool get hasPrev => page > 1;

  /// تحويل من JSON مع دالة تحويل العنصر
  factory PaginatedResponse.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    final rawItems =
        j['items'] ?? j['entries'] ?? j['transactions'] ?? j['data'] ?? [];
    final list = rawItems is List ? rawItems : [];

    return PaginatedResponse(
      items: list
          .map((e) => fromItem(e as Map<String, dynamic>))
          .toList(),
      page: j['page'] is int ? j['page'] : 1,
      pageSize: j['pageSize'] is int ? j['pageSize'] : 50,
      totalPages: j['totalPages'] is int ? j['totalPages'] : 1,
      total: j['total'] is int ? j['total'] : list.length,
    );
  }
}
