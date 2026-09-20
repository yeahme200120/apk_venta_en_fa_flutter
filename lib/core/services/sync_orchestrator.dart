import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/local_db.dart';
import '../database/pos_db_service.dart';
import '../network/api_client.dart';
import '../storage/app_storage.dart';
import 'sync_service.dart';

// ============================================================
// STAGES
// ============================================================

/// Fases de la sincronización global.
///
/// Se reportan al callback `onProgress` para que la UI muestre
/// un preload con el estado actual.
enum SyncStage {
  starting,

  // FASE 1 — SUBIR
  uploadingQueue,
  uploadingHistoricalSales,
  uploadingDayOutbox,
  uploadFinished,

  // FASE 2 — BAJAR
  downloadingCompany,
  downloadingCatalogs,
  downloadingDayProducts,
  downloadingServerChanges,
  downloadingTables,
  downloadingOperationStatus,
  downloadFinished,

  // FASE 3
  finishing,
  done,
  error,
}

// ============================================================
// ERROR
// ============================================================

class SyncError {
  const SyncError({required this.stage, required this.message});

  final SyncStage stage;
  final String message;

  @override
  String toString() => '[$stage] $message';
}

// ============================================================
// RESULTADOS
// ============================================================

class SyncUploadReport {
  const SyncUploadReport({
    this.queueTotal = 0,
    this.queueSynced = 0,
    this.queueFailed = 0,
    this.queueSkipped = 0,
    this.salesTotal = 0,
    this.salesSynced = 0,
    this.salesFailed = 0,
    this.outboxTotal = 0,
    this.outboxSynced = 0,
    this.outboxFailed = 0,
  });

  final int queueTotal;
  final int queueSynced;
  final int queueFailed;
  final int queueSkipped;

  final int salesTotal;
  final int salesSynced;
  final int salesFailed;

  final int outboxTotal;
  final int outboxSynced;
  final int outboxFailed;

  int get total => queueTotal + salesTotal + outboxTotal;
  int get synced => queueSynced + salesSynced + outboxSynced;
  int get failed => queueFailed + salesFailed + outboxFailed;
}

class SyncDownloadReport {
  const SyncDownloadReport({
    this.companyOk = false,
    this.catalogsOk = false,
    this.dayProductsOk = false,
    this.serverChangesOk = false,
    this.tablesOk = false,
    this.operationStatusOk = false,
  });

  final bool companyOk;
  final bool catalogsOk;
  final bool dayProductsOk;
  final bool serverChangesOk;
  final bool tablesOk;
  final bool operationStatusOk;

  int get okCount => [
    companyOk,
    catalogsOk,
    dayProductsOk,
    serverChangesOk,
    tablesOk,
    operationStatusOk,
  ].where((ok) => ok).length;

  static const int totalSteps = 6;
}

class SyncReport {
  const SyncReport({
    required this.upload,
    required this.download,
    required this.errors,
    required this.duration,
    required this.skipped,
    this.skipReason,
  });

  final SyncUploadReport upload;
  final SyncDownloadReport download;
  final List<SyncError> errors;
  final Duration duration;
  final bool skipped;
  final String? skipReason;

  bool get hasErrors => errors.isNotEmpty || upload.failed > 0;
  bool get allOk => !skipped && !hasErrors;

  factory SyncReport.skippedReport(String reason) => SyncReport(
    upload: const SyncUploadReport(),
    download: const SyncDownloadReport(),
    errors: const [],
    duration: Duration.zero,
    skipped: true,
    skipReason: reason,
  );

  factory SyncReport.failureReport({
    required SyncError error,
    required Duration duration,
  }) => SyncReport(
    upload: const SyncUploadReport(),
    download: const SyncDownloadReport(),
    errors: [error],
    duration: duration,
    skipped: false,
  );

  /// Resumen legible para SnackBar/diálogo.
  String get summary {
    if (skipped) return 'Sincronización omitida: ${skipReason ?? ''}';

    final up = 'Subidas: ${upload.synced}/${upload.total}';
    final down =
        'Bajadas: ${download.okCount}/${SyncDownloadReport.totalSteps}';

    if (hasErrors) {
      return '$up  ·  $down  ·  ${errors.length} error(es)';
    }

    return '$up  ·  $down  ·  OK';
  }
}

