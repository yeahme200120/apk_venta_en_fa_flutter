import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class CatalogService {
  final ApiClient _apiClient;

  CatalogService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> syncCatalog({
    required int companyId,
    required int userId,
    DateTime? businessDate,
  }) async {
    final remoteProducts = await _apiClient.getCatalog();

    final db = await PosDatabaseService().open(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate ?? DateTime.now(),
    );

    await PosDatabaseService().upsertProducts(db, remoteProducts);

    return remoteProducts;
  }

  Future<List<Map<String, dynamic>>> downloadCatalogForToday({
    required int companyId,
    required int userId,
    DateTime? businessDate,
  }) async {
    return syncCatalog(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate ?? DateTime.now(),
    );
  }
}
