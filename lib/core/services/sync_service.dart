import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/local_db.dart';
import '../database/pos_db_service.dart';
import '../network/api_client.dart';
import '../storage/app_storage.dart';

class SyncResult {
  const SyncResult({
    required this.total,
    required this.synced,
    required this.failed,
    required this.skipped,
  });

  final int total;
  final int synced;
  final int failed;
  final int skipped;
}

/// Coordinador único de sincronización.
///
/// LocalDb:
///   histórico + ventas multidía + relación producto local/servidor.
///
/// PosDatabaseService:
///   operación de la base diaria.
///
/// API:
///   Laravel /api/v1/sync/offline
///   Laravel /api/v1/sync/pull
class SyncService {
  final ApiClient _apiClient;
  final PosDatabaseService _dayDb;
  final LocalDb _historyDb;

  SyncService({
    ApiClient? apiClient,
    PosDatabaseService? posDbService,
    LocalDb? localDb,
  }) : _apiClient = apiClient ?? ApiClient(),
       _dayDb = posDbService ?? PosDatabaseService(),
       _historyDb = localDb ?? LocalDb();

  static bool _running = false;

  static Timer? _automaticSyncTimer;
  static bool _automaticSyncStarted = false;

  // ============================================================
  // 🔐 AUTH
  // ============================================================

  /// Comprueba que exista una sesión autenticada válida antes
  /// de intentar sincronizar.
  ///
  /// Esto evita iniciar peticiones cuando el usuario ya fue
  /// desconectado por expiración de sesión.
  Future<bool> _hasAuthenticatedSession() async {
    final storage = AppStorage();

    final loggedIn = await storage.isLoggedIn();
    final token = await storage.getToken();

    return loggedIn && token != null && token.trim().isNotEmpty;
  }

  /// Devuelve una operación de venta histórica que estaba en
  /// "syncing" a "pending".
  ///
  /// No se marca como failed porque la causa fue la sesión.
  Future<void> _resetHistoricalSaleForAuthentication(int saleId) async {
    if (saleId <= 0) {
      return;
    }

    try {
      await _historyDb.resetSaleForRetry(saleId);

      print(
        '🔐 Venta histórica $saleId '
        'regresada a pendiente por autenticación.',
      );
    } catch (e) {
      print(
        '⚠️ No fue posible regresar la venta histórica '
        '$saleId a pendiente: $e',
      );
    }
  }