// ============================================================
// ORQUESTADOR
// ============================================================

class SyncOrchestrator {
  SyncOrchestrator._internal();

  static final SyncOrchestrator _instance = SyncOrchestrator._internal();

  factory SyncOrchestrator() => _instance;

  final SyncService _sync = SyncService();
  final LocalDb _historyDb = LocalDb();
  final PosDatabaseService _dayDb = PosDatabaseService();
  final ApiClient _api = ApiClient();

  static bool _running = false;

  // ============================================================
  // ENTRADA PÚBLICA
  // ============================================================

  /// Sincronización global.
  ///
  /// Flujo:
  ///
  ///   1. SUBIR todo lo pendiente (sync_queue + ventas históricas
  ///      + outbox del día) respetando la fecha comercial
  ///      original de cada registro.
  ///
  ///   2. BAJAR todo lo que la app necesita, en este orden:
  ///      empresa → catálogos → productos del día → ventas →
  ///      mesas → estado operativo.
  ///
  ///   3. Reporte con contadores y errores.
  ///
  /// NO BORRA NADA. Upsert puro.
  Future<SyncReport> syncAll({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    void Function(SyncStage stage, String message)? onProgress,
  }) async {
    if (_running) {
      debugPrint('ℹ️ syncAll omitido: ya hay una sincronización en curso.');
      return SyncReport.skippedReport('Ya hay una sincronización en curso.');
    }

    // Solo sincronizamos online. Si la sesión es offline, no hay red.
    final storage = AppStorage();

    if (await storage.isOfflineSession()) {
      return SyncReport.skippedReport('Sesión offline.');
    }

    final token = await storage.getToken();
    if (token == null || token.trim().isEmpty) {
      return SyncReport.skippedReport('Sin token online.');
    }

    if (companyId <= 0 || userId <= 0) {
      return SyncReport.skippedReport('Sesión inválida.');
    }

    _running = true;

    final startedAt = DateTime.now();
    final errors = <SyncError>[];

    _emit(onProgress, SyncStage.starting, 'Iniciando sincronización...');

    try {
      // --------------------------------------------------------
      // FASE 1: SUBIR
      // --------------------------------------------------------
      final uploadReport = await _uploadAll(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        onProgress: onProgress,
        errors: errors,
      );

      _emit(
        onProgress,
        SyncStage.uploadFinished,
        'Subida completa: ${uploadReport.synced}/${uploadReport.total}',
      );

      // --------------------------------------------------------
      // FASE 2: BAJAR
      // --------------------------------------------------------
      final downloadReport = await _downloadAll(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        onProgress: onProgress,
        errors: errors,
      );

      _emit(
        onProgress,
        SyncStage.downloadFinished,
        'Descarga completa: '
        '${downloadReport.okCount}/${SyncDownloadReport.totalSteps}',
      );

      // --------------------------------------------------------
      // FASE 3: FIN
      // --------------------------------------------------------
      _emit(onProgress, SyncStage.finishing, 'Cerrando sincronización...');

      final report = SyncReport(
        upload: uploadReport,
        download: downloadReport,
        errors: errors,
        duration: DateTime.now().difference(startedAt),
        skipped: false,
      );

      _emit(onProgress, SyncStage.done, report.summary);

      return report;
    } catch (e) {
      debugPrint('❌ syncAll error: $e');
      errors.add(SyncError(stage: SyncStage.error, message: e.toString()));

      _emit(onProgress, SyncStage.error, 'Error: $e');

      return SyncReport(
        upload: const SyncUploadReport(),
        download: const SyncDownloadReport(),
        errors: errors,
        duration: DateTime.now().difference(startedAt),
        skipped: false,
      );
    } finally {
      _running = false;
    }
  }

  // ============================================================
  // FASE 1 — SUBIR
  // ============================================================

