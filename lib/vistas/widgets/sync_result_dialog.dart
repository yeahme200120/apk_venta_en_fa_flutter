import 'package:flutter/material.dart';

import '../../core/services/sync_orchestrator.dart';

/// Muestra el resultado de una sincronización con estilo unificado
/// en todas las pantallas que usan `SyncOrchestrator.syncAll()`.
///
/// Reglas:
///   • Sin errores  → SnackBar con icono de check.
///   • Skipped      → SnackBar informativo.
///   • Con errores  → AlertDialog con el detalle expandible.
///
/// Todos los colores provienen de `Theme.of(context).colorScheme`,
/// así que respeta el seed color global.
Future<void> showSyncResultDialog(
  BuildContext context, {
  required SyncReport report,
  VoidCallback? onRetry,
}) async {
  if (!context.mounted) return;

  final cs = Theme.of(context).colorScheme;

  if (report.skipped) {
    _showSnack(
      context,
      report.summary,
      icon: Icons.info_outline,
      color: cs.secondary,
    );
    return;
  }

  if (!report.hasErrors) {
    _showSnack(
      context,
      'Sincronización completada · '
      '${report.upload.synced}/${report.upload.total} subidas · '
      '${report.download.okCount}/${SyncDownloadReport.totalSteps} bajadas',
      icon: Icons.check_circle_outline,
      color: cs.primary,
    );
    return;
  }

  // Con errores → diálogo con detalle.
  final errorColor = cs.error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: errorColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: errorColor,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Sincronización con avisos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          maxWidth: 480,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow(
                ctx,
                'Subidas',
                '${report.upload.synced}/${report.upload.total}',
                Icons.cloud_upload_outlined,
              ),
              const SizedBox(height: 6),
              _summaryRow(
                ctx,
                'Bajadas',
                '${report.download.okCount}/${SyncDownloadReport.totalSteps}',
                Icons.cloud_download_outlined,
              ),
              if (report.errors.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Detalles:',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ...report.errors.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: errorColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: errorColor.withValues(alpha: 0.40),
                        ),
                      ),
                      child: Text(
                        e.toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onRetry();
            },
            child: const Text('Reintentar'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}

// ============================================================
// SNACKBAR UNIFICADO
// ============================================================

void _showSnack(
  BuildContext context,
  String message, {
  required IconData icon,
  required Color color,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Widget _summaryRow(
  BuildContext context,
  String label,
  String value,
  IconData icon,
) {
  final cs = Theme.of(context).colorScheme;
  return Row(
    children: [
      Icon(icon, size: 18, color: cs.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ),
      Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    ],
  );
}