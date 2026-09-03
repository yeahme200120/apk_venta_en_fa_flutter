import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';

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

  // ============================================================
  // CERRAR SESIÓN
  // ============================================================

  Future<void> _logout(BuildContext context) async {
    try {
      await AppStorage().logOut();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No fue posible cerrar sesión: $error',
          ),
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
          content: Text(
            'No hay sesión activa para descargar catálogos.',
          ),
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
          content: Text(
            'Catálogos del día descargados correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo descargar el catálogo: $error',
          ),
        ),
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
          content: Text(
            'No existe una sesión válida para sincronizar.',
          ),
        ),
      );

      return;
    }

    try {
      await SyncService().syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sincronización manual completada.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No fue posible sincronizar: $error',
          ),
        ),
      );
    }
  }

  // ============================================================
  // INFORMACIÓN GENERAL
  // ============================================================

  Future<void> _showSessionInfo(
    BuildContext context,
    String title,
    String value,
  ) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(dialogContext).height * 0.65,
            ),
            child: SingleChildScrollView(
              child: Text(value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                  rootNavigator: true,
                ).pop();
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXTRAER MAPA DE RESPUESTA
  // ============================================================

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  // ============================================================
  // NORMALIZAR RESPUESTA DE USUARIO
  // ============================================================

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

  // ============================================================
  // NORMALIZAR RESPUESTA DE EMPRESA
  // ============================================================

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

  // ============================================================
  // OBTENER VALOR SEGURO
  // ============================================================

  String _valueFromMap(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) continue;

      if (value is Map || value is List) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }

  String _userValue(
    Map<String, dynamic> user,
    List<String> keys,
  ) {
    return _valueFromMap(user, keys);
  }

  // ============================================================
  // INFORMACIÓN DE EMPRESA
  // ============================================================

  Future<void> _showCompanyInfo(
    BuildContext context,
  ) async {
    try {
      final localCompanyId = await AppStorage().getEmpresaId();
      final localCompanyName = await AppStorage().getCompanyName();

      Map<String, dynamic> company = <String, dynamic>{};
      String? apiError;

      try {
        final response = await ApiClient().getCompanyConfig();
        company = _extractCompany(response);
        print('🏢 Empresa recibida: $company');
      } catch (error) {
        apiError = error.toString();
        print('⚠️ No se pudo cargar configuración de empresa: $error');
      }

      final companyId = _valueFromMap(
        company,
        const [
          'id',
          'empresa_id',
          'company_id',
        ],
      );

      final name = _valueFromMap(
        company,
        const [
          'nombre',
          'name',
          'razon_social',
          'razonSocial',
        ],
      );

      final razonSocial = _valueFromMap(
        company,
        const [
          'razon_social',
          'razonSocial',
          'nombre',
          'name',
        ],
      );

      final rfc = _valueFromMap(
        company,
        const [
          'rfc',
          'RFC',
          'tax_id',
        ],
      );

      final telefono = _valueFromMap(
        company,
        const [
          'telefono',
          'phone',
          'telefono_contacto',
        ],
      );

      final email = _valueFromMap(
        company,
        const [
          'email',
          'correo',
          'correo_electronico',
          'contact_email',
        ],
      );

      final direccion = _valueFromMap(
        company,
        const [
          'direccion',
          'address',
          'domicilio',
        ],
      );

      final logo = _valueFromMap(
        company,
        const [
          'logo',
          'logo_url',
          'logoUrl',
        ],
      );

      final activo = _valueFromMap(
        company,
        const [
          'activo',
          'is_active',
          'active',
        ],
      );

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
      details.writeln(
        'RFC: ${rfc.isNotEmpty ? rfc : 'No disponible'}',
      );
      details.writeln(
        'Teléfono: ${telefono.isNotEmpty ? telefono : 'No disponible'}',
      );
      details.writeln(
        'Correo: ${email.isNotEmpty ? email : 'No disponible'}',
      );
      details.writeln(
        'Dirección: ${direccion.isNotEmpty ? direccion : 'No disponible'}',
      );
      details.writeln(
        'ID técnico: ${resolvedId.isNotEmpty ? resolvedId : 'No disponible'}',
      );
      details.writeln(
        'Estado: ${activo.isNotEmpty ? activo : 'No disponible'}',
      );
      details.write(
        'Logo: ${logo.isNotEmpty ? logo : 'No configurado'}',
      );

      if (apiError != null && company.isEmpty) {
        details.write('\n\nAviso: se mostró la información disponible localmente porque no fue posible consultar la configuración remota.');
      }

      await _showSessionInfo(
        context,
        'Empresa actual',
        details.toString(),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No fue posible consultar la empresa: $error',
          ),
        ),
      );
    }
  }

  // ============================================================
  // BRANDING
  // ============================================================

  Future<void> _editBranding(
    BuildContext context,
  ) async {
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subheading: const Text(
          'Colores disponibles',
        ),
        wheelSubheading: const Text(
          'Selecciona el tono',
        ),
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
        SnackBar(
          content: Text(
            'No fue posible cambiar el branding: $error',
          ),
        ),
      );
    }
  }

  // ============================================================
  // USUARIO ACTUAL
  // ============================================================

  Future<void> _showCurrentUser(
    BuildContext context,
  ) async {
    try {
      final userResponse =
          await ApiClient().getCurrentUser();

      final user = _extractUser(userResponse);

      print('👤 Usuario recibido: $user');

      Map<String, dynamic> company = <String, dynamic>{};

      // Primero intenta la empresa que venga dentro de /user.
      final userCompany = user['empresa'];
      if (userCompany is Map) {
        company = Map<String, dynamic>.from(userCompany);
      }

      // Si no viene anidada, intenta la configuración específica.
      if (company.isEmpty) {
        try {
          final companyResponse =
              await ApiClient().getCompanyConfig();

          company = _extractCompany(companyResponse);

          print('🏢 Empresa recibida desde configuración: $company');
        } catch (error) {
          print(
            '⚠️ No se pudo consultar configuración de empresa: $error',
          );
        }
      }

      final storedCompanyName =
          await AppStorage().getCompanyName();
      final storedCompanyId =
          await AppStorage().getEmpresaId();

      final name = _userValue(
        user,
        const [
          'name',
          'nombre',
          'usuario_nombre',
        ],
      );

      final email = _userValue(
        user,
        const [
          'email',
          'correo',
          'correo_electronico',
        ],
      );

      final numeroUsuario = _userValue(
        user,
        const [
          'numero_usuario',
          'numeroUsuario',
          'numero',
          'user_number',
          'username',
        ],
      );

      final rol = _userValue(
        user,
        const [
          'rol',
          'role',
          'tipo_usuario',
        ],
      );

      final userId = _userValue(
        user,
        const [
          'id',
          'user_id',
        ],
      );

      final companyNameFromUser = _valueFromMap(
        user,
        const [
          'empresa_nombre',
          'company_name',
        ],
      );

      final companyNameFromCompany = _valueFromMap(
        company,
        const [
          'nombre',
          'name',
          'razon_social',
          'razonSocial',
        ],
      );

      final companyIdFromUser = _valueFromMap(
        user,
        const [
          'empresa_id',
          'company_id',
        ],
      );

      final companyIdFromCompany = _valueFromMap(
        company,
        const [
          'id',
          'empresa_id',
          'company_id',
        ],
      );

      final resolvedCompanyName =
          companyNameFromCompany.isNotEmpty
              ? companyNameFromCompany
              : (companyNameFromUser.isNotEmpty
                  ? companyNameFromUser
                  : (storedCompanyName?.trim() ?? ''));

      final resolvedCompanyId =
          companyIdFromCompany.isNotEmpty
              ? companyIdFromCompany
              : (companyIdFromUser.isNotEmpty
                  ? companyIdFromUser
                  : (storedCompanyId?.toString() ?? ''));

      final companyRfc = _valueFromMap(
        company,
        const [
          'rfc',
          'RFC',
          'tax_id',
        ],
      );

      final companyPhone = _valueFromMap(
        company,
        const [
          'telefono',
          'phone',
          'telefono_contacto',
        ],
      );

      final companyEmail = _valueFromMap(
        company,
        const [
          'email',
          'correo',
          'correo_electronico',
        ],
      );

      final companyAddress = _valueFromMap(
        company,
        const [
          'direccion',
          'address',
          'domicilio',
        ],
      );

      if (!context.mounted) {
        return;
      }

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

      if (!context.mounted) {
        return;
      }

      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Usuario actualizado correctamente.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo cargar la información del usuario: $error',
          ),
        ),
      );
    }
  }

  // ============================================================
  // CONFIGURACIÓN DE TICKET
  // ============================================================

  Future<void> _editTicket(
    BuildContext context,
  ) async {
    try {
      final local = await AppStorage().getTicketConfig();

      if (!context.mounted) return;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _TicketConfigDialog(
          initialConfig: local ?? <String, dynamic>{},
        ),
      );

      if (result == null) return;

      await AppStorage().saveTicketConfig(result);

      try {
        await ApiClient().updateTicketConfig(result);
      } catch (_) {
        // La configuración local permanece disponible.
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ticket guardado localmente y enviado al servidor si hay conexión.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No fue posible guardar el ticket: $error',
          ),
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Administración y configuración',
        ),
      ),
      body: ListView(
        keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Empresa'),

          _SettingTile(
            title: 'Empresa actual',
            subtitle:
                'Consulta los datos de la empresa activa de esta sesión.',
            icon: Icons.business_outlined,
            onTap: () => _showCompanyInfo(context),
          ),

          _SettingTile(
            title: 'Colores y branding',
            subtitle:
                'Configuración visual de la empresa.',
            icon: Icons.palette_outlined,
            onTap: () => _editBranding(context),
          ),

          _SettingTile(
            title: 'Ticket y formato',
            subtitle:
                'Papel, encabezado, pie y QR.',
            icon: Icons.receipt_long_outlined,
            onTap: () => _editTicket(context),
          ),

          const SizedBox(height: 16),

          const _SectionTitle('Dispositivo'),

          _SettingTile(
            title: 'Dispositivo actual',
            subtitle:
                'Consulta la configuración local del dispositivo.',
            icon: Icons.devices_outlined,
            onTap: () => _showSessionInfo(
              context,
              'Dispositivo actual',
              'La configuración local está activa.',
            ),
          ),

          _SettingTile(
            title: 'Impresoras',
            subtitle: 'Bluetooth, USB y red.',
            icon: Icons.print_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const PrinterSettingsScreen(),
              ),
            ),
          ),

          _SettingTile(
            title: 'Usuario actual',
            subtitle:
                'Perfil y configuración de acceso.',
            icon: Icons.person_outline,
            onTap: () => _showCurrentUser(context),
          ),

          const SizedBox(height: 16),

          const _SectionTitle('Sistema'),

          _SettingTile(
            title: 'Catálogos del día',
            subtitle:
                'Descarga por internet y prepara la base del día.',
            icon: Icons.download_outlined,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const DayCatalogScreen(),
                ),
              );
            },
          ),

          _SettingTile(
            title: 'Administrar catálogo',
            subtitle:
                'Crear, editar o desactivar productos offline.',
            icon: Icons.inventory_2_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const CatalogAdminScreen(),
              ),
            ),
          ),

          _SettingTile(
            title: 'Sincronizar ahora',
            subtitle:
                'Reintento manual de ventas pendientes y fallidas.',
            icon: Icons.sync_outlined,
            onTap: () => _syncNow(context),
          ),

          _SettingTile(
            title: 'Descargar catálogo ahora',
            subtitle:
                'Obtiene el inventario más reciente desde la API.',
            icon: Icons.cloud_download_outlined,
            onTap: () => _downloadCatalog(context),
          ),

          _SettingTile(
            title: 'Cerrar sesión',
            subtitle:
                'Borra la sesión local del dispositivo.',
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
  State<_UserProfileDialog> createState() =>
      _UserProfileDialogState();
}

