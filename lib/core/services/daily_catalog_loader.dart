import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class DailyCatalogLoader {
  final ApiClient _apiClient;
  final PosDatabaseService _dbService;

  DailyCatalogLoader({ApiClient? apiClient, PosDatabaseService? dbService})
      : _apiClient = apiClient ?? ApiClient(),
        _dbService = dbService ?? PosDatabaseService();

  Future<void> loadFirstDayCatalog({required int companyId, required int userId, required DateTime businessDate}) async {
    final response = await _apiClient.getCatalog();
    final data = response['data'] is Map ? Map<String, dynamic>.from(response['data']) : response;
    final raw = data['productos'];
    final products = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    final db = await _dbService.open(companyId: companyId, userId: userId, businessDate: businessDate);
    await _dbService.upsertProducts(db, products);
  }

  /// Limpia solo la base operativa del día. No toca LocalDb.
  Future<void> clearDailyDatabase({required int companyId, required int userId, required DateTime businessDate}) async {
    final db = await _dbService.open(companyId: companyId, userId: userId, businessDate: businessDate);
    await db.transaction((txn) async {
      await txn.delete('sale_items');
      await txn.delete('sale_payments');
      await txn.delete('sales');
      await txn.delete('sync_outbox');
    });
  }
}
