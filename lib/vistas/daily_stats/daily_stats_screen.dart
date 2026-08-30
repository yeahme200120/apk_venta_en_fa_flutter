import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/models/sale_model.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';
import '../ventas/sale_detail_screen.dart';

class DailyStatsScreen extends StatefulWidget {
  const DailyStatsScreen({super.key});

  @override
  State<DailyStatsScreen> createState() => _DailyStatsScreenState();
}

class _DailyStatsScreenState extends State<DailyStatsScreen> {
  final LocalDb _db = LocalDb();
  bool _loading = true;
  bool _syncing = false;
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final sales = await _db.getTodaySales();
    setState(() {
      _sales = sales;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await SyncService().syncPendingSales(
        companyId: await AppStorage().getEmpresaId() ?? 0,
        userId: await AppStorage().getUserId() ?? 0,
        businessDate: DateTime.now(),
      );
      await _loadStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ventas pendientes sincronizadas.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible sincronizar: $error')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openSale(Map<String, dynamic> sale) async {
    final saleId = int.tryParse('${sale['id'] ?? 0}') ?? 0;
    final items = await _db.getSaleItemsBySaleId(saleId);
    final payments = await _db.getSalePaymentsBySaleId(saleId);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailScreen(
          sale: SaleModel.fromMap(
            sale,
            saleItems: items.map(SaleItemModel.fromMap).toList(),
            salePayments: payments.map(SalePaymentModel.fromMap).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelSale(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar venta'),
        content: const Text('Se devolverán las cantidades al stock local.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancelar venta')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final saleId = int.tryParse('${sale['id'] ?? 0}') ?? 0;
    final cancelled = await _db.cancelSale(saleId);
    if (!mounted) return;
    if (cancelled) {
      await _loadStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta cancelada y stock restaurado localmente.')),
      );
    }
  }

  double get _total {
    return _sales.fold(0.0, (sum, sale) => sum + (sale['total'] as num? ?? 0).toDouble());
  }

  int get _tickets => _sales.length;

  double get _ticketPromedio => _tickets == 0 ? 0 : _total / _tickets;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas del día'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar ventas pendientes',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(label: 'Total', value: '\$${_total.toStringAsFixed(2)}'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(label: 'Tickets', value: '$_tickets'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(label: 'Promedio', value: '\$${_ticketPromedio.toStringAsFixed(2)}'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: 'Pendientes',
                          value: '${_sales.where((sale) => (sale['status'] ?? sale['sync_status'] ?? 'pending').toString() != 'synced').length}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ventas del día',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _sales.length,
                      itemBuilder: (context, index) {
                        final sale = _sales[index];
                        final saleStatus = (sale['status'] ?? sale['sync_status'] ?? 'pending').toString();
                        final syncStatus = (sale['sync_status'] ?? 'pending').toString();
                        final displayStatus = saleStatus == 'paid' && syncStatus == 'pending'
                            ? 'Pagada / sin sincronizar'
                            : saleStatus == 'pending'
                                ? 'Pendiente'
                                : saleStatus == 'synced'
                                    ? 'Sincronizada'
                                    : saleStatus;
                        return Card(
                          child: ListTile(
                            title: Text('Venta ${sale['id']}'),
                            subtitle: Text('Estado: $displayStatus'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('\$${((sale['total'] as num?) ?? 0).toStringAsFixed(2)}'),
                                if (saleStatus != 'cancelled')
                                  IconButton(
                                    tooltip: 'Cancelar venta',
                                    onPressed: () => _cancelSale(sale),
                                    icon: const Icon(Icons.cancel_outlined),
                                  ),
                              ],
                            ),
                            onTap: () => _openSale(sale),
                            onLongPress: () => _cancelSale(sale),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF9AC53B).withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