class _UserProfileDialogState
    extends State<_UserProfileDialog> {
  late final TextEditingController _nameController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.initialName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALOR VISUAL
  // ============================================================

  String _display(
    String value,
    String fallback,
  ) {
    final text = value.trim();

    return text.isEmpty ? fallback : text;
  }

  // ============================================================
  // GUARDAR
  // ============================================================

  Future<void> _save() async {
    if (_saving) return;

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showMessage(
        'Ingresa el nombre del usuario.',
      );
      return;
    }

    if (name.length < 2) {
      _showMessage(
        'El nombre debe contener al menos 2 caracteres.',
      );
      return;
    }

    if (name.length > 100) {
      _showMessage(
        'El nombre no puede superar 100 caracteres.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await ApiClient().updateProfile({
        'name': name,
      });

      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showMessage(
        'No fue posible actualizar el usuario: $error',
      );
    }
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // CAMPO DE SOLO LECTURA
  // ============================================================

  Widget _readOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final displayValue =
        value.trim().isEmpty ? 'No disponible' : value.trim();

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
        style: const TextStyle(
          color: Colors.black87,
        ),
      ),
    );
  }

  // ============================================================
  // INFORMACIÓN DE EMPRESA
  // ============================================================

  Widget _buildCompanySummary() {
    final name = _display(
      widget.empresa,
      'Empresa actual',
    );

    final hasAdditionalData =
        widget.empresaId.trim().isNotEmpty ||
        widget.empresaRfc.trim().isNotEmpty ||
        widget.empresaTelefono.trim().isNotEmpty ||
        widget.empresaEmail.trim().isNotEmpty ||
        widget.empresaDireccion.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF9AC53B).withAlpha(18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF9AC53B).withAlpha(55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.business_outlined,
                color: Color(0xFF6B8E23),
              ),
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
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            if (widget.empresaRfc.trim().isNotEmpty)
              Text(
                'RFC: ${widget.empresaRfc.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            if (widget.empresaTelefono.trim().isNotEmpty)
              Text(
                'Teléfono: ${widget.empresaTelefono.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            if (widget.empresaEmail.trim().isNotEmpty)
              Text(
                'Correo: ${widget.empresaEmail.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            if (widget.empresaDireccion.trim().isNotEmpty)
              Text(
                'Dirección: ${widget.empresaDireccion.trim()}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height * 0.90,
            maxWidth: 600,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              12,
            ),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF9AC53B,
                        ).withAlpha(25),
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF6B8E23),
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
                          : () {
                              Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pop(false);
                            },
                      icon: const Icon(
                        Icons.close,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                _buildCompanySummary(),

                const SizedBox(height: 16),

                // --------------------------------------------------
                // NOMBRE
                // --------------------------------------------------

                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  textInputAction:
                      TextInputAction.done,
                  textCapitalization:
                      TextCapitalization.words,
                  keyboardType:
                      TextInputType.name,
                  maxLength: 100,
                  scrollPadding: const EdgeInsets.only(
                    bottom: 140,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText:
                        'Nombre del usuario',
                    prefixIcon: Icon(
                      Icons.person_outline,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    _save();
                  },
                ),

                const SizedBox(height: 14),

                // --------------------------------------------------
                // CORREO
                // --------------------------------------------------

                _readOnlyField(
                  label: 'Correo',
                  value: _display(
                    widget.email,
                    'No disponible',
                  ),
                  icon: Icons.email_outlined,
                ),

                const SizedBox(height: 14),

                // --------------------------------------------------
                // NÚMERO DE USUARIO
                // --------------------------------------------------

                _readOnlyField(
                  label: 'Número de usuario',
                  value: _display(
                    widget.numeroUsuario,
                    'No disponible',
                  ),
                  icon: Icons.badge_outlined,
                ),

                const SizedBox(height: 14),

                // --------------------------------------------------
                // ROL
                // --------------------------------------------------

                _readOnlyField(
                  label: 'Rol',
                  value: _display(
                    widget.rol,
                    'No disponible',
                  ),
                  icon: Icons.admin_panel_settings_outlined,
                ),

                const SizedBox(height: 14),

                // --------------------------------------------------
                // EMPRESA
                // --------------------------------------------------

                _readOnlyField(
                  label: 'Empresa',
                  value: _display(
                    widget.empresa,
                    'Empresa actual',
                  ),
                  icon: Icons.business_outlined,
                ),

                const SizedBox(height: 14),

                // --------------------------------------------------
                // ID
                // --------------------------------------------------

                _readOnlyField(
                  label: 'ID de usuario',
                  value: _display(
                    widget.userId,
                    'No disponible',
                  ),
                  icon: Icons.numbers_outlined,
                ),

                const SizedBox(height: 8),

                Container(
                  padding:
                      const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(12),
                    borderRadius:
                        BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          Colors.blue.withAlpha(35),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El correo, número de usuario, rol e ID '
                          'son administrados por el sistema y no '
                          'pueden modificarse desde este dispositivo.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --------------------------------------------------
                // BOTONES
                // --------------------------------------------------

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () {
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(false);
                              },
                        child: const Text(
                          'Cerrar',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.save_outlined,
                              ),
                        label: Text(
                          _saving
                              ? 'Guardando...'
                              : 'Guardar',
                        ),
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
  const _TicketConfigDialog({
    required this.initialConfig,
  });

  final Map<String, dynamic> initialConfig;

  @override
  State<_TicketConfigDialog> createState() =>
      _TicketConfigDialogState();
}

class _TicketConfigDialogState
    extends State<_TicketConfigDialog> {
  late final TextEditingController _header;
  late final TextEditingController _footer;

  late String _paper;

  @override
  void initState() {
    super.initState();

    _header = TextEditingController(
      text: widget.initialConfig['cabecera']
              ?.toString() ??
          '',
    );

    _footer = TextEditingController(
      text: widget.initialConfig['pie_pagina']
              ?.toString() ??
          '',
    );

    final configuredPaper =
        widget.initialConfig['papel']
                ?.toString()
                .trim() ??
            '58mm';

    _paper = configuredPaper == '80mm'
        ? '80mm'
        : '58mm';
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  // ============================================================
  // GUARDAR
  // ============================================================

  void _save() {
    final header = _header.text.trim();
    final footer = _footer.text.trim();

    if (header.length > 200) {
      _showMessage(
        'La cabecera no puede superar 200 caracteres.',
      );
      return;
    }

    if (footer.length > 200) {
      _showMessage(
        'El pie de página no puede superar 200 caracteres.',
      );
      return;
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).pop(
      <String, dynamic>{
        'papel': _paper,
        'cabecera': header,
        'pie_pagina': footer,
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height * 0.90,
            maxWidth: 600,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              12,
            ),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ticket y formato',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 20),

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
                    if (value == null) return;

                    setState(() {
                      _paper = value;
                    });
                  },
                  decoration:
                      const InputDecoration(
                    labelText: 'Papel',
                    prefixIcon: Icon(
                      Icons.receipt_long_outlined,
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: _header,
                  textInputAction:
                      TextInputAction.next,
                  textCapitalization:
                      TextCapitalization.sentences,
                  maxLength: 200,
                  minLines: 1,
                  maxLines: 3,
                  scrollPadding: const EdgeInsets.only(
                    bottom: 140,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText: 'Cabecera',
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
                  textInputAction:
                      TextInputAction.done,
                  textCapitalization:
                      TextCapitalization.sentences,
                  maxLength: 200,
                  minLines: 1,
                  maxLines: 3,
                  scrollPadding: const EdgeInsets.only(
                    bottom: 140,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText: 'Pie de página',
                    prefixIcon: Icon(
                      Icons.vertical_align_bottom_outlined,
                    ),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pop();
                        },
                        child: const Text(
                          'Cancelar',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(
                          Icons.save_outlined,
                        ),
                        label: const Text(
                          'Guardar',
                        ),
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
// TÍTULO DE SECCIÓN
// ============================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
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
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: const Color(
            0xFF9AC53B,
          ).withAlpha(50),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF9AC53B,
            ).withAlpha(12),
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
            color: const Color(
              0xFF9AC53B,
            ).withAlpha(18),
            borderRadius:
                BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(
              0xFF9AC53B,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Color(
            0xFF9AC53B,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
