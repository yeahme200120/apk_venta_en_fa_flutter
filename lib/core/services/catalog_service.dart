import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class CatalogService {
  final ApiClient _apiClient;

  CatalogService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> syncCatalog({
    required int companyId,
    required int userId,
    DateTime? businessDate,
  }) async {
    final response = await _apiClient.getCatalog();

    // El endpoint /api/v1/catalogos devuelve el catálogo completo.
    // Aquí solamente necesitamos la lista de productos.
    dynamic productsData = response['productos'];

    // Soporte por si Laravel envuelve la respuesta dentro de "data".
    if (productsData == null && response['data'] is Map) {
      final data = Map<String, dynamic>.from(response['data'] as Map);
      productsData = data['productos'];
    }

    final remoteProducts = productsData is List
        ? productsData
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList()
        : <Map<String, dynamic>>[];

    final db = await PosDatabaseService().open(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate ?? DateTime.now(),
    );

    await PosDatabaseService().upsertProducts(
      db,
      remoteProducts,
    );

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