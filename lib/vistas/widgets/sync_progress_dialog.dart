import 'package:flutter/material.dart';

/// Diálogo modal de progreso durante la sincronización.
///
/// Uso:
///
/// ```dart
/// final progressNotifier = ValueNotifier<String>('Iniciando...');
///
/// showDialog<void>(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => SyncProgressDialog(progressNotifier: progressNotifier),
/// );
///
/// // Durante el proceso:
/// progressNotifier.value = 'Subiendo ventas...';
/// ```
///
/// Todos los colores provienen del `Theme.of(context).colorScheme`,
/// por lo que el diálogo respeta el seed color configurado en
/// `AppTheme` y funciona tanto en modo claro como oscuro.
class SyncProgressDialog extends StatelessWidget {
  const SyncProgressDialog({
    super.key,
    required this.progressNotifier,
    this.title = 'Sincronizando',
  });

  final ValueNotifier<String> progressNotifier;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      content: ValueListenableBuilder<String>(
        valueListenable: progressNotifier,
        builder: (context, message, _) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: Text(
                    message.isEmpty ? 'Preparando...' : message,
                    key: ValueKey(message),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'No cierres la aplicación',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}