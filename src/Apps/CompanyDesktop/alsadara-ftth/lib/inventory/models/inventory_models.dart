// inventory_models.dart
// Simple Dart data classes for the inventory system.
// No code generation, no freezed — just plain constructors, fromJson, toJson.

/// Helper: الـ API يرجع PascalCase (مثل Id, Name) لكن أحياناً camelCase
/// هذه الدالة تبحث بكلا الحالتين
dynamic _v(Map<String, dynamic> j, String key) {
  if (j.containsKey(key)) return j[key];
  final pascal = key[0].toUpperCase() + key.substring(1);
  if (j.containsKey(pascal)) return j[pascal];
  // حالة خاصة: managerUserName → ManagerName
  if (key == 'managerUserName' && j.containsKey('ManagerName')) return j['ManagerName'];
  if (key == 'managerUserName' && j.containsKey('managerName')) return j['managerName'];
  return null;
}

// ---------------------------------------------------------------------------
// Warehouse
// ---------------------------------------------------------------------------
class Warehouse {
  final String id;
  final String name;
  final String? code;
  final String? address;
  final String? description;
  final bool isActive;
  final bool isDefault;
  final String? managerUserId;
  final String? managerUserName;
  final String companyId;

  Warehouse({
    required this.id,
    required this.name,
    this.code,
    this.address,
    this.description,
    required this.isActive,
    required this.isDefault,
    this.managerUserId,
    this.managerUserName,
    required this.companyId,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: _v(json, 'id') as String? ?? '',
      name: _v(json, 'name') as String? ?? '',
      code: _v(json, 'code') as String?,
      address: _v(json, 'address') as String?,
      description: _v(json, 'description') as String?,
      isActive: _v(json, 'isActive') as bool? ?? true,
      isDefault: _v(json, 'isDefault') as bool? ?? false,
      managerUserId: _v(json, 'managerUserId') as String?,
      managerUserName: _v(json, 'managerUserName') as String?,
      companyId: _v(json, 'companyId') as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'address': address,
      'description': description,
      'isActive': isActive,
      'isDefault': isDefault,
      'managerUserId': managerUserId,
      'managerUserName': managerUserName,
      'companyId': companyId,
    };
  }
}

// ---------------------------------------------------------------------------
// InventoryCategory
// ---------------------------------------------------------------------------
class InventoryCategory {
  final int id;
  final String name;
  final String? nameEn;
  final int? parentCategoryId;
  final int sortOrder;
  final bool isActive;
  final String companyId;
  final int? itemCount;

  InventoryCategory({
    required this.id,
    required this.name,
    this.nameEn,
    this.parentCategoryId,
    required this.sortOrder,
    required this.isActive,
    required this.companyId,
    this.itemCount,
  });

  factory InventoryCategory.fromJson(Map<String, dynamic> json) {
    return InventoryCategory(
      id: _v(json, 'id') as int? ?? 0,
      name: _v(json, 'name') as String? ?? '',
      nameEn: _v(json, 'nameEn') as String?,
      parentCategoryId: _v(json, 'parentCategoryId') as int?,
      sortOrder: _v(json, 'sortOrder') as int? ?? 0,
      isActive: _v(json, 'isActive') as bool? ?? true,
      companyId: _v(json, 'companyId') as String? ?? '',
      itemCount: _v(json, 'itemCount') as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'nameEn': nameEn,
      'parentCategoryId': parentCategoryId,
      'sortOrder': sortOrder,
      'isActive': isActive,
      'companyId': companyId,
      'itemCount': itemCount,
    };
  }
}

// ---------------------------------------------------------------------------
// WarehouseStockInfo
// ---------------------------------------------------------------------------
class WarehouseStockInfo {
  final String warehouseId;
  final String warehouseName;
  final int currentQuantity;
  final int reservedQuantity;
  final double averageCost;

  WarehouseStockInfo({
    required this.warehouseId,
    required this.warehouseName,
    required this.currentQuantity,
    required this.reservedQuantity,
    required this.averageCost,
  });

