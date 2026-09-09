import 'package:flutter/material.dart';

import '../../core/models/sale_model.dart';

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({super.key, required this.sale});

  final SaleModel sale;

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'paid':
        return 'Pagada / sin sincronizar';
      case 'synced':
        return 'Sincronizada';
      case 'failed':
        return 'Fallida';
      default:
        return 'Borrador';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.blue;
      case 'synced':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }


  @override
  Widget build(BuildContext context) {
    final paymentStatus = sale.status ?? sale.syncStatus;
    final displayedStatus = paymentStatus == 'paid' ? 'paid' : sale.syncStatus;
    return Scaffold(
      appBar: AppBar(
        title: Text('Venta ${sale.folio ?? sale.uuidLocal.substring(0, 8)}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor(displayedStatus).withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estado', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(
                    _statusLabel(displayedStatus),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      backgroundColor: _statusColor(displayedStatus),
                      label: Text(
                        _statusLabel(displayedStatus),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Fecha: ${sale.businessDate}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text('Total: \$${sale.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (sale.payments.isNotEmpty) ...[
              const Text('Pagos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...sale.payments.map(
                (payment) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined, color: Color(0xFF9AC53B)),
                    title: Text(payment.method),
                    trailing: Text('\$${payment.amount.toStringAsFixed(2)}'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Productos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sale.items.length,
                itemBuilder: (context, index) {
                  final item = sale.items[index];
                  return Card(
                    child: ListTile(
                      title: Text(item.name),
                      subtitle: Text('${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}'),
                      trailing: Text('\$${item.total.toStringAsFixed(2)}'),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            if (sale.errorMessage != null && sale.errorMessage!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Error: ${sale.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
