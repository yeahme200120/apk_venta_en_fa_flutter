import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DailyCleanupService {
  Future<void> archiveAndClearDailyDatabase({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final rootDir = await getApplicationDocumentsDirectory();
    final dailyDir = Directory(
      '${rootDir.path}/app-data/companies/$companyId/users/$userId',
    );

    if (!await dailyDir.exists()) {
      await dailyDir.create(recursive: true);
    }

    final currentFile = File(
      '${dailyDir.path}/pos_day_${businessDate.toIso8601String().substring(0, 10)}.sqlite',
    );

    if (await currentFile.exists()) {
      final archiveFile = File(
        '${dailyDir.path}/pos_day_${businessDate.toIso8601String().substring(0, 10)}_archived.sqlite',
      );
      await currentFile.copy(archiveFile.path);
      await currentFile.delete();
    }
  }

  Future<void> prepareNewBusinessDay({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    await archiveAndClearDailyDatabase(
      companyId: companyId,
      userId: userId,
      businessDate: businessDate,
    );
  }
}