  factory WarehouseStockInfo.fromJson(Map<String, dynamic> json) {
    return WarehouseStockInfo(
      warehouseId: _v(json, 'warehouseId') as String? ?? '',
      warehouseName: _v(json, 'warehouseName') as String? ?? '',
      currentQuantity: _v(json, 'currentQuantity') as int? ?? 0,
      reservedQuantity: _v(json, 'reservedQuantity') as int? ?? 0,
      averageCost: (_v(json, 'averageCost') as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'currentQuantity': currentQuantity,
      'reservedQuantity': reservedQuantity,
      'averageCost': averageCost,
    };
  }
}

// ---------------------------------------------------------------------------
// InventoryItem
// ---------------------------------------------------------------------------
class InventoryItem {
  final String id;
  final String name;
  final String? nameEn;
  final String sku;
  final String? barcode;
  final String? description;
  final int? categoryId;
  final String? categoryName;
  final String unit;
  final double costPrice;
  final double? sellingPrice;
  final double? wholesalePrice;
  final int minStockLevel;
  final int maxStockLevel;
  final String? imageUrl;
  final bool isActive;
  final String companyId;
  final int? totalStock;
  final List<WarehouseStockInfo>? stocks;

  InventoryItem({
    required this.id,
    required this.name,
    this.nameEn,
    required this.sku,
    this.barcode,
    this.description,
    this.categoryId,
    this.categoryName,
    required this.unit,
    required this.costPrice,
    this.sellingPrice,
    this.wholesalePrice,
    required this.minStockLevel,
    required this.maxStockLevel,
    this.imageUrl,
    required this.isActive,
    required this.companyId,
    this.totalStock,
    this.stocks,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: _v(json, 'id') as String? ?? '',
      name: _v(json, 'name') as String? ?? '',
      nameEn: _v(json, 'nameEn') as String?,
      sku: _v(json, 'sku') as String? ?? '',
      barcode: _v(json, 'barcode') as String?,
      description: _v(json, 'description') as String?,
      categoryId: _v(json, 'categoryId') as int?,
      categoryName: _v(json, 'categoryName') as String?,
      unit: _v(json, 'unit') as String? ?? 'Piece',
      costPrice: (_v(json, 'costPrice') as num?)?.toDouble() ?? 0.0,
      sellingPrice: (_v(json, 'sellingPrice') as num?)?.toDouble(),
      wholesalePrice: (_v(json, 'wholesalePrice') as num?)?.toDouble(),
      minStockLevel: _v(json, 'minStockLevel') as int? ?? 0,
      maxStockLevel: _v(json, 'maxStockLevel') as int? ?? 0,
      imageUrl: _v(json, 'imageUrl') as String?,
      isActive: _v(json, 'isActive') as bool? ?? true,
      companyId: _v(json, 'companyId') as String? ?? '',
      totalStock: _v(json, 'totalStock') as int?,
      stocks: _v(json, 'stocks') != null
          ? (_v(json, 'stocks') as List<dynamic>)
              .map((e) =>
                  WarehouseStockInfo.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'nameEn': nameEn,
      'sku': sku,
      'barcode': barcode,
      'description': description,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'unit': unit,
      'costPrice': costPrice,
      'sellingPrice': sellingPrice,
      'wholesalePrice': wholesalePrice,
      'minStockLevel': minStockLevel,
      'maxStockLevel': maxStockLevel,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'companyId': companyId,
      'totalStock': totalStock,
      'stocks': stocks?.map((e) => e.toJson()).toList(),
    };
  }
}

// ---------------------------------------------------------------------------
// Supplier
// ---------------------------------------------------------------------------
class Supplier {
  final String id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxNumber;
  final String? notes;
  final bool isActive;
  final String companyId;
  final int? purchaseOrdersCount;
  final double? totalPurchases;

