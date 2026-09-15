import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
///      quedar `synced`.
class DailyCleanupService {
  final PosDatabaseService _dayDb;
  final SyncService _syncService;

  DailyCleanupService({
    PosDatabaseService? dayDb,
    SyncService? syncService,
  })  : _dayDb = dayDb ?? PosDatabaseService(),
        _syncService = syncService ?? SyncService();

  Future<int> archiveAndClearDailyDatabase({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    debugPrint(
      '🧹 Iniciando cleanup de día ${businessDate.toIso8601String()}',
    );

    // 1. Sincronizar lo pendiente contra el servidor.
    try {
      final result = await _syncService.syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      debugPrint(
        '🧹 Sync previo: '
        'synced=${result.synced} failed=${result.failed}',
      );
    } catch (e) {
      debugPrint(
        '🧹 Sync previo falló (seguimos): $e',
      );
    }

    // 2. Archivar pendientes en LocalDb (histórico).
    final pending = await _syncService.archivePendingSalesFromDay(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    debugPrint('🧹 Pendientes archivados en LocalDb: $pending');

    // 3. Borrar la base diaria vieja.
    final root = await getApplicationDocumentsDirectory();
    final date = businessDate.toIso8601String().substring(0, 10);
    final file = File(
      '${root.path}/app-data/companies/$companyId/users/$userId/pos_day_$date.sqlite',
    );

    if (await file.exists()) {
      debugPrint('🧹 Borrando base diaria: ${file.path}');
    }

    await _dayDb.deleteDatabaseFile(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );

    debugPrint('🧹 Cleanup finalizado.');

    return pending;
  }

  Future<int> prepareNewBusinessDay({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) =>
      archiveAndClearDailyDatabase(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );
}