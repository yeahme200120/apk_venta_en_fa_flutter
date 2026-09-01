import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class DailyCatalogLoader {
  final ApiClient _apiClient;
  final PosDatabaseService _dbService;

  DailyCatalogLoader({
    ApiClient? apiClient,
    PosDatabaseService? dbService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _dbService = dbService ?? PosDatabaseService();

  Future<void> loadFirstDayCatalog({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final response = await _apiClient.getCatalog();

    dynamic productsData = response['productos'];

    // Soporte para respuestas envueltas en "data".
    if (productsData == null && response['data'] is Map) {
      final data = Map<String, dynamic>.from(response['data'] as Map);
      productsData = data['productos'];
    }

    final products = productsData is List
        ? productsData
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList()
        : <Map<String, dynamic>>[];

    final db = await _dbService.open(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    await _dbService.upsertProducts(
      db,
      products,
    );
  }

  Future<void> clearDailyDatabase({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final db = await _dbService.open(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    await db.delete('sales');
    await db.delete('sale_items');
    await db.delete('sale_payments');
    await db.delete('sync_outbox');
  }
}