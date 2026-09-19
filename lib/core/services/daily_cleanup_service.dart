import 'package:flutter/foundation.dart';

import '../database/local_db.dart';
import '../database/pos_db_service.dart';
import 'sync_service.dart';

/// Cierra el archivo diario, conserva sus pendientes en LocalDb y
/// después elimina la base operativa del día.
///
/// Reglas:
///
///   1. Intentar sincronizar TODO lo pendiente contra el servidor.
///   2. Archivar lo que no se pudo sincronizar en LocalDb (histórico).
///   3. Borrar la base diaria vieja.
///   4. Los pendientes archivados se reintentan en cada sync hasta
///      quedar `synced` o ser purgados por antigüedad.
class DailyCleanupService {
  final PosDatabaseService _dayDb;
  final SyncService _syncService;
  final LocalDb _historyDb;

  DailyCleanupService({
    PosDatabaseService? dayDb,
    SyncService? syncService,
    LocalDb? historyDb,
  })  : _dayDb = dayDb ?? PosDatabaseService(),
        _syncService = syncService ?? SyncService(),
        _historyDb = historyDb ?? LocalDb();

  /// Archiva pendientes, limpia datos del día y NO toca catálogos.
  Future<void> archiveAndClearDailyDatabase({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    // 1. Sincronizar pendientes del día anterior
    try {
      await _syncService.syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );
    } catch (e) {
      debugPrint('⚠️ Sync del día anterior falló: $e');
    }

    // 2. Archivar pendientes que no se sincronizaron
    try {
      await _syncService.archivePendingSalesFromDay(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );
    } catch (e) {
      debugPrint('⚠️ Archivar pendientes falló: $e');
    }

    // 3. Limpiar SOLO datos operativos del día
    try {
      await _dayDb.clearDailyData(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );
    } catch (e) {
      debugPrint('⚠️ Limpiar datos del día falló: $e');
    }

    // 4. Eliminar el archivo .sqlite del día anterior
    try {
      await _dayDb.deleteDatabaseFile(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );
    } catch (e) {
      debugPrint('⚠️ Borrar archivo .sqlite falló: $e');
    }

    // 5. Purgar la cola de sync antigua
    try {
      await _historyDb.purgeOldSyncQueue();
    } catch (e) {
      debugPrint('⚠️ Purga de cola falló: $e');
    }
  }

  Future<int> prepareNewBusinessDay({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    await archiveAndClearDailyDatabase(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );
    return 0;
  }
}