import '../../services/sadara_api_service.dart';

/// خدمة API المخزون — Inventory Management
class InventoryApiService {
  static InventoryApiService? _instance;
  static InventoryApiService get instance =>
      _instance ??= InventoryApiService._internal();
  InventoryApiService._internal();

  final SadaraApiService _api = SadaraApiService.instance;

  // ============================================================
  //  المستودعات (Warehouses)
  // ============================================================

  /// جلب المستودعات
  Future<Map<String, dynamic>> getWarehouses({
    required String companyId,
  }) async {
    return await _api.get('/inventory/warehouses?companyId=$companyId');
  }

  /// إنشاء مستودع
  Future<Map<String, dynamic>> createWarehouse({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/warehouses', body: data);
  }

  /// تعديل مستودع
  Future<Map<String, dynamic>> updateWarehouse(
    String id, {
    required Map<String, dynamic> data,
  }) async {
    return await _api.put('/inventory/warehouses/$id', body: data);
  }

  /// حذف مستودع
  Future<Map<String, dynamic>> deleteWarehouse(String id) async {
    return await _api.delete('/inventory/warehouses/$id');
  }

  // ============================================================
  //  التصنيفات (Categories)
  // ============================================================

  /// جلب التصنيفات
  Future<Map<String, dynamic>> getCategories({
    required String companyId,
  }) async {
    return await _api.get('/inventory/categories?companyId=$companyId');
  }

  /// إنشاء تصنيف
  Future<Map<String, dynamic>> createCategory({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/categories', body: data);
  }

  /// تعديل تصنيف
  Future<Map<String, dynamic>> updateCategory(
    int id, {
    required Map<String, dynamic> data,
  }) async {
    return await _api.put('/inventory/categories/$id', body: data);
  }

  /// حذف تصنيف
  Future<Map<String, dynamic>> deleteCategory(int id) async {
    return await _api.delete('/inventory/categories/$id');
  }

  // ============================================================
  //  المواد (Items / Materials)
  // ============================================================

  /// جلب المواد مع فلاتر
  Future<Map<String, dynamic>> getItems({
    required String companyId,
    String? categoryId,
    String? search,
    bool? lowStockOnly,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (categoryId != null) params.add('categoryId=$categoryId');
    if (search != null) params.add('search=$search');
    if (lowStockOnly != null) params.add('lowStockOnly=$lowStockOnly');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    return await _api.get('/inventory/items?${params.join('&')}');
  }

  /// جلب مادة واحدة
  Future<Map<String, dynamic>> getItem(String id) async {
    return await _api.get('/inventory/items/$id');
  }

  /// جلب المواد منخفضة المخزون
  Future<Map<String, dynamic>> getLowStockItems({
    required String companyId,
  }) async {
    return await _api.get('/inventory/items/low-stock?companyId=$companyId');
  }

  /// إنشاء مادة
  Future<Map<String, dynamic>> createItem({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/items', body: data);
  }

  /// تعديل مادة
  Future<Map<String, dynamic>> updateItem(
    String id, {
    required Map<String, dynamic> data,
  }) async {
    return await _api.put('/inventory/items/$id', body: data);
  }

  /// حذف مادة
  Future<Map<String, dynamic>> deleteItem(String id) async {
    return await _api.delete('/inventory/items/$id');
  }

  // ============================================================
  //  الموردون (Suppliers)
  // ============================================================

  /// جلب الموردين
  Future<Map<String, dynamic>> getSuppliers({
    required String companyId,
    String? search,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (search != null) params.add('search=$search');
    return await _api.get('/inventory/suppliers?${params.join('&')}');
  }

  /// جلب مورد واحد
  Future<Map<String, dynamic>> getSupplier(String id) async {
    return await _api.get('/inventory/suppliers/$id');
  }

  /// إنشاء مورد
  Future<Map<String, dynamic>> createSupplier({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/suppliers', body: data);
  }

  /// تعديل مورد
  Future<Map<String, dynamic>> updateSupplier(
    String id, {
    required Map<String, dynamic> data,
  }) async {
    return await _api.put('/inventory/suppliers/$id', body: data);
  }

  /// حذف مورد
  Future<Map<String, dynamic>> deleteSupplier(String id) async {
    return await _api.delete('/inventory/suppliers/$id');
  }

  // ============================================================
  //  أوامر الشراء (Purchase Orders)
  // ============================================================

  /// جلب أوامر الشراء
  Future<Map<String, dynamic>> getPurchaseOrders({
    required String companyId,
    String? status,
    String? supplierId,
    String? from,
    String? to,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (status != null) params.add('status=$status');
    if (supplierId != null) params.add('supplierId=$supplierId');
    if (from != null) params.add('from=$from');
    if (to != null) params.add('to=$to');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    return await _api.get('/inventory/purchases?${params.join('&')}');
  }

  /// جلب أمر شراء واحد
  Future<Map<String, dynamic>> getPurchaseOrder(String id) async {
    return await _api.get('/inventory/purchases/$id');
  }

  /// إنشاء أمر شراء
  Future<Map<String, dynamic>> createPurchaseOrder({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/purchases', body: data);
  }

  /// تعديل أمر شراء
  Future<Map<String, dynamic>> updatePurchaseOrder(
    String id, {
    required Map<String, dynamic> data,
  }) async {
    return await _api.put('/inventory/purchases/$id', body: data);
  }

  /// اعتماد أمر شراء
  Future<Map<String, dynamic>> approvePurchaseOrder(String id) async {
    return await _api.post('/inventory/purchases/$id/approve', body: {});
  }

  /// استلام أمر شراء
  Future<Map<String, dynamic>> receivePurchaseOrder(
    String id, {
    required List<Map<String, dynamic>> items,
  }) async {
    return await _api.post('/inventory/purchases/$id/receive', body: {
      'items': items,
    });
  }

  /// إلغاء أمر شراء
  Future<Map<String, dynamic>> cancelPurchaseOrder(String id) async {
    return await _api.post('/inventory/purchases/$id/cancel', body: {});
  }

  // ============================================================
  //  أوامر البيع (Sales Orders)
  // ============================================================

  /// جلب أوامر البيع
  Future<Map<String, dynamic>> getSalesOrders({
    required String companyId,
    String? status,
    String? from,
    String? to,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (status != null) params.add('status=$status');
    if (from != null) params.add('from=$from');
    if (to != null) params.add('to=$to');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    return await _api.get('/inventory/sales?${params.join('&')}');
  }

  /// جلب أمر بيع واحد
  Future<Map<String, dynamic>> getSalesOrder(String id) async {
    return await _api.get('/inventory/sales/$id');
  }

  /// إنشاء أمر بيع
  Future<Map<String, dynamic>> createSalesOrder({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/sales', body: data);
  }

  /// تأكيد أمر بيع
  Future<Map<String, dynamic>> confirmSalesOrder(String id) async {
    return await _api.post('/inventory/sales/$id/confirm', body: {});
  }

  /// إلغاء أمر بيع
  Future<Map<String, dynamic>> cancelSalesOrder(String id) async {
    return await _api.post('/inventory/sales/$id/cancel', body: {});
  }

  // ============================================================
  //  صرف للفنيين (Technician Dispensing)
  // ============================================================

  /// جلب عمليات الصرف
  Future<Map<String, dynamic>> getDispensings({
    required String companyId,
    String? technicianId,
    String? status,
    String? from,
    String? to,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (technicianId != null) params.add('technicianId=$technicianId');
    if (status != null) params.add('status=$status');
    if (from != null) params.add('from=$from');
    if (to != null) params.add('to=$to');
    return await _api.get('/inventory/dispensing?${params.join('&')}');
  }

  /// جلب عملية صرف واحدة
  Future<Map<String, dynamic>> getDispensing(String id) async {
    return await _api.get('/inventory/dispensing/$id');
  }

  /// جلب المواد المصروفة لمهمة محددة (حسب ServiceRequestId)
  Future<Map<String, dynamic>> getDispensingsByServiceRequest(
    String serviceRequestId, {
    required String companyId,
  }) async {
    return await _api.get(
      '/inventory/dispensing?serviceRequestId=$serviceRequestId&companyId=$companyId',
    );
  }

  /// إنشاء عملية صرف
  Future<Map<String, dynamic>> createDispensing({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/dispensing', body: data);
  }

  /// اعتماد عملية صرف
  Future<Map<String, dynamic>> approveDispensing(String id) async {
    return await _api.post('/inventory/dispensing/$id/approve', body: {});
  }

  /// إرجاع مواد من فني
  Future<Map<String, dynamic>> returnDispensing(
    String id, {
    required List<Map<String, dynamic>> items,
  }) async {
    return await _api.post('/inventory/dispensing/$id/return', body: {
      'items': items,
    });
  }

  /// جلب مواد بحوزة فني
  Future<Map<String, dynamic>> getTechnicianHoldings(
    String technicianId,
  ) async {
    return await _api
        .get('/inventory/dispensing/technician/$technicianId');
  }

  // ============================================================
  //  المخزون والحركات (Stock & Movements)
  // ============================================================

  /// جلب مستويات المخزون
  Future<Map<String, dynamic>> getStockLevels({
    required String companyId,
    String? warehouseId,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (warehouseId != null) params.add('warehouseId=$warehouseId');
    return await _api.get('/inventory/stock?${params.join('&')}');
  }

  /// جلب مخزون مستودع معين
  Future<Map<String, dynamic>> getWarehouseStock(
    String warehouseId, {
    required String companyId,
  }) async {
    return await _api
        .get('/inventory/stock/$warehouseId?companyId=$companyId');
  }

  /// تعديل مخزون (جرد)
  Future<Map<String, dynamic>> adjustStock({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/stock/adjust', body: data);
  }

  /// نقل مخزون بين مستودعات
  Future<Map<String, dynamic>> transferStock({
    required Map<String, dynamic> data,
  }) async {
    return await _api.post('/inventory/stock/transfer', body: data);
  }

  /// جلب حركات المخزون
  Future<Map<String, dynamic>> getMovements({
    required String companyId,
    String? inventoryItemId,
    String? warehouseId,
    String? movementType,
    String? from,
    String? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String>[];
    params.add('companyId=$companyId');
    if (inventoryItemId != null) {
      params.add('inventoryItemId=$inventoryItemId');
    }
    if (warehouseId != null) params.add('warehouseId=$warehouseId');
    if (movementType != null) params.add('movementType=$movementType');
    if (from != null) params.add('from=$from');
    if (to != null) params.add('to=$to');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    return await _api.get('/inventory/movements?${params.join('&')}');
  }

  // ============================================================
  //  التقارير (Reports)
  // ============================================================

  /// ملخص لوحة المعلومات
  Future<Map<String, dynamic>> getDashboardSummary({
    required String companyId,
  }) async {
    return await _api
        .get('/inventory/reports/summary?companyId=$companyId');
  }

  /// تقرير تقييم المخزون
  Future<Map<String, dynamic>> getValuationReport({
    required String companyId,
  }) async {
    return await _api
        .get('/inventory/reports/valuation?companyId=$companyId');
  }

  /// تقرير مواد بحوزة الفنيين
  Future<Map<String, dynamic>> getTechnicianHoldingsReport({
    required String companyId,
  }) async {
    return await _api.get(
        '/inventory/reports/technician-holdings?companyId=$companyId');
  }
}
