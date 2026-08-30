class SaleModel {
  SaleModel({
    required this.id,
    required this.uuidLocal,
    required this.serverId,
    required this.businessDate,
    required this.total,
    required this.syncStatus,
    required this.items,
    required this.payments,
    required this.createdAt,
    required this.updatedAt,
    this.status,
    this.folio,
    this.errorMessage,
  });

  final int id;
  final String uuidLocal;
  final int? serverId;
  final String businessDate;
  final double total;
  final String syncStatus;
  final List<SaleItemModel> items;
  final List<SalePaymentModel> payments;
  final String createdAt;
  final String updatedAt;
  final String? status;
  final String? folio;
  final String? errorMessage;

  factory SaleModel.fromMap(Map<String, dynamic> map, {List<SaleItemModel>? saleItems, List<SalePaymentModel>? salePayments}) {
    return SaleModel(
      id: int.tryParse('${map['id'] ?? 0}') ?? 0,
      uuidLocal: (map['uuid_local'] ?? '').toString(),
      serverId: int.tryParse('${map['server_id'] ?? map['id_servidor'] ?? ''}'),
      businessDate: (map['business_date'] ?? '').toString(),
      total: (map['total'] is num) ? (map['total'] as num).toDouble() : 0.0,
      syncStatus: (map['sync_status'] ?? 'draft').toString(),
      items: saleItems ?? const [],
      payments: salePayments ?? const [],
      createdAt: (map['created_at'] ?? DateTime.now().toIso8601String()).toString(),
      updatedAt: (map['updated_at'] ?? DateTime.now().toIso8601String()).toString(),
      status: map['status']?.toString(),
      folio: map['folio']?.toString(),
      errorMessage: map['error_message']?.toString(),
    );
  }
}

class SaleItemModel {
  SaleItemModel({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final int id;
  final int saleId;
  final int productId;
  final String name;
  final double quantity;
  final double unitPrice;
  final double total;

  factory SaleItemModel.fromMap(Map<String, dynamic> map) {
    return SaleItemModel(
      id: int.tryParse('${map['id'] ?? 0}') ?? 0,
      saleId: int.tryParse('${map['sale_id'] ?? 0}') ?? 0,
      productId: int.tryParse('${map['product_id'] ?? 0}') ?? 0,
      name: (map['name'] ?? '').toString(),
      quantity: (map['quantity'] is num) ? (map['quantity'] as num).toDouble() : 0.0,
      unitPrice: (map['unit_price'] is num) ? (map['unit_price'] as num).toDouble() : 0.0,
      total: (map['total'] is num) ? (map['total'] as num).toDouble() : 0.0,
    );
  }
}

class SalePaymentModel {
  SalePaymentModel({
    required this.id,
    required this.saleId,
    required this.method,
    required this.amount,
  });

  final int id;
  final int saleId;
  final String method;
  final double amount;

  factory SalePaymentModel.fromMap(Map<String, dynamic> map) {
    return SalePaymentModel(
      id: int.tryParse('${map['id'] ?? 0}') ?? 0,
      saleId: int.tryParse('${map['sale_id'] ?? 0}') ?? 0,
      method: (map['method'] ?? '').toString(),
      amount: (map['amount'] is num) ? (map['amount'] as num).toDouble() : 0.0,
    );
  }
}
