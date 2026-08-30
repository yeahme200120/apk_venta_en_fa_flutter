import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';

class CatalogAdminScreen extends StatefulWidget {
  const CatalogAdminScreen({super.key});

  @override
  State<CatalogAdminScreen> createState() => _CatalogAdminScreenState();
}

class _CatalogAdminScreenState extends State<CatalogAdminScreen> {
  final LocalDb _db = LocalDb();
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final products = await _db.getProducts();
    if (mounted) setState(() => _products = products);
  }

  Future<void> _edit([Map<String, dynamic>? product]) async {
    final code = TextEditingController(text: product?['code']?.toString() ?? '');
    final name = TextEditingController(text: product?['name']?.toString() ?? '');
    final price = TextEditingController(text: product?['price']?.toString() ?? '');
    final stock = TextEditingController(text: product?['stock']?.toString() ?? '0');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product == null ? 'Nuevo producto' : 'Editar producto'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: code, decoration: const InputDecoration(labelText: 'Código'), validator: _required),
                TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre'), validator: _required),
                TextFormField(controller: price, decoration: const InputDecoration(labelText: 'Precio'), keyboardType: TextInputType.number, validator: _number),
                TextFormField(controller: stock, decoration: const InputDecoration(labelText: 'Existencia'), keyboardType: TextInputType.number, validator: _number),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final values = (price: double.parse(price.text), stock: double.parse(stock.text));
              if (product == null) {
                await _db.createProduct(code: code.text.trim(), name: name.text.trim(), price: values.price, stock: values.stock);
              } else {
                await _db.updateProduct(id: product['id'] as int, code: code.text.trim(), name: name.text.trim(), price: values.price, stock: values.stock);
              }
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    code.dispose();
    name.dispose();
    price.dispose();
    stock.dispose();
    if (saved == true) _load();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Requerido' : null;
  String? _number(String? value) => double.tryParse(value ?? '') == null ? 'Número inválido' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de la empresa')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          return Card(
            child: ListTile(
              title: Text(product['name'].toString()),
              subtitle: Text('${product['code']}  |  Stock: ${product['stock']}'),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('\$${(product['price'] as num).toStringAsFixed(2)}'),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: 'Editar', onPressed: () => _edit(product), icon: const Icon(Icons.edit_outlined)),
                      IconButton(
                        tooltip: 'Desactivar',
                        onPressed: () async {
                          await _db.deleteProduct(product['id'] as int);
                          _load();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _edit,
        backgroundColor: const Color(0xFF9AC53B),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
