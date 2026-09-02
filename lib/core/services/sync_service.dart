import 'dart:async';
import 'dart:convert';

import '../database/local_db.dart';
import '../database/pos_db_service.dart';
import '../network/api_client.dart';
import '../storage/app_storage.dart';

class SyncResult {
  const SyncResult({required this.total, required this.synced, required this.failed, required this.skipped});
  final int total;
  final int synced;
  final int failed;
  final int skipped;
}

/// Coordinador único de sincronización.
///
/// PosDatabaseService = operación del día.
/// LocalDb = histórico/cola multidía.
class SyncService {
  final ApiClient _apiClient;
  final PosDatabaseService _dayDb;
  final LocalDb _historyDb;

  SyncService({ApiClient? apiClient, PosDatabaseService? posDbService, LocalDb? localDb})
      : _apiClient = apiClient ?? ApiClient(),
        _dayDb = posDbService ?? PosDatabaseService(),
        _historyDb = localDb ?? LocalDb();

  static bool _running = false;

  Future<SyncResult> syncPendingSales({required int companyId, required int userId, required DateTime businessDate, int? limit}) async {
    if (_running) return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    if (await AppStorage().isOfflineSession()) {
      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }
    _running = true;
    var total = 0, synced = 0, failed = 0, skipped = 0;
    try {
      // Primero procesa el histórico: puede contener ventas de hace días.
      final historical = await _historyDb.getPendingSalesReadyToSync(limit: limit);
      for (final sale in historical) {
        total++;
        final ok = await _syncHistoricalSale(sale);
        ok ? synced++ : failed++;
      }

      // Después procesa la base diaria.
      final dayOutbox = await _dayDb.getPendingOutbox(companyId: companyId, userId: userId, businessDate: businessDate, limit: limit);
      for (final item in dayOutbox) {
        total++;
        final ok = await _syncDayOutbox(companyId, userId, businessDate, item);
        ok ? synced++ : failed++;
      }

      return SyncResult(total: total, synced: synced, failed: failed, skipped: skipped);
    } finally {
      _running = false;
    }
  }

  Future<bool> syncSaleById(int saleId) async {
    final sale = await _historyDb.getSaleById(saleId);
    if (sale == null) return false;
    if (sale['sync_status'] == 'synced') return true;
    return _syncHistoricalSale(sale, force: true);
  }

