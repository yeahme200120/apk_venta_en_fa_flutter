import 'dart:async';
import 'dart:convert';

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
///   histórico + ventas multidía.
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
  })  : _apiClient = apiClient ?? ApiClient(),
        _dayDb = posDbService ?? PosDatabaseService(),
        _historyDb = localDb ?? LocalDb();

  static bool _running = false;

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
      return const SyncResult(
        total: 0,
        synced: 0,
        failed: 0,
        skipped: 0,
      );
    }

    if (await AppStorage().isOfflineSession()) {
      return const SyncResult(
        total: 0,
        synced: 0,
        failed: 0,
        skipped: 0,
      );
    }

    _running = true;

    var total = 0;
    var synced = 0;
    var failed = 0;
    var skipped = 0;

    try {
      // ----------------------------------------------------------
      // 1. HISTÓRICO
      // ----------------------------------------------------------

      final historical =
          await _historyDb.getPendingSalesReadyToSync(
        limit: limit,
      );

      for (final sale in historical) {
        total++;

        final ok = await _syncHistoricalSale(
          sale,
        );

        if (ok) {
          synced++;
        } else {
          failed++;
        }
      }

      // ----------------------------------------------------------
      // 2. OUTBOX DEL DÍA
      // ----------------------------------------------------------

      final dayOutbox =
          await _dayDb.getPendingOutbox(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        limit: limit,
      );

      for (final item in dayOutbox) {
        total++;

        final ok = await _syncDayOutbox(
          companyId,
          userId,
          businessDate,
          item,
        );

        if (ok) {
          synced++;
        } else {
          failed++;
        }
      }

      return SyncResult(
        total: total,
        synced: synced,
        failed: failed,
        skipped: skipped,
      );
    } finally {
      _running = false;
    }
  }

  // ============================================================
  // SINCRONIZAR UNA VENTA
  // ============================================================

  Future<bool> syncSaleById(
    int saleId,
  ) async {
    final sale =
        await _historyDb.getSaleById(
      saleId,
    );

    if (sale == null) {
      return false;
    }

    if (sale['sync_status'] == 'synced') {
      return true;
    }

    return _syncHistoricalSale(
      sale,
      force: true,
    );
  }

  // ============================================================
  // SINCRONIZAR VENTA HISTÓRICA
  // ============================================================

  Future<bool> _syncHistoricalSale(
    Map<String, dynamic> sale, {
    bool force = false,
  }) async {
    final id = _toInt(
      sale['id'],
    );

    if (id <= 0) {
      return false;
    }

    if (!force &&
        sale['next_retry_at'] != null) {
      final nextRetry =
          DateTime.tryParse(
        sale['next_retry_at'].toString(),
      );

      if (nextRetry != null &&
          nextRetry.isAfter(
            DateTime.now(),
          )) {
        return true;
      }
    }

    if (sale['status']
            ?.toString()
            .toLowerCase() ==
        'cancelled') {
      await _historyDb.markSaleAsSynced(
        id,
        serverResponse: {
          'server_id': sale['server_id'],
          'folio': sale['server_folio'],
        },
      );

      return true;
    }

    await _historyDb.markSaleSyncing(
      id,
    );

    try {
      final venta =
          await _buildHistoricalPayload(
        sale,
      );

      final payload =
          <String, dynamic>{
        'ventas': [
          venta,
        ],
      };

      print(
        '🔄 Sincronizando venta histórica '
        '${sale['uuid_local']}',
      );

      print(
        '📦 Payload: $payload',
      );

      final response =
          await _apiClient.syncOffline(
        payload,
      );

      final errores =
          response['errores'];

      if (errores is List &&
          errores.isNotEmpty) {
        throw Exception(
          'El servidor rechazó la venta: $errores',
        );
      }

      final procesadas =
          response['procesadas'];

      if (procesadas is List &&
          procesadas.isEmpty) {
        throw Exception(
          'El servidor no confirmó la venta sincronizada.',
        );
      }

      await _historyDb.markSaleAsSynced(
        id,
        serverResponse: response,
      );

      return true;
    } catch (e) {
      print(
        '❌ Error sincronizando venta histórica '
        '${sale['uuid_local']}: $e',
      );

      await _historyDb.markSaleSyncFailed(
        id,
        e.toString(),
      );

      return false;
    }
  }

  // ============================================================
  // CONSTRUIR PAYLOAD HISTÓRICO
  // ============================================================

  Future<Map<String, dynamic>>
      _buildHistoricalPayload(
    Map<String, dynamic> sale,
  ) async {
    final saleId =
        _toInt(sale['id']);

    final items =
        await _historyDb
            .getSaleItemsBySaleId(
      saleId,
    );

    final payments =
        await _historyDb
            .getSalePaymentsBySaleId(
      saleId,
    );

    return _buildPayload(
      sale,
      items,
      payments,
    );
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
    final uuid =
        item['uuid_local']
                ?.toString()
                .trim() ??
            '';

    if (uuid.isEmpty) {
      return false;
    }

    final attempts =
        _toInt(
      item['attempts'],
    );

    try {
      final decoded =
          jsonDecode(
        item['payload']
                ?.toString() ??
            '{}',
      );

      if (decoded is! Map) {
        throw const FormatException(
          'Payload de sincronización inválido.',
        );
      }

      final rawPayload =
          Map<String, dynamic>.from(
        decoded,
      );

      final requestPayload =
          await _normalizeOfflinePayload(
        rawPayload,
        uuidLocal: uuid,
        businessDate: date,
      );

      final ventas =
          requestPayload['ventas'];

      if (ventas is! List ||
          ventas.isEmpty) {
        throw const FormatException(
          'El outbox no contiene ventas para sincronizar.',
        );
      }

      print(
        '🔄 Sincronizando outbox $uuid',
      );

      final response =
          await _apiClient.syncOffline(
        requestPayload,
      );

      final errores =
          response['errores'];

      if (errores is List &&
          errores.isNotEmpty) {
        throw Exception(
          'El servidor devolvió errores: $errores',
        );
      }

      final procesadas =
          response['procesadas'];

      if (procesadas is List &&
          procesadas.isEmpty) {
        throw Exception(
          'El servidor no confirmó la operación offline.',
        );
      }

      await _dayDb.markOutboxSynced(
        companyId: companyId,
        userId: userId,
        businessDate: date,
        uuidLocal: uuid,
        serverResponse: response,
      );

      return true;
    } catch (e) {
      print(
        '❌ Error sincronizando outbox $uuid: $e',
      );

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

  Future<Map<String, dynamic>>
      _normalizeOfflinePayload(
    Map<String, dynamic> payload, {
    required String uuidLocal,
    required DateTime businessDate,
  }) async {
    final ventas =
        payload['ventas'];

    if (ventas is List) {
      final normalizedVentas =
          <Map<String, dynamic>>[];

      for (final item in ventas) {
        if (item is! Map) {
          continue;
        }

        final venta =
            Map<String, dynamic>.from(
          item,
        );

        final currentUuid =
            venta['uuid_local']
                    ?.toString()
                    .trim() ??
                '';

        venta['uuid_local'] =
            currentUuid.isNotEmpty
                ? currentUuid
                : uuidLocal;

        venta['fecha_venta'] =
            _normalizeSaleDate(
          venta['fecha_venta'] ??
              venta['business_date'] ??
              businessDate
                  .toIso8601String(),
        );

        normalizedVentas.add(
          _normalizeVenta(
            venta,
          ),
        );
      }

      return {
        'ventas': normalizedVentas,
      };
    }

    final venta =
        Map<String, dynamic>.from(
      payload,
    );

    venta['uuid_local'] =
        uuidLocal;

    venta['fecha_venta'] =
        _normalizeSaleDate(
      venta['fecha_venta'] ??
          venta['business_date'] ??
          businessDate
              .toIso8601String(),
    );

    return {
      'ventas': [
        _normalizeVenta(
          venta,
        ),
      ],
    };
  }

  // ============================================================
  // NORMALIZAR VENTA
  // ============================================================

  Map<String, dynamic> _normalizeVenta(
    Map<String, dynamic> venta,
  ) {
    final normalized =
        <String, dynamic>{
      'uuid_local':
          venta['uuid_local']
                  ?.toString() ??
              '',
      'cliente_id':
          venta['cliente_id'],
      'productos':
          _normalizeProducts(
        venta['productos'],
      ),
      'pagos':
          _normalizePayments(
        venta['pagos'],
      ),
      'forma_pago':
          venta['forma_pago'],
      'monto_pagado':
          venta['monto_pagado'],
      'referencia':
          venta['referencia'],
      'descuento_global':
          _toDouble(
        venta['descuento_global'],
      ),
      'impuesto_global':
          _toDouble(
        venta['impuesto_global'],
      ),
      'dispositivo_id':
          venta['dispositivo_id'],
      'fecha_venta':
          _normalizeSaleDate(
        venta['fecha_venta'],
      ),
    };

    normalized.removeWhere(
      (key, value) =>
          value == null,
    );

    return normalized;
  }

  // ============================================================
  // PRODUCTOS
  // ============================================================

  List<Map<String, dynamic>>
      _normalizeProducts(
    dynamic value,
  ) {
    if (value is! List) {
      return [];
    }

    final result =
        <Map<String, dynamic>>[];

    for (final raw in value) {
      if (raw is! Map) {
        continue;
      }

      final item =
          Map<String, dynamic>.from(
        raw,
      );

      final productoId =
          _toInt(
        item['producto_id'] ??
            item['product_id'],
      );

      final cantidad =
          _toDouble(
        item['cantidad'] ??
            item['quantity'],
      );

      if (productoId <= 0 ||
          cantidad <= 0) {
        continue;
      }

      result.add({
        'producto_id':
            productoId,
        'cantidad':
            cantidad,
        'precio_unitario':
            _toDouble(
          item['precio_unitario'] ??
              item['precio'] ??
              item['unit_price'],
        ),
        'descuento':
            _toDouble(
          item['descuento'],
        ),
      });
    }

    return result;
  }

  // ============================================================
  // PAGOS
  // ============================================================

  List<Map<String, dynamic>>
      _normalizePayments(
    dynamic value,
  ) {
    if (value is! List) {
      return [];
    }

    final result =
        <Map<String, dynamic>>[];

    for (final raw in value) {
      if (raw is! Map) {
        continue;
      }

      final item =
          Map<String, dynamic>.from(
        raw,
      );

      final method =
          item['forma_pago']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
              ? item['forma_pago'].toString()
              : item['method']
                      ?.toString() ??
                  'Efectivo';

      final amount =
          _toDouble(
        item['monto'] ??
            item['amount'],
      );

      if (amount <= 0) {
        continue;
      }

      result.add({
        'forma_pago':
            _mapPaymentMethod(
          method,
        ),
        'monto': amount,
        'cambio':
            _toDouble(
          item['cambio'],
        ),
        'referencia':
            item['referencia'],
      });
    }

    return result;
  }

  // ============================================================
  // CONSTRUIR PAYLOAD DESDE SQLITE
  // ============================================================

  Map<String, dynamic> _buildPayload(
    Map<String, dynamic> sale,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> payments,
  ) {
    final total =
        _toDouble(
      sale['total'],
    );

    final changeDue =
        _toDouble(
      sale['change_due'],
    );

    final normalizedPayments =
        <Map<String, dynamic>>[];

    var cashAdjusted = false;
    var totalNetPayments = 0.0;

    for (final payment in payments) {
      final method =
          payment['method']
                  ?.toString() ??
              'Efectivo';

      final original =
          _toDouble(
        payment['amount'],
      );

      if (original <= 0) {
        continue;
      }

      var amount = original;
      var change = 0.0;

      if (_isCash(method) &&
          !cashAdjusted &&
          changeDue > 0) {
        amount =
            original - changeDue;

        change =
            changeDue;

        cashAdjusted = true;
      }

      if (amount < 0) {
        amount = 0;
      }

      if (amount <= 0) {
        continue;
      }

      normalizedPayments.add({
        'forma_pago':
            _mapPaymentMethod(
          method,
        ),
        'monto':
            roundMoney(
          amount,
        ),
        'cambio':
            roundMoney(
          change,
        ),
        'referencia':
            payment['referencia'],
      });

      totalNetPayments +=
          amount;
    }

    final difference =
        roundMoney(
      total - totalNetPayments,
    );

    if (difference.abs() >
        0.009) {
      if (normalizedPayments
          .isNotEmpty) {
        final first =
            normalizedPayments[0];

        first['monto'] =
            roundMoney(
          _toDouble(
                first['monto'],
              ) +
              difference,
        );
      } else if (difference > 0) {
        normalizedPayments.add({
          'forma_pago':
              'Efectivo',
          'monto':
              roundMoney(
            difference,
          ),
          'cambio':
              0.0,
          'referencia':
              null,
        });
      }
    }

    final fechaVenta =
        _normalizeSaleDate(
      sale['fecha_venta'] ??
          sale['created_at'] ??
          sale['business_date'] ??
          DateTime.now()
              .toIso8601String(),
    );

    /*
     * IMPORTANTE:
     *
     * precio_unitario es el nombre requerido
     * por /api/v1/sync/offline.
     */
    final normalizedProducts =
        <Map<String, dynamic>>[];

    for (final item in items) {
      final productoId =
          _toInt(
        item['product_id'] ??
            item['producto_id'],
      );

      final cantidad =
          _toDouble(
        item['quantity'] ??
            item['cantidad'],
      );

      if (productoId <= 0 ||
          cantidad <= 0) {
        continue;
      }

      normalizedProducts.add({
        'producto_id':
            productoId,
        'cantidad':
            cantidad,
        'precio_unitario':
            _toDouble(
          item['unit_price'] ??
              item['precio_unitario'] ??
              item['precio'],
        ),
        'descuento':
            _toDouble(
          item['descuento'],
        ),
      });
    }

    return {
      'uuid_local':
          sale['uuid_local']
                  ?.toString()
                  .trim() ??
              '',
      'cliente_id':
          sale['cliente_id'],
      'productos':
          normalizedProducts,
      'pagos':
          normalizedPayments,
      'descuento_global':
          _toDouble(
        sale['descuento_global'],
      ),
      'impuesto_global':
          _toDouble(
        sale['impuesto_global'],
      ),
      'dispositivo_id':
          sale['dispositivo_id'],
      'fecha_venta':
          fechaVenta,
    }..removeWhere(
        (key, value) =>
            value == null,
      );
  }

  // ============================================================
  // ARCHIVAR PENDIENTES DEL DÍA
  // ============================================================

  Future<int>
      archivePendingSalesFromDay({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final db =
        await _dayDb.open(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    final rows = await db.query(
      'sales',
      where:
          "sync_status IN ('pending','failed','syncing')",
      orderBy:
          'created_at ASC',
    );

    var count = 0;

    for (final sale in rows) {
      final uuid =
          sale['uuid_local']
                  ?.toString()
                  .trim() ??
              '';

      if (uuid.isEmpty) {
        continue;
      }

      final items =
          await _dayDb.getSaleItems(
        db,
        _toInt(
          sale['id'],
        ),
      );

      final payments =
          await _dayDb.getSalePayments(
        db,
        _toInt(
          sale['id'],
        ),
      );

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
  // SINCRONIZAR CATÁLOGOS
  // ============================================================

  Future<void> syncCatalogs({
    bool force = false,
  }) async {
    final versions =
        await _historyDb
            .getCatalogVersions();

    final cursor =
        await _historyDb
            .getCatalogCursor(
              'global',
            );

    final response =
        await _apiClient.getCatalog(
      desde: force
          ? null
          : cursor ??
              versions['global'],
    );

    if (response.isEmpty) {
      return;
    }

    await _historyDb.syncCatalogs(
      response,
    );

    final nextCursor =
        response['next_cursor']
                ?.toString() ??
            response['cursor']
                ?.toString();

    final nextVersion =
        response['version']
                ?.toString() ??
            (
              response['versiones']
                      is Map
                  ? (response['versiones']
                          as Map)['global']
                      ?.toString()
                  : null
            );

    if (nextCursor != null ||
        nextVersion != null) {
      await _historyDb
          .setCatalogVersion(
        'global',
        nextVersion,
        cursor: nextCursor,
      );
    }
  }

  // ============================================================
  // PULL DE CAMBIOS DEL SERVIDOR
  // ============================================================

  Future<Map<String, dynamic>>
      syncPull() async {
    final cursor =
        await _historyDb
            .getCatalogCursor(
              'server_changes',
            );

    print(
      '⬇️ Iniciando SYNC PULL '
      'cursor=${cursor ?? 'SIN_CURSOR'}',
    );

    final response =
        await _apiClient.syncPull(
      cursor: cursor,
    );

    print(
      '⬇️ SYNC PULL recibido.',
    );

    /*
     * El backend devuelve:
     *
     * {
     *   cambios: {
     *     productos: [],
     *     clientes: [],
     *     ...
     *     ventas: []
     *   },
     *   tombstones: {},
     *   cursor: "..."
     * }
     */
    final cambios =
        response['cambios'];

    final tombstones =
        response['tombstones'];

    final serverData =
        <String, dynamic>{};

    List<Map<String, dynamic>> ventas =
        <Map<String, dynamic>>[];

    if (cambios is Map) {
      final cambiosMap =
          Map<String, dynamic>.from(
        cambios,
      );

      /*
       * EXTRAER VENTAS.
       *
       * Separamos ventas de catálogos porque necesitan
       * sus propias tablas de cabecera, detalles y pagos.
       */
      final rawVentas =
          cambiosMap.remove('ventas');

      if (rawVentas is List) {
        ventas = rawVentas
            .whereType<Map>()
            .map(
              (item) =>
                  Map<String, dynamic>.from(
                item,
              ),
            )
            .where(
              (venta) =>
                  _serverSaleUuid(
                    venta,
                  ).isNotEmpty,
            )
            .toList();
      }

      /*
       * Catálogos existentes.
       */
      serverData.addAll(
        cambiosMap,
      );
    }

    print(
      '⬇️ Ventas recibidas del servidor: '
      '${ventas.length}',
    );

    /*
     * Procesar catálogos y tombstones.
     */
    if (tombstones != null) {
      serverData['tombstones'] =
          tombstones;
    }

    if (serverData.isNotEmpty) {
      await _historyDb.syncCatalogs(
        serverData,
      );
    }

    /*
     * Procesar ventas.
     */
    if (ventas.isNotEmpty) {
      await _upsertServerSales(
        ventas,
      );
    }

    /*
     * IMPORTANTE:
     *
     * El cursor se guarda únicamente después de
     * haber procesado correctamente las ventas.
     */
    final nextCursor =
        response['next_cursor']
                ?.toString() ??
            response['cursor']
                ?.toString();

    if (nextCursor != null &&
        nextCursor.isNotEmpty) {
      await _historyDb
          .setCatalogVersion(
        'server_changes',
        null,
        cursor: nextCursor,
      );

      print(
        '✅ Cursor actualizado: $nextCursor',
      );
    }

    print(
      '✅ SYNC PULL finalizado.',
    );

    return response;
  }

  // ============================================================
  // UPSERT DE VENTAS RECIBIDAS
  // ============================================================

  Future<void> _upsertServerSales(
    List<Map<String, dynamic>> ventas,
  ) async {
    final db =
        await _historyDb.database;

    /*
     * Deduplicación dentro de la misma respuesta.
     */
    final uniqueSales =
        <String, Map<String, dynamic>>{};

    for (final venta in ventas) {
      final uuid =
          _serverSaleUuid(
        venta,
      );

      if (uuid.isEmpty) {
        continue;
      }

      uniqueSales[uuid] =
          venta;
    }

    if (uniqueSales.isEmpty) {
      print(
        'ℹ️ No existen ventas válidas para aplicar.',
      );
      return;
    }

    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    await db.transaction(
      (txn) async {
        for (final venta
            in uniqueSales.values) {
          final result =
              await _upsertServerSale(
            txn,
            venta,
          );

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
      },
    );

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
    final uuid =
        _serverSaleUuid(
      venta,
    );

    if (uuid.isEmpty) {
      return 'skipped';
    }

    final existing =
        await txn.query(
      'sales',
      where: 'uuid_local = ?',
      whereArgs: [uuid],
      limit: 1,
    );

    /*
     * Venta ya existente localmente.
     */
    if (existing.isNotEmpty) {
      final localSale =
          Map<String, dynamic>.from(
        existing.first,
      );

      final localId =
          _toInt(
        localSale['id'],
      );

      /*
       * NUNCA reemplazar una venta que todavía está
       * pendiente de enviar.
       */
      if (_isLocalSalePending(
        localSale,
      )) {
        print(
          '⚠️ Venta $uuid '
          'pendiente localmente. '
          'No se sobrescribe.',
        );

        return 'skipped';
      }

      await _updateExistingServerSale(
        txn,
        localId,
        venta,
      );

      return 'updated';
    }

    /*
     * Venta que todavía no existe localmente.
     */
    final saleId =
        await _insertServerSale(
      txn,
      venta,
    );

    await _replaceServerSaleChildren(
      txn,
      saleId,
      venta,
    );

    return 'inserted';
  }

  // ============================================================
  // INSERTAR VENTA SERVIDOR
  // ============================================================

  Future<int> _insertServerSale(
    dynamic txn,
    Map<String, dynamic> venta,
  ) async {
    final uuid =
        _serverSaleUuid(
      venta,
    );

    final estado =
        venta['estado']
                ?.toString()
                .trim() ??
            'pagado';

    final payments =
        _serverPayments(
      venta,
    );

    final paymentMethod =
        payments.isNotEmpty
            ? payments.first['method']
            : null;

    final cashReceived =
        _cashReceived(
      payments,
    );

    final changeDue =
        _cashChange(
      payments,
    );

    return txn.insert(
      'sales',
      {
        'uuid_local':
            uuid,

        'total':
            _toDouble(
          venta['total'],
        ),

        'status':
            _normalizeSaleStatus(
          estado,
        ),

        /*
         * Venta recibida del servidor ya está
         * sincronizada.
         */
        'sync_status':
            'synced',

        'payment_method':
            paymentMethod,

        'cash_received':
            cashReceived,

        'change_due':
            changeDue,

        'mesa_id':
            venta['mesa_id'],

        'mesa_nombre':
            venta['mesa_nombre']
                ?.toString(),

        /*
         * Guardamos created_at en hora local
         * para que getTodaySales() pueda encontrarla.
         */
        'created_at':
            _serverLocalDate(
          venta['created_at'] ??
              venta['fecha'],
        ),

        'updated_at':
            _serverLocalDate(
          venta['updated_at'] ??
              venta['created_at'] ??
              venta['fecha'],
        ),

        'paid_at':
            estado.toLowerCase() ==
                    'pagado'
                ? _serverLocalDate(
                    venta['fecha'] ??
                        venta['created_at'],
                  )
                : null,
      },
    );
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

    final estado =
        venta['estado']
                ?.toString()
                .trim() ??
            'pagado';

    final payments =
        _serverPayments(
      venta,
    );

    final paymentMethod =
        payments.isNotEmpty
            ? payments.first['method']
            : null;

    await txn.update(
      'sales',
      {
        'total':
            _toDouble(
          venta['total'],
        ),

        'status':
            _normalizeSaleStatus(
          estado,
        ),

        'sync_status':
            'synced',

        'payment_method':
            paymentMethod,

        'cash_received':
            _cashReceived(
          payments,
        ),

        'change_due':
            _cashChange(
          payments,
        ),

        'mesa_id':
            venta['mesa_id'],

        'mesa_nombre':
            venta['mesa_nombre']
                ?.toString(),

        'created_at':
            _serverLocalDate(
          venta['created_at'] ??
              venta['fecha'],
        ),

        'updated_at':
            _serverLocalDate(
          venta['updated_at'] ??
              venta['created_at'] ??
              venta['fecha'],
        ),

        'paid_at':
            estado.toLowerCase() ==
                    'pagado'
                ? _serverLocalDate(
                    venta['fecha'] ??
                        venta['created_at'],
                  )
                : null,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    await _replaceServerSaleChildren(
      txn,
      saleId,
      venta,
    );
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

    await txn.delete(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );

    await txn.delete(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );

    /*
     * ----------------------------------------------------------
     * DETALLES
     * ----------------------------------------------------------
     */
    final detalles =
        venta['detalles'];

    if (detalles is List) {
      for (final raw in detalles) {
        if (raw is! Map) {
          continue;
        }

        final detalle =
            Map<String, dynamic>.from(
          raw,
        );

        final productId =
            _toInt(
          detalle['producto_id'],
        );

        final quantity =
            _toDouble(
          detalle['cantidad'],
        );

        final unitPrice =
            _toDouble(
          detalle['precio'] ??
              detalle['precio_unitario'],
        );

        final total =
            _toDouble(
          detalle['total'],
        );

        if (productId <= 0 ||
            quantity <= 0) {
          continue;
        }

        final producto =
            detalle['producto'];

        String? name;

        if (producto is Map) {
          name =
              producto['nombre']
                      ?.toString() ??
                  producto['name']
                      ?.toString();
        }

        name ??=
            detalle['nombre']
                ?.toString() ??
                detalle['name']
                    ?.toString();

        final itemTotal =
            total > 0
                ? total
                : roundMoney(
                    quantity *
                        unitPrice,
                  );

        await txn.insert(
          'sale_items',
          {
            'sale_id':
                saleId,

            'product_id':
                productId,

            'name':
                name ?? 'Producto',

            'quantity':
                quantity,

            'unit_price':
                unitPrice,

            'total':
                itemTotal,
          },
        );
      }
    }

    /*
     * ----------------------------------------------------------
     * PAGOS
     * ----------------------------------------------------------
     */
    final pagos =
        venta['pagos'];

    if (pagos is List) {
      for (final raw in pagos) {
        if (raw is! Map) {
          continue;
        }

        final pago =
            Map<String, dynamic>.from(
          raw,
        );

        final method =
            pago['forma_pago']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
                ? pago['forma_pago']
                    .toString()
                : pago['method']
                        ?.toString() ??
                    'Efectivo';

        final amount =
            _toDouble(
          pago['monto'] ??
              pago['amount'],
        );

        if (amount <= 0) {
          continue;
        }

        await txn.insert(
          'sale_payments',
          {
            'sale_id':
                saleId,

            'method':
                _mapPaymentMethod(
              method,
            ),

            'amount':
                roundMoney(
              amount,
            ),
          },
        );
      }
    }
  }

  // ============================================================
  // UUID
  // ============================================================

  String _serverSaleUuid(
    Map<String, dynamic> venta,
  ) {
    return (
      venta['uuid'] ??
          venta['uuid_local']
    )
        ?.toString()
        .trim() ??
        '';
  }

  // ============================================================
  // NO PISAR VENTA PENDIENTE
  // ============================================================

  bool _isLocalSalePending(
    Map<String, dynamic> sale,
  ) {
    final syncStatus =
        sale['sync_status']
            ?.toString()
            .trim()
            .toLowerCase();

    return syncStatus == null ||
        syncStatus.isEmpty ||
        syncStatus == 'pending' ||
        syncStatus == 'syncing' ||
        syncStatus == 'failed';
  }

  // ============================================================
  // PAGOS SERVIDOR
  // ============================================================

  List<Map<String, dynamic>> _serverPayments(
    Map<String, dynamic> venta,
  ) {
    final raw =
        venta['pagos'];

    if (raw is! List) {
      return [];
    }

    final result =
        <Map<String, dynamic>>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final pago =
          Map<String, dynamic>.from(
        item,
      );

      final method =
          pago['forma_pago']
                  ?.toString() ??
              pago['method']
                  ?.toString() ??
              'Efectivo';

      final amount =
          _toDouble(
        pago['monto'] ??
            pago['amount'],
      );

      if (amount <= 0) {
        continue;
      }

      result.add({
        'method':
            _mapPaymentMethod(
          method,
        ),
        'amount':
            roundMoney(
          amount,
        ),
        'cambio':
            roundMoney(
          _toDouble(
            pago['cambio'],
          ),
        ),
      });
    }

    return result;
  }

  // ============================================================
  // EFECTIVO RECIBIDO
  // ============================================================

  double _cashReceived(
    List<Map<String, dynamic>> payments,
  ) {
    var total = 0.0;

    for (final payment
        in payments) {
      final method =
          payment['method']
                  ?.toString() ??
              '';

      if (_isCash(method)) {
        total +=
            _toDouble(
              payment['amount'],
            ) +
            _toDouble(
              payment['cambio'],
            );
      }
    }

    return roundMoney(
      total,
    );
  }

  // ============================================================
  // CAMBIO
  // ============================================================

  double _cashChange(
    List<Map<String, dynamic>> payments,
  ) {
    var total = 0.0;

    for (final payment
        in payments) {
      total +=
          _toDouble(
        payment['cambio'],
      );
    }

    return roundMoney(
      total,
    );
  }

  // ============================================================
  // ESTADO LOCAL
  // ============================================================

  String _normalizeSaleStatus(
    String status,
  ) {
    final normalized =
        status
            .trim()
            .toLowerCase();

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
        return status.trim().isEmpty
            ? 'paid'
            : status;
    }
  }

  // ============================================================
  // FECHA ISO NORMALIZADA
  // ============================================================

  String _normalizeSaleDate(
    dynamic value,
  ) {
    if (value is DateTime) {
      return value.toIso8601String();
    }

    final text =
        value
                ?.toString()
                .trim() ??
            '';

    if (text.isEmpty) {
      return DateTime.now()
          .toIso8601String();
    }

    final parsed =
        DateTime.tryParse(text);

    if (parsed != null) {
      return parsed
          .toIso8601String();
    }

    return text;
  }

  // ============================================================
  // FECHA DEL SERVIDOR → HORA LOCAL
  // ============================================================

  String _serverLocalDate(
    dynamic value,
  ) {
    if (value is DateTime) {
      return value
          .toLocal()
          .toIso8601String();
    }

    final text =
        value
                ?.toString()
                .trim() ??
            '';

    if (text.isEmpty) {
      return DateTime.now()
          .toIso8601String();
    }

    final parsed =
        DateTime.tryParse(text);

    if (parsed == null) {
      return text;
    }

    return parsed
        .toLocal()
        .toIso8601String();
  }

  // ============================================================
  // CONVERSION
  // ============================================================

  int _toInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  double _toDouble(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    var text =
        value?.toString() ?? '';

    text =
        text.replaceAll(
      ',',
      '.',
    );

    return double.tryParse(
          text,
        ) ??
        0.0;
  }

  double roundMoney(
    double value,
  ) {
    return double.parse(
      value.toStringAsFixed(2),
    );
  }

  bool _isCash(
    String method,
  ) {
    return method
            .trim()
            .toLowerCase() ==
        'efectivo';
  }

  // ============================================================
  // MAPEAR FORMAS DE PAGO
  // ============================================================

  String _mapPaymentMethod(
    String method,
  ) {
    final normalized =
        method
            .trim()
            .toLowerCase();

    if (normalized ==
        'efectivo') {
      return 'Efectivo';
    }

    if (normalized ==
            'tarjeta' ||
        normalized ==
            'tarjeta crédito' ||
        normalized ==
            'tarjeta credito') {
      return 'Tarjeta Crédito';
    }

    if (normalized ==
            'tarjeta débito' ||
        normalized ==
            'tarjeta debito') {
      return 'Tarjeta Débito';
    }

    if (normalized ==
        'transferencia') {
      return 'Transferencia';
    }

    if (normalized ==
            'crédito' ||
        normalized ==
            'credito') {
      return 'Crédito';
    }

    if (normalized ==
        'cheque') {
      return 'Cheque';
    }

    return 'Otro';
  }
}