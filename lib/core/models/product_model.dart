class ProductModel {
  ProductModel({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
    required this.stock,
    this.version = 0,
    this.deletedAt,
    this.syncedAt,
  });

  final int id;
  final String code;
  final String name;
  final double price;
  final double stock;
  final int version;
  final String? deletedAt;
  final String? syncedAt;

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    final rawPrice = map['price'];
    final rawStock = map['stock'];

    return ProductModel(
      id: int.tryParse('${map['id'] ?? map['product_id'] ?? 0}') ?? 0,
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      price: rawPrice is num ? rawPrice.toDouble() : 0.0,
      stock: rawStock is num ? rawStock.toDouble() : 0.0,
      version: int.tryParse('${map['version'] ?? 0}') ?? 0,
      deletedAt: map['deleted_at']?.toString(),
      syncedAt: map['synced_at']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'price': price,
      'stock': stock,
      'version': version,
      'deleted_at': deletedAt,
      'synced_at': syncedAt,
    };
  }
}

class CartItemModel {
  CartItemModel({
    required this.product,
    required this.quantity,
  });

  final ProductModel product;
  final int quantity;

  double get subtotal => product.price * quantity;
}