  /// Regresa un elemento del outbox diario de "syncing" a "queued".
  ///
  /// También devuelve la venta asociada a "pending".
  Future<void> _resetDayOutboxForAuthentication({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    required String uuidLocal,
  }) async {
    if (uuidLocal.trim().isEmpty) {
      return;
    }

    try {
      final db = await _dayDb.open(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      final now = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        await txn.update(
          'sync_outbox',
          {
            'status': 'queued',
            'next_retry_at': null,
            'error_message': null,
            'updated_at': now,
          },
          where: 'uuid_local = ?',
          whereArgs: [uuidLocal],
        );

        await txn.update(
          'sales',
          {
            'sync_status': 'pending',
            'next_retry_at': null,
            'error_message': null,
            'updated_at': now,
          },
          where: 'uuid_local = ?',
          whereArgs: [uuidLocal],
        );
      });

      print(
        '🔐 Outbox $uuidLocal '
        'regresado a queued por autenticación.',
      );
    } catch (e) {
      print(
        '⚠️ No fue posible regresar outbox $uuidLocal '
        'a queued: $e',
      );
    }
  }

  /// Regresa una operación de sync_queue de "syncing" a "pending".
  Future<void> _resetSyncQueueItemForAuthentication(int queueId) async {
    if (queueId <= 0) {
      return;
    }

    try {
      final db = await _historyDb.database;

      await db.update(
        'sync_queue',
        {
          'status': 'pending',
          'error_code': null,
          'error_message': null,
          'next_retry_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [queueId],
      );

      print(
        '🔐 Sync Queue $queueId '
        'regresada a pending por autenticación.',
      );
    } catch (e) {
      print(
        '⚠️ No fue posible regresar Sync Queue '
        '$queueId a pending: $e',
      );
    }
  }

  // ============================================================
  // SINCRONIZACIÓN AUTOMÁTICA
  // ============================================================

  /// Inicia la sincronización automática.
  ///
  /// La sincronización:
  ///
  ///   1. Se ejecuta inmediatamente.
  ///   2. Después se repite periódicamente.
  ///   3. Usa syncManual(), por lo que:
  ///
  ///      Sync Queue
  ///          ↓
  ///      Ventas pendientes
  ///          ↓
  ///      Pull servidor
  ///
  /// No bloquea la operación local del POS.
  void startAutomaticSync({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    Duration interval = const Duration(minutes: 2),
  }) {
    if (_automaticSyncStarted) {
      return;
    }

    _automaticSyncStarted = true;

    print('🔄 Sincronización automática iniciada.');

    unawaited(
      _runAutomaticSync(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      ),
    );

    _automaticSyncTimer?.cancel();

    _automaticSyncTimer = Timer.periodic(interval, (_) {
      unawaited(
        _runAutomaticSync(
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
        ),
      );
    });
  }

  /// Ejecuta una sincronización automática sin interferir
  /// con otra sincronización que ya esté en curso.
  Future<void> _runAutomaticSync({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    if (_running) {
      print(
        'ℹ️ Sincronización automática omitida: '
        'ya existe una sincronización en curso.',
      );

      return;
    }

    if (await AppStorage().isOfflineSession()) {
      print(
        'ℹ️ Sincronización automática omitida: '
        'sesión offline.',
      );

      return;
    }

    // 🔐 AUTH
    if (!await _hasAuthenticatedSession()) {
      print(
        'ℹ️ Sincronización automática omitida: '
        'no existe sesión autenticada.',
      );

      return;
    }

    try {
      print('🔄 Ejecutando sincronización automática...');

      final result = await syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      print(
        '✅ Sincronización automática finalizada: '
        'total=${result.total} '
        'synced=${result.synced} '
        'failed=${result.failed} '
        'skipped=${result.skipped}',
      );
    } on AuthenticationException catch (e) {
      // 🔐 AUTH
      // Nunca convertir 401 en failed.
      print(
        '🔐 Sincronización automática detenida: '
        'sesión no autenticada: $e',
      );
    } catch (e) {
      // La sincronización automática nunca debe cerrar
      // ni bloquear el POS por un error de red.
      print('⚠️ Error en sincronización automática: $e');
    }
  }

  /// Detiene la sincronización automática.
  void stopAutomaticSync() {
    _automaticSyncTimer?.cancel();
    _automaticSyncTimer = null;
    _automaticSyncStarted = false;

    print('⏹️ Sincronización automática detenida.');
  }

  // ============================================================
  // SINCRONIZACIÓN MANUAL
  // ============================================================
  //
  // CAMBIO AUTH:
  // Se conserva este método público porque es utilizado por:
  // - AutomaticSyncService
  // - DailyStatsScreen
  // - otras llamadas internas de SyncService
  //
  // La lógica real continúa centralizada en syncPendingSales().
  // Esto evita duplicar la lógica de sincronización.
  //
  Future<SyncResult> syncManual({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    int? limit,
  }) async {
    // ==========================================================
    // CAMBIO AUTH:
    // Si no existe una sesión autenticada, no se intenta llamar
    // nuevamente al servidor.
    //
    // syncPendingSales() también mantiene sus propias validaciones,
    // por lo que este método no altera la lógica existente.
    // ==========================================================
    final storage = AppStorage();

    final loggedIn = await storage.isLoggedIn();
    final token = await storage.getToken();

    if (!loggedIn || token == null || token.trim().isEmpty) {
      print(
        'ℹ️ Sincronización manual omitida: '
        'no existe una sesión autenticada.',
      );

      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    return syncPendingSales(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
      limit: limit,
    );
  }

  // ============================================================
  // SINCRONIZAR VENTAS PENDIENTES
  // ============================================================

  Future<SyncResult> syncPendingSales({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    int? limit,
  }) async {
    if (_running) {
      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    if (await AppStorage().isOfflineSession()) {
      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    // 🔐 AUTH
    if (!await _hasAuthenticatedSession()) {
      print(
        '🔐 Sincronización omitida: '
        'no existe sesión autenticada.',
      );

      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    _running = true;

    var total = 0;
    var synced = 0;
    var failed = 0;
    var skipped = 0;

    try {
      // ==========================================================
      // 1. SYNC QUEUE
      // ==========================================================

      final queueResult = await _syncPendingQueueInternal(limit: limit);

      total += queueResult.total;
      synced += queueResult.synced;
      failed += queueResult.failed;
      skipped += queueResult.skipped;

      // ==========================================================
      // 2. HISTÓRICO
      // ==========================================================

      final historical = await _historyDb.getPendingSalesReadyToSync(
        limit: limit,
      );

      for (final sale in historical) {
        total++;

        final ok = await _syncHistoricalSale(sale);

        if (ok) {
          synced++;
        } else {
          failed++;
        }
      }

      // ==========================================================
      // 3. OUTBOX DEL DÍA
      // ==========================================================

      final dayOutbox = await _dayDb.getPendingOutbox(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        limit: limit,
      );

      for (final item in dayOutbox) {
        total++;

        final ok = await _syncDayOutbox(companyId, userId, businessDate, item);

        if (ok) {
          synced++;
        } else {
          failed++;
        }
      }

      print(
        '✅ Sincronización general finalizada: '
        'total=$total '
        'synced=$synced '
        'failed=$failed '
        'skipped=$skipped',
      );

      return SyncResult(
        total: total,
        synced: synced,
        failed: failed,
        skipped: skipped,
      );
    } on AuthenticationException {
      // 🔐 AUTH
      // La operación actual ya fue regresada a pending/queued.
      // Se detiene inmediatamente toda la sincronización.
      print(
        '🔐 Sesión expirada durante sincronización. '
        'Los pendientes permanecen disponibles para reintento.',
      );

      rethrow;
    } finally {
      _running = false;
    }
  }

  // ============================================================
  // SINCRONIZAR UNA VENTA
  // ============================================================

  Future<bool> syncSaleById(int saleId) async {
    final sale = await _historyDb.getSaleById(saleId);

    if (sale == null) {
      return false;
    }

    if (sale['sync_status'] == 'synced') {
      return true;
    }

    // 🔐 AUTH
    if (!await _hasAuthenticatedSession()) {
      print(
        '🔐 No se puede sincronizar venta $saleId: '
        'no existe sesión autenticada.',
      );

      return false;
    }

    return _syncHistoricalSale(sale, force: true);
  }

  // ============================================================
  // SINCRONIZAR VENTA HISTÓRICA
  // ============================================================

  Future<bool> _syncHistoricalSale(
    Map<String, dynamic> sale, {
    bool force = false,
  }) async {
    final id = _toInt(sale['id']);

    if (id <= 0) {
      return false;
    }

    if (!force && sale['next_retry_at'] != null) {
      final nextRetry = DateTime.tryParse(sale['next_retry_at'].toString());

      if (nextRetry != null && nextRetry.isAfter(DateTime.now())) {
        return true;
      }
    }

    if (sale['status']?.toString().toLowerCase() == 'cancelled') {
      await _historyDb.markSaleAsSynced(
        id,
        serverResponse: {
          'server_id': sale['server_id'],
          'folio': sale['server_folio'],
        },
      );

      return true;
    }

    await _historyDb.markSaleSyncing(id);

    try {
      final venta = await _buildHistoricalPayload(sale);

      final payload = <String, dynamic>{
        'ventas': [venta],
      };

      print(
        '🔄 Sincronizando venta histórica '
        '${sale['uuid_local']}',
      );

      print('📦 Payload: $payload');

      final response = await _apiClient.syncOffline(payload);

      final errores = response['errores'];

      if (errores is List && errores.isNotEmpty) {
        throw Exception('El servidor rechazó la venta: $errores');
      }

      final procesadas = response['procesadas'];

      if (procesadas is List && procesadas.isEmpty) {
        throw Exception('El servidor no confirmó la venta sincronizada.');
      }

      await _applyHistoricalProductMappings(response);

      await _historyDb.markSaleAsSynced(id, serverResponse: response);

      return true;
    } on AuthenticationException {
      // 🔐 AUTH
      // IMPORTANTE:
      // NO usar markSaleSyncFailed().
      // La venta sigue pendiente y podrá reintentarse después
      // de iniciar sesión nuevamente.
      print(
        '🔐 Sesión expirada sincronizando venta histórica '
        '${sale['uuid_local']}.',
      );

      await _resetHistoricalSaleForAuthentication(id);

      rethrow;
    } catch (e) {
      print(
        '❌ Error sincronizando venta histórica '
        '${sale['uuid_local']}: $e',
      );

      await _historyDb.markSaleSyncFailed(id, e.toString());

      return false;
    }
  }

  // ============================================================
  // CONSTRUIR PAYLOAD HISTÓRICO
  // ============================================================

  Future<Map<String, dynamic>> _buildHistoricalPayload(
    Map<String, dynamic> sale,
  ) async {
    final saleId = _toInt(sale['id']);

    final items = await _historyDb.getSaleItemsBySaleId(saleId);

    final payments = await _historyDb.getSalePaymentsBySaleId(saleId);

    return _buildPayload(sale, items, payments);
  }

  // ============================================================
  // SINCRONIZAR OUTBOX DEL DÍA
  // ============================================================

  Future<bool> _syncDayOutbox(
    int companyId,
    int userId,
    DateTime date,
    Map<String, dynamic> item,
  ) async {
    final uuid = item['uuid_local']?.toString().trim() ?? '';

    if (uuid.isEmpty) {
      return false;
    }

    final attempts = _toInt(item['attempts']);

    try {
      final decoded = jsonDecode(item['payload']?.toString() ?? '{}');

      if (decoded is! Map) {
        throw const FormatException('Payload de sincronización inválido.');
      }

      final rawPayload = Map<String, dynamic>.from(decoded);

      final requestPayload = await _normalizeOfflinePayload(
        rawPayload,
        uuidLocal: uuid,
        businessDate: date,
        companyId: companyId,
        userId: userId,
      );

      final ventas = requestPayload['ventas'];

      if (ventas is! List || ventas.isEmpty) {
        throw const FormatException(
          'El outbox no contiene ventas para sincronizar.',
        );
      }

      print('🔄 Sincronizando outbox $uuid');

      final response = await _apiClient.syncOffline(requestPayload);

      final errores = response['errores'];

      if (errores is List && errores.isNotEmpty) {
        throw Exception('El servidor devolvió errores: $errores');
      }

      final procesadas = response['procesadas'];

      if (procesadas is List && procesadas.isEmpty) {
        throw Exception('El servidor no confirmó la operación offline.');
      }

      await _applyHistoricalProductMappings(response);

      await _dayDb.markOutboxSynced(
        companyId: companyId,
        userId: userId,
        businessDate: date,
        uuidLocal: uuid,
        serverResponse: response,
      );

      return true;
    } on AuthenticationException {
      // 🔐 AUTH
      // NO marcar como failed.
      // El outbox vuelve a queued y la venta a pending.
      print('🔐 Sesión expirada sincronizando outbox $uuid.');

      await _resetDayOutboxForAuthentication(
        companyId: companyId,
        userId: userId,
        businessDate: date,
        uuidLocal: uuid,
      );

      rethrow;
    } catch (e) {
      print('❌ Error sincronizando outbox $uuid: $e');

      await _dayDb.markOutboxFailed(
        companyId: companyId,
        userId: userId,
        businessDate: date,
        uuidLocal: uuid,
        error: e.toString(),
        attempts: attempts + 1,
      );

      return false;
    }
  }

  // ============================================================
  // NORMALIZAR PAYLOAD OFFLINE
  // ============================================================

  Future<Map<String, dynamic>> _normalizeOfflinePayload(
    Map<String, dynamic> payload, {
    required String uuidLocal,
    required DateTime businessDate,
    required int companyId,
    required int userId,
  }) async {
    final ventas = payload['ventas'];

    if (ventas is List) {
      final normalizedVentas = <Map<String, dynamic>>[];

      for (final item in ventas) {
        if (item is! Map) {
          continue;
        }

        final venta = Map<String, dynamic>.from(item);

        final currentUuid = venta['uuid_local']?.toString().trim() ?? '';

        venta['uuid_local'] = currentUuid.isNotEmpty ? currentUuid : uuidLocal;

        venta['fecha_venta'] = _normalizeSaleDate(
          venta['fecha_venta'] ??
              venta['business_date'] ??
              businessDate.toIso8601String(),
        );

        normalizedVentas.add(
          await _normalizeVenta(
            venta,
            companyId: companyId,
            userId: userId,
            businessDate: businessDate,
          ),
        );
      }

      return {'ventas': normalizedVentas};
    }

    final venta = Map<String, dynamic>.from(payload);

    venta['uuid_local'] = uuidLocal;

    venta['fecha_venta'] = _normalizeSaleDate(
      venta['fecha_venta'] ??
          venta['business_date'] ??
          businessDate.toIso8601String(),
    );

    return {
      'ventas': [
        await _normalizeVenta(
          venta,
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
        ),
      ],
    };
  }

  // ============================================================
  // NORMALIZAR VENTA
  // ============================================================

  Future<Map<String, dynamic>> _normalizeVenta(
    Map<String, dynamic> venta, {
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final normalized = <String, dynamic>{
      'uuid_local': venta['uuid_local']?.toString() ?? '',
      'cliente_id': venta['cliente_id'],
      'productos': await _normalizeProducts(
        venta['productos'],
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      ),
      'pagos': _normalizePayments(venta['pagos']),
      'forma_pago': venta['forma_pago'],
      'monto_pagado': venta['monto_pagado'],
      'referencia': venta['referencia'],
      'descuento_global': _toDouble(venta['descuento_global']),
      'impuesto_global': _toDouble(venta['impuesto_global']),
      'dispositivo_id': venta['dispositivo_id'],
      'fecha_venta': _normalizeSaleDate(venta['fecha_venta']),
    };

    normalized.removeWhere((key, value) => value == null);

    return normalized;
  }

  // ============================================================
  // PRODUCTOS DE VENTA DIARIA
  // ============================================================

  /// Normaliza productos provenientes del OUTBOX de la base diaria.
  ///
  /// IMPORTANTE:
  ///
  /// En PosDatabaseService:
  ///
  ///   products.id = ID REAL DEL SERVIDOR
  ///
  /// Por lo tanto:
  ///
  ///   product_id = server product ID
  ///
  /// NO debe interpretarse como LocalDb.products.id.
  ///
  /// LocalDb se consulta únicamente como respaldo por código cuando
  /// el producto diario no puede encontrarse en la base diaria.
  Future<List<Map<String, dynamic>>> _normalizeProducts(
    dynamic value, {
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    if (value is! List) {
      return [];
    }

    final result = <Map<String, dynamic>>[];

    Database? dayDatabase;

    try {
      dayDatabase = await _dayDb.open(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );
    } catch (e) {
      print(
        '⚠️ No fue posible abrir la base diaria '
        'para resolver productos: $e',
      );

      dayDatabase = null;
    }

    for (final raw in value) {
      if (raw is! Map) {
        continue;
      }

      final item = Map<String, dynamic>.from(raw);

      final explicitServerProductId = _toInt(
        item['producto_id'] ?? item['product_id'],
      );

      final localProductId = _toInt(
        item['producto_local_id'] ?? item['product_local_id'],
      );

      final cantidad = _toDouble(item['cantidad'] ?? item['quantity']);

      if (cantidad <= 0) {
        continue;
      }

      Map<String, dynamic>? product;

      final embeddedProduct = item['producto'];

      if (embeddedProduct is Map) {
        product = Map<String, dynamic>.from(embeddedProduct);
      }

      if (product == null &&
          dayDatabase != null &&
          explicitServerProductId > 0) {
        product = await _getDayProduct(dayDatabase, explicitServerProductId);
      }

      if (product == null && explicitServerProductId > 0) {
        product = await _historyDb.getProductByServerId(
          explicitServerProductId,
        );
      }

      if (product == null) {
        final codeCandidate = _firstNonEmpty(item['codigo'], item['code']);

        if (codeCandidate != null && codeCandidate.isNotEmpty) {
          product = await _historyDb.getProductByCode(codeCandidate);
        }
      }

      var serverProductId = explicitServerProductId;

      if (serverProductId <= 0) {
        serverProductId = _extractServerProductId(product);
      }

      final code = _firstNonEmpty(
        item['codigo'],
        item['code'],
        product?['code'],
        product?['codigo'],
      );

      final name = _firstNonEmpty(
        item['nombre'],
        item['name'],
        product?['name'],
        product?['nombre'],
      );

      final description = _firstNonEmpty(
        item['descripcion'],
        item['description'],
        product?['descripcion'],
        product?['description'],
      );

      final unitPrice = _toDouble(
        item['precio_unitario'] ??
            item['precio'] ??
            item['unit_price'] ??
            product?['price'] ??
            product?['precio'],
      );

      final cost = _toDouble(
        item['costo'] ?? item['cost'] ?? product?['cost'] ?? product?['costo'],
      );

      final tax = _toDouble(
        item['impuesto'] ??
            item['tax'] ??
            product?['tax'] ??
            product?['impuesto'],
      );

      final stock = _toDouble(item['stock'] ?? product?['stock']);

      final stockMinimo = _toDouble(
        item['stock_minimo'] ??
            item['stock_min'] ??
            product?['stock_minimo'] ??
            product?['stock_min'],
      );

      final activo = _toBool(
        item['activo'] ??
            item['active'] ??
            product?['activo'] ??
            product?['is_active'],
        defaultValue: true,
      );

      final isInventoriable = _extractInventoriable(item, product);

      print(
        '🔎 PRODUCTO VENTA DIARIA '
        'server_id=$serverProductId '
        'local_id=${localProductId > 0 ? localProductId : '-'} '
        'codigo=${code ?? '-'} '
        'nombre=${name ?? '-'}',
      );

      final line = <String, dynamic>{
        if (localProductId > 0) 'producto_local_id': localProductId,
        if (serverProductId > 0) 'producto_id': serverProductId,
        if (code != null && code.isNotEmpty) 'codigo': code,
        if (name != null && name.isNotEmpty) 'nombre': name,
        if (description != null && description.isNotEmpty)
          'descripcion': description,
        'cantidad': cantidad,
        'precio_unitario': unitPrice,
        'costo': cost,
        'impuesto': tax,
        'stock': stock,
        'stock_minimo': stockMinimo,
        'activo': activo,
        'is_inventariable': isInventoriable,
        'descuento': _toDouble(item['descuento']),
      };

      result.add(line);
    }

    return result;
  }

  // ============================================================
  // OBTENER PRODUCTO DE LA BASE DIARIA
  // ============================================================

  Future<Map<String, dynamic>?> _getDayProduct(
    Database db,
    int serverProductId,
  ) async {
    if (serverProductId <= 0) {
      return null;
    }

    final result = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [serverProductId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(result.first);
  }

  // ============================================================
  // MAPEAR PRODUCTOS LOCAL ↔ SERVIDOR
  // ============================================================

  Future<void> _applyHistoricalProductMappings(
    Map<String, dynamic> response,
  ) async {
    final rawMappings = response['productos_sincronizados'];

    if (rawMappings is! List || rawMappings.isEmpty) {
      return;
    }

    try {
      await _historyDb.applySyncProductMappings(rawMappings);

      print(
        '✅ Mapeos de productos aplicados: '
        '${rawMappings.length}',
      );
    } catch (e) {
      print(
        '⚠️ No fue posible aplicar los mapeos '
        'producto local/servidor: $e',
      );

      rethrow;
    }
  }

  // ============================================================
  // PAGOS
  // ============================================================

  List<Map<String, dynamic>> _normalizePayments(dynamic value) {
    if (value is! List) {
      return [];
    }

    final result = <Map<String, dynamic>>[];

    for (final raw in value) {
      if (raw is! Map) {
        continue;
      }

      final item = Map<String, dynamic>.from(raw);

      final method = item['forma_pago']?.toString().trim().isNotEmpty == true
          ? item['forma_pago'].toString()
          : item['method']?.toString() ?? 'Efectivo';

      final amount = _toDouble(item['monto'] ?? item['amount']);

      if (amount <= 0) {
        continue;
      }

      result.add({
        'forma_pago': _mapPaymentMethod(method),
        'monto': roundMoney(amount),
        'cambio': roundMoney(_toDouble(item['cambio'])),
        'referencia': item['referencia'],
      });
    }

    return result;
  }

  // ============================================================
  // CONSTRUIR PAYLOAD DESDE SQLITE
  // ============================================================

  Future<Map<String, dynamic>> _buildPayload(
    Map<String, dynamic> sale,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> payments,
  ) async {
    final total = _toDouble(sale['total']);

    final changeDue = _toDouble(sale['change_due']);

    final normalizedPayments = <Map<String, dynamic>>[];

    var cashAdjusted = false;
    var totalNetPayments = 0.0;

    for (final payment in payments) {
      final method = payment['method']?.toString() ?? 'Efectivo';

      final original = _toDouble(payment['amount']);

      if (original <= 0) {
        continue;
      }

      var amount = original;
      var change = 0.0;

      if (_isCash(method) && !cashAdjusted && changeDue > 0) {
        amount = original - changeDue;

        change = changeDue;

        cashAdjusted = true;
      }

      if (amount < 0) {
        amount = 0;
      }

      if (amount <= 0) {
        continue;
      }

      normalizedPayments.add({
        'forma_pago': _mapPaymentMethod(method),
        'monto': roundMoney(amount),
        'cambio': roundMoney(change),
        'referencia': payment['referencia'],
      });

      totalNetPayments += amount;
    }

    final difference = roundMoney(total - totalNetPayments);

    if (difference.abs() > 0.009) {
      if (normalizedPayments.isNotEmpty) {
        final first = normalizedPayments.first;

        first['monto'] = roundMoney(_toDouble(first['monto']) + difference);
      } else if (difference > 0) {
        normalizedPayments.add({
          'forma_pago': 'Efectivo',
          'monto': roundMoney(difference),
          'cambio': 0.0,
          'referencia': null,
        });
      }
    }

    final fechaVenta = _normalizeSaleDate(
      sale['fecha_venta'] ??
          sale['created_at'] ??
          sale['business_date'] ??
          DateTime.now().toIso8601String(),
    );

    final normalizedProducts = <Map<String, dynamic>>[];

    for (final item in items) {
      final localProductId = _toInt(
        item['producto_local_id'] ?? item['product_id'] ?? item['producto_id'],
      );

      final cantidad = _toDouble(item['quantity'] ?? item['cantidad']);

      if (localProductId <= 0 || cantidad <= 0) {
        continue;
      }

      final product = await _historyDb.getProductById(localProductId);

      final serverProductId = _extractServerProductId(product);

      final code = _firstNonEmpty(
        item['codigo'],
        item['code'],
        product?['code'],
        product?['codigo'],
      );

      final name = _firstNonEmpty(
        item['nombre'],
        item['name'],
        product?['name'],
        product?['nombre'],
      );

      final description = _firstNonEmpty(
        item['descripcion'],
        item['description'],
        product?['descripcion'],
        product?['description'],
      );

      final unitPrice = _toDouble(
        item['unit_price'] ??
            item['precio_unitario'] ??
            item['precio'] ??
            product?['price'] ??
            product?['precio'],
      );

      final cost = _toDouble(
        item['costo'] ?? item['cost'] ?? product?['cost'] ?? product?['costo'],
      );

      final tax = _toDouble(
        item['impuesto'] ??
            item['tax'] ??
            product?['tax'] ??
            product?['impuesto'],
      );

      final stock = _toDouble(item['stock'] ?? product?['stock']);

      final stockMinimo = _toDouble(
        item['stock_minimo'] ??
            item['stock_min'] ??
            product?['stock_minimo'] ??
            product?['stock_min'],
      );

      final activo = _toBool(
        item['activo'] ??
            item['active'] ??
            product?['activo'] ??
            product?['is_active'],
        defaultValue: true,
      );

      final isInventoriable = _extractInventoriable(item, product);

      print(
        '🔎 PRODUCTO HISTÓRICO '
        'local_id=$localProductId '
        'server_id=$serverProductId '
        'codigo=${code ?? '-'} '
        'nombre=${name ?? '-'}',
      );

      normalizedProducts.add({
        'producto_local_id': localProductId,
        if (serverProductId > 0) 'producto_id': serverProductId,
        if (code != null && code.isNotEmpty) 'codigo': code,
        if (name != null && name.isNotEmpty) 'nombre': name,
        if (description != null && description.isNotEmpty)
          'descripcion': description,
        'cantidad': cantidad,
        'precio_unitario': unitPrice,
        'costo': cost,
        'impuesto': tax,
        'stock': stock,
        'stock_minimo': stockMinimo,
        'activo': activo,
        'is_inventariable': isInventoriable,
        'descuento': _toDouble(item['descuento']),
      });
    }

    return {
      'uuid_local': sale['uuid_local']?.toString().trim() ?? '',
      'cliente_id': sale['cliente_id'],
      'productos': normalizedProducts,
      'pagos': normalizedPayments,
      'descuento_global': _toDouble(sale['descuento_global']),
      'impuesto_global': _toDouble(sale['impuesto_global']),
      'dispositivo_id': sale['dispositivo_id'],
      'fecha_venta': fechaVenta,
    }..removeWhere((key, value) => value == null);
  }

  // ============================================================
  // ARCHIVAR PENDIENTES DEL DÍA
  // ============================================================

  Future<int> archivePendingSalesFromDay({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final db = await _dayDb.open(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    final rows = await db.query(
      'sales',
      where: "sync_status IN ('pending','failed','syncing')",
      orderBy: 'created_at ASC',
    );

    var count = 0;

    for (final sale in rows) {
      final uuid = sale['uuid_local']?.toString().trim() ?? '';

      if (uuid.isEmpty) {
        continue;
      }

      final items = await _dayDb.getSaleItems(db, _toInt(sale['id']));

      final payments = await _dayDb.getSalePayments(db, _toInt(sale['id']));

      await _historyDb.archiveDailySale(
        sale: sale,
        items: items,
        payments: payments,
      );

      count++;
    }

    return count;
  }

  // ============================================================
  // SYNC QUEUE
  // ============================================================

  Future<SyncResult> syncPendingQueue({int? limit}) async {
    if (_running) {
      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    if (await AppStorage().isOfflineSession()) {
      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    // 🔐 AUTH
    if (!await _hasAuthenticatedSession()) {
      print(
        '🔐 Sync Queue omitida: '
        'no existe sesión autenticada.',
      );

      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    _running = true;

    try {
      return await _syncPendingQueueInternal(limit: limit);
    } finally {
      _running = false;
    }
  }

  Future<SyncResult> _syncPendingQueueInternal({int? limit}) async {
    var total = 0;
    var synced = 0;
    var failed = 0;
    var skipped = 0;

    final queue = await _historyDb.getPendingSyncQueue(limit: limit);

    if (queue.isEmpty) {
      print('ℹ️ Sync Queue vacía.');

      return const SyncResult(total: 0, synced: 0, failed: 0, skipped: 0);
    }

    final categories = queue
        .where(
          (item) =>
              item['entity_type']?.toString().trim().toLowerCase() ==
              'category',
        )
        .toList();

    final products = queue
        .where(
          (item) =>
              item['entity_type']?.toString().trim().toLowerCase() == 'product',
        )
        .toList();

    final ignored = queue.where((item) {
      final type = item['entity_type']?.toString().trim().toLowerCase() ?? '';

      return type != 'category' && type != 'product';
    }).toList();

    skipped += ignored.length;

    if (ignored.isNotEmpty) {
      print(
        '⚠️ Sync Queue: '
        '${ignored.length} operaciones ignoradas '
        'por entity_type no soportado.',
      );
    }

    // ==========================================================
    // 1. CATEGORÍAS
    // ==========================================================

    for (final item in categories) {
      total++;

      final result = await _processCategoryQueueItem(item);

      if (result) {
        synced++;
      } else {
        failed++;
      }
    }

    // ==========================================================
    // 2. PRODUCTOS
    // ==========================================================

    for (final item in products) {
      total++;

      final result = await _processProductQueueItem(item);

      if (result) {
        synced++;
      } else {
        failed++;
      }
    }

    print(
      '✅ Sync Queue finalizada: '
      'total=$total '
      'synced=$synced '
      'failed=$failed '
      'skipped=$skipped',
    );

    return SyncResult(
      total: total,
      synced: synced,
      failed: failed,
      skipped: skipped,
    );
  }

  // ============================================================
  // PROCESAR CATEGORÍA
  // ============================================================

  Future<bool> _processCategoryQueueItem(Map<String, dynamic> item) async {
    final queueId = _toInt(item['id']);

    if (queueId <= 0) {
      return false;
    }

    await _historyDb.markSyncQueueSyncing(queueId);

    try {
      final payloadJson = item['payload_json']?.toString() ?? '{}';

      final decoded = jsonDecode(payloadJson);

      if (decoded is! Map) {
        throw const FormatException('Payload de categoría inválido.');
      }

      final payload = Map<String, dynamic>.from(decoded);

      final localId = _toInt(payload['local_id'] ?? item['entity_id_local']);

      if (localId <= 0) {
        throw const FormatException('La categoría no tiene local_id válido.');
      }

      final existingServerId = _toInt(payload['server_id']);

      final empresaId = _toInt(payload['empresa_id'] ?? item['empresa_id']);

      final nombre = payload['nombre']?.toString().trim() ?? '';

      if (nombre.isEmpty) {
        throw const FormatException('La categoría no tiene nombre.');
      }

      final codigo = payload['codigo']?.toString().trim();

      final activo = _toBool(payload['activo'], defaultValue: true);

      final serverPayload = <String, dynamic>{
        if (empresaId > 0) 'empresa_id': empresaId,
        'nombre': nombre,
        'activo': activo,
        if (codigo != null && codigo.isNotEmpty) 'codigo': codigo,
      };

      print(
        '🔄 Sync categoría '
        'local=$localId '
        'server='
        '${existingServerId > 0 ? existingServerId : 'NUEVA'}',
      );

      final response = existingServerId > 0
          ? await _apiClient.updateCategory(existingServerId, serverPayload)
          : await _apiClient.createCategory(serverPayload);

      final serverId = _extractServerId(response);

      final resolvedServerId = serverId > 0 ? serverId : existingServerId;

      if (resolvedServerId <= 0) {
        throw Exception(
          'El servidor no devolvió server_id '
          'para la categoría.',
        );
      }

      final db = await _historyDb.database;

      await db.update(
        'categories',
        {
          'server_id': resolvedServerId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [localId],
      );

      await _historyDb.markSyncQueueSynced(
        queueId,
        serverId: resolvedServerId,
        serverUuid: _extractServerUuid(response),
        serverStatus: 'accepted',
        serverReceivedAt: DateTime.now().toIso8601String(),
      );

      print(
        '✅ Categoría sincronizada '
        'local=$localId '
        'server=$resolvedServerId',
      );

      return true;
    } on AuthenticationException {
      // 🔐 AUTH
      // NO marcar como failed.
      await _resetSyncQueueItemForAuthentication(queueId);

      print(
        '🔐 Sesión expirada sincronizando categoría '
        '${item['uuid_local']}.',
      );

      rethrow;
    } catch (e) {
      print(
        '❌ Error sincronizando categoría '
        '${item['uuid_local']}: $e',
      );

      await _historyDb.markSyncQueueFailed(queueId, errorMessage: e.toString());

      return false;
    }
  }

  // ============================================================
  // PROCESAR PRODUCTO
  // ============================================================

  Future<bool> _processProductQueueItem(Map<String, dynamic> item) async {
    final queueId = _toInt(item['id']);

    if (queueId <= 0) {
      return false;
    }

    await _historyDb.markSyncQueueSyncing(queueId);

    try {
      final payloadJson = item['payload_json']?.toString() ?? '{}';

      final decoded = jsonDecode(payloadJson);

      if (decoded is! Map) {
        throw const FormatException('Payload de producto inválido.');
      }

      final payload = Map<String, dynamic>.from(decoded);

      final localId = _toInt(payload['local_id'] ?? item['entity_id_local']);

      if (localId <= 0) {
        throw const FormatException('El producto no tiene local_id válido.');
      }

      final existingServerId = _toInt(payload['server_id']);

      final categoryLocalId = _toInt(
        payload['categoria_local_id'] ?? payload['category_id'],
      );

      // ----------------------------------------------------------
      // RESOLVER CATEGORÍA LOCAL → SERVIDOR
      // ----------------------------------------------------------

      int? categoryServerId;

      if (categoryLocalId > 0) {
        final db = await _historyDb.database;

        final rows = await db.query(
          'categories',
          columns: ['id', 'server_id'],
          where: 'id = ?',
          whereArgs: [categoryLocalId],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception(
            'No existe la categoría local '
            '$categoryLocalId.',
          );
        }

        categoryServerId = _toInt(rows.first['server_id']);

        if (categoryServerId <= 0) {
          throw Exception(
            'La categoría local '
            '$categoryLocalId '
            'todavía no tiene server_id.',
          );
        }
      }

      final empresaId = _toInt(payload['empresa_id'] ?? item['empresa_id']);

      final codigo = payload['codigo']?.toString().trim() ?? '';

      final nombre = payload['nombre']?.toString().trim() ?? '';

      if (codigo.isEmpty) {
        throw const FormatException('El producto no tiene código.');
      }

      if (nombre.isEmpty) {
        throw const FormatException('El producto no tiene nombre.');
      }

      final precio = _toDouble(payload['precio']);

      final stock = _toDouble(payload['stock']);

      final activo = _toBool(payload['activo'], defaultValue: true);

      final inventariable = _toBool(
        payload['inventariable'],
        defaultValue: true,
      );

      final rawData = payload['data'];

      final serverPayload = <String, dynamic>{
        if (rawData is Map) ...Map<String, dynamic>.from(rawData),
        if (empresaId > 0) 'empresa_id': empresaId,
        'codigo': codigo,
        'nombre': nombre,
        'precio': precio,
        'stock': stock,
        'activo': activo,
        'is_inventariable': inventariable,
        if (categoryServerId != null) 'categoria_id': categoryServerId,
      };

      print(
        '🔄 Sync producto '
        'local=$localId '
        'server='
        '${existingServerId > 0 ? existingServerId : 'NUEVO'} '
        'categoria='
        '$categoryLocalId→'
        '${categoryServerId ?? '-'}',
      );

      print(
        '📤 PRODUCT PAYLOAD '
        'local=$localId: '
        '${jsonEncode(serverPayload)}',
      );

      final response = existingServerId > 0
          ? await _apiClient.updateProduct(existingServerId, serverPayload)
          : await _apiClient.createProduct(serverPayload);

      final serverId = _extractServerId(response);

      final resolvedServerId = serverId > 0 ? serverId : existingServerId;

      if (resolvedServerId <= 0) {
        throw Exception(
          'El servidor no devolvió server_id '
          'para el producto.',
        );
      }

      await _historyDb.setProductServerId(
        localId: localId,
        serverId: resolvedServerId,
      );

      await _historyDb.markSyncQueueSynced(
        queueId,
        serverId: resolvedServerId,
        serverUuid: _extractServerUuid(response),
        serverStatus: 'accepted',
        serverReceivedAt: DateTime.now().toIso8601String(),
      );

      print(
        '✅ Producto sincronizado '
        'local=$localId '
        'server=$resolvedServerId',
      );

      return true;
    } on AuthenticationException {
      // 🔐 AUTH
      // NO marcar como failed.
      await _resetSyncQueueItemForAuthentication(queueId);

      print(
        '🔐 Sesión expirada sincronizando producto '
        '${item['uuid_local']}.',
      );

      rethrow;
    } catch (e) {
      print(
        '❌ Error sincronizando producto '
        '${item['uuid_local']}: $e',
      );

      await _historyDb.markSyncQueueFailed(queueId, errorMessage: e.toString());

      return false;
    }
  }

  // ============================================================
  // EXTRAER SERVER ID DE RESPUESTA
  // ============================================================

  int _extractServerId(dynamic response) {
    if (response is! Map) {
      return 0;
    }

    final map = Map<String, dynamic>.from(response);

    final direct = _toInt(map['server_id'] ?? map['id']);

    if (direct > 0) {
      return direct;
    }

    final data = map['data'];

    if (data is Map) {
      final nested = _toInt(data['server_id'] ?? data['id']);

      if (nested > 0) {
        return nested;
      }
    }

    for (final key in const ['categoria', 'category', 'producto', 'product']) {
      final entity = map[key];

      if (entity is Map) {
        final nested = _toInt(entity['server_id'] ?? entity['id']);

        if (nested > 0) {
          return nested;
        }
      }
    }

    return 0;
  }

  // ============================================================
  // EXTRAER UUID DEL SERVIDOR
  // ============================================================

  String? _extractServerUuid(dynamic response) {
    if (response is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(response);

    final direct = map['server_uuid'] ?? map['uuid'];

    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }

    final data = map['data'];

    if (data is Map) {
      final uuid = data['server_uuid'] ?? data['uuid'];

      if (uuid != null && uuid.toString().trim().isNotEmpty) {
        return uuid.toString().trim();
      }
    }

    return null;
  }

  // ============================================================
  // SINCRONIZAR CATÁLOGOS
  // ============================================================

  Future<void> syncCatalogs({bool force = false}) async {
    final versions = await _historyDb.getCatalogVersions();

    final cursor = await _historyDb.getCatalogCursor('global');

    final String? catalogDate = force ? null : cursor ?? versions['global'];

    final DateTime? desde = catalogDate == null || catalogDate.trim().isEmpty
        ? null
        : DateTime.tryParse(catalogDate);

    final response = await _apiClient.getCatalog(
      desde: desde?.toIso8601String(),
    );

    if (response.isEmpty) {
      return;
    }

    await _historyDb.syncCatalogs(response);

    final nextCursor =
        response['next_cursor']?.toString() ?? response['cursor']?.toString();

    final nextVersion =
        response['version']?.toString() ??
        (response['versiones'] is Map
            ? (response['versiones'] as Map)['global']?.toString()
            : null);

    if (nextCursor != null || nextVersion != null) {
      await _historyDb.setCatalogVersion(
        'global',
        nextVersion,
        cursor: nextCursor,
      );
    }
  }

  // ============================================================
  // PULL DE CAMBIOS DEL SERVIDOR
  // ============================================================

  Future<Map<String, dynamic>> syncPull() async {
    final cursor = await _historyDb.getCatalogCursor('server_changes');

    print(
      '⬇️ Iniciando SYNC PULL '
      'cursor=${cursor ?? 'SIN_CURSOR'}',
    );

    // 🔐 AUTH
    // AuthenticationException se propaga intencionalmente.
    // No se convierte en un error genérico porque el cursor NO
    // debe avanzar cuando la sesión expiró.
    final response = await _apiClient.syncPull(cursor: cursor);

    print('⬇️ SYNC PULL recibido.');

    final cambios = response['cambios'];

    final tombstones = response['tombstones'];

    final serverData = <String, dynamic>{};

    List<Map<String, dynamic>> ventas = <Map<String, dynamic>>[];

    if (cambios is Map) {
      final cambiosMap = Map<String, dynamic>.from(cambios);

      final rawVentas = cambiosMap.remove('ventas');

      if (rawVentas is List) {
        ventas = rawVentas
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where((venta) => _serverSaleUuid(venta).isNotEmpty)
            .toList();
      }

      serverData.addAll(cambiosMap);
      final empresa = cambiosMap['empresa'];

      print('🏢 EMPRESA RECIBIDA EN SYNC: $empresa');
    }

    print(
      '⬇️ Ventas recibidas del servidor: '
      '${ventas.length}',
    );

    if (tombstones != null) {
      serverData['tombstones'] = tombstones;
    }

    if (serverData.isNotEmpty) {
      await _historyDb.syncCatalogs(serverData);
    }

    final empresaLocal = await _historyDb.getCompany();

    print('🏢 EMPRESA LOCAL: $empresaLocal');

    if (ventas.isNotEmpty) {
      await _upsertServerSales(ventas);
    }

    final nextCursor =
        response['next_cursor']?.toString() ?? response['cursor']?.toString();

    if (nextCursor != null && nextCursor.isNotEmpty) {
      await _historyDb.setCatalogVersion(
        'server_changes',
        null,
        cursor: nextCursor,
      );

      print(
        '✅ Cursor actualizado: '
        '$nextCursor',
      );
    }

    print('✅ SYNC PULL finalizado.');

    return response;
  }

  // ============================================================
  // UPSERT DE VENTAS RECIBIDAS
  // ============================================================

  Future<void> _upsertServerSales(List<Map<String, dynamic>> ventas) async {
    final db = await _historyDb.database;

    final uniqueSales = <String, Map<String, dynamic>>{};

    for (final venta in ventas) {
      final uuid = _serverSaleUuid(venta);

      if (uuid.isEmpty) {
        continue;
      }

      uniqueSales[uuid] = venta;
    }

    if (uniqueSales.isEmpty) {
      print(
        'ℹ️ No existen ventas válidas '
        'para aplicar.',
      );

      return;
    }

    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    await db.transaction((txn) async {
      for (final venta in uniqueSales.values) {
        final result = await _upsertServerSale(txn, venta);

        switch (result) {
          case 'inserted':
            inserted++;
            break;

          case 'updated':
            updated++;
            break;

          case 'skipped':
            skipped++;
            break;
        }
      }
    });

    print(
      '✅ Ventas servidor aplicadas: '
      'insertadas=$inserted '
      'actualizadas=$updated '
      'omitidas=$skipped',
    );
  }

  // ============================================================
  // UPSERT INDIVIDUAL
  // ============================================================

  Future<String> _upsertServerSale(
    dynamic txn,
    Map<String, dynamic> venta,
  ) async {
    final uuid = _serverSaleUuid(venta);

    if (uuid.isEmpty) {
      return 'skipped';
    }

    final existing = await txn.query(
      'sales',
      where: 'uuid_local = ?',
      whereArgs: [uuid],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final localSale = Map<String, dynamic>.from(existing.first);

      final localId = _toInt(localSale['id']);

      if (_isLocalSalePending(localSale)) {
        print(
          '⚠️ Venta $uuid '
          'pendiente localmente. '
          'No se sobrescribe.',
        );

        return 'skipped';
      }

      await _updateExistingServerSale(txn, localId, venta);

      return 'updated';
    }

    final saleId = await _insertServerSale(txn, venta);

    await _replaceServerSaleChildren(txn, saleId, venta);

    return 'inserted';
  }

  // ============================================================
  // INSERTAR VENTA SERVIDOR
  // ============================================================

  Future<int> _insertServerSale(dynamic txn, Map<String, dynamic> venta) async {
    final uuid = _serverSaleUuid(venta);

    final estado = venta['estado']?.toString().trim() ?? 'pagado';

    final payments = _serverPayments(venta);

    final paymentMethod = payments.isNotEmpty ? payments.first['method'] : null;

    final cashReceived = _cashReceived(payments);

    final changeDue = _cashChange(payments);

    return txn.insert('sales', {
      'uuid_local': uuid,
      'total': _toDouble(venta['total']),
      'status': _normalizeSaleStatus(estado),
      'sync_status': 'synced',
      'payment_method': paymentMethod,
      'cash_received': cashReceived,
      'change_due': changeDue,
      'mesa_id': venta['mesa_id'],
      'mesa_nombre': venta['mesa_nombre']?.toString(),
      'created_at': _serverLocalDate(venta['created_at'] ?? venta['fecha']),
      'updated_at': _serverLocalDate(
        venta['updated_at'] ?? venta['created_at'] ?? venta['fecha'],
      ),
      'paid_at': estado.toLowerCase() == 'pagado'
          ? _serverLocalDate(venta['fecha'] ?? venta['created_at'])
          : null,
    });
  }

  // ============================================================
  // ACTUALIZAR VENTA SERVIDOR
  // ============================================================

  Future<void> _updateExistingServerSale(
    dynamic txn,
    int saleId,
    Map<String, dynamic> venta,
  ) async {
    if (saleId <= 0) {
      return;
    }

    final estado = venta['estado']?.toString().trim() ?? 'pagado';

    final payments = _serverPayments(venta);

    final paymentMethod = payments.isNotEmpty ? payments.first['method'] : null;

    await txn.update(
      'sales',
      {
        'total': _toDouble(venta['total']),
        'status': _normalizeSaleStatus(estado),
        'sync_status': 'synced',
        'payment_method': paymentMethod,
        'cash_received': _cashReceived(payments),
        'change_due': _cashChange(payments),
        'mesa_id': venta['mesa_id'],
        'mesa_nombre': venta['mesa_nombre']?.toString(),
        'created_at': _serverLocalDate(venta['created_at'] ?? venta['fecha']),
        'updated_at': _serverLocalDate(
          venta['updated_at'] ?? venta['created_at'] ?? venta['fecha'],
        ),
        'paid_at': estado.toLowerCase() == 'pagado'
            ? _serverLocalDate(venta['fecha'] ?? venta['created_at'])
            : null,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    await _replaceServerSaleChildren(txn, saleId, venta);
  }

  // ============================================================
  // REEMPLAZAR DETALLES Y PAGOS
  // ============================================================

  Future<void> _replaceServerSaleChildren(
    dynamic txn,
    int saleId,
    Map<String, dynamic> venta,
  ) async {
    if (saleId <= 0) {
      return;
    }

    await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);

    await txn.delete(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );

    final detalles = venta['detalles'];

    if (detalles is List) {
      for (final raw in detalles) {
        if (raw is! Map) {
          continue;
        }

        final detalle = Map<String, dynamic>.from(raw);

        final productId = _toInt(detalle['producto_id']);

        final quantity = _toDouble(detalle['cantidad']);

        final unitPrice = _toDouble(
          detalle['precio'] ?? detalle['precio_unitario'],
        );

        final total = _toDouble(detalle['total']);

        if (productId <= 0 || quantity <= 0) {
          continue;
        }

        final producto = detalle['producto'];

        String? name;

        if (producto is Map) {
          name = producto['nombre']?.toString() ?? producto['name']?.toString();
        }

        name ??= detalle['nombre']?.toString() ?? detalle['name']?.toString();

        final itemTotal = total > 0 ? total : roundMoney(quantity * unitPrice);

        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': productId,
          'name': name ?? 'Producto',
          'quantity': quantity,
          'unit_price': unitPrice,
          'total': itemTotal,
        });
      }
    }

    final pagos = venta['pagos'];

    if (pagos is List) {
      for (final raw in pagos) {
        if (raw is! Map) {
          continue;
        }

        final pago = Map<String, dynamic>.from(raw);

        final method = pago['forma_pago']?.toString().trim().isNotEmpty == true
            ? pago['forma_pago'].toString()
            : pago['method']?.toString() ?? 'Efectivo';

        final amount = _toDouble(pago['monto'] ?? pago['amount']);

        if (amount <= 0) {
          continue;
        }

        await txn.insert('sale_payments', {
          'sale_id': saleId,
          'method': _mapPaymentMethod(method),
          'amount': roundMoney(amount),
        });
      }
    }
  }

  // ============================================================
  // UUID
  // ============================================================

  String _serverSaleUuid(Map<String, dynamic> venta) {
    return (venta['uuid'] ?? venta['uuid_local']).toString().trim();
  }

  // ============================================================
  // NO PISAR VENTA PENDIENTE
  // ============================================================

  bool _isLocalSalePending(Map<String, dynamic> sale) {
    final syncStatus = sale['sync_status']?.toString().trim().toLowerCase();

    return syncStatus == null ||
        syncStatus.isEmpty ||
        syncStatus == 'pending' ||
        syncStatus == 'syncing' ||
        syncStatus == 'failed';
  }

  // ============================================================
  // PAGOS SERVIDOR
  // ============================================================

  List<Map<String, dynamic>> _serverPayments(Map<String, dynamic> venta) {
    final raw = venta['pagos'];

    if (raw is! List) {
      return [];
    }

    final result = <Map<String, dynamic>>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final pago = Map<String, dynamic>.from(item);

      final method =
          pago['forma_pago']?.toString() ??
          pago['method']?.toString() ??
          'Efectivo';

      final amount = _toDouble(pago['monto'] ?? pago['amount']);

      if (amount <= 0) {
        continue;
      }

      result.add({
        'method': _mapPaymentMethod(method),
        'amount': roundMoney(amount),
        'cambio': roundMoney(_toDouble(pago['cambio'])),
      });
    }

    return result;
  }

  // ============================================================
  // EFECTIVO RECIBIDO
  // ============================================================

  double _cashReceived(List<Map<String, dynamic>> payments) {
    var total = 0.0;

    for (final payment in payments) {
      final method = payment['method']?.toString() ?? '';

      if (_isCash(method)) {
        total += _toDouble(payment['amount']) + _toDouble(payment['cambio']);
      }
    }

    return roundMoney(total);
  }

  // ============================================================
  // CAMBIO
  // ============================================================

  double _cashChange(List<Map<String, dynamic>> payments) {
    var total = 0.0;

    for (final payment in payments) {
      total += _toDouble(payment['cambio']);
    }

    return roundMoney(total);
  }

  // ============================================================
  // ESTADO LOCAL
  // ============================================================

  String _normalizeSaleStatus(String status) {
    final normalized = status.trim().toLowerCase();

    switch (normalized) {
      case 'paid':
      case 'pagado':
      case 'pagada':
      case 'completed':
      case 'completada':
        return 'paid';

      case 'cancelled':
      case 'canceled':
      case 'cancelado':
      case 'cancelada':
      case 'anulado':
      case 'anulada':
        return 'cancelled';

      case 'pending':
      case 'pendiente':
        return 'pending';

      default:
        return status.trim().isEmpty ? 'paid' : status;
    }
  }

  // ============================================================
  // FECHA ISO NORMALIZADA
  // ============================================================

  String _normalizeSaleDate(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    }

    final text = value?.toString().trim() ?? '';

    if (text.isEmpty) {
      return DateTime.now().toIso8601String();
    }

    final parsed = DateTime.tryParse(text);

    if (parsed != null) {
      return parsed.toIso8601String();
    }

    return text;
  }

  // ============================================================
  // FECHA DEL SERVIDOR → HORA LOCAL
  // ============================================================

  String _serverLocalDate(dynamic value) {
    if (value is DateTime) {
      return value.toLocal().toIso8601String();
    }

    final text = value?.toString().trim() ?? '';

    if (text.isEmpty) {
      return DateTime.now().toIso8601String();
    }

    final parsed = DateTime.tryParse(text);

    if (parsed == null) {
      return text;
    }

    return parsed.toLocal().toIso8601String();
  }

  // ============================================================
  // EXTRAER SERVER ID DEL PRODUCTO
  // ============================================================

  int _extractServerProductId(Map<String, dynamic>? product) {
    if (product == null) {
      return 0;
    }

    final serverId = _toInt(
      product['server_id'] ?? product['producto_server_id'],
    );

    if (serverId > 0) {
      return serverId;
    }

    if (!product.containsKey('server_id') &&
        !product.containsKey('producto_server_id')) {
      return _toInt(product['id']);
    }

    return 0;
  }

  // ============================================================
  // PRIMER VALOR NO VACÍO
  // ============================================================

  String? _firstNonEmpty(dynamic a, dynamic b, [dynamic c, dynamic d]) {
    final values = [a, b, c, d];

    for (final value in values) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        return text;
      }
    }

    return null;
  }

  // ============================================================
  // INVENTARIO
  // ============================================================

  bool _extractInventoriable(dynamic item, Map<String, dynamic>? product) {
    dynamic value;

    if (item is Map) {
      value =
          item['is_inventariable'] ??
          item['isInventoriable'] ??
          item['inventariable'];
    }

    if (value == null && product != null) {
      value =
          product['is_inventariable'] ??
          product['isInventoriable'] ??
          product['inventariable'];
    }

    if (value == null && product != null) {
      final rawDataJson = product['data_json'];

      if (rawDataJson is String && rawDataJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawDataJson);

          if (decoded is Map) {
            value =
                decoded['is_inventariable'] ??
                decoded['isInventoriable'] ??
                decoded['inventariable'];
          }
        } catch (_) {}
      }
    }

    return _toBool(value, defaultValue: true);
  }

  // ============================================================
  // BOOLEAN
  // ============================================================

  bool _toBool(dynamic value, {bool defaultValue = false}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase() ?? '';

    if (text == 'true' ||
        text == '1' ||
        text == 'yes' ||
        text == 'si' ||
        text == 'sí') {
      return true;
    }

    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }

    return defaultValue;
  }

  // ============================================================
  // CONVERSION
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    var text = value?.toString() ?? '';

    text = text.replaceAll(',', '.');

    return double.tryParse(text) ?? 0.0;
  }

  double roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  bool _isCash(String method) {
    return method.trim().toLowerCase() == 'efectivo';
  }

  // ============================================================
  // MAPEAR FORMAS DE PAGO
  // ============================================================

  String _mapPaymentMethod(String method) {
    final normalized = method.trim().toLowerCase();

    if (normalized == 'efectivo') {
      return 'Efectivo';
    }

    if (normalized == 'tarjeta' ||
        normalized == 'tarjeta crédito' ||
        normalized == 'tarjeta credito') {
      return 'Tarjeta Crédito';
    }

    if (normalized == 'tarjeta débito' || normalized == 'tarjeta debito') {
      return 'Tarjeta Débito';
    }

    if (normalized == 'transferencia') {
      return 'Transferencia';
    }

    if (normalized == 'crédito' || normalized == 'credito') {
      return 'Crédito';
    }

    if (normalized == 'cheque') {
      return 'Cheque';
    }

    return 'Otro';
  }
}