  Supplier({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.taxNumber,
    this.notes,
    required this.isActive,
    required this.companyId,
    this.purchaseOrdersCount,
    this.totalPurchases,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: _v(json, 'id') as String? ?? '',
      name: _v(json, 'name') as String? ?? '',
      contactPerson: _v(json, 'contactPerson') as String?,
      phone: _v(json, 'phone') as String?,
      email: _v(json, 'email') as String?,
      address: _v(json, 'address') as String?,
      taxNumber: _v(json, 'taxNumber') as String?,
      notes: _v(json, 'notes') as String?,
      isActive: _v(json, 'isActive') as bool? ?? true,
      companyId: _v(json, 'companyId') as String? ?? '',
      purchaseOrdersCount: _v(json, 'purchaseOrdersCount') as int?,
      totalPurchases: (_v(json, 'totalPurchases') as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contactPerson': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'taxNumber': taxNumber,
      'notes': notes,
      'isActive': isActive,
      'companyId': companyId,
      'purchaseOrdersCount': purchaseOrdersCount,
      'totalPurchases': totalPurchases,
    };
  }
}

// ---------------------------------------------------------------------------
// PurchaseOrderItem
// ---------------------------------------------------------------------------
class PurchaseOrderItem {
  final int id;
  final String inventoryItemId;
  final String? itemName;
  final String? itemSku;
  final int quantity;
  final int receivedQuantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;

  PurchaseOrderItem({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.quantity,
    required this.receivedQuantity,
    required this.unitPrice,
    required this.totalPrice,
    this.notes,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      id: _v(json, 'id') as int? ?? 0,
      inventoryItemId: _v(json, 'inventoryItemId') as String? ?? '',
      itemName: _v(json, 'itemName') as String?,
      itemSku: _v(json, 'itemSku') as String?,
      quantity: _v(json, 'quantity') as int? ?? 0,
      receivedQuantity: _v(json, 'receivedQuantity') as int? ?? 0,
      unitPrice: (_v(json, 'unitPrice') as num?)?.toDouble() ?? 0.0,
      totalPrice: (_v(json, 'totalPrice') as num?)?.toDouble() ?? 0.0,
      notes: _v(json, 'notes') as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryItemId': inventoryItemId,
      'itemName': itemName,
      'itemSku': itemSku,
      'quantity': quantity,
      'receivedQuantity': receivedQuantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
      'notes': notes,
    };
  }
}

// ---------------------------------------------------------------------------
// PurchaseOrder
// ---------------------------------------------------------------------------
class PurchaseOrder {
  final String id;
  final String orderNumber;
  final String supplierId;
  final String? supplierName;
  final String warehouseId;
  final String? warehouseName;
  final DateTime orderDate;
  final DateTime? expectedDeliveryDate;
  final DateTime? receivedDate;
  final String status;
  final double totalAmount;
  final double? discountAmount;
  final double? taxAmount;
  final double netAmount;
  final String? notes;
  final String? attachmentUrl;
  final String createdById;
  final String? createdByName;
  final String? approvedById;
  final String companyId;
  final int? itemsCount;
  final List<PurchaseOrderItem>? items;

  PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    this.supplierName,
    required this.warehouseId,
    this.warehouseName,
    required this.orderDate,
    this.expectedDeliveryDate,
    this.receivedDate,
    required this.status,
    required this.totalAmount,
    this.discountAmount,
    this.taxAmount,
    required this.netAmount,
    this.notes,
    this.attachmentUrl,
    required this.createdById,
    this.createdByName,
    this.approvedById,
    required this.companyId,
    this.itemsCount,
    this.items,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: _v(json, 'id') as String? ?? '',
      orderNumber: _v(json, 'orderNumber') as String? ?? '',
      supplierId: _v(json, 'supplierId') as String? ?? '',
      supplierName: _v(json, 'supplierName') as String?,
      warehouseId: _v(json, 'warehouseId') as String? ?? '',
      warehouseName: _v(json, 'warehouseName') as String?,
      orderDate:
          DateTime.tryParse(_v(json, 'orderDate') as String? ?? '') ?? DateTime.now(),
      expectedDeliveryDate: _v(json, 'expectedDeliveryDate') != null
          ? DateTime.tryParse(_v(json, 'expectedDeliveryDate') as String)
          : null,
      receivedDate: _v(json, 'receivedDate') != null
          ? DateTime.tryParse(_v(json, 'receivedDate') as String)
          : null,
      status: _v(json, 'status') as String? ?? 'Draft',
      totalAmount: (_v(json, 'totalAmount') as num?)?.toDouble() ?? 0.0,
      discountAmount: (_v(json, 'discountAmount') as num?)?.toDouble(),
      taxAmount: (_v(json, 'taxAmount') as num?)?.toDouble(),
      netAmount: (_v(json, 'netAmount') as num?)?.toDouble() ?? 0.0,
      notes: _v(json, 'notes') as String?,
      attachmentUrl: _v(json, 'attachmentUrl') as String?,
      createdById: _v(json, 'createdById') as String? ?? '',
      createdByName: _v(json, 'createdByName') as String?,
      approvedById: _v(json, 'approvedById') as String?,
      companyId: _v(json, 'companyId') as String? ?? '',
      itemsCount: _v(json, 'itemsCount') as int?,
      items: _v(json, 'items') != null
          ? (_v(json, 'items') as List<dynamic>)
              .map((e) =>
                  PurchaseOrderItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderNumber': orderNumber,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'orderDate': orderDate.toIso8601String(),
      'expectedDeliveryDate': expectedDeliveryDate?.toIso8601String(),
      'receivedDate': receivedDate?.toIso8601String(),
      'status': status,
      'totalAmount': totalAmount,
      'discountAmount': discountAmount,
      'taxAmount': taxAmount,
      'netAmount': netAmount,
      'notes': notes,
      'attachmentUrl': attachmentUrl,
      'createdById': createdById,
      'createdByName': createdByName,
      'approvedById': approvedById,
      'companyId': companyId,
      'itemsCount': itemsCount,
      'items': items?.map((e) => e.toJson()).toList(),
    };
  }
}

// ---------------------------------------------------------------------------
// SalesOrderItem
// ---------------------------------------------------------------------------
class SalesOrderItem {
  final int id;
  final String inventoryItemId;
  final String? itemName;
  final String? itemSku;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  SalesOrderItem({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) {
    return SalesOrderItem(
      id: _v(json, 'id') as int? ?? 0,
      inventoryItemId: _v(json, 'inventoryItemId') as String? ?? '',
      itemName: _v(json, 'itemName') as String?,
      itemSku: _v(json, 'itemSku') as String?,
      quantity: _v(json, 'quantity') as int? ?? 0,
      unitPrice: (_v(json, 'unitPrice') as num?)?.toDouble() ?? 0.0,
      totalPrice: (_v(json, 'totalPrice') as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryItemId': inventoryItemId,
      'itemName': itemName,
      'itemSku': itemSku,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
    };
  }
}

// ---------------------------------------------------------------------------
// SalesOrder
// ---------------------------------------------------------------------------
class SalesOrder {
  final String id;
  final String orderNumber;
  final String? customerName;
  final String? customerPhone;
  final String warehouseId;
  final String? warehouseName;
  final DateTime orderDate;
  final String status;
  final double totalAmount;
  final double? discountAmount;
  final double? taxAmount;
  final double netAmount;
  final String? paymentMethod;
  final String? notes;
  final String createdById;
  final String? createdByName;
  final String companyId;
  final List<SalesOrderItem>? items;

  SalesOrder({
    required this.id,
    required this.orderNumber,
    this.customerName,
    this.customerPhone,
    required this.warehouseId,
    this.warehouseName,
    required this.orderDate,
    required this.status,
    required this.totalAmount,
    this.discountAmount,
    this.taxAmount,
    required this.netAmount,
    this.paymentMethod,
    this.notes,
    required this.createdById,
    this.createdByName,
    required this.companyId,
    this.items,
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    return SalesOrder(
      id: _v(json, 'id') as String? ?? '',
      orderNumber: _v(json, 'orderNumber') as String? ?? '',
      customerName: _v(json, 'customerName') as String?,
      customerPhone: _v(json, 'customerPhone') as String?,
      warehouseId: _v(json, 'warehouseId') as String? ?? '',
      warehouseName: _v(json, 'warehouseName') as String?,
      orderDate:
          DateTime.tryParse(_v(json, 'orderDate') as String? ?? '') ?? DateTime.now(),
      status: _v(json, 'status') as String? ?? 'Draft',
      totalAmount: (_v(json, 'totalAmount') as num?)?.toDouble() ?? 0.0,
      discountAmount: (_v(json, 'discountAmount') as num?)?.toDouble(),
      taxAmount: (_v(json, 'taxAmount') as num?)?.toDouble(),
      netAmount: (_v(json, 'netAmount') as num?)?.toDouble() ?? 0.0,
      paymentMethod: _v(json, 'paymentMethod') as String?,
      notes: _v(json, 'notes') as String?,
      createdById: _v(json, 'createdById') as String? ?? '',
      createdByName: _v(json, 'createdByName') as String?,
      companyId: _v(json, 'companyId') as String? ?? '',
      items: _v(json, 'items') != null
          ? (_v(json, 'items') as List<dynamic>)
              .map((e) =>
                  SalesOrderItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderNumber': orderNumber,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'orderDate': orderDate.toIso8601String(),
      'status': status,
      'totalAmount': totalAmount,
      'discountAmount': discountAmount,
      'taxAmount': taxAmount,
      'netAmount': netAmount,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'createdById': createdById,
      'createdByName': createdByName,
      'companyId': companyId,
      'items': items?.map((e) => e.toJson()).toList(),
    };
  }
}

// ---------------------------------------------------------------------------
// TechnicianDispensingItemModel
// ---------------------------------------------------------------------------
class TechnicianDispensingItemModel {
  final int id;
  final String inventoryItemId;
  final String? itemName;
  final String? itemSku;
  final int quantity;
  final int returnedQuantity;
  final String? notes;

  TechnicianDispensingItemModel({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.quantity,
    required this.returnedQuantity,
    this.notes,
  });

  factory TechnicianDispensingItemModel.fromJson(Map<String, dynamic> json) {
    return TechnicianDispensingItemModel(
      id: _v(json, 'id') as int? ?? 0,
      inventoryItemId: _v(json, 'inventoryItemId') as String? ?? '',
      itemName: _v(json, 'itemName') as String?,
      itemSku: _v(json, 'itemSku') as String?,
      quantity: _v(json, 'quantity') as int? ?? 0,
      returnedQuantity: _v(json, 'returnedQuantity') as int? ?? 0,
      notes: _v(json, 'notes') as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryItemId': inventoryItemId,
      'itemName': itemName,
      'itemSku': itemSku,
      'quantity': quantity,
      'returnedQuantity': returnedQuantity,
      'notes': notes,
    };
  }
}

// ---------------------------------------------------------------------------
// TechnicianDispensingModel
// ---------------------------------------------------------------------------
class TechnicianDispensingModel {
  final String id;
  final String voucherNumber;
  final String technicianId;
  final String? technicianName;
  final String warehouseId;
  final String? warehouseName;
  final String? serviceRequestId;
  final DateTime dispensingDate;
  final String status;
  final String type;
  final String? notes;
  final String createdById;
  final String? createdByName;
  final String companyId;
  final List<TechnicianDispensingItemModel>? items;

  TechnicianDispensingModel({
    required this.id,
    required this.voucherNumber,
    required this.technicianId,
    this.technicianName,
    required this.warehouseId,
    this.warehouseName,
    this.serviceRequestId,
    required this.dispensingDate,
    required this.status,
    required this.type,
    this.notes,
    required this.createdById,
    this.createdByName,
    required this.companyId,
    this.items,
  });

  factory TechnicianDispensingModel.fromJson(Map<String, dynamic> json) {
    return TechnicianDispensingModel(
      id: _v(json, 'id') as String? ?? '',
      voucherNumber: _v(json, 'voucherNumber') as String? ?? '',
      technicianId: _v(json, 'technicianId') as String? ?? '',
      technicianName: _v(json, 'technicianName') as String?,
      warehouseId: _v(json, 'warehouseId') as String? ?? '',
      warehouseName: _v(json, 'warehouseName') as String?,
      serviceRequestId: _v(json, 'serviceRequestId') as String?,
      dispensingDate: DateTime.tryParse(
              _v(json, 'dispensingDate') as String? ?? '') ??
          DateTime.now(),
      status: _v(json, 'status') as String? ?? 'Pending',
      type: _v(json, 'type') as String? ?? 'Dispensing',
      notes: _v(json, 'notes') as String?,
      createdById: _v(json, 'createdById') as String? ?? '',
      createdByName: _v(json, 'createdByName') as String?,
      companyId: _v(json, 'companyId') as String? ?? '',
      items: _v(json, 'items') != null
          ? (_v(json, 'items') as List<dynamic>)
              .map((e) => TechnicianDispensingItemModel.fromJson(
                  e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'voucherNumber': voucherNumber,
      'technicianId': technicianId,
      'technicianName': technicianName,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'serviceRequestId': serviceRequestId,
      'dispensingDate': dispensingDate.toIso8601String(),
      'status': status,
      'type': type,
      'notes': notes,
      'createdById': createdById,
      'createdByName': createdByName,
      'companyId': companyId,
      'items': items?.map((e) => e.toJson()).toList(),
    };
  }
}

// ---------------------------------------------------------------------------
// StockMovement
// ---------------------------------------------------------------------------
class StockMovement {
  final int id;
  final String inventoryItemId;
  final String? itemName;
  final String? itemSku;
  final String warehouseId;
  final String? warehouseName;
  final String movementType;
  final int quantity;
  final int stockBefore;
  final int stockAfter;
  final double? unitCost;
  final String? referenceType;
  final String? referenceId;
  final String? referenceNumber;
  final String? description;
  final String createdById;
  final String? createdByName;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.warehouseId,
    this.warehouseName,
    required this.movementType,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.unitCost,
    this.referenceType,
    this.referenceId,
    this.referenceNumber,
    this.description,
    required this.createdById,
    this.createdByName,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: _v(json, 'id') as int? ?? 0,
      inventoryItemId: _v(json, 'inventoryItemId') as String? ?? '',
      itemName: _v(json, 'itemName') as String?,
      itemSku: _v(json, 'itemSku') as String?,
      warehouseId: _v(json, 'warehouseId') as String? ?? '',
      warehouseName: _v(json, 'warehouseName') as String?,
      movementType: _v(json, 'movementType') as String? ?? '',
      quantity: _v(json, 'quantity') as int? ?? 0,
      stockBefore: _v(json, 'stockBefore') as int? ?? 0,
      stockAfter: _v(json, 'stockAfter') as int? ?? 0,
      unitCost: (_v(json, 'unitCost') as num?)?.toDouble(),
      referenceType: _v(json, 'referenceType') as String?,
      referenceId: _v(json, 'referenceId') as String?,
      referenceNumber: _v(json, 'referenceNumber') as String?,
      description: _v(json, 'description') as String?,
      createdById: _v(json, 'createdById') as String? ?? '',
      createdByName: _v(json, 'createdByName') as String?,
      createdAt:
          DateTime.tryParse(_v(json, 'createdAt') as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryItemId': inventoryItemId,
      'itemName': itemName,
      'itemSku': itemSku,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'movementType': movementType,
      'quantity': quantity,
      'stockBefore': stockBefore,
      'stockAfter': stockAfter,
      'unitCost': unitCost,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'referenceNumber': referenceNumber,
      'description': description,
      'createdById': createdById,
      'createdByName': createdByName,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

// ---------------------------------------------------------------------------
// InventorySummary
// ---------------------------------------------------------------------------
class InventorySummary {
  final int totalItems;
  final double totalValue;
  final int lowStockCount;
  final int todayMovementsCount;

  InventorySummary({
    required this.totalItems,
    required this.totalValue,
    required this.lowStockCount,
    required this.todayMovementsCount,
  });

  factory InventorySummary.fromJson(Map<String, dynamic> json) {
    return InventorySummary(
      totalItems: _v(json, 'totalItems') as int? ?? 0,
      totalValue: (_v(json, 'totalValue') as num?)?.toDouble() ?? 0.0,
      lowStockCount: _v(json, 'lowStockCount') as int? ?? 0,
      todayMovementsCount: _v(json, 'todayMovementsCount') as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalItems': totalItems,
      'totalValue': totalValue,
      'lowStockCount': lowStockCount,
      'todayMovementsCount': todayMovementsCount,
    };
  }
}
