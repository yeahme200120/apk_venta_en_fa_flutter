import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/local_db.dart';
import '../database/pos_db_service.dart';
import '../network/api_client.dart';

class SyncService {
  final ApiClient _apiClient;
  final PosDatabaseService _dbService;
  final LocalDb _localDb;

  SyncService({
    ApiClient? apiClient,
    PosDatabaseService? posDbService,
    LocalDb? localDb,
  })  : _apiClient = apiClient ?? ApiClient(),
        _dbService = posDbService ?? PosDatabaseService(),
        _localDb = localDb ?? LocalDb();

  // ============================================================
  // VENTAS PENDIENTES
  // ============================================================

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

    // ----------------------------------------------------------
    // Ventas almacenadas directamente en LocalDb
    // ----------------------------------------------------------

    for (final sale in localSales) {
      final saleId = int.tryParse('${sale['id'] ?? 0}') ?? 0;
      if (saleId == 0) continue;

      final status = (sale['status'] ?? 'pending').toString().toLowerCase();

      // ✅ Si la venta está cancelada, no se envía al backend
      // Simplemente se marca como sincronizada (no hay nada que crear)
      if (status == 'cancelled') {
        await _localDb.markSaleAsSynced(saleId);
        continue;
      }

      // Para ventas pagadas o pendientes, se envían al backend
      try {
        final items = await _localDb.getSaleItemsBySaleId(saleId);
        final payments = await _localDb.getSalePaymentsBySaleId(saleId);

        final totalVenta = double.tryParse(sale['total']?.toString() ?? '0') ?? 0;
        final changeDue = double.tryParse(sale['change_due']?.toString() ?? '0') ?? 0;

        List<Map<String, dynamic>> pagosNetos = [];
        double sumNeto = 0.0;
        bool efectivoAjustado = false;

        for (final payment in payments) {
          final method = payment['method'] ?? '';
          final montoOriginal = double.tryParse(payment['amount']?.toString() ?? '0') ?? 0;

          double montoNeto;
          double cambioPago = 0.0;

          if (method.toLowerCase() == 'efectivo' && !efectivoAjustado) {
            montoNeto = montoOriginal - changeDue;
            cambioPago = changeDue;
            efectivoAjustado = true;
          } else if (method.toLowerCase() == 'efectivo' && efectivoAjustado) {
            montoNeto = montoOriginal;
            cambioPago = 0.0;
          } else {
            montoNeto = montoOriginal;
            cambioPago = 0.0;
          }

          pagosNetos.add({
            'forma_pago': _mapPaymentMethod(method),
            'monto': montoNeto,
            'cambio': cambioPago,
            'referencia': payment['referencia'] ?? null,
          });
          sumNeto += montoNeto;
        }

        final diff = totalVenta - sumNeto;
        if (diff.abs() > 0.001) {
          int? indexToAdjust;
          for (int i = 0; i < pagosNetos.length; i++) {
            if (pagosNetos[i]['forma_pago'] == 'Efectivo') {
              indexToAdjust = i;
              break;
            }
          }
          if (indexToAdjust == null && pagosNetos.isNotEmpty) {
            indexToAdjust = 0;
          }

          if (indexToAdjust != null) {
            final nuevoMonto = (pagosNetos[indexToAdjust]['monto'] as double) + diff;
            pagosNetos[indexToAdjust]['monto'] = nuevoMonto;
            sumNeto += diff;
          } else {
            pagosNetos.add({
              'forma_pago': 'Efectivo',
              'monto': diff,
              'cambio': 0.0,
              'referencia': null,
            });
            sumNeto += diff;
          }
        }

        final payload = {
          'cliente_id': sale['cliente_id'] ?? null,
          'productos': items.map((item) => {
            'producto_id': item['product_id'],
            'cantidad': item['quantity'],
            'precio': item['unit_price'],
            'descuento': item['descuento'] ?? 0,
          }).toList(),
          'pagos': pagosNetos,
          'descuento_global': sale['descuento_global'] ?? 0,
          'impuesto_global': sale['impuesto_global'] ?? 0,
          'notas': sale['notas'] ?? '',
        };

        await _apiClient.createSale(payload);
        // ✅ Ahora markSaleAsSynced solo actualiza sync_status, no status
        await _localDb.markSaleAsSynced(saleId);
      } catch (e) {
        // Si falla, se mantiene el status comercial y sync_status se pone a failed
        await _localDb.updateSaleStatus(
          saleId,
          status, // Mantiene el mismo status comercial
          syncStatus: 'failed',
        );
      }
    }

