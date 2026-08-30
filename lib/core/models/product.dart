class Product {
  Product({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
    required this.stock,
    this.isActive = true,
  });

  final int id;
  final String code;
  final String name;
  final double price;
  final double stock;
  final bool isActive;

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int,
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      price: (map['price'] ?? 0.0) as double,
      stock: (map['stock'] ?? 0.0) as double,
      isActive: (map['is_active'] ?? 1) == 1,
    );
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
