import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config/app_theme.dart';
import '../../core/database/pos_db_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_monitor.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';
import '../auth/login_screen.dart';
import '../catalog/catalog_admin_screen.dart';
import 'printer_settings_screen.dart';
import 'company_logo_screen.dart';

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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

    try {
      await CatalogService().downloadCatalogForToday(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
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
  // SINCRONIZAR
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

    final String? rawBusinessDate = await AppStorage().getBusinessDate();

    final DateTime businessDate =
        DateTime.tryParse(rawBusinessDate ?? '') ?? DateTime.now();

    try {
      await SyncService().syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
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

  // ============================================================
  // LIMPIAR DATOS DEL DÍA
  // ============================================================

  Future<void> _limpiarDia(BuildContext context) async {
    final networkMonitor = NetworkMonitor();

    if (!networkMonitor.isOnline) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
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
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar datos del día'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción eliminará todas las ventas y datos de la jornada '
              'actual de este dispositivo. La sesión permanece activa.',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 10),
            Text(
              'Antes de limpiar, se sincronizarán automáticamente las ventas '
              'pendientes con el servidor.',
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpiar de todos modos'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) {
      return;
    }

    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Sincronizando ventas pendientes...'),
          ],
        ),
      ),
    );

    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;

      final userId = await AppStorage().getUserId() ?? 0;

      final String? rawBusinessDate = await AppStorage().getBusinessDate();

      final DateTime businessDate =
          DateTime.tryParse(rawBusinessDate ?? '') ?? DateTime.now();

      if (companyId <= 0 || userId <= 0) {
        throw Exception('No hay sesión activa.');
      }

      final syncResult = await SyncService().syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      if (syncResult.failed > 0 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Se sincronizaron ${syncResult.synced} ventas, '
              'pero ${syncResult.failed} fallaron. La limpieza continuará.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      await PosDatabaseService().deleteDatabaseFile(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      await AppStorage().saveBusinessDate(nowIso);

      await AppStorage().saveServerBusinessDate(nowIso);

      await AppStorage().saveOperationState({});

      if (context.mounted) {
        Navigator.of(context).pop(progressDialog);
      }

      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Datos del día eliminados'),
          content: const Text(
            'La base de datos del día se ha limpiado correctamente. '
            'La sesión sigue activa.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context).pop(progressDialog);
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al limpiar: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administración y configuración')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Empresa'),
          _SettingTile(
            title: 'Empresa actual',
            subtitle: 'Consulta los datos del negocio activo en esta sesión.',
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
            subtitle:
                'Sistema operativo, versión de app, red y datos de instalación.',
            icon: Icons.devices_outlined,
            onTap: () => _showDeviceInfo(context),
          ),
          _SettingTile(
            title: 'Impresoras',
            subtitle: 'Bluetooth, USB y red.',
            icon: Icons.print_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Sistema'),
          _SettingTile(
            title: 'Administrar catálogo',
            subtitle:
                'Crear, editar o desactivar categorías, productos y formas de pago.',
            icon: Icons.inventory_2_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CatalogAdminScreen()),
            ),
          ),
          _SettingTile(
            title: 'Limpiar datos del día',
            subtitle:
                'Elimina las ventas y datos de la jornada actual de este dispositivo. '
                'La sesión permanece activa. Requiere Internet.',
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
            subtitle:
                'Borra la sesión local y los datos del día del dispositivo.',
            icon: Icons.logout,
            onTap: () => _logout(context),
          ),
        ],
      ),
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
    final displayValue = value.trim().isEmpty ? 'No disponible' : value.trim();

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(),
      ),
      child: Text(
        displayValue,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.black87),
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
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (widget.empresaRfc.trim().isNotEmpty)
              Text(
                'RFC: ${widget.empresaRfc.trim()}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (widget.empresaTelefono.trim().isNotEmpty)
              Text(
                'Teléfono: ${widget.empresaTelefono.trim()}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (widget.empresaEmail.trim().isNotEmpty)
              Text(
                'Correo: ${widget.empresaEmail.trim()}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (widget.empresaDireccion.trim().isNotEmpty)
              Text(
                'Dirección: ${widget.empresaDireccion.trim()}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                    color: Colors.blue.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withAlpha(35)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El correo, número de usuario, rol e ID son administrados por '
                          'el sistema y no pueden modificarse desde este dispositivo.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
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
      text: _readString(const [
        'qr_contenido',
        'qrContenido',
      ]),
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

    _showQr = _readBool(
      const [
        'mostrar_qr',
        'mostrarQr',
      ],
      fallback: false,
    );
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
      _showMessage(
        'Ingresa el contenido del QR o desactiva el código QR.',
      );
      return;
    }

    if (qrContent.length > 2000) {
      _showMessage(
        'El contenido del QR no puede superar 2000 caracteres.',
      );
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

    if (!_showQr || content.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withAlpha(12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blueGrey.withAlpha(30),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Colors.blueGrey,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Activa el QR e ingresa su contenido para '
                'ver la previsualización.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
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
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Vista previa del QR',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
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
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ticket y formato',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Configura la apariencia y los datos impresos.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
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
                              subtitle:
                                  'Envía la orden de corte al finalizar la impresión.',
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
                                hintText:
                                    'Texto que aparecerá debajo de los datos de empresa.',
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
                        subtitle:
                            'Configura el contenido que aparecerá como código QR en el ticket.',
                        icon: Icons.qr_code_2_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _switchTile(
                              title: 'Mostrar código QR',
                              subtitle:
                                  'El QR aparecerá al final del ticket impreso.',
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
                                hintText:
                                    'Ejemplo: https://miempresa.com/consulta/12345',
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
                        subtitle:
                            'Selecciona qué datos de la empresa aparecerán impresos.',
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
                              subtitle:
                                  'Muestra la dirección registrada de la empresa.',
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
                        subtitle:
                            'Controla los datos operativos visibles en el ticket.',
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.07),
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
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: cs.primary),
        onTap: onTap,
      ),
    );
  }
}