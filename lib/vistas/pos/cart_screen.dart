import 'package:flutter/material.dart';

import '../../core/models/product.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({
    super.key,
    required this.items,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onClear,
    required this.onCheckout,
  });

  final List<CartItem> items;
  final void Function(int productId, int delta) onQuantityChanged;
  final ValueChanged<int> onRemove;
  final VoidCallback onClear;
  final Future<void> Function() onCheckout;

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carrito de compra')),
      body: items.isEmpty
          ? const Center(child: Text('Agrega productos desde la caja para comenzar.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('\$${item.product.price.toStringAsFixed(2)} c/u'),
                              Text('\$${item.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Disminuir cantidad',
                          onPressed: () => onQuantityChanged(item.product.id, -1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          tooltip: 'Aumentar cantidad',
                          onPressed: () => onQuantityChanged(item.product.id, 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Eliminar producto',
                          onPressed: () => onRemove(item.product.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: items.isEmpty ? null : onClear,
                icon: const Icon(Icons.remove_shopping_cart_outlined),
                label: const Text('Vaciar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: items.isEmpty ? null : onCheckout,
                icon: const Icon(Icons.check_circle_outline),
                label: Text('Cobrar \$${total.toStringAsFixed(2)}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9AC53B),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
