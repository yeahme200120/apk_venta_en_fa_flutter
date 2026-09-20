import 'dart:async';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config/app_theme.dart';
import '../../core/database/local_db.dart';
import '../../core/database/pos_db_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_monitor.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/sync_orchestrator.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';
import '../auth/login_screen.dart';
import '../catalog/catalog_admin_screen.dart';
import 'printer_settings_screen.dart';
import 'company_logo_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/sync_progress_dialog.dart';
import '../widgets/sync_result_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ============================================================
  // CERRAR SESIÓN
  // ============================================================

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Se eliminarán los datos locales de tu cuenta en este dispositivo. '
          'Las ventas ya sincronizadas con el servidor no se perderán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AppStorage().logOut();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible cerrar sesión: $error')),
      );
    }
  }

  // ============================================================
  // CAMBIAR CONTRASEÑA
  // ============================================================
  //
  // CAMBIO:
  // Cuando la contraseña se cambia correctamente, se cierra la
  // sesión SIEMPRE y se regresa al login.
  //
  // El Navigator se captura ANTES de los awaits largos para que
  // el push no sea sobrescrito por rebuilds del árbol (listeners
  // de sesión, AuthGate, etc.).

  Future<void> _cambiarPassword(BuildContext context) async {
    final networkMonitor = NetworkMonitor();

    if (!networkMonitor.isOnline) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas conexión a Internet para cambiar tu contraseña.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );

    if (result == null || !context.mounted) return;

    // Capturamos el Navigator raíz AHORA, antes de cualquier
    // await adicional.
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    NavigatorState? progressNavigator;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          progressNavigator = Navigator.of(ctx, rootNavigator: true);

          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Actualizando contraseña...'),
              ],
            ),
          );
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 120));

    try {
      await ApiClient().changePassword(
        currentPassword: result['actual'] as String,
        newPassword: result['nueva'] as String,
      );

      await AppStorage().setRequiresPasswordChange(false);

      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      if (!context.mounted) return;

      // ==========================================================
      // AVISO AL USUARIO: SESIÓN CERRADA
      // ==========================================================
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle_outline, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Contraseña actualizada',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: const Text(
              'Tu contraseña se cambió correctamente. '
              'Por seguridad, cerraremos la sesión para que inicies '
              'con tu nueva contraseña.',
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          );
        },
      );

      // ==========================================================
      // FORZAR LOGOUT + REGRESO AL LOGIN
      // ==========================================================
      await AppStorage().logOut();

      rootNavigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      if (!context.mounted) return;

      final raw = error.toString().replaceFirst('Exception: ', '').trim();
      final cs = Theme.of(context).colorScheme;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            raw.isEmpty ? 'No fue posible cambiar la contraseña.' : raw,
          ),
          backgroundColor: cs.error,
        ),
      );
    }
  }

  // ============================================================
  // DESCARGAR CATÁLOGO
  // ============================================================

  Future<void> _downloadCatalog(BuildContext context) async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay sesión activa para descargar catálogos.'),
        ),
      );

      return;
    }

    final rawBusinessDate = await AppStorage().getServerBusinessDate();

    final businessDate =
        DateTime.tryParse(rawBusinessDate ?? '') ?? DateTime.now();

    try {
      await CatalogService().downloadCatalogForToday(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Catálogos del día descargados correctamente.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descargar el catálogo: $error')),
      );
    }
  }

  // ============================================================
  // SINCRONIZAR (orquestador único)
  // ============================================================

  Future<void> _syncNow(BuildContext context) async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No existe una sesión válida para sincronizar.'),
        ),
      );

      return;
    }

    final rawBusinessDate = await AppStorage().getServerBusinessDate();

    final businessDate =
        DateTime.tryParse(rawBusinessDate ?? '') ?? DateTime.now();

    if (!context.mounted) return;

    final progressNotifier = ValueNotifier<String>(
      'Iniciando sincronización...',
    );

    NavigatorState? progressNavigator;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          progressNavigator = Navigator.of(ctx, rootNavigator: true);

          return SyncProgressDialog(progressNotifier: progressNotifier);
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final report = await SyncOrchestrator().syncAll(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        onProgress: (stage, message) {
          progressNotifier.value = message;
        },
      );

      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      if (!context.mounted) return;

      await showSyncResultDialog(
        context,
        report: report,
        onRetry: () => _syncNow(context),
      );
    } catch (error) {
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      if (!context.mounted) return;

      final cs = Theme.of(context).colorScheme;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible sincronizar: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.error,
        ),
      );
    }
  }

  // ============================================================
  // SINCRONIZAR TODOS LOS DÍAS CON PENDIENTES
  // ============================================================
  //
  // Recorre todas las business_date distintas con pendientes
  // en LocalDb (días anteriores incluidos) y las sincroniza.
  //
  // Devuelve un resumen consolidado:
  //
  //   {
  //     'total': int,
  //     'synced': int,
  //     'failed': int,
  //     'skipped': int,
  //     'dates': List<String>,
  //   }
  //
  // NO toca catálogos. Solo ventas y sus pendientes.
  Future<Map<String, dynamic>> _syncAllBusinessDates({
    required int companyId,
    required int userId,
    required DateTime currentBusinessDate,
    required void Function(String message) onProgress,
  }) async {
    final db = LocalDb();

    final totalSynced = <int>[0];
    final totalFailed = <int>[0];
    final totalSkipped = <int>[0];
    final totalCount = <int>[0];
    final processedDates = <String>[];

    // ----------------------------------------------------------
    // 1. DÍA ACTUAL
    // ----------------------------------------------------------
    onProgress('Sincronizando día actual...');

    try {
      final result = await SyncService().syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: currentBusinessDate,
      );

      totalCount[0] += result.total;
      totalSynced[0] += result.synced;
      totalFailed[0] += result.failed;
      totalSkipped[0] += result.skipped;

      processedDates.add(_businessDateKey(currentBusinessDate));
    } catch (e) {
      debugPrint('⚠️ Sync del día actual falló: $e');
    }

    // ----------------------------------------------------------
    // 2. DÍAS ANTERIORES CON PENDIENTES
    // ----------------------------------------------------------
    //
    // En LocalDb ya existe getDistinctBusinessDatesWithPendingSales().
    // Trae solo días con sync_status en pending/failed/syncing.
    final pendingDates = await db.getDistinctBusinessDatesWithPendingSales();

    final currentKey = _businessDateKey(currentBusinessDate);

    for (final rawDate in pendingDates) {
      final dateStr = rawDate.trim();

      if (dateStr.isEmpty) continue;
      if (dateStr == currentKey) continue; // ya procesado arriba

      onProgress('Sincronizando pendientes del $dateStr...');

      final parsed = DateTime.tryParse(dateStr);

      if (parsed == null) continue;

      try {
        final result = await SyncService().syncPendingSales(
          companyId: companyId,
          userId: userId,
          businessDate: parsed,
        );

        totalCount[0] += result.total;
        totalSynced[0] += result.synced;
        totalFailed[0] += result.failed;
        totalSkipped[0] += result.skipped;

        processedDates.add(dateStr);
      } catch (e) {
        debugPrint('⚠️ Sync del día $dateStr falló: $e');
      }
    }

    // ----------------------------------------------------------
    // 3. PURGAR COLA CON LA REGLA DE 3
    // ----------------------------------------------------------
    //
    // LocalDb.purgeOldSyncQueue() ya implementa:
    //   - Borrar items synced > 7 días.
    //   - Borrar items failed > 30 días.
    //   - Borrar items failed con attempts >= 3 (la 4ª no sube → fuera).
    //   - Recortar a máximo 500.
    onProgress('Purgando cola de sincronización...');

    try {
      await db.purgeOldSyncQueue();
    } catch (e) {
      debugPrint('⚠️ Purga de cola falló: $e');
    }

    return {
      'total': totalCount[0],
      'synced': totalSynced[0],
      'failed': totalFailed[0],
      'skipped': totalSkipped[0],
      'dates': processedDates,
    };
  }

  String _businessDateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // LIMPIAR DATOS DEL DÍA
  // ============================================================
  //
  // Reglas aplicadas:
  //
  //   1. Sincroniza GLOBALMENTE con SyncOrchestrator().syncAll
  //      (Sync Queue + ventas pendientes + outbox + pull).
  //   2. Barre días anteriores con pendientes
  //      (_syncAllBusinessDates) y purga la cola con la regla
  //      de 3 intentos (la 4ª se borra).
  //   3. Borra SOLO datos contables del día:
  //         - LocalDb: sales, sale_items, sale_payments,
  //                    cash_registers, cash_movements
  //         - Pos DB del día: borra el archivo de base diaria.
  //      NO toca catálogos.
  //   4. logOutForCleanup() borra usuario/empresa/credenciales
  //      offline y preserva únicamente:
  //         - license_snapshot (licencia del dispositivo)
  //         - ticket_config (config global del dispositivo)
  //         - terms_accepted_user_* (consentimiento T&C)
  //   5. Regresa al login usando el Navigator raíz capturado
  //      al inicio, para que el push no sea descartado por
  //      rebuilds del árbol.
  //
  // Requiere Internet para poder sincronizar antes de borrar.

  Future<void> _limpiarDia(BuildContext context) async {
    // ==========================================================
    // CAPTURA DE ESTADO ANTES DE CUALQUIER AWAIT
    // ==========================================================
    //
    // Todo lo que toque `context` debe ocurrir AQUÍ, antes de
    // cualquier await, para no disparar warnings de
    // use_build_context_synchronously.
    //
    // Además:
    //   • El push final no será sobrescrito por rebuilds del
    //     árbol disparados por logOut() (AuthGate, etc.).
    //   • El messenger sobrevive aunque el árbol se reconstruya.
    //   • Usamos rootNavigator.context para abrir diálogos,
    //     evitando referenciar el `context` original del método
    //     después de un async gap.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;

    final networkMonitor = NetworkMonitor();

    if (!networkMonitor.isOnline) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No hay conexión a Internet. Conéctate para sincronizar antes de limpiar.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final confirm = await showDialog<bool>(
      context: rootNavigator.context,
      builder: (dialogContext) {
        final dialogCs = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          title: const Text('Limpiar datos del día'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se sincronizarán primero TODOS los pendientes '
                '(día actual y días anteriores).',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 10),
              Text(
                'Después se eliminarán ventas, movimientos de caja y '
                'registros de caja del dispositivo. Los catálogos '
                '(productos, clientes, categorías, etc.) NO se tocan.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 10),
              Text(
                'Al final, la sesión se cerrará y volverás al login.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                '⚠️ Esta operación no se puede deshacer.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: dialogCs.error,
                foregroundColor: dialogCs.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Limpiar y salir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final progressNotifier = ValueNotifier<String>('Iniciando limpieza...');

    NavigatorState? progressNavigator;

    unawaited(
      showDialog<void>(
        // ignore: use_build_context_synchronously
        context: rootNavigator.context,
        barrierDismissible: false,
        builder: (progressContext) {
          progressNavigator = Navigator.of(
            progressContext,
            rootNavigator: true,
          );

          return SyncProgressDialog(progressNotifier: progressNotifier);
        },
      ),
    );

    // --------------------------------------------------------
    // A PARTIR DE AQUÍ: SOLO VARIABLES LOCALES, NO `context`
    // --------------------------------------------------------

    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('No hay sesión activa para limpiar datos.'),
        ),
      );

      return;
    }

    final rawBusinessDate = await AppStorage().getServerBusinessDate();

    final businessDate =
        DateTime.tryParse(rawBusinessDate ?? '') ?? DateTime.now();

    await Future.delayed(const Duration(milliseconds: 120));

    try {
      // ========================================================
      // 1. SINCRONIZACIÓN GLOBAL CON EL ORQUESTADOR
      // ========================================================
      //
      // SyncOrchestrator().syncAll es la ruta canónica:
      //   • Sync Queue (categorías, productos, cajas, movimientos)
      //   • Ventas pendientes
      //   • Outbox del día
      //   • Pull de cambios del servidor
      //
      // Se ejecuta ANTES de cualquier borrado.
      progressNotifier.value = 'Sincronizando pendientes...';

      try {
        final report = await SyncOrchestrator().syncAll(
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
          onProgress: (stage, message) {
            progressNotifier.value = message;
          },
        );

        debugPrint(
          '✅ SyncOrchestrator.syncAll en limpieza: '
          '$report',
        );
      } catch (e) {
        debugPrint('⚠️ SyncOrchestrator.syncAll falló: $e');
        // No abortamos: seguimos con el barrido de días
        // anteriores y la purga.
      }

      // ========================================================
      // 2. BARRIDO DE DÍAS ANTERIORES CON PENDIENTES
      // ========================================================
      //
      // syncAll suele tocar solo el día actual. Aquí iteramos
      // todas las business_date distintas con pendientes en
      // LocalDb para cubrir días anteriores.
      progressNotifier.value = 'Revisando días anteriores...';

      final syncSummary = await _syncAllBusinessDates(
        companyId: companyId,
        userId: userId,
        currentBusinessDate: businessDate,
        onProgress: (msg) => progressNotifier.value = msg,
      );

      final failed = syncSummary['failed'] as int;
      final synced = syncSummary['synced'] as int;

      if (failed > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Se sincronizaron $synced operaciones, '
              'pero $failed fallaron. Se purgarán automáticamente '
              'los pendientes con 3 intentos fallidos.',
            ),
            backgroundColor: cs.tertiary,
          ),
        );
      }

      // ========================================================
      // 3. ARCHIVAR PENDIENTES DEL DÍA (a LocalDb) ANTES DE BORRAR
      // ========================================================
      progressNotifier.value = 'Archivando pendientes del día...';

      try {
        await SyncService().archivePendingSalesFromDay(
          companyId: companyId,
          userId: userId,
          businessDate: businessDate,
        );
      } catch (e) {
        debugPrint('⚠️ Archivar pendientes falló: $e');
      }

      // ========================================================
      // 4. BORRAR BASE DIARIA
      // ========================================================
      progressNotifier.value = 'Eliminando base diaria...';

      await PosDatabaseService().deleteDatabaseFile(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      // ========================================================
      // 5. LIMPIAR OPERATION STATE
      // ========================================================
      await AppStorage().saveOperationState({});

      // ========================================================
      // 6. BORRAR SOLO DATOS CONTABLES EN LOCALDB
      // ========================================================
      //
      // clearDailyData() borra exactamente:
      //   sales, sale_items, sale_payments,
      //   cash_registers, cash_movements
      //
      // NO toca catálogos ni company.
      progressNotifier.value = 'Eliminando ventas y cajas locales...';

      await LocalDb().clearDailyData();

      // ========================================================
      // 7. CERRAR SESIÓN Y BORRAR USUARIO/EMPRESA
      // ========================================================
      //
      // logOutForCleanup() preserva ÚNICAMENTE:
      //   • license_snapshot  → licencia del dispositivo
      //   • ticket_config     → config global del dispositivo
      //   • terms_accepted_*  → consentimiento T&C
      //
      // Borra usuario, empresa, credenciales offline y fecha
      // comercial para que el auto-login no pueda reentrar.
      progressNotifier.value = 'Cerrando sesión...';

      await AppStorage().logOutForCleanup();

      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      // ========================================================
      // 8. REGRESAR AL LOGIN
      // ========================================================
      //
      // Usamos el rootNavigator capturado al inicio para que el
      // push no sea descartado por rebuilds del árbol.
      rootNavigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al limpiar: $error'),
          backgroundColor: cs.error,
        ),
      );
    }
  } // ============================================================
  // DISPOSITIVO ACTUAL
  // ============================================================

  Future<void> _showDeviceInfo(BuildContext context) async {
    final String os = Platform.operatingSystem;
    final String osVersion = Platform.operatingSystemVersion;
    final String dartVersion = Platform.version;

    final userId = await AppStorage().getUserId();
    final companyId = await AppStorage().getEmpresaId();
    final lastOnlineAt = await AppStorage().getLastOnlineAt();

    final networkMonitor = NetworkMonitor();
    final String networkStatus = networkMonitor.isOnline
        ? 'En línea'
        : 'Sin conexión';

    const String appVersion = '1.0.0+1';

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.devices_outlined, size: 22),
            SizedBox(width: 10),
            Text('Dispositivo actual'),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _deviceInfoRow(
                  dialogContext,
                  Icons.phone_android_outlined,
                  'Sistema operativo',
                  os,
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.info_outline,
                  'Versión del SO',
                  osVersion,
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.apps_outlined,
                  'Versión de la app',
                  appVersion,
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.code,
                  'Dart runtime',
                  dartVersion.split(' ').first,
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.person_outline,
                  'ID de usuario',
                  userId?.toString() ?? 'No disponible',
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.business_outlined,
                  'ID de empresa',
                  companyId?.toString() ?? 'No disponible',
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.wifi,
                  'Estado de red',
                  networkStatus,
                ),
                _deviceInfoRow(
                  dialogContext,
                  Icons.sync,
                  'Último acceso online',
                  lastOnlineAt ?? 'Sin conexión registrada',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _deviceInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFORMACIÓN DE SESIÓN
  // ============================================================

  Future<void> _showSessionInfo(
    BuildContext context,
    String title,
    String value,
  ) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.65,
          ),
          child: SingleChildScrollView(child: Text(value)),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  Map<String, dynamic> _extractUser(dynamic response) {
    final root = _asMap(response);

    final directUser = root['user'];

    if (directUser is Map) {
      return Map<String, dynamic>.from(directUser);
    }

    final data = root['data'];

    if (data is Map) {
      final nestedUser = data['user'];

      if (nestedUser is Map) {
        return Map<String, dynamic>.from(nestedUser);
      }

      return Map<String, dynamic>.from(data);
    }

    return root;
  }

  Map<String, dynamic> _extractCompany(dynamic response) {
    final root = _asMap(response);

    final directCompany = root['empresa'];

    if (directCompany is Map) {
      return Map<String, dynamic>.from(directCompany);
    }

    final directCompanyAlt = root['company'];

    if (directCompanyAlt is Map) {
      return Map<String, dynamic>.from(directCompanyAlt);
    }

    final data = root['data'];

    if (data is Map) {
      final nestedCompany = data['empresa'];

      if (nestedCompany is Map) {
        return Map<String, dynamic>.from(nestedCompany);
      }

      final nestedCompanyAlt = data['company'];

      if (nestedCompanyAlt is Map) {
        return Map<String, dynamic>.from(nestedCompanyAlt);
      }

      return Map<String, dynamic>.from(data);
    }

    return root;
  }

  Map<String, dynamic> _extractTicketConfig(dynamic response) {
    final root = _asMap(response);

    final config = root['config'];

    if (config is Map) {
      return Map<String, dynamic>.from(config);
    }

    final data = root['data'];

    if (data is Map) {
      final nestedConfig = data['config'];

      if (nestedConfig is Map) {
        return Map<String, dynamic>.from(nestedConfig);
      }
    }

    return root;
  }

  String _valueFromMap(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) continue;

      if (value is Map || value is List) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }

  String _userValue(Map<String, dynamic> user, List<String> keys) {
    return _valueFromMap(user, keys);
  }

  // ============================================================
  // EMPRESA ACTUAL
  // ============================================================

  Future<void> _showCompanyInfo(BuildContext context) async {
    try {
      final localCompanyId = await AppStorage().getEmpresaId();

      final localCompanyName = await AppStorage().getCompanyName();

      Map<String, dynamic> company = <String, dynamic>{};

      String? apiError;

      try {
        final response = await ApiClient().getCompanyConfig();

        company = _extractCompany(response);
      } catch (error) {
        apiError = error.toString();
      }

      final companyId = _valueFromMap(company, const [
        'id',
        'empresa_id',
        'company_id',
      ]);

      final name = _valueFromMap(company, const [
        'nombre',
        'name',
        'razon_social',
        'razonSocial',
      ]);

      final razonSocial = _valueFromMap(company, const [
        'razon_social',
        'razonSocial',
        'nombre',
        'name',
      ]);

      final rfc = _valueFromMap(company, const ['rfc', 'RFC', 'tax_id']);

      final telefono = _valueFromMap(company, const [
        'telefono',
        'phone',
        'telefono_contacto',
      ]);

      final email = _valueFromMap(company, const [
        'email',
        'correo',
        'correo_electronico',
        'contact_email',
      ]);

      final direccion = _valueFromMap(company, const [
        'direccion',
        'address',
        'domicilio',
      ]);

      final logo = _valueFromMap(company, const [
        'logo',
        'logo_url',
        'logoUrl',
      ]);

      final activo = _valueFromMap(company, const [
        'activo',
        'is_active',
        'active',
      ]);

      final resolvedId = companyId.isNotEmpty
          ? companyId
          : (localCompanyId?.toString() ?? '');

      final resolvedName = name.isNotEmpty
          ? name
          : (localCompanyName?.trim() ?? '');

      if (!context.mounted) return;

      final details = StringBuffer();

      details.writeln(
        'Nombre: ${resolvedName.isNotEmpty ? resolvedName : 'No disponible'}',
      );

      details.writeln(
        'Razón social: ${razonSocial.isNotEmpty ? razonSocial : 'No disponible'}',
      );

      details.writeln('RFC: ${rfc.isNotEmpty ? rfc : 'No disponible'}');

      details.writeln(
        'Teléfono: ${telefono.isNotEmpty ? telefono : 'No disponible'}',
      );

      details.writeln('Correo: ${email.isNotEmpty ? email : 'No disponible'}');

      details.writeln(
        'Dirección: ${direccion.isNotEmpty ? direccion : 'No disponible'}',
      );

      details.writeln(
        'ID técnico: ${resolvedId.isNotEmpty ? resolvedId : 'No disponible'}',
      );

      details.writeln(
        'Estado: ${activo.isNotEmpty ? activo : 'No disponible'}',
      );

      details.write('Logo: ${logo.isNotEmpty ? logo : 'No configurado'}');

      if (apiError != null && company.isEmpty) {
        details.write(
          '\n\nAviso: se mostró la información local porque '
          'no fue posible consultar la configuración remota.',
        );
      }

      await _showSessionInfo(context, 'Empresa actual', details.toString());
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible consultar la empresa: $error')),
      );
    }
  }

  // ============================================================
  // BRANDING
  // ============================================================

  Future<void> _editBranding(BuildContext context) async {
    try {
      final color = await showColorPickerDialog(
        context,
        AppTheme.seedColor.value,
        title: const Text('Colores y branding'),
        width: 42,
        height: 42,
        spacing: 6,
        runSpacing: 6,
        borderRadius: 8,
        wheelDiameter: 220,
        showColorCode: false,
        showColorName: true,
        showMaterialName: true,
        heading: const Text(
          'Selecciona un color',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subheading: const Text('Colores disponibles'),
        wheelSubheading: const Text('Selecciona el tono'),
        pickersEnabled: const <ColorPickerType, bool>{
          ColorPickerType.both: false,
          ColorPickerType.primary: true,
          ColorPickerType.accent: true,
          ColorPickerType.bw: true,
          ColorPickerType.custom: false,
          ColorPickerType.wheel: true,
        },
      );

      if (!context.mounted) return;

      AppTheme.setSeedColor(color);
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible cambiar el branding: $error')),
      );
    }
  }

  // ============================================================
  // USUARIO ACTUAL
  // ============================================================

  Future<void> _showCurrentUser(BuildContext context) async {
    try {
      final userResponse = await ApiClient().getCurrentUser();

      final user = _extractUser(userResponse);

      Map<String, dynamic> company = <String, dynamic>{};

      final userCompany = user['empresa'];

      if (userCompany is Map) {
        company = Map<String, dynamic>.from(userCompany);
      }

      if (company.isEmpty) {
        try {
          final companyResponse = await ApiClient().getCompanyConfig();

          company = _extractCompany(companyResponse);
        } catch (_) {}
      }

      final storedCompanyName = await AppStorage().getCompanyName();

      final storedCompanyId = await AppStorage().getEmpresaId();

      final name = _userValue(user, const ['name', 'nombre', 'usuario_nombre']);

      final email = _userValue(user, const [
        'email',
        'correo',
        'correo_electronico',
      ]);

      final numeroUsuario = _userValue(user, const [
        'numero_usuario',
        'numeroUsuario',
        'numero',
        'user_number',
        'username',
      ]);

      final rol = _userValue(user, const ['rol', 'role', 'tipo_usuario']);

      final userId = _userValue(user, const ['id', 'user_id']);

      final companyNameFromCompany = _valueFromMap(company, const [
        'nombre',
        'name',
        'razon_social',
        'razonSocial',
      ]);

      final companyNameFromUser = _valueFromMap(user, const [
        'empresa_nombre',
        'company_name',
      ]);

      final companyIdFromCompany = _valueFromMap(company, const [
        'id',
        'empresa_id',
        'company_id',
      ]);

      final companyIdFromUser = _valueFromMap(user, const [
        'empresa_id',
        'company_id',
      ]);

      final resolvedCompanyName = companyNameFromCompany.isNotEmpty
          ? companyNameFromCompany
          : (companyNameFromUser.isNotEmpty
                ? companyNameFromUser
                : (storedCompanyName?.trim() ?? ''));

      final resolvedCompanyId = companyIdFromCompany.isNotEmpty
          ? companyIdFromCompany
          : (companyIdFromUser.isNotEmpty
                ? companyIdFromUser
                : (storedCompanyId?.toString() ?? ''));

      final companyRfc = _valueFromMap(company, const ['rfc', 'RFC', 'tax_id']);

      final companyPhone = _valueFromMap(company, const [
        'telefono',
        'phone',
        'telefono_contacto',
      ]);

      final companyEmail = _valueFromMap(company, const [
        'email',
        'correo',
        'correo_electronico',
      ]);

      final companyAddress = _valueFromMap(company, const [
        'direccion',
        'address',
        'domicilio',
      ]);

      if (!context.mounted) return;

      final result = await showDialog<bool>(
        context: context,
        builder: (_) => _UserProfileDialog(
          initialName: name,
          email: email,
          numeroUsuario: numeroUsuario,
          rol: rol,
          empresa: resolvedCompanyName,
          userId: userId,
          empresaId: resolvedCompanyId,
          empresaRfc: companyRfc,
          empresaTelefono: companyPhone,
          empresaEmail: companyEmail,
          empresaDireccion: companyAddress,
        ),
      );

      if (!context.mounted) return;

      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario actualizado correctamente.')),
        );
      }
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar la información del usuario: $error'),
        ),
      );
    }
  }

  // ============================================================
  // TICKET
  // ============================================================

  Future<void> _editTicket(BuildContext context) async {
    try {
      Map<String, dynamic> local = await AppStorage().getTicketConfig();

      try {
        final remoteResponse = await ApiClient().getTicketConfig();

        final remoteConfig = _extractTicketConfig(remoteResponse);

        if (remoteConfig.isNotEmpty) {
          local = {...local, ...remoteConfig};

          await AppStorage().saveTicketConfig(local);
        }
      } catch (_) {}

      if (!context.mounted) return;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _TicketConfigDialog(initialConfig: local),
      );

      if (result == null) return;

      final payload = <String, dynamic>{...local, ...result};

      await AppStorage().saveTicketConfig(payload);

      bool serverSaved = false;

      try {
        final response = await ApiClient().updateTicketConfig(result);

        final serverConfig = _extractTicketConfig(response);

        if (serverConfig.isNotEmpty) {
          final mergedConfig = <String, dynamic>{...payload, ...serverConfig};

          await AppStorage().saveTicketConfig(mergedConfig);
        }

        serverSaved = true;
      } catch (_) {}

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverSaved
                ? 'Configuración del ticket guardada y sincronizada con el servidor.'
                : 'Configuración del ticket guardada localmente. Se sincronizará cuando haya conexión.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible guardar el ticket: $error')),
      );
    }
  }

  // ============================================================
  // BANNER PERSISTENTE DE CAMBIO DE CONTRASEÑA
  // ============================================================

  Widget _buildRequierePasswordChangeBanner(
    BuildContext context,
    VoidCallback onCambiar,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.error.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.error.withAlpha(90), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.error.withAlpha(30),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.lock_reset_outlined,
              color: colorScheme.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cambia tu contraseña',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Estás usando la contraseña genérica. '
                  'Por seguridad, cámbiala ahora.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onCambiar,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Administración y configuración',
      body: FutureBuilder<bool>(
        future: AppStorage().getRequiresPasswordChange(),
        builder: (context, snapshot) {
          final requiereCambio = snapshot.data == true;

          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              if (requiereCambio)
                _buildRequierePasswordChangeBanner(
                  context,
                  () => _cambiarPassword(context),
                ),

              const _SectionTitle('Empresa'),
              _SettingTile(
                title: 'Empresa actual',
                subtitle:
                    'Consulta los datos del negocio activo en esta sesión.',
                icon: Icons.business_outlined,
                onTap: () => _showCompanyInfo(context),
              ),
              _SettingTile(
                title: 'Usuario actual',
                subtitle: 'Perfil y datos de acceso del usuario en sesión.',
                icon: Icons.person_outline,
                onTap: () => _showCurrentUser(context),
              ),
              _SettingTile(
                title: 'Cambiar contraseña',
                subtitle:
                    'Actualiza tu contraseña periódicamente por seguridad. '
                    'Requiere Internet y cierra la sesión actual.',
                icon: Icons.lock_reset_outlined,
                onTap: () => _cambiarPassword(context),
              ),
              _SettingTile(
                title: 'Colores y branding',
                subtitle: 'Configuración visual de la empresa.',
                icon: Icons.palette_outlined,
                onTap: () => _editBranding(context),
              ),
              _SettingTile(
                title: 'Logo de empresa',
                subtitle: 'Selecciona, recorta y actualiza el logo.',
                icon: Icons.image_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CompanyLogoScreen()),
                ),
              ),
              _SettingTile(
                title: 'Ticket y formato',
                subtitle: 'Papel, encabezado, pie y QR.',
                icon: Icons.receipt_long_outlined,
                onTap: () => _editTicket(context),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('Dispositivo'),
              _SettingTile(
                title: 'Dispositivo actual',
                subtitle: 'Sistema operativo, versión de app, red y datos de instalación.',
                icon: Icons.devices_outlined,
                onTap: () => _showDeviceInfo(context),
              ),
              _SettingTile(
                title: 'Impresoras',
                subtitle: 'Bluetooth, USB y red.',
                icon: Icons.print_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrinterSettingsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('Sistema'),
              _SettingTile(
                title: 'Administrar catálogo',
                subtitle: 'Crear, editar o desactivar categorías, productos y formas de pago.',
                icon: Icons.inventory_2_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CatalogAdminScreen()),
                ),
              ),
              _SettingTile(
                title: 'Limpiar datos del día',
                subtitle:
                    'Sincroniza todos los pendientes, elimina ventas y cajas '
                    'del dispositivo (los catálogos no se tocan) y cierra '
                    'la sesión. Requiere Internet.',
                icon: Icons.cleaning_services_outlined,
                onTap: () => _limpiarDia(context),
              ),
              _SettingTile(
                title: 'Sincronizar ahora',
                subtitle: 'Reintento manual de ventas pendientes y fallidas.',
                icon: Icons.sync_outlined,
                onTap: () => _syncNow(context),
              ),
              _SettingTile(
                title: 'Descargar catálogo ahora',
                subtitle: 'Obtiene el inventario más reciente desde la API.',
                icon: Icons.cloud_download_outlined,
                onTap: () => _downloadCatalog(context),
              ),
              _SettingTile(
                title: 'Cerrar sesión',
                subtitle: 'Borra la sesión local y los datos del día del dispositivo.',
                icon: Icons.logout,
                onTap: () => _logout(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// DIÁLOGO CAMBIAR CONTRASEÑA
// ============================================================

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _mostrarActual = false;
  bool _mostrarNueva = false;
  bool _mostrarConfirmar = false;

  String? _errorActual;
  String? _errorNueva;
  String? _errorConfirmar;

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  String? _validarPassword(String value) {
    if (value.isEmpty) return 'Ingresa una contraseña.';
    if (value.length < 8) {
      return 'Debe tener al menos 8 caracteres.';
    }

    final tieneMayuscula = value.contains(RegExp(r'[A-Z]'));
    final tieneMinuscula = value.contains(RegExp(r'[a-z]'));
    final tieneNumero = value.contains(RegExp(r'[0-9]'));

    if (!tieneMayuscula || !tieneMinuscula || !tieneNumero) {
      return 'Debe incluir mayúscula, minúscula y número.';
    }

    return null;
  }

  void _confirmar() {
    final actual = _actualController.text;
    final nueva = _nuevaController.text;
    final confirmar = _confirmarController.text;

    setState(() {
      _errorActual = null;
      _errorNueva = null;
      _errorConfirmar = null;
    });

    if (actual.isEmpty) {
      setState(() => _errorActual = 'Ingresa tu contraseña actual.');
      return;
    }

    final errorNueva = _validarPassword(nueva);

    if (errorNueva != null) {
      setState(() => _errorNueva = errorNueva);
      return;
    }

    if (nueva == actual) {
      setState(
        () =>
            _errorNueva = 'La nueva contraseña debe ser diferente a la actual.',
      );
      return;
    }

    if (confirmar.isEmpty) {
      setState(() => _errorConfirmar = 'Confirma tu contraseña.');
      return;
    }

    if (nueva != confirmar) {
      setState(() => _errorConfirmar = 'Las contraseñas no coinciden.');
      return;
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).pop(<String, dynamic>{'actual': actual, 'nueva': nueva});
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
    String? errorText,
    required ValueChanged<String> onChanged,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: onToggle,
            ),
            border: const OutlineInputBorder(),
            errorText: errorText,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset_outlined, size: 22),
          SizedBox(width: 8),
          Text('Cambiar contraseña'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ingresa tu contraseña actual y la nueva contraseña.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            _passwordField(
              controller: _actualController,
              label: 'Contraseña actual',
              obscureText: !_mostrarActual,
              onToggle: () => setState(() => _mostrarActual = !_mostrarActual),
              errorText: _errorActual,
              onChanged: (_) {
                if (_errorActual != null) {
                  setState(() => _errorActual = null);
                }
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _nuevaController,
              label: 'Nueva contraseña',
              obscureText: !_mostrarNueva,
              onToggle: () => setState(() => _mostrarNueva = !_mostrarNueva),
              errorText: _errorNueva,
              onChanged: (_) {
                if (_errorNueva != null) {
                  setState(() => _errorNueva = null);
                }
              },
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Mín. 8 caracteres, con mayúscula, minúscula y número.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _confirmarController,
              label: 'Confirmar nueva contraseña',
              obscureText: !_mostrarConfirmar,
              onToggle: () =>
                  setState(() => _mostrarConfirmar = !_mostrarConfirmar),
              errorText: _errorConfirmar,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_errorConfirmar != null) {
                  setState(() => _errorConfirmar = null);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _confirmar,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Actualizar contraseña'),
        ),
      ],
    );
  }
}

