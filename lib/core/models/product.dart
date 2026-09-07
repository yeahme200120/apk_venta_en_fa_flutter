import 'dart:convert';

class Product {
  Product({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
    required this.stock,
    this.isActive = true,
    this.isInventoriable = true,
    this.categoryId,
  });

  final int id;
  final String code;
  final String name;
  final double price;
  final double stock;
  final bool isActive;

  /// true  → el producto controla inventario; la venta descuenta stock
  ///         y se bloquea cuando stock <= 0.
  /// false → el producto no maneja stock; siempre se puede vender.
  final bool isInventoriable;

  /// ID de la categoría, leído desde data_json si está disponible.
  final int? categoryId;

  factory Product.fromMap(Map<String, dynamic> map) {
    // Leer is_inventoriable desde el campo directo o desde data_json
    bool inventoriable = true;
    int? catId;

    final rawDataJson = map['data_json'];
    if (rawDataJson is String && rawDataJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDataJson);
        if (decoded is Map) {
          final inv = decoded['is_inventariable'] ?? decoded['inventariable'];
          if (inv != null) inventoriable = _parseBool(inv);
          final cid = decoded['categoria_id'] ?? decoded['category_id'];
          if (cid != null) catId = _parseInt(cid);
        }
      } catch (_) {}
    }

    // El campo directo tiene precedencia sobre data_json
    final directInv = map['is_inventariable'] ?? map['inventariable'];
    if (directInv != null) inventoriable = _parseBool(directInv);
    final directCat = map['categoria_id'] ?? map['category_id'];
    if (directCat != null) catId = _parseInt(directCat);

    return Product(
      id: _parseInt(map['id']),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      price: _parseDouble(map['price'] ?? map['precio'] ?? 0),
      stock: _parseDouble(map['stock'] ?? 0),
      isActive: (map['is_active'] ?? 1) != 0,
      isInventoriable: inventoriable,
      categoryId: catId,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'si' || s == 'yes';
  }
}

class CartItem {
  CartItem({
    required this.product,
    required this.quantity,
  });

  final Product product;
  final int quantity;

  double get subtotal => product.price * quantity;
}
