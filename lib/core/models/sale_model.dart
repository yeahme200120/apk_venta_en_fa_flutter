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
    this.changeDue,
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

  /// Cambio entregado al cliente.
  ///
  /// Se mantiene nullable para no romper otras partes del proyecto
  /// que puedan crear un SaleModel sin especificarlo.
  final double? changeDue;

  factory SaleModel.fromMap(
    Map<String, dynamic> map, {
    List<SaleItemModel>? saleItems,
    List<SalePaymentModel>? salePayments,
  }) {
    return SaleModel(
      id: _toInt(map['id']),

      uuidLocal: (map['uuid_local'] ?? map['uuidLocal'] ?? '').toString(),

      serverId: _toNullableInt(
        map['server_id'] ?? map['serverId'] ?? map['id_servidor'],
      ),

      businessDate: (
        map['business_date'] ??
        map['businessDate'] ??
        ''
      ).toString(),

      total: _toDouble(map['total']),

      syncStatus: (
        map['sync_status'] ??
        map['syncStatus'] ??
        'draft'
      ).toString(),

      items: saleItems ?? const <SaleItemModel>[],

      payments: salePayments ?? const <SalePaymentModel>[],

      createdAt: (
        map['created_at'] ??
        map['createdAt'] ??
        DateTime.now().toIso8601String()
      ).toString(),

      updatedAt: (
        map['updated_at'] ??
        map['updatedAt'] ??
        DateTime.now().toIso8601String()
      ).toString(),

      status: map['status']?.toString(),

      folio: (
        map['folio'] ??
        map['server_folio']
      )?.toString(),

      errorMessage: (
        map['error_message'] ??
        map['errorMessage'] ??
        map['last_sync_error']
      )?.toString(),

      // La base SQLite utiliza change_due.
      // También aceptamos changeDue por compatibilidad con respuestas API.
      changeDue: _toNullableDouble(
        map['change_due'] ?? map['changeDue'],
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          (value ?? '').toString(),
        ) ??
        0;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value > 0 ? value : null;
    }

    if (value is num) {
      final result = value.toInt();
      return result > 0 ? result : null;
    }

    final result = int.tryParse(value.toString());

    if (result == null || result <= 0) {
      return null;
    }

    return result;
  }

  static double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          (value ?? '')
              .toString()
              .replaceAll(',', '.'),
        ) ??
        0.0;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return double.tryParse(
      text.replaceAll(',', '.'),
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

  factory SaleItemModel.fromMap(
    Map<String, dynamic> map,
  ) {
    return SaleItemModel(
      id: _toInt(map['id']),

      saleId: _toInt(
        map['sale_id'] ?? map['saleId'],
      ),

      productId: _toInt(
        map['product_id'] ?? map['productId'],
      ),

      name: (
        map['name'] ??
        map['nombre'] ??
        ''
      ).toString(),

      quantity: _toDouble(
        map['quantity'] ?? map['cantidad'],
      ),

      unitPrice: _toDouble(
        map['unit_price'] ??
        map['unitPrice'] ??
        map['precio_unitario'],
      ),

      total: _toDouble(
        map['total'],
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          (value ?? '').toString(),
        ) ??
        0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          (value ?? '')
              .toString()
              .replaceAll(',', '.'),
        ) ??
        0.0;
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

  factory SalePaymentModel.fromMap(
    Map<String, dynamic> map,
  ) {
    return SalePaymentModel(
      id: _toInt(map['id']),

      saleId: _toInt(
        map['sale_id'] ?? map['saleId'],
      ),

      method: (
        map['method'] ??
        map['metodo'] ??
        ''
      ).toString(),

      amount: _toDouble(
        map['amount'] ??
        map['monto'],
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          (value ?? '').toString(),
        ) ??
        0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          (value ?? '')
              .toString()
              .replaceAll(',', '.'),
        ) ??
        0.0;
  }
}