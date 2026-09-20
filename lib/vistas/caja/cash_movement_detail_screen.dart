import 'package:flutter/material.dart';

import '../../core/services/pdf_service.dart';
import '../../core/services/printer_service.dart';
import '../../core/services/whatsapp_service.dart';

/// Pantalla de detalle de un movimiento de caja.
///
/// Reutiliza el mismo flujo de PDF / impresión que las ventas:
///   • Botón "Imprimir" → impresora térmica vía PrinterService.
///   • Botón "Compartir PDF" → WhatsAppService.sharePdf (selector nativo).
///
/// Los datos vienen como Map crudo desde LocalDb (mismo formato que
/// el usado por CashManagementScreen).
class CashMovementDetailScreen extends StatefulWidget {
  const CashMovementDetailScreen({
    super.key,
    required this.movement,
    this.cajaNombre,
    this.fechaComercial,
  });

  final Map<String, dynamic> movement;
  final String? cajaNombre;
  final String? fechaComercial;

  @override
  State<CashMovementDetailScreen> createState() =>
      _CashMovementDetailScreenState();
}

class _CashMovementDetailScreenState extends State<CashMovementDetailScreen> {
  final PrinterService _printerService = PrinterService();

  bool _printing = false;
  bool _sharing = false;

  // ============================================================
  // HELPERS
  // ============================================================

  String get _tipo => widget.movement['tipo']?.toString().toLowerCase() ?? '';

  String get _tipoLabel {
    switch (_tipo) {
      case 'ingreso':
        return 'Ingreso';
      case 'egreso':
        return 'Egreso';
      case 'retiro':
        return 'Retiro';
      case 'ajuste':
        return 'Ajuste';
      default:
        return _tipo.isEmpty ? '—' : _tipo;
    }
  }

  Color _tipoColor(ColorScheme cs) {
    switch (_tipo) {
      case 'ingreso':
        return cs.primary;
      case 'egreso':
        return cs.error;
      case 'retiro':
        return cs.tertiary;
      case 'ajuste':
        return cs.secondary;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData get _tipoIcon => switch (_tipo) {
        'ingreso' => Icons.arrow_downward,
        'egreso' => Icons.arrow_upward,
        'retiro' => Icons.savings_outlined,
        'ajuste' => Icons.tune,
        _ => Icons.circle_outlined,
      };

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _money(dynamic v) => '\$${_d(v).toStringAsFixed(2)}';

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _payload() {
    return Map<String, dynamic>.from(widget.movement)
      ..['caja_nombre'] = widget.cajaNombre
      ..['fecha_comercial'] = widget.fechaComercial;
  }

  // ============================================================
  // IMPRIMIR
  // ============================================================

  Future<void> _imprimir() async {
    if (_printing) return;
    setState(() => _printing = true);

    try {
      final config = await _printerService.loadCachedTicketConfig();

      final result = await _printerService.printMovementByTipo(
        _payload(),
        config: config,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success
              ? null
              : Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible imprimir: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ============================================================
  // COMPARTIR PDF
  // ============================================================

  Future<void> _compartirPdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final config = await _printerService.loadCachedTicketConfig();

      final bytes = await PdfService.generateCashMovementPdf(
        movement: _payload(),
        config: config,
      );

      final folio = widget.movement['folio']?.toString().trim();
      final tipo = _tipo.isEmpty ? 'movimiento' : _tipo;

      final fileName = (folio != null && folio.isNotEmpty)
          ? '${tipo}_$folio.pdf'
          : '${tipo}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      await WhatsAppService.sharePdf(
        bytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible compartir: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _tipoColor(cs);

    return Scaffold(
      appBar: AppBar(
        title: Text('Detalle · $_tipoLabel'),
        actions: [
          IconButton(
            tooltip: 'Imprimir',
            onPressed: _printing ? null : _imprimir,
            icon: _printing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Compartir PDF',
            onPressed: _sharing ? null : _compartirPdf,
            icon: _sharing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // =========================================================
          // TARJETA PRINCIPAL
          // =========================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_tipoIcon, color: color, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _tipoLabel,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fmt(widget.movement['registrado_at']?.toString()),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _money(widget.movement['monto']),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _row('Folio', widget.movement['folio']?.toString()),
                  _row('Concepto', widget.movement['concepto']?.toString()),
                  _row(
                    'Forma de pago',
                    widget.movement['forma_pago']?.toString(),
                  ),
                  _row('Referencia', widget.movement['referencia']?.toString()),
                  _row('Notas', widget.movement['notas']?.toString()),
                  _row('Usuario', widget.movement['usuario']?.toString()),
                  _row('Caja', widget.cajaNombre),
                  _row('Fecha comercial', widget.fechaComercial),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // =========================================================
          // BOTONES GRANDES
          // =========================================================
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printing ? null : _imprimir,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Imprimir'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _compartirPdf,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Compartir PDF'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}