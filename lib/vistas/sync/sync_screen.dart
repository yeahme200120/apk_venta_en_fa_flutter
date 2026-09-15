import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final LocalDb _db = LocalDb();
  final SyncService _sync = SyncService();

  bool _loading = true;
  bool _syncing = false;
  bool _offline = false;

  Map<String, int> _queuePorTipo = const {};
  Map<String, int> _salesPorEstado = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final offline = await AppStorage().isOfflineSession();

    final queue = await _db.debugSyncQueue();
    final queuePorTipo = <String, int>{};
    for (final item in queue) {
      final t = item['entity_type']?.toString() ?? 'otros';
      queuePorTipo[t] = (queuePorTipo[t] ?? 0) + 1;
    }

    final sales = await _db.getSyncSummary();

    if (!mounted) return;
    setState(() {
      _offline = offline;
      _queuePorTipo = queuePorTipo;
      _salesPorEstado = sales;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;

      if (companyId <= 0 || userId <= 0) {
        throw Exception('No hay sesión válida para sincronizar.');
      }

      final result = await _sync.syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sincronización: total=${result.total} '
            'ok=${result.synced} '
            'fail=${result.failed} '
            'skip=${result.skipped}',
          ),
        ),
      );

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronización'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _offline ? Icons.cloud_off : Icons.cloud_done,
                                color: _offline ? Colors.orange : Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _offline ? 'Sesión offline' : 'Sesión online',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _syncing ? null : _syncNow,
                              icon: _syncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.sync),
                              label: Text(
                                _syncing
                                    ? 'Sincronizando...'
                                    : 'Sincronizar ahora',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cola pendiente',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_queuePorTipo.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sin operaciones pendientes.'),
                      ),
                    )
                  else
                    ..._queuePorTipo.entries.map(
                      (e) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.pending_actions),
                          title: Text(_label(e.key)),
                          trailing: Text(
                            '${e.value}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Ventas por estado',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._salesPorEstado.entries.map(
                    (e) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text(e.key),
                        trailing: Text(
                          '${e.value}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _label(String tipo) {
    switch (tipo) {
      case 'category':
        return 'Categorías';
      case 'product':
        return 'Productos';
      case 'cash_register':
        return 'Aperturas de caja';
      case 'cash_register_close':
        return 'Cierres de caja';
      case 'cash_movement':
        return 'Movimientos de caja';
      default:
        return tipo;
    }
  }
}