// ============================================================
// DIÁLOGO DE USUARIO
// ============================================================

class _UserProfileDialog extends StatefulWidget {
  const _UserProfileDialog({
    required this.initialName,
    required this.email,
    required this.numeroUsuario,
    required this.rol,
    required this.empresa,
    required this.userId,
    required this.empresaId,
    required this.empresaRfc,
    required this.empresaTelefono,
    required this.empresaEmail,
    required this.empresaDireccion,
  });

  final String initialName;
  final String email;
  final String numeroUsuario;
  final String rol;
  final String empresa;
  final String userId;
  final String empresaId;
  final String empresaRfc;
  final String empresaTelefono;
  final String empresaEmail;
  final String empresaDireccion;

  @override
  State<_UserProfileDialog> createState() => _UserProfileDialogState();
}

class _UserProfileDialogState extends State<_UserProfileDialog> {
  late final TextEditingController _nameController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _display(String value, String fallback) {
    final text = value.trim();

    return text.isEmpty ? fallback : text;
  }

  Future<void> _save() async {
    if (_saving) return;

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showMessage('Ingresa el nombre del usuario.');
      return;
    }

    if (name.length < 2) {
      _showMessage('El nombre debe tener al menos 2 caracteres.');
      return;
    }

    if (name.length > 100) {
      _showMessage('El nombre no puede superar 100 caracteres.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await ApiClient().updateProfile({'name': name});

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showMessage('No fue posible actualizar el usuario: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _readOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final displayValue = value.trim().isEmpty ? 'No disponible' : value.trim();

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(),
      ),
      child: Text(
        displayValue,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurface),
      ),
    );
  }

  Widget _buildCompanySummary() {
    final name = _display(widget.empresa, 'Empresa actual');

    final hasAdditionalData =
        widget.empresaId.trim().isNotEmpty ||
        widget.empresaRfc.trim().isNotEmpty ||
        widget.empresaTelefono.trim().isNotEmpty ||
        widget.empresaEmail.trim().isNotEmpty ||
        widget.empresaDireccion.trim().isNotEmpty;

    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.business_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          if (hasAdditionalData) ...[
            const SizedBox(height: 10),
            if (widget.empresaId.trim().isNotEmpty)
              Text(
                'ID: ${widget.empresaId.trim()}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            if (widget.empresaRfc.trim().isNotEmpty)
              Text(
                'RFC: ${widget.empresaRfc.trim()}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            if (widget.empresaTelefono.trim().isNotEmpty)
              Text(
                'Teléfono: ${widget.empresaTelefono.trim()}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            if (widget.empresaEmail.trim().isNotEmpty)
              Text(
                'Correo: ${widget.empresaEmail.trim()}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            if (widget.empresaDireccion.trim().isNotEmpty)
              Text(
                'Dirección: ${widget.empresaDireccion.trim()}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.90,
            maxWidth: 600,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: cs.onPrimaryContainer,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Usuario actual',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildCompanySummary(),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.name,
                  maxLength: 100,
                  scrollPadding: const EdgeInsets.only(bottom: 140),
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Nombre del usuario',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 14),
                _readOnlyField(
                  label: 'Correo',
                  value: _display(widget.email, 'No disponible'),
                  icon: Icons.email_outlined,
                ),
                const SizedBox(height: 14),
                _readOnlyField(
                  label: 'Número de usuario',
                  value: _display(widget.numeroUsuario, 'No disponible'),
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 14),
                _readOnlyField(
                  label: 'Rol',
                  value: _display(widget.rol, 'No disponible'),
                  icon: Icons.admin_panel_settings_outlined,
                ),
                const SizedBox(height: 14),
                _readOnlyField(
                  label: 'Empresa',
                  value: _display(widget.empresa, 'Empresa actual'),
                  icon: Icons.business_outlined,
                ),
                const SizedBox(height: 14),
                _readOnlyField(
                  label: 'ID de usuario',
                  value: _display(widget.userId, 'No disponible'),
                  icon: Icons.numbers_outlined,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.secondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.secondary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El correo, número de usuario, rol e ID son administrados por '
                          'el sistema y no pueden modificarse desde este dispositivo.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pop(false),
                        child: const Text('Cerrar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Guardando...' : 'Guardar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DIÁLOGO DE TICKET
// ============================================================

class _TicketConfigDialog extends StatefulWidget {
  const _TicketConfigDialog({required this.initialConfig});

  final Map<String, dynamic> initialConfig;

  @override
  State<_TicketConfigDialog> createState() => _TicketConfigDialogState();
}

class _TicketConfigDialogState extends State<_TicketConfigDialog> {
  late final TextEditingController _header;
  late final TextEditingController _footer;
  late final TextEditingController _qrContent;

  late String _paper;
  late String _font;
  late String _alignment;

  late double _fontSize;
  late int _copies;

  late bool _showLogo;
  late bool _showAddress;
  late bool _showPhone;
  late bool _showEmail;
  late bool _showSeller;
  late bool _showPaymentMethod;
  late bool _showChange;
  late bool _showFolio;
  late bool _showDate;
  late bool _cutTicket;

  late bool _showBusinessName;
  late bool _showProducts;
  late bool _showTotal;

  late bool _showQr;

  Map<String, dynamic> get _fields {
    final value = widget.initialConfig['campos'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List) {
      final result = <String, dynamic>{};

      for (final item in value) {
        if (item is! Map) continue;

        final name = item['nombre']?.toString().trim();

        if (name == null || name.isEmpty) {
          continue;
        }

        result[name] = item['visible'] != false;
      }

      return result;
    }

    return <String, dynamic>{};
  }

  bool _readBool(List<String> keys, {bool fallback = false}) {
    for (final key in keys) {
      final value = widget.initialConfig[key];

      if (value == null) continue;

      if (value is bool) {
        return value;
      }

      if (value is num) {
        return value != 0;
      }

      final text = value.toString().trim().toLowerCase();

      if (text == 'true' ||
          text == '1' ||
          text == 'si' ||
          text == 'sí' ||
          text == 'yes') {
        return true;
      }

      if (text == 'false' || text == '0' || text == 'no') {
        return false;
      }
    }

    return fallback;
  }

  int _readInt(
    List<String> keys, {
    int fallback = 1,
    int min = 1,
    int max = 10,
  }) {
    for (final key in keys) {
      final value = widget.initialConfig[key];

      if (value == null) continue;

      final parsed = int.tryParse(value.toString());

      if (parsed != null) {
        return parsed.clamp(min, max).toInt();
      }
    }

    return fallback.clamp(min, max).toInt();
  }

  String _readString(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = widget.initialConfig[key];

      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  bool _fieldVisible(String name, {bool fallback = true}) {
    final value = _fields[name];

    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    return value.toString().toLowerCase() != 'false';
  }

  @override
  void initState() {
    super.initState();

    _header = TextEditingController(
      text: _readString(const ['cabecera', 'encabezado']),
    );

    _footer = TextEditingController(
      text: _readString(const ['pie_pagina', 'pie']),
    );

    _qrContent = TextEditingController(
      text: _readString(const ['qr_contenido', 'qrContenido']),
    );

    final configuredPaper = _readString(const ['papel'], fallback: '58mm');

    _paper = configuredPaper == '80mm' ? '80mm' : '58mm';

    final configuredFont = _readString(const ['fuente'], fallback: 'Arial');

    _font = const ['Arial', 'Roboto', 'Courier'].contains(configuredFont)
        ? configuredFont
        : 'Arial';

    final configuredAlignment = _readString(const [
      'alineacion',
    ], fallback: 'izquierda').toLowerCase();

    if (configuredAlignment == 'centro' || configuredAlignment == 'center') {
      _alignment = 'centro';
    } else if (configuredAlignment == 'derecha' ||
        configuredAlignment == 'right') {
      _alignment = 'derecha';
    } else {
      _alignment = 'izquierda';
    }

    final configuredSize =
        double.tryParse(
          _readString(const ['tamano_fuente', 'font_size'], fallback: '12'),
        ) ??
        12;

    _fontSize = configuredSize.clamp(8, 30);

    _copies = _readInt(
      const ['copias', 'copies'],
      fallback: 1,
      min: 1,
      max: 10,
    );

    _showLogo = _readBool(const ['mostrar_logo'], fallback: false);
    _showAddress = _readBool(const ['mostrar_direccion'], fallback: true);
    _showPhone = _readBool(const ['mostrar_telefono'], fallback: true);
    _showEmail = _readBool(const ['mostrar_email'], fallback: false);
    _showSeller = _readBool(const ['mostrar_vendedor'], fallback: true);

    _showPaymentMethod = _readBool(const [
      'mostrar_metodo_pago',
    ], fallback: true);

    _showChange = _readBool(const ['mostrar_cambio'], fallback: true);
    _showFolio = _readBool(const ['mostrar_folio'], fallback: true);
    _showDate = _readBool(const ['mostrar_fecha'], fallback: true);
    _cutTicket = _readBool(const ['cortar_ticket'], fallback: true);

    _showBusinessName = _readBool(const [
      'mostrar_nombre_negocio',
    ], fallback: _fieldVisible('nombre_negocio', fallback: true));

    _showProducts = _readBool(const [
      'mostrar_productos',
    ], fallback: _fieldVisible('productos', fallback: true));

    _showTotal = _readBool(const [
      'mostrar_total',
    ], fallback: _fieldVisible('total', fallback: true));

    _showQr = _readBool(const ['mostrar_qr', 'mostrarQr'], fallback: false);
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _qrContent.dispose();
    super.dispose();
  }

  void _save() {
    final header = _header.text.trim();

    final footer = _footer.text.trim();

    final qrContent = _qrContent.text.trim();

    if (header.length > 200) {
      _showMessage('La cabecera no puede superar 200 caracteres.');
      return;
    }

    if (footer.length > 200) {
      _showMessage('El pie no puede superar 200 caracteres.');
      return;
    }

    if (_showQr && qrContent.isEmpty) {
      _showMessage('Ingresa el contenido del QR o desactiva el código QR.');
      return;
    }

    if (qrContent.length > 2000) {
      _showMessage('El contenido del QR no puede superar 2000 caracteres.');
      return;
    }

    final fields = <String, bool>{
      'nombre_negocio': _showBusinessName,
      'productos': _showProducts,
      'total': _showTotal,
    };

    Navigator.of(context, rootNavigator: true).pop(<String, dynamic>{
      'papel': _paper,
      'fuente': _font,
      'tamano_fuente': _fontSize.round(),
      'alineacion': _alignment,
      'mostrar_logo': _showLogo,
      'mostrar_direccion': _showAddress,
      'mostrar_telefono': _showPhone,
      'mostrar_email': _showEmail,
      'mostrar_vendedor': _showSeller,
      'mostrar_metodo_pago': _showPaymentMethod,
      'mostrar_cambio': _showChange,
      'mostrar_folio': _showFolio,
      'mostrar_fecha': _showDate,
      'cortar_ticket': _cutTicket,
      'copias': _copies,
      'mostrar_nombre_negocio': _showBusinessName,
      'mostrar_productos': _showProducts,
      'mostrar_total': _showTotal,
      'mostrar_qr': _showQr,
      'qr_contenido': qrContent,
      'campos': fields.entries
          .map((entry) => {'nombre': entry.key, 'visible': entry.value})
          .toList(),
      'cabecera': header,
      'pie_pagina': footer,
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      secondary: icon == null ? null : Icon(icon),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${value.round()}$suffix',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '${value.round()}$suffix',
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildQrPreview(BuildContext context) {
    final content = _qrContent.text.trim();
    final cs = Theme.of(context).colorScheme;

    if (!_showQr || content.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Activa el QR e ingresa su contenido para '
                'ver la previsualización.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          const Text(
            'Vista previa del QR',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          QrImageView(
            data: content,
            version: QrVersions.auto,
            size: _paper == '80mm' ? 180 : 150,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.all(8),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este es el QR que se enviará a la impresora.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.94,
            maxWidth: 680,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: cs.onPrimaryContainer,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ticket y formato',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Configura la apariencia y los datos impresos.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionCard(
                        context: context,
                        title: 'Formato de impresión',
                        subtitle: 'Define el papel y la tipografía del ticket.',
                        icon: Icons.settings_outlined,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _paper,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: '58mm',
                                  child: Text('58 mm'),
                                ),
                                DropdownMenuItem(
                                  value: '80mm',
                                  child: Text('80 mm'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() => _paper = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Tamaño de papel',
                                prefixIcon: Icon(Icons.receipt_long_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _font,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Arial',
                                        child: Text('Arial'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Roboto',
                                        child: Text('Roboto'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Courier',
                                        child: Text('Courier'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() => _font = value);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'Fuente',
                                      prefixIcon: Icon(
                                        Icons.font_download_outlined,
                                      ),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _alignment,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'izquierda',
                                        child: Text('Izquierda'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'centro',
                                        child: Text('Centro'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'derecha',
                                        child: Text('Derecha'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() => _alignment = value);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'Alineación',
                                      prefixIcon: Icon(
                                        Icons.format_align_center,
                                      ),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _sliderRow(
                              label: 'Tamaño de fuente',
                              value: _fontSize,
                              min: 8,
                              max: 30,
                              divisions: 22,
                              suffix: ' pt',
                              onChanged: (value) {
                                setState(() => _fontSize = value);
                              },
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              initialValue: _copies,
                              isExpanded: true,
                              items: List.generate(10, (index) {
                                final value = index + 1;

                                return DropdownMenuItem<int>(
                                  value: value,
                                  child: Text(
                                    value == 1 ? '1 copia' : '$value copias',
                                  ),
                                );
                              }),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() => _copies = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Copias',
                                prefixIcon: Icon(Icons.content_copy_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _switchTile(
                              title: 'Cortar ticket automáticamente',
                              subtitle: 'Envía la orden de corte al finalizar la impresión.',
                              value: _cutTicket,
                              icon: Icons.content_cut_outlined,
                              onChanged: (value) {
                                setState(() => _cutTicket = value);
                              },
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        context: context,
                        title: 'Encabezado y pie',
                        subtitle:
                            'Textos adicionales que aparecerán en el ticket.',
                        icon: Icons.vertical_align_top_outlined,
                        child: Column(
                          children: [
                            TextField(
                              controller: _header,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.sentences,
                              maxLength: 200,
                              minLines: 1,
                              maxLines: 3,
                              scrollPadding: const EdgeInsets.only(bottom: 140),
                              decoration: const InputDecoration(
                                labelText: 'Cabecera',
                                hintText: 'Texto que aparecerá debajo de los datos de empresa.',
                                prefixIcon: Icon(
                                  Icons.vertical_align_top_outlined,
                                ),
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _footer,
                              textInputAction: TextInputAction.done,
                              textCapitalization: TextCapitalization.sentences,
                              maxLength: 200,
                              minLines: 1,
                              maxLines: 3,
                              scrollPadding: const EdgeInsets.only(bottom: 140),
                              decoration: const InputDecoration(
                                labelText: 'Pie de página',
                                hintText: 'Gracias por su compra',
                                prefixIcon: Icon(
                                  Icons.vertical_align_bottom_outlined,
                                ),
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        context: context,
                        title: 'Código QR',
                        subtitle: 'Configura el contenido que aparecerá como código QR en el ticket.',
                        icon: Icons.qr_code_2_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _switchTile(
                              title: 'Mostrar código QR',
                              subtitle: 'El QR aparecerá al final del ticket impreso.',
                              value: _showQr,
                              icon: Icons.qr_code_2_outlined,
                              onChanged: (value) {
                                setState(() => _showQr = value);
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _qrContent,
                              enabled: _showQr,
                              minLines: 2,
                              maxLines: 5,
                              maxLength: 2000,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                labelText: 'Contenido del QR',
                                hintText: 'Ejemplo: https://miempresa.com/consulta/12345',
                                prefixIcon: Icon(Icons.link_outlined),
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildQrPreview(context),
                          ],
                        ),
                      ),
                      _sectionCard(
                        context: context,
                        title: 'Información de empresa',
                        subtitle: 'Selecciona qué datos de la empresa aparecerán impresos.',
                        icon: Icons.business_outlined,
                        child: Column(
                          children: [
                            _switchTile(
                              title: 'Nombre del negocio',
                              subtitle: 'Muestra el nombre de la empresa.',
                              value: _showBusinessName,
                              icon: Icons.business_outlined,
                              onChanged: (value) {
                                setState(() => _showBusinessName = value);
                              },
                            ),
                            _switchTile(
                              title: 'Logo',
                              subtitle:
                                  'Muestra el logo configurado cuando exista.',
                              value: _showLogo,
                              icon: Icons.image_outlined,
                              onChanged: (value) {
                                setState(() => _showLogo = value);
                              },
                            ),
                            _switchTile(
                              title: 'Dirección',
                              subtitle: 'Muestra la dirección registrada de la empresa.',
                              value: _showAddress,
                              icon: Icons.location_on_outlined,
                              onChanged: (value) {
                                setState(() => _showAddress = value);
                              },
                            ),
                            _switchTile(
                              title: 'Teléfono',
                              subtitle: 'Muestra el teléfono de contacto.',
                              value: _showPhone,
                              icon: Icons.phone_outlined,
                              onChanged: (value) {
                                setState(() => _showPhone = value);
                              },
                            ),
                            _switchTile(
                              title: 'Correo electrónico',
                              subtitle: 'Muestra el correo de contacto.',
                              value: _showEmail,
                              icon: Icons.email_outlined,
                              onChanged: (value) {
                                setState(() => _showEmail = value);
                              },
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        context: context,
                        title: 'Información de venta',
                        subtitle: 'Controla los datos operativos visibles en el ticket.',
                        icon: Icons.point_of_sale_outlined,
                        child: Column(
                          children: [
                            _switchTile(
                              title: 'Folio',
                              subtitle: 'Muestra el folio de la venta.',
                              value: _showFolio,
                              icon: Icons.confirmation_number_outlined,
                              onChanged: (value) {
                                setState(() => _showFolio = value);
                              },
                            ),
                            _switchTile(
                              title: 'Fecha',
                              subtitle: 'Muestra la fecha de la venta.',
                              value: _showDate,
                              icon: Icons.calendar_today_outlined,
                              onChanged: (value) {
                                setState(() => _showDate = value);
                              },
                            ),
                            _switchTile(
                              title: 'Vendedor',
                              subtitle:
                                  'Muestra el usuario o vendedor asociado.',
                              value: _showSeller,
                              icon: Icons.person_outline,
                              onChanged: (value) {
                                setState(() => _showSeller = value);
                              },
                            ),
                            _switchTile(
                              title: 'Productos',
                              subtitle:
                                  'Muestra el detalle de productos vendidos.',
                              value: _showProducts,
                              icon: Icons.inventory_2_outlined,
                              onChanged: (value) {
                                setState(() => _showProducts = value);
                              },
                            ),
                            _switchTile(
                              title: 'Total',
                              subtitle: 'Muestra el total de la venta.',
                              value: _showTotal,
                              icon: Icons.payments_outlined,
                              onChanged: (value) {
                                setState(() => _showTotal = value);
                              },
                            ),
                            _switchTile(
                              title: 'Método de pago',
                              subtitle: 'Muestra la forma de pago utilizada.',
                              value: _showPaymentMethod,
                              icon: Icons.credit_card_outlined,
                              onChanged: (value) {
                                setState(() => _showPaymentMethod = value);
                              },
                            ),
                            _switchTile(
                              title: 'Cambio',
                              subtitle:
                                  'Muestra el cambio entregado al cliente.',
                              value: _showChange,
                              icon: Icons.currency_exchange_outlined,
                              onChanged: (value) {
                                setState(() => _showChange = value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TÍTULO DE SECCIÓN
// ============================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ============================================================
// SETTING TILE
// ============================================================

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: Icon(Icons.chevron_right, color: cs.primary),
          onTap: onTap,
        ),
      ),
    );
  }
}
