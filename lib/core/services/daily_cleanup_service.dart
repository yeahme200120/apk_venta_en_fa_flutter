import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../database/pos_db_service.dart';
import 'sync_service.dart';

/// Cierra el archivo diario, conserva sus pendientes en LocalDb y después
/// elimina solamente la base operativa del día.
class DailyCleanupService {
  final PosDatabaseService _dayDb;
  final SyncService _syncService;

  DailyCleanupService({PosDatabaseService? dayDb, SyncService? syncService})
      : _dayDb = dayDb ?? PosDatabaseService(),
        _syncService = syncService ?? SyncService();

  Future<int> archiveAndClearDailyDatabase({required int companyId, required int userId, required DateTime businessDate}) async {
    final pending = await _syncService.archivePendingSalesFromDay(companyId: companyId, userId: userId, businessDate: businessDate);
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/app-data/companies/$companyId/users/$userId');
    await dir.create(recursive: true);
    final date = businessDate.toIso8601String().substring(0, 10);
    final current = File('${dir.path}/pos_day_$date.sqlite');

    // El archivo diario es operativo. No lo respaldamos como fuente de verdad;
    // los pendientes ya están en LocalDb. Se puede borrar sin perder ventas.
    await _dayDb.deleteDatabaseFile(companyId: companyId, userId: userId, businessDate: businessDate);
    return pending;
  }

  Future<int> prepareNewBusinessDay({required int companyId, required int userId, required DateTime businessDate}) =>
      archiveAndClearDailyDatabase(companyId: companyId, userId: userId, businessDate: businessDate);
}
