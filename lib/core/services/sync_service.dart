import 'dart:convert';

import '../database/local_db.dart';
import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class SyncService {
  final ApiClient _apiClient;
  final PosDatabaseService _dbService;
  final LocalDb _localDb;

  SyncService({ApiClient? apiClient, PosDatabaseService? posDbService, LocalDb? localDb})
      : _apiClient = apiClient ?? ApiClient(),
        _dbService = posDbService ?? PosDatabaseService(),
        _localDb = localDb ?? LocalDb();

  Future<void> syncPendingSales({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final queue = await _dbService.getPendingOutbox(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    final localSales = await _localDb.getPendingSales();
    for (final sale in localSales) {
      final saleId = int.tryParse('${sale['id'] ?? 0}') ?? 0;
      if (saleId == 0) continue;
      try {
        final payload = {
          'uuid_local': sale['uuid_local'],
          'total': sale['total'],
          'status': sale['status'] ?? 'pending',
          'items': await _localDb.getSaleItemsBySaleId(saleId),
          'payments': await _localDb.getSalePaymentsBySaleId(saleId),
        };
        await _apiClient.createSale(payload);
        await _localDb.markSaleAsSynced(saleId);
      } catch (_) {
        await _localDb.updateSaleStatus(
          saleId,
          (sale['status'] ?? 'pending').toString() == 'paid' ? 'paid' : 'pending',
          syncStatus: 'failed',
        );
      }
    }

    for (final item in queue) {
      final uuidLocal = item['uuid_local'] as String;
      final attempts = (item['attempts'] as int?) ?? 0;

      try {
        final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
        await _apiClient.createSale(payload);
        await _dbService.markOutboxSynced(
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
          uuidLocal: uuidLocal,
        );
      } catch (error) {
        await _dbService.markOutboxFailed(
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
          uuidLocal: uuidLocal,
          error: error.toString(),
          attempts: attempts + 1,
        );
      }
    }
  }
}