    // ----------------------------------------------------------
    // Ventas almacenadas en Outbox (PosDatabaseService)
    // (Aquí se aplica la misma lógica si se usara outbox)
    // ----------------------------------------------------------

    for (final item in queue) {
      final uuidLocal = item['uuid_local'] as String;
      final attempts = item['attempts'] is int
          ? item['attempts'] as int
          : int.tryParse('${item['attempts'] ?? 0}') ?? 0;

      try {
        final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
        // Si el payload incluye status, se podría filtrar cancelados, pero asumimos que outbox solo contiene ventas a crear
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

  // ============================================================
  // CATÁLOGOS (sin cambios)
  // ============================================================

  Future<void> syncCatalogs({bool force = false}) async {
    try {
      final response = await _apiClient.getCatalog();
      if (response.isEmpty) return;

      await _saveProducts(response['productos']);
      await _saveCatalog(table: 'clients', data: response['clientes']);
      await _saveCatalog(table: 'taxes', data: response['impuestos']);
      await _saveCatalog(table: 'payment_methods', data: response['formas_pago']);
      await _saveCatalog(table: 'units', data: response['unidades_medida']);
      await _saveCatalog(table: 'categories', data: response['categorias']);
      await _saveCatalog(table: 'promotions', data: response['promociones']);
      await _saveCatalog(table: 'coupons', data: response['cupones']);

      final versions = response['versiones'] as Map<String, dynamic>?;
      if (versions != null) {
        await _saveCatalogVersions(versions);
      }
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================
  // MÉTODOS PRIVADOS (sin cambios)
  // ============================================================

  Future<void> _saveProducts(dynamic data) async {
    if (data is! List) return;
    final db = await _localDb.database;
    await db.transaction((txn) async {
      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = _toInt(map['id']);
        if (id == null) continue;
        await txn.insert(
          'products',
          {
            'id': id,
            'code': _toString(map['codigo'] ?? map['code'] ?? map['clave']),
            'name': _toString(map['nombre'] ?? map['name'] ?? 'Producto'),
            'price': _toDouble(map['precio'] ?? map['price'] ?? 0),
            'stock': _toDouble(map['stock'] ?? 0),
            'is_active': _toBoolInt(map['activo'] ?? map['is_active'] ?? true),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> _saveCatalog({
    required String table,
    required dynamic data,
  }) async {
    if (data is! List) return;
    final db = await _localDb.database;
    await db.transaction((txn) async {
      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = _toInt(map['id']);
        if (id == null) continue;

        final name = _toString(map['nombre'] ?? map['name'] ?? map['descripcion'] ?? '');
        final code = _toString(map['codigo'] ?? map['code'] ?? map['clave'] ?? '');

        final values = <String, dynamic>{
          'id': id,
          'name': name,
          'is_active': _toBoolInt(map['activo'] ?? map['is_active'] ?? true),
          'data_json': jsonEncode(map),
          'updated_at': _toString(map['updated_at'] ?? map['updatedAt'] ?? ''),
        };

        if (table != 'clients') {
          values['code'] = code;
        }

        await txn.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);

        if (table == 'taxes') {
          await txn.update(
            table,
            {
              'rate': _toDouble(map['porcentaje'] ?? map['tasa'] ?? map['rate'] ?? 0),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    });
  }

  Future<void> _saveCatalogVersions(Map<String, dynamic> versions) async {
    final db = await _localDb.database;
    await db.transaction((txn) async {
      for (final entry in versions.entries) {
        final catalog = entry.key;
        final version = entry.value?.toString();
        if (version == null || version.isEmpty) continue;
        await txn.insert(
          'catalog_sync',
          {
            'catalog': catalog,
            'version': version,
            'synced_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
  }

  String _toString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  int _toBoolInt(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value != 0 ? 1 : 0;
    final text = value.toString().toLowerCase();
    return text == 'true' || text == '1' || text == 'activo' ? 1 : 0;
  }

  String _mapPaymentMethod(String method) {
    final normalized = method.toLowerCase().trim();
    if (normalized == 'efectivo') return 'Efectivo';
    if (normalized == 'tarjeta' || normalized == 'tarjeta crédito') return 'Tarjeta Crédito';
    if (normalized == 'tarjeta débito') return 'Tarjeta Débito';
    if (normalized == 'transferencia') return 'Transferencia';
    if (normalized == 'crédito') return 'Crédito';
    return 'Otro';
  }
}