  Future<bool> _syncHistoricalSale(Map<String, dynamic> sale, {bool force = false}) async {
    final id = _toInt(sale['id']);
    if (id <= 0) return false;
    if (!force && sale['next_retry_at'] != null && DateTime.tryParse(sale['next_retry_at'].toString())?.isAfter(DateTime.now()) == true) return true;
    if (sale['status']?.toString().toLowerCase() == 'cancelled') {
      await _historyDb.markSaleAsSynced(id, serverResponse: {'server_id': sale['server_id'], 'folio': sale['server_folio']});
      return true;
    }

    await _historyDb.markSaleSyncing(id);
    try {
      final payload = await _buildHistoricalPayload(sale);
      payload['uuid_local'] = sale['uuid_local'];
      payload['business_date'] = sale['business_date'];
      final response = await _apiClient.syncOffline(payload);
      await _historyDb.markSaleAsSynced(id, serverResponse: response);
      return true;
    } catch (e) {
      await _historyDb.markSaleSyncFailed(id, e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>> _buildHistoricalPayload(Map<String, dynamic> sale) async {
    final id = _toInt(sale['id']);
    final items = await _historyDb.getSaleItemsBySaleId(id);
    final payments = await _historyDb.getSalePaymentsBySaleId(id);
    return _buildPayload(sale, items, payments);
  }

  Future<bool> _syncDayOutbox(int companyId, int userId, DateTime date, Map<String, dynamic> item) async {
    final uuid = item['uuid_local']?.toString() ?? '';
    if (uuid.isEmpty) return false;
    final attempts = _toInt(item['attempts']);
    try {
      final payload = jsonDecode(item['payload']?.toString() ?? '{}');
      if (payload is! Map) throw const FormatException('Payload de sincronización inválido.');
      final map = Map<String, dynamic>.from(payload);
      map['uuid_local'] = uuid;
      map['business_date'] ??= date.toIso8601String().substring(0, 10);
      final response = await _apiClient.syncOffline(map);
      await _dayDb.markOutboxSynced(companyId: companyId, userId: userId, businessDate: date, uuidLocal: uuid, serverResponse: response);
      return true;
    } catch (e) {
      await _dayDb.markOutboxFailed(companyId: companyId, userId: userId, businessDate: date, uuidLocal: uuid, error: e.toString(), attempts: attempts + 1);
      return false;
    }
  }

  Map<String, dynamic> _buildPayload(Map<String, dynamic> sale, List<Map<String, dynamic>> items, List<Map<String, dynamic>> payments) {
    final total = _toDouble(sale['total']);
    final changeDue = _toDouble(sale['change_due']);
    final normalized = <Map<String, dynamic>>[];
    var cashAdjusted = false;
    var sum = 0.0;

    for (final p in payments) {
      final method = p['method']?.toString() ?? '';
      final original = _toDouble(p['amount']);
      var amount = original;
      var change = 0.0;
      if (method.trim().toLowerCase() == 'efectivo' && !cashAdjusted) {
        amount = original - changeDue;
        change = changeDue;
        cashAdjusted = true;
      }
      if (amount < 0) amount = 0;
      normalized.add({'forma_pago': _mapPaymentMethod(method), 'monto': amount, 'cambio': change, 'referencia': p['referencia']});
      sum += amount;
    }

    final diff = total - sum;
    if (diff.abs() > 0.001) {
      if (normalized.isNotEmpty) {
        normalized[0]['monto'] = _toDouble(normalized[0]['monto']) + diff;
      } else {
        normalized.add({'forma_pago': 'Efectivo', 'monto': diff, 'cambio': 0.0, 'referencia': null});
      }
    }

    return {
      'cliente_id': sale['cliente_id'],
      'productos': items.map((i) => {'producto_id': _toInt(i['product_id']), 'cantidad': _toDouble(i['quantity']), 'precio': _toDouble(i['unit_price']), 'descuento': _toDouble(i['descuento'])}).toList(),
      'pagos': normalized,
      'descuento_global': _toDouble(sale['descuento_global']),
      'impuesto_global': _toDouble(sale['impuesto_global']),
      'notas': sale['notas']?.toString() ?? '',
    };
  }

  /// Mueve pendientes de la base diaria a la histórica.
  /// Debe ejecutarse antes de borrar el archivo del día.
  Future<int> archivePendingSalesFromDay({required int companyId, required int userId, required DateTime businessDate}) async {
    final db = await _dayDb.open(companyId: companyId, userId: userId, businessDate: businessDate);
    final rows = await db.query('sales', where: "sync_status IN ('pending','failed','syncing')", orderBy: 'created_at ASC');
    var count = 0;
    for (final sale in rows) {
      final uuid = sale['uuid_local']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      final items = await _dayDb.getSaleItems(db, _toInt(sale['id']));
      final payments = await _dayDb.getSalePayments(db, _toInt(sale['id']));
      await _historyDb.archiveDailySale(sale: sale, items: items, payments: payments);
      count++;
    }
    return count;
  }

  Future<void> syncCatalogs({bool force = false}) async {
    final versions = await _historyDb.getCatalogVersions();
    final cursor = await _historyDb.getCatalogCursor('global');
    final response = await _apiClient.getCatalog(desde: force ? null : cursor ?? versions['global']);
    if (response.isEmpty) return;
    await _historyDb.syncCatalogs(response);
    final nextCursor = response['next_cursor']?.toString() ?? response['cursor']?.toString();
    final nextVersion = response['version']?.toString() ?? (response['versiones'] is Map ? (response['versiones'] as Map)['global']?.toString() : null);
    if (nextCursor != null || nextVersion != null) await _historyDb.setCatalogVersion('global', nextVersion, cursor: nextCursor);
  }

  /// Aplica únicamente cambios entregados por el servidor desde el cursor.
  Future<Map<String, dynamic>> syncPull() async {
    final cursor = await _historyDb.getCatalogCursor('server_changes');
    final response = await _apiClient.syncPull(cursor: cursor);
    final next = response['next_cursor']?.toString() ?? response['cursor']?.toString();
    if (next != null) await _historyDb.setCatalogVersion('server_changes', null, cursor: next);
    if (response['data'] is Map) await _historyDb.syncCatalogs(Map<String, dynamic>.from(response['data']));
    return response;
  }

  int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0;
  String _mapPaymentMethod(String method) { final n = method.toLowerCase().trim(); if (n == 'efectivo') return 'Efectivo'; if (n == 'tarjeta' || n == 'tarjeta crédito') return 'Tarjeta Crédito'; if (n == 'tarjeta débito') return 'Tarjeta Débito'; if (n == 'transferencia') return 'Transferencia'; if (n == 'crédito') return 'Crédito'; return 'Otro'; }
}
