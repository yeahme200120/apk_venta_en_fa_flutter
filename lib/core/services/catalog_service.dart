import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class CatalogService {
  final ApiClient _apiClient;
  final PosDatabaseService _dbService;

  CatalogService({ApiClient? apiClient, PosDatabaseService? dbService})
      : _apiClient = apiClient ?? ApiClient(),
        _dbService = dbService ?? PosDatabaseService();

  Future<List<Map<String, dynamic>>> syncCatalog({required int companyId, required int userId, DateTime? businessDate, bool force = false}) async {
    final response = await _apiClient.getCatalog(desde: force ? null : null);
    final data = response['data'] is Map ? Map<String, dynamic>.from(response['data']) : response;
    final raw = data['productos'];
    final products = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    final db = await _dbService.open(companyId: companyId, userId: userId, businessDate: businessDate ?? DateTime.now());
    await _dbService.upsertProducts(db, products);
    return products;
  }

  Future<List<Map<String, dynamic>>> downloadCatalogForToday({required int companyId, required int userId, DateTime? businessDate}) =>
      syncCatalog(companyId: companyId, userId: userId, businessDate: businessDate ?? DateTime.now(), force: true);
}
