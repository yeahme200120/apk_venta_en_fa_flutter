import 'package:flutter/material.dart';

import '../../core/config/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';
import '../auth/login_screen.dart';
import '../catalog/day_catalog_screen.dart';
import '../catalog/catalog_admin_screen.dart';
import 'printer_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await AppStorage().logOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _downloadCatalog(BuildContext context) async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    if (companyId == 0 || userId == 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay sesión activa para descargar catálogos.')),
      );
      return;
    }

    try {
      await CatalogService().downloadCatalogForToday(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catálogos del día descargados correctamente.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descargar el catálogo: $error')),
      );
    }
  }

  Future<void> _syncNow(BuildContext context) async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    try {
      await SyncService().syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronización manual completada.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible sincronizar: $error')),
      );
    }
  }

  Future<void> _showSessionInfo(BuildContext context, String title, String value) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(value),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<void> _showCompanyInfo(BuildContext context) async {
    final companyId = await AppStorage().getEmpresaId();
    final companyName = await AppStorage().getCompanyName();
    if (!context.mounted) return;
    await _showSessionInfo(context, 'Empresa actual', '${companyName ?? 'Empresa sin nombre'}\nID técnico: ${companyId ?? 'No disponible'}');
  }

  Future<void> _editBranding(BuildContext context) async {
    final controller = TextEditingController(text: AppTheme.seedColor.value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2));
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Colores y branding'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Color hexadecimal', prefixText: '#'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.replaceFirst('#', ''), radix: 16);
              if (value != null && controller.text.replaceFirst('#', '').length == 6) Navigator.pop(context, Color(0xFF000000 | value));
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (color != null) AppTheme.setSeedColor(color);
  }

  Future<void> _showCurrentUser(BuildContext context) async {
    try {
      final user = await ApiClient().getCurrentUser();
      if (!context.mounted) return;
      final name = TextEditingController(text: user['name']?.toString() ?? '');
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Usuario actual'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
                TextFormField(initialValue: user['email']?.toString() ?? '', readOnly: true, decoration: const InputDecoration(labelText: 'Correo')), 
                TextFormField(initialValue: user['numero_usuario']?.toString() ?? '', readOnly: true, decoration: const InputDecoration(labelText: 'Número de usuario')), 
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar')),
            FilledButton(
              onPressed: () async {
                await ApiClient().updateProfile({'name': name.text.trim()});
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Guardar nombre'),
            ),
          ],
        ),
      );
      name.dispose();
      if (result == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuario actualizado.')));
      }
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cargar el usuario: $error')));
    }
  }

  Future<void> _editTicket(BuildContext context) async {
    final local = await AppStorage().getTicketConfig();
    if (!context.mounted) return;
    final header = TextEditingController(text: local['cabecera']?.toString() ?? '');
    final footer = TextEditingController(text: local['pie_pagina']?.toString() ?? '');
    var paper = local['papel']?.toString() ?? '58mm';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ticket y formato'),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: paper,
                items: const [DropdownMenuItem(value: '58mm', child: Text('58 mm')), DropdownMenuItem(value: '80mm', child: Text('80 mm'))],
                onChanged: (value) => setDialogState(() => paper = value ?? '58mm'),
                decoration: const InputDecoration(labelText: 'Papel'),
              ),
              TextField(controller: header, decoration: const InputDecoration(labelText: 'Cabecera')),
              TextField(controller: footer, decoration: const InputDecoration(labelText: 'Pie de página')),
            ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, {'papel': paper, 'cabecera': header.text, 'pie_pagina': footer.text}), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    header.dispose();
    footer.dispose();
    if (result == null) return;
    await AppStorage().saveTicketConfig(result);
    try {
      await ApiClient().updateTicketConfig(result);
    } catch (_) {
      // La configuración local permanece disponible sin conexión.
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket guardado localmente y enviado al servidor si hay conexión.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administración y configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Empresa'),
          _SettingTile(
            title: 'Empresa actual',
            subtitle: 'Consulta la empresa activa de esta sesión.',
            icon: Icons.business_outlined,
            onTap: () => _showCompanyInfo(context),
          ),
          _SettingTile(
            title: 'Colores y branding',
            subtitle: 'Configuración visual de la empresa.',
            icon: Icons.palette_outlined,
            onTap: () => _editBranding(context),
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
            subtitle: 'Consulta la configuración local del dispositivo.',
            icon: Icons.devices_outlined,
            onTap: () => _showSessionInfo(context, 'Dispositivo actual', 'La configuración local está activa.'),
          ),
          _SettingTile(
            title: 'Impresoras',
            subtitle: 'Bluetooth, USB y red.',
            icon: Icons.print_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
            ),
          ),
          _SettingTile(
            title: 'Usuario actual',
            subtitle: 'Perfil y contraseña.',
            icon: Icons.person_outline,
            onTap: () => _showCurrentUser(context),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Sistema'),
          _SettingTile(
            title: 'Catálogos del día',
            subtitle: 'Descarga por internet y prepara la base del día.',
            icon: Icons.download_outlined,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DayCatalogScreen()),
              );
            },
          ),
          _SettingTile(
            title: 'Administrar catálogo',
            subtitle: 'Crear, editar o desactivar productos offline.',
            icon: Icons.inventory_2_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CatalogAdminScreen()),
            ),
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
            subtitle: 'Borra la sesión local del dispositivo.',
            icon: Icons.logout,
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF3A3A3A),
        ),
      ),
    );
  }
}

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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF9AC53B).withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9AC53B).withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF9AC53B).withAlpha(18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF9AC53B)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF9AC53B)),
        onTap: onTap,
      ),
    );
  }
}
