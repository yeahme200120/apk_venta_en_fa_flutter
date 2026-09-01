import 'dart:async';

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

class _DailyStatsScreenState extends State<DailyStatsScreen>
    with WidgetsBindingObserver {
  final LocalDb _db = LocalDb();
  final SyncService _syncService = SyncService();

  Timer? _refreshTimer;

  bool _loading = true;
  bool _refreshing = false;
  bool _syncing = false;

  List<Map<String, dynamic>> _sales = const [];

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();

    // Refresco suave cada 2 segundos solo si el widget está montado.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (timer) {
        if (mounted && !_refreshing && !_syncing) {
          _refreshSilently();
        }
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshSilently();
    }
  }

  // ============================================================
  // CARGA PRINCIPAL
  // ============================================================

  Future<void> _loadStats() async {
    if (!mounted) return;
    if (_refreshing) return;

    _refreshing = true;

    try {
      final sales = await _db.getTodaySales();
      if (!mounted) return;

      final normalized = sales
          .map((sale) => Map<String, dynamic>.from(sale))
          .toList(growable: false);

      setState(() {
        _sales = normalized;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('No fue posible cargar las ventas: $error', isError: true);
    } finally {
      _refreshing = false;
    }
  }

  // ============================================================
  // REFRESCO SILENCIOSO (sin mostrar SnackBar)
  // ============================================================

  Future<void> _refreshSilently() async {
    if (!mounted) return;
    if (_refreshing || _syncing) return;

    _refreshing = true;
    try {
      final sales = await _db.getTodaySales();
      if (!mounted) return;

      final normalized = sales
          .map((sale) => Map<String, dynamic>.from(sale))
          .toList(growable: false);

      if (mounted) {
        setState(() {
          _sales = normalized;
          _loading = false;
        });
      }
    } catch (_) {
      // Silencio total
    } finally {
      _refreshing = false;
    }
  }

  // ============================================================
  // SINCRONIZACIÓN MANUAL
  // ============================================================

  Future<void> _syncNow() async {
    if (!mounted || _syncing) return;

    setState(() => _syncing = true);

    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;

      await _syncService.syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!mounted) return;
      await _loadStats();

      if (mounted) {
        _showMessage('Sincronización completada.');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('No fue posible sincronizar: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        await _refreshSilently();
      }
    }
  }

  // ============================================================
  // ABRIR DETALLE DE VENTA
  // ============================================================

  Future<void> _openSale(Map<String, dynamic> sale) async {
    if (!mounted) return;

    final saleId = _toInt(sale['id']);
    if (saleId <= 0) {
      _showMessage('No se pudo identificar la venta.', isError: true);
      return;
    }

    try {
      final items = await _db.getSaleItemsBySaleId(saleId);
      final payments = await _db.getSalePaymentsBySaleId(saleId);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(
            sale: SaleModel.fromMap(
              Map<String, dynamic>.from(sale),
              saleItems: items.map(SaleItemModel.fromMap).toList(),
              salePayments: payments.map(SalePaymentModel.fromMap).toList(),
            ),
          ),
        ),
      );

      if (mounted) await _refreshSilently();
    } catch (error) {
      if (!mounted) return;
      _showMessage('No fue posible abrir la venta: $error', isError: true);
    }
  }

  // ============================================================
  // CANCELAR VENTA
  // ============================================================

  Future<void> _cancelSale(Map<String, dynamic> sale) async {
    if (!mounted) return;

    final currentStatus = _businessStatus(sale);
    if (currentStatus == _SaleBusinessStatus.cancelled) return;

    final saleId = _toInt(sale['id']);
    if (saleId <= 0) {
      _showMessage('No se pudo identificar la venta.', isError: true);
      return;
    }

    final confirmed = await _showCancelDialog();
    if (confirmed != true || !mounted) return;

    try {
      final cancelled = await _db.cancelSale(saleId);
      if (!mounted) return;

      if (!cancelled) {
        await _refreshSilently();
        if (mounted) {
          _showMessage('La venta ya estaba cancelada o no existe.', isError: true);
        }
        return;
      }

      await _refreshSilently();
      if (mounted) {
        _showMessage(
          'Venta cancelada localmente. Quedó pendiente de sincronización con el servidor.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('No fue posible cancelar la venta: $error', isError: true);
    }
  }

  Future<bool?> _showCancelDialog() {
    if (!mounted) return Future.value(null);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar venta'),
          content: const Text(
            'La venta será marcada como cancelada y '
            'el stock será restaurado localmente.\n\n'
            'La operación quedará pendiente de sincronización '
            'con el servidor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
              child: const Text('Cancelar venta'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // ESTADO COMERCIAL (NUNCA usar sync_status para la etiqueta)
  // ============================================================

  _SaleBusinessStatus _businessStatus(Map<String, dynamic> sale) {
    final raw = (sale['status'] ?? '').toString().trim().toLowerCase();
    switch (raw) {
      case 'cancelled':
      case 'canceled':
      case 'cancelado':
      case 'cancelada':
      case 'anulado':
      case 'anulada':
        return _SaleBusinessStatus.cancelled;
      case 'paid':
      case 'pagado':
      case 'pagada':
        return _SaleBusinessStatus.paid;
      case 'pending':
      case 'pendiente':
      case '':
        return _SaleBusinessStatus.pending;
      default:
        return _SaleBusinessStatus.pending;
    }
  }

  String _statusText(Map<String, dynamic> sale) {
    switch (_businessStatus(sale)) {
      case _SaleBusinessStatus.paid:
        return 'Pagada';
      case _SaleBusinessStatus.pending:
        return 'Pendiente';
      case _SaleBusinessStatus.cancelled:
        return 'Cancelada';
    }
  }

  Color _statusColor(Map<String, dynamic> sale) {
    switch (_businessStatus(sale)) {
      case _SaleBusinessStatus.paid:
        return Colors.green;
      case _SaleBusinessStatus.pending:
        return Colors.orange;
      case _SaleBusinessStatus.cancelled:
        return Colors.red;
    }
  }

  bool _canCancel(Map<String, dynamic> sale) =>
      _businessStatus(sale) != _SaleBusinessStatus.cancelled;

  // ============================================================
  // TOTALES Y CONTADORES
  // ============================================================

  Iterable<Map<String, dynamic>> get _activeSales =>
      _sales.where((sale) => _businessStatus(sale) != _SaleBusinessStatus.cancelled);

  double get _total => _activeSales.fold(0, (sum, sale) => sum + _saleTotal(sale));
  int get _tickets => _activeSales.length;
  double get _ticketPromedio => _tickets == 0 ? 0 : _total / _tickets;
  int get _pendingSales => _sales.where((sale) => _businessStatus(sale) == _SaleBusinessStatus.pending).length;
  int get _cancelledSales => _sales.where((sale) => _businessStatus(sale) == _SaleBusinessStatus.cancelled).length;

  double _saleTotal(Map<String, dynamic> sale) => _toDouble(sale['total']);

  // ============================================================
  // HELPERS DE CONVERSIÓN Y MENSAJES
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--/--/---- --:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$minute';
    } catch (_) {
      return isoString;
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas del día'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar ventas',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildStatsHorizontal(),
                  const SizedBox(height: 24),
                  _buildSalesHeader(),
                  const SizedBox(height: 10),
                  if (_sales.isEmpty)
                    _buildEmptyState()
                  else
                    ..._sales.map(
                      (sale) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SaleCard(
                          sale: sale,
                          total: _saleTotal(sale),
                          status: _statusText(sale),
                          statusColor: _statusColor(sale),
                          canCancel: _canCancel(sale),
                          onTap: () => _openSale(sale),
                          onCancel: () => _cancelSale(sale),
                          formatDateTime: _formatDateTime,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // UI COMPONENTS
  // ============================================================

  Widget _buildStatsHorizontal() {
    return SizedBox(
      height: 125,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _StatCard(icon: Icons.attach_money, label: 'Total', value: '\$${_total.toStringAsFixed(2)}'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.receipt_long_outlined, label: 'Tickets', value: '$_tickets'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.analytics_outlined, label: 'Promedio', value: '\$${_ticketPromedio.toStringAsFixed(2)}'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.sync_problem_outlined, label: 'Pendientes', value: '$_pendingSales'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.cancel_outlined, label: 'Canceladas', value: '$_cancelledSales'),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Ventas del día',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
        ),
        if (_sales.isNotEmpty)
          Text(
            '${_sales.length} ${_sales.length == 1 ? 'venta' : 'ventas'}',
            style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 58, color: Colors.black26),
          SizedBox(height: 14),
          Text(
            'No hay ventas registradas hoy',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'Las ventas realizadas aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ENUM DE ESTADOS COMERCIALES
// ============================================================

enum _SaleBusinessStatus {
  paid,
  pending,
  cancelled,
}

// ============================================================
// SALE CARD (con fecha y hora)
// ============================================================

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.total,
    required this.status,
    required this.statusColor,
    required this.canCancel,
    required this.onTap,
    required this.onCancel,
    required this.formatDateTime,
  });

  final Map<String, dynamic> sale;
  final double total;
  final String status;
  final Color statusColor;
  final bool canCancel;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final String Function(String?) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final saleId = sale['id']?.toString() ?? '-';
    final fechaHora = formatDateTime(sale['created_at']);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMainInfo(saleId, fechaHora),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\$${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (canCancel)
                          OutlinedButton.icon(
                            onPressed: onCancel,
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: _buildMainInfo(saleId, fechaHora)),
                  const SizedBox(width: 16),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  if (canCancel) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Cancelar venta',
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined),
                      color: Colors.red,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainInfo(String saleId, String fechaHora) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF9AC53B).withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF58751F)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Venta $saleId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      fechaHora,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// STAT CARD
// ============================================================

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 175,
      constraints: const BoxConstraints(minHeight: 115, maxHeight: 125),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF9AC53B).withAlpha(25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF9AC53B).withAlpha(45)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF9AC53B).withAlpha(35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF58751F)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}