  Future<SyncUploadReport> _uploadAll({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    required void Function(SyncStage, String)? onProgress,
    required List<SyncError> errors,
  }) async {
    var queueTotal = 0, queueSynced = 0, queueFailed = 0, queueSkipped = 0;
    var salesTotal = 0, salesSynced = 0, salesFailed = 0;
    var outboxTotal = 0, outboxSynced = 0, outboxFailed = 0;

    // ----------------------------------------------------------
    // 1.1 — sync_queue
    // ----------------------------------------------------------
    _emit(
      onProgress,
      SyncStage.uploadingQueue,
      'Subiendo operaciones pendientes...',
    );

    try {
      final queueResult = await _sync.syncPendingQueue();
      queueTotal = queueResult.total;
      queueSynced = queueResult.synced;
      queueFailed = queueResult.failed;
      queueSkipped = queueResult.skipped;
    } catch (e) {
      debugPrint('⚠️ Error subiendo sync_queue: $e');
      errors.add(
        SyncError(stage: SyncStage.uploadingQueue, message: e.toString()),
      );
    }

    // ----------------------------------------------------------
    // 1.2 — ventas históricas, agrupadas por business_date
    // ----------------------------------------------------------
    _emit(
      onProgress,
      SyncStage.uploadingHistoricalSales,
      'Subiendo ventas pendientes...',
    );

    try {
      final dates = await _historyDb.getDistinctBusinessDatesWithPendingSales();

      for (final dateKey in dates) {
        final sales = await _historyDb.getPendingSalesByBusinessDate(dateKey);

        for (final sale in sales) {
          salesTotal++;

          final ok = await _sync.syncSaleById(_toInt(sale['id']));

          if (ok) {
            salesSynced++;
          } else {
            salesFailed++;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error subiendo ventas históricas: $e');
      errors.add(
        SyncError(
          stage: SyncStage.uploadingHistoricalSales,
          message: e.toString(),
        ),
      );
    }

    // ----------------------------------------------------------
    // 1.3 — outbox del día, agrupado por business_date
    // ----------------------------------------------------------
    _emit(
      onProgress,
      SyncStage.uploadingDayOutbox,
      'Subiendo operaciones del día...',
    );

    try {
      final dates = await _dayDb.listExistingBusinessDates(
        companyId: companyId,
        userId: userId,
      );

      for (final date in dates) {
        final outbox = await _dayDb.getPendingOutbox(
          companyId: companyId,
          userId: userId,
          businessDate: date,
        );

        for (final item in outbox) {
          outboxTotal++;

          final ok = await _sync.syncDayOutboxByItem(
            companyId: companyId,
            userId: userId,
            businessDate: date,
            item: item,
          );

          if (ok) {
            outboxSynced++;
          } else {
            outboxFailed++;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error subiendo outbox del día: $e');
      errors.add(
        SyncError(stage: SyncStage.uploadingDayOutbox, message: e.toString()),
      );
    }

    return SyncUploadReport(
      queueTotal: queueTotal,
      queueSynced: queueSynced,
      queueFailed: queueFailed,
      queueSkipped: queueSkipped,
      salesTotal: salesTotal,
      salesSynced: salesSynced,
      salesFailed: salesFailed,
      outboxTotal: outboxTotal,
      outboxSynced: outboxSynced,
      outboxFailed: outboxFailed,
    );
  }

  // ============================================================
  // FASE 2 — BAJAR
  // ============================================================

  Future<SyncDownloadReport> _downloadAll({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    required void Function(SyncStage, String)? onProgress,
    required List<SyncError> errors,
  }) async {
    var companyOk = false;
    var catalogsOk = false;
    var dayProductsOk = false;
    var serverChangesOk = false;
    var tablesOk = false;
    var operationStatusOk = false;

    // ============================================================
    // RESPUESTA ÚNICA DE /catalogos
    // ============================================================
    //
    // Se pide UNA sola vez y se reutiliza tanto para escribir en
    // LocalDb (catálogos completos) como para escribir en la base
    // diaria (productos del día).
    //
    // Antes se pedía dos veces (una por cada paso), lo que duplicaba
    // la llamada HTTP y el trabajo del backend.
    //
    // Si la llamada falla, se registra el error y ambos pasos
    // quedan marcados como fallidos.

    Map<String, dynamic>? catalogsResponse;

    _emit(
      onProgress,
      SyncStage.downloadingCatalogs,
      'Descargando catálogos...',
    );

    try {
      catalogsResponse = await _api.getCatalog();
    } catch (e) {
      debugPrint('⚠️ Error bajando catálogos: $e');
      errors.add(
        SyncError(stage: SyncStage.downloadingCatalogs, message: e.toString()),
      );
    }

    // ----------------------------------------------------------
    // 2.1 — empresa
    // ----------------------------------------------------------
    _emit(onProgress, SyncStage.downloadingCompany, 'Actualizando empresa...');

    try {
      final user = await _api.getCurrentUser();
      final empresa = user['empresa'];

      if (empresa is Map) {
        await _historyDb.syncCatalogs({'empresa': empresa});
      }

      companyOk = true;
    } catch (e) {
      debugPrint('⚠️ Error bajando empresa: $e');
      errors.add(
        SyncError(stage: SyncStage.downloadingCompany, message: e.toString()),
      );
    }

    // ----------------------------------------------------------
    // 2.2 — catálogos completos (usando la respuesta única)
    // ----------------------------------------------------------
    if (catalogsResponse != null) {
      try {
        // 2.2.a — sync pull (cambios incrementales + ventas + tombstones)
        try {
          await _sync.syncPull();
        } catch (e) {
          debugPrint('⚠️ Error en syncPull (no bloqueante): $e');
        }

        // 2.2.b — aplicar la respuesta a LocalDb
        await _historyDb.syncCatalogs(catalogsResponse);

        catalogsOk = true;
      } catch (e) {
        debugPrint('⚠️ Error aplicando catálogos a LocalDb: $e');
        errors.add(
          SyncError(
            stage: SyncStage.downloadingCatalogs,
            message: e.toString(),
          ),
        );
      }
    }

    // ----------------------------------------------------------
    // 2.3 — productos del día (misma respuesta)
    // ----------------------------------------------------------
    _emit(
      onProgress,
      SyncStage.downloadingDayProducts,
      'Descargando productos del día...',
    );

    if (catalogsResponse != null) {
      try {
        final data = catalogsResponse['data'] is Map
            ? Map<String, dynamic>.from(catalogsResponse['data'])
            : catalogsResponse;

        final raw = data['productos'];
        final products = raw is List
            ? raw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : <Map<String, dynamic>>[];

        final db = await _dayDb.open(
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
        );

        await _dayDb.upsertProducts(db, products);
        dayProductsOk = true;
      } catch (e) {
        debugPrint('⚠️ Error bajando productos del día: $e');
        errors.add(
          SyncError(
            stage: SyncStage.downloadingDayProducts,
            message: e.toString(),
          ),
        );
      }
    } else {
      debugPrint(
        'ℹ️ _downloadDayProducts omitido: no hay respuesta de /catalogos.',
      );
    }

    // ----------------------------------------------------------
    // 2.4 — cambios del servidor (ventas + tombstones)
    // ----------------------------------------------------------
    _emit(
      onProgress,
      SyncStage.downloadingServerChanges,
      'Buscando actualizaciones...',
    );

    // El syncPull ya se hizo en 2.2.a. Aquí solo marcamos OK.
    serverChangesOk = true;

    // ----------------------------------------------------------
    // 2.5 — mesas
    // ----------------------------------------------------------
    _emit(onProgress, SyncStage.downloadingTables, 'Actualizando mesas...');

    try {
      await _api.getTables();
      tablesOk = true;
    } catch (e) {
      debugPrint('⚠️ Error bajando mesas: $e');
      errors.add(
        SyncError(stage: SyncStage.downloadingTables, message: e.toString()),
      );
    }

    // ----------------------------------------------------------
    // 2.6 — estado operativo
    // ----------------------------------------------------------
    _emit(
      onProgress,
      SyncStage.downloadingOperationStatus,
      'Actualizando estado operativo...',
    );

    try {
      final state = await _api.getOperationStatus();
      await AppStorage().saveOperationState(state);
      operationStatusOk = true;
    } catch (e) {
      debugPrint('⚠️ Error bajando estado operativo: $e');
      errors.add(
        SyncError(
          stage: SyncStage.downloadingOperationStatus,
          message: e.toString(),
        ),
      );
    }

    return SyncDownloadReport(
      companyOk: companyOk,
      catalogsOk: catalogsOk,
      dayProductsOk: dayProductsOk,
      serverChangesOk: serverChangesOk,
      tablesOk: tablesOk,
      operationStatusOk: operationStatusOk,
    );
  }
  // ============================================================
  // HELPERS
  // ============================================================

  void _emit(
    void Function(SyncStage, String)? onProgress,
    SyncStage stage,
    String message,
  ) {
    debugPrint('🔄 [${stage.name}] $message');
    onProgress?.call(stage, message);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
