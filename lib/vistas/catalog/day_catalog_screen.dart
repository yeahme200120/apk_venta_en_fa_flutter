import 'package:flutter/material.dart';

import '../../core/services/catalog_service.dart';
import '../../core/storage/app_storage.dart';

class DayCatalogScreen extends StatefulWidget {
  const DayCatalogScreen({super.key});

  @override
  State<DayCatalogScreen> createState() => _DayCatalogScreenState();
}

class _DayCatalogScreenState extends State<DayCatalogScreen> {
  final CatalogService _catalogService = CatalogService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    if (companyId == 0 || userId == 0) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final items = await _catalogService.downloadCatalogForToday(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!mounted) return;
      setState(() {
        _products = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar el catálogo del día.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogos del día'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sin catálogo disponible. Descárgalo desde internet para iniciar el día.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final name = product['name']?.toString() ?? 'Producto';
                    final code = product['code']?.toString() ?? 'N/A';
                    final price = (product['price'] is num ? product['price'] as num : 0).toDouble();
                    final stock = (product['stock'] is num ? product['stock'] as num : 0).toDouble();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF9AC53B).withAlpha(55)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9AC53B).withAlpha(15),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9AC53B).withAlpha(28),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2B3A1E),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2A1A),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Código: $code',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF9AC53B).withAlpha(18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Stock: ${stock.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2D6A1E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '\$${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1F2A1A),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadCatalog,
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar'),
      ),
    );
  }
}
