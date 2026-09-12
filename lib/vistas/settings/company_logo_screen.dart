import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';

class CompanyLogoScreen extends StatefulWidget {
  const CompanyLogoScreen({super.key});

  @override
  State<CompanyLogoScreen> createState() =>
      _CompanyLogoScreenState();
}

class _CompanyLogoScreenState
    extends State<CompanyLogoScreen> {
  static const String _companyLogoPathKey =
      'company_logo_local_path';

  static const String _companyLogoRemoteKey =
      'company_logo_remote_path';

  static const String _companyLogoSyncStatusKey =
      'company_logo_sync_status';

  static const String _companyLogoUpdatedAtKey =
      'company_logo_updated_at';

  static const String _syncPending = 'pending';
  static const String _syncSynced = 'synced';

  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();

  File? _selectedLogo;

  File? _localLogo;

  String? _currentLogoUrl;
  String? _currentLogoPath;

  Uint8List? _currentLogoBytes;

  bool _loading = true;
  bool _processing = false;

  bool _logoLoadedLocally = false;
  bool _logoSyncPending = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentLogo();
  }

  // ============================================================
  // CARGAR LOGO
  //
  // LOCAL FIRST
  // ============================================================

  Future<void> _loadCurrentLogo() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // ----------------------------------------------------------
      // 1. PRIMERO LOCAL
      // ----------------------------------------------------------

      final localLoaded =
          await _loadLocalLogo();

      // ----------------------------------------------------------
      // 2. DESPUÉS SERVIDOR
      //
      // Si ya tenemos logo local, no dependemos de este paso.
      // El servidor solamente sirve para actualizar información
      // remota cuando está disponible.
      // ----------------------------------------------------------

      try {
        await _loadRemoteLogo(
          keepLocalLogo: localLoaded,
        );
      } catch (error) {
        debugPrint(
          '[LOGO] Servidor no disponible: $error',
        );

        if (!localLoaded) {
          if (!mounted) return;

          setState(() {
            _loading = false;
            _error =
                'No fue posible cargar el logo local ni conectar con el servidor.';
          });

          return;
        }
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (error) {
      debugPrint(
        '[LOGO] Error cargando logo: $error',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  // ============================================================
  // CARGAR LOGO LOCAL
  // ============================================================

  Future<bool> _loadLocalLogo() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      final localPath =
          prefs.getString(
        _companyLogoPathKey,
      );

      final syncStatus =
          prefs.getString(
        _companyLogoSyncStatusKey,
      );

      debugPrint(
        '[LOGO] Ruta local: $localPath',
      );

      debugPrint(
        '[LOGO] Estado sincronización: '
        '$syncStatus',
      );

      if (localPath == null ||
          localPath.trim().isEmpty) {
        return false;
      }

      final file =
          File(localPath);

      if (!await file.exists()) {
        debugPrint(
          '[LOGO] El archivo local no existe.',
        );

        return false;
      }

      final bytes =
          await file.readAsBytes();

      if (bytes.isEmpty) {
        debugPrint(
          '[LOGO] El archivo local está vacío.',
        );

        return false;
      }

      if (!mounted) {
        return true;
      }

      setState(() {
        _localLogo = file;
        _currentLogoBytes = bytes;
        _logoLoadedLocally = true;
        _logoSyncPending =
            syncStatus == _syncPending;
      });

      debugPrint(
        '[LOGO] Logo local cargado: '
        '${bytes.length} bytes',
      );

      return true;
    } catch (error) {
      debugPrint(
        '[LOGO] Error leyendo logo local: $error',
      );

      return false;
    }
  }

  // ============================================================
  // CARGAR LOGO REMOTO
  // ============================================================

  Future<void> _loadRemoteLogo({
    required bool keepLocalLogo,
  }) async {
    final response =
        await _apiClient.getCompanyLogo();

    debugPrint(
      '[LOGO] Respuesta empresa/logo: $response',
    );

    final logoUrlValue =
        response['logo_url'];

    final logoPathValue =
        response['logo'];

    final logoUrl =
        logoUrlValue is String &&
                logoUrlValue.trim().isNotEmpty
            ? logoUrlValue.trim()
            : null;

    final logoPath =
        logoPathValue is String &&
                logoPathValue.trim().isNotEmpty
            ? logoPathValue.trim()
            : null;

    Uint8List? logoBytes;

    // ----------------------------------------------------------
    // PRIMER INTENTO: logo_url
    // ----------------------------------------------------------

    if (logoUrl != null) {
      try {
        debugPrint(
          '[LOGO] Intentando descargar logo_url: '
          '$logoUrl',
        );

        final downloadedBytes =
            await _apiClient.downloadCompanyLogo(
          logoUrl: logoUrl,
        );

        if (downloadedBytes != null &&
            downloadedBytes.isNotEmpty) {
          logoBytes =
              Uint8List.fromList(
            downloadedBytes,
          );
        }

        debugPrint(
          '[LOGO] Bytes recibidos: '
          '${logoBytes?.length ?? 0}',
        );
      } catch (error) {
        debugPrint(
          '[LOGO] Error descargando logo_url: $error',
        );
      }
    }

    // ----------------------------------------------------------
    // SEGUNDO INTENTO: logo
    // ----------------------------------------------------------

    if ((logoBytes == null ||
            logoBytes.isEmpty) &&
        logoPath != null) {
      final normalizedPath =
          logoPath.startsWith('/')
              ? logoPath
              : '/storage/$logoPath';

      try {
        debugPrint(
          '[LOGO] Intentando descargar logo: '
          '$normalizedPath',
        );

        final downloadedBytes =
            await _apiClient.downloadCompanyLogo(
          logoUrl: normalizedPath,
        );

        if (downloadedBytes != null &&
            downloadedBytes.isNotEmpty) {
          logoBytes =
              Uint8List.fromList(
            downloadedBytes,
          );
        }

        debugPrint(
          '[LOGO] Bytes recibidos desde logo: '
          '${logoBytes?.length ?? 0}',
        );
      } catch (error) {
        debugPrint(
          '[LOGO] Error descargando logo: $error',
        );
      }
    }

    // ----------------------------------------------------------
    // SI NO PUDO DESCARGARSE
    //
    // El logo local sigue siendo válido.
    // ----------------------------------------------------------

    if (logoBytes == null ||
        logoBytes.isEmpty) {
      debugPrint(
        '[LOGO] No fue posible obtener logo remoto.',
      );

      if (keepLocalLogo) {
        debugPrint(
          '[LOGO] Conservando logo local.',
        );
        return;
      }

      return;
    }

    // ----------------------------------------------------------
    // IMPORTANTE
    //
    // Si ya existe un logo local, NO lo reemplazamos
    // automáticamente. El local es la fuente principal
    // para el funcionamiento offline.
    // ----------------------------------------------------------

    if (keepLocalLogo) {
      debugPrint(
        '[LOGO] Existe logo local. '
        'Se conserva como fuente principal.',
      );

      if (!mounted) return;

      setState(() {
        _currentLogoUrl = logoUrl;
        _currentLogoPath = logoPath;
      });

      return;
    }

    if (!mounted) return;

    setState(() {
      _currentLogoUrl = logoUrl;
      _currentLogoPath = logoPath;
      _currentLogoBytes = logoBytes;
    });
  }

  // ============================================================
  // SELECCIONAR IMAGEN
  // ============================================================

  Future<void> _selectLogo() async {
    if (_processing) return;

    try {
      final image =
          await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (image == null) {
        return;
      }

      await _cropLogo(
        File(image.path),
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        'No fue posible seleccionar la imagen: $error',
        isError: true,
      );
    }
  }

  // ============================================================
  // RECORTAR LOGO
  // ============================================================

  Future<void> _cropLogo(
    File sourceFile,
  ) async {
    setState(() {
      _processing = true;
    });

    try {
      final croppedFile =
          await ImageCropper().cropImage(
        sourcePath: sourceFile.path,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Ajustar logo',
            toolbarColor:
                Theme.of(context)
                    .colorScheme
                    .primary,
            toolbarWidgetColor:
                Colors.white,
            initAspectRatio:
                CropAspectRatioPreset.square,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Ajustar logo',
            aspectRatioLockEnabled: false,
          ),
        ],
      );

      if (croppedFile == null) {
        if (mounted) {
          setState(() {
            _processing = false;
          });
        }

        return;
      }

      if (!mounted) return;

      setState(() {
        _selectedLogo =
            File(croppedFile.path);

        _processing = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _processing = false;
      });

      _showMessage(
        'No fue posible recortar el logo: $error',
        isError: true,
      );
    }
  }

  // ============================================================
  // GUARDAR LOGO LOCALMENTE
  //
  // ESTE PASO SIEMPRE OCURRE ANTES DEL SERVIDOR.
  // ============================================================

  Future<File> _saveLogoLocally(
    File sourceFile,
  ) async {
    if (!await sourceFile.exists()) {
      throw Exception(
        'El archivo seleccionado no existe.',
      );
    }

    final directory =
        await getApplicationDocumentsDirectory();

    final companyDirectory =
        Directory(
      '${directory.path}/company',
    );

    if (!await companyDirectory.exists()) {
      await companyDirectory.create(
        recursive: true,
      );
    }

    final localPath =
        '${companyDirectory.path}/company_logo.webp';

    final localFile =
        await sourceFile.copy(
      localPath,
    );

    final bytes =
        await localFile.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception(
        'No fue posible guardar el logo localmente.',
      );
    }

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _companyLogoPathKey,
      localFile.path,
    );

    await prefs.setString(
      _companyLogoSyncStatusKey,
      _syncPending,
    );

    await prefs.setString(
      _companyLogoUpdatedAtKey,
      DateTime.now()
          .toUtc()
          .toIso8601String(),
    );

    debugPrint(
      '[LOGO] Logo guardado LOCALMENTE: '
      '${localFile.path}',
    );

    debugPrint(
      '[LOGO] Bytes locales: '
      '${bytes.length}',
    );

    debugPrint(
      '[LOGO] Estado local: pending',
    );

    return localFile;
  }

  // ============================================================
  // MARCAR LOGO COMO SINCRONIZADO
  // ============================================================

  Future<void> _markLogoAsSynced({
    String? remotePath,
  }) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _companyLogoSyncStatusKey,
      _syncSynced,
    );

    if (remotePath != null &&
        remotePath.trim().isNotEmpty) {
      await prefs.setString(
        _companyLogoRemoteKey,
        remotePath.trim(),
      );
    }

    debugPrint(
      '[LOGO] Estado local: synced',
    );
  }

  // ============================================================
  // GUARDAR LOGO
  //
  // 1. LOCAL
  // 2. UI
  // 3. SERVER
  // ============================================================

  Future<void> _saveLogo() async {
    final logo =
        _selectedLogo;

    if (logo == null) {
      _showMessage(
        'Selecciona y ajusta un logo antes de guardar.',
        isError: true,
      );

      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    File? localFile;

    try {
      // --------------------------------------------------------
      // PASO 1
      // GUARDAR LOCALMENTE
      // --------------------------------------------------------

      debugPrint(
        '[LOGO] Guardando logo localmente: '
        '${logo.path}',
      );

      localFile =
          await _saveLogoLocally(
        logo,
      );

      final localBytes =
          await localFile.readAsBytes();

      // --------------------------------------------------------
      // ACTUALIZAR UI INMEDIATAMENTE
      // --------------------------------------------------------

      if (mounted) {
        setState(() {
          _localLogo = localFile;
          _currentLogoBytes = localBytes;
          _selectedLogo = null;
          _logoLoadedLocally = true;
          _logoSyncPending = true;
        });
      }

      _showMessage(
        'Logo guardado localmente.',
      );

      // --------------------------------------------------------
      // PASO 2
      // INTENTAR SERVIDOR
      // --------------------------------------------------------

      try {
        debugPrint(
          '[LOGO] Intentando subir logo al servidor...',
        );

        final response =
            await _apiClient.uploadCompanyLogo(
          localFile,
        );

        debugPrint(
          '[LOGO] Respuesta upload: $response',
        );

        // ------------------------------------------------------
        // OBTENER INFORMACIÓN REMOTA
        // ------------------------------------------------------

        Map<String, dynamic>?
            refreshedResponse;

        try {
          refreshedResponse =
              await _apiClient.getCompanyLogo();

          debugPrint(
            '[LOGO] Logo después de guardar: '
            '$refreshedResponse',
          );
        } catch (error) {
          debugPrint(
            '[LOGO] Upload OK, pero no se pudo '
            'consultar información remota: $error',
          );
        }

        String? remotePath;

        if (refreshedResponse != null) {
          final remotePathValue =
              refreshedResponse['logo'];

          if (remotePathValue is String &&
              remotePathValue
                  .trim()
                  .isNotEmpty) {
            remotePath =
                remotePathValue.trim();
          }

          final remoteUrlValue =
              refreshedResponse['logo_url'];

          final remoteUrl =
              remoteUrlValue is String &&
                      remoteUrlValue
                          .trim()
                          .isNotEmpty
                  ? remoteUrlValue.trim()
                  : null;

          if (mounted) {
            setState(() {
              _currentLogoUrl = remoteUrl;
              _currentLogoPath = remotePath;
            });
          }
        }

        // ------------------------------------------------------
        // MARCAR COMO SINCRONIZADO
        // ------------------------------------------------------

        await _markLogoAsSynced(
          remotePath: remotePath,
        );

        if (!mounted) return;

        setState(() {
          _logoSyncPending = false;
          _processing = false;
        });

        _showMessage(
          'Logo guardado localmente y sincronizado con el servidor.',
        );
      } catch (error) {
        // ------------------------------------------------------
        // IMPORTANTE:
        //
        // EL LOGO LOCAL YA ESTÁ GUARDADO.
        //
        // NO LO BORRAMOS.
        // ------------------------------------------------------

        debugPrint(
          '[LOGO] Servidor no disponible: $error',
        );

        debugPrint(
          '[LOGO] El logo permanece guardado '
          'localmente como pendiente.',
        );

        if (!mounted) return;

        setState(() {
          _logoSyncPending = true;
          _processing = false;
        });

        _showMessage(
          'Logo guardado localmente. '
          'Quedará pendiente de sincronización cuando haya conexión.',
        );
      }
    } catch (error) {
      debugPrint(
        '[LOGO] Error guardando logo local: $error',
      );

      if (!mounted) return;

      setState(() {
        _processing = false;
      });

      _showMessage(
        'No fue posible guardar el logo localmente: $error',
        isError: true,
      );
    }
  }

  // ============================================================
  // ELIMINAR CAMBIO LOCAL
  // ============================================================

  void _cancelSelection() {
    if (_processing) return;

    setState(() {
      _selectedLogo = null;
    });
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError
                  ? Colors.red.shade700
                  : null,
        ),
      );
  }

  // ============================================================
  // PREVIEW
  // ============================================================

  Widget _buildLogoPreview() {
    // ----------------------------------------------------------
    // 1. LOGO NUEVO SELECCIONADO
    // ----------------------------------------------------------

    if (_selectedLogo != null) {
      return Padding(
        padding:
            const EdgeInsets.all(24),
        child: Image.file(
          _selectedLogo!,
          fit: BoxFit.contain,
          errorBuilder:
              (_, __, ___) =>
                  _buildEmptyLogo(
            message:
                'No se pudo mostrar la imagen seleccionada',
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // 2. LOGO LOCAL
    //
    // ES LA FUENTE PRINCIPAL.
    // ----------------------------------------------------------

    if (_localLogo != null) {
      return Padding(
        padding:
            const EdgeInsets.all(24),
        child: Image.file(
          _localLogo!,
          fit: BoxFit.contain,
          errorBuilder:
              (_, __, ___) =>
                  _buildMemoryLogo(),
        ),
      );
    }

    // ----------------------------------------------------------
    // 3. BYTES LOCALES / REMOTOS
    // ----------------------------------------------------------

    if (_currentLogoBytes != null &&
        _currentLogoBytes!.isNotEmpty) {
      return _buildMemoryLogo();
    }

    // ----------------------------------------------------------
    // 4. FALLBACK DIRECTO A URL
    // ----------------------------------------------------------

    if (_currentLogoUrl != null &&
        _currentLogoUrl!.isNotEmpty) {
      return Padding(
        padding:
            const EdgeInsets.all(24),
        child: Image.network(
          _currentLogoUrl!,
          fit: BoxFit.contain,
          errorBuilder:
              (_, __, ___) =>
                  _buildEmptyLogo(),
          loadingBuilder:
              (
                context,
                child,
                loadingProgress,
              ) {
            if (loadingProgress == null) {
              return child;
            }

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          },
        ),
      );
    }

    return _buildEmptyLogo();
  }

  // ============================================================
  // PREVIEW BYTES
  // ============================================================

  Widget _buildMemoryLogo() {
    if (_currentLogoBytes == null ||
        _currentLogoBytes!.isEmpty) {
      return _buildEmptyLogo();
    }

    return Padding(
      padding:
          const EdgeInsets.all(24),
      child: Image.memory(
        _currentLogoBytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder:
            (_, __, ___) =>
                _buildNetworkFallback(),
      ),
    );
  }

  // ============================================================
  // FALLBACK NETWORK
  // ============================================================

  Widget _buildNetworkFallback() {
    if (_currentLogoUrl == null ||
        _currentLogoUrl!.isEmpty) {
      return _buildEmptyLogo();
    }

    return Image.network(
      _currentLogoUrl!,
      fit: BoxFit.contain,
      errorBuilder:
          (_, __, ___) =>
              _buildEmptyLogo(),
    );
  }

  // ============================================================
  // SIN LOGO
  // ============================================================

  Widget _buildEmptyLogo({
    String message =
        'Sin logo configurado',
  }) {
    return Column(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children: [
        Icon(
          Icons.business_outlined,
          size: 64,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Logo de empresa',
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : SafeArea(
              child: ListView(
                padding:
                    const EdgeInsets.all(20),
                children: [
                  // ------------------------------------------------
                  // TITULO
                  // ------------------------------------------------

                  Text(
                    'Identidad visual',
                    style:
                        theme.textTheme
                            .headlineSmall
                            ?.copyWith(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Selecciona el logo de la empresa, '
                    'ajusta su posición y guárdalo.',
                    style:
                        theme.textTheme
                            .bodyMedium
                            ?.copyWith(
                      color:
                          Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ------------------------------------------------
                  // ESTADO OFFLINE
                  // ------------------------------------------------

                  if (_logoSyncPending)
                    Container(
                      padding:
                          const EdgeInsets.all(
                        14,
                      ),
                      margin:
                          const EdgeInsets.only(
                        bottom: 16,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.orange.shade50,
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                        border: Border.all(
                          color:
                              Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Icon(
                            Icons
                                .cloud_off_outlined,
                            color:
                                Colors.orange.shade800,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child: Text(
                              'El logo está guardado en este dispositivo '
                              'y queda pendiente de sincronización con el servidor.',
                              style:
                                  TextStyle(
                                color:
                                    Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ------------------------------------------------
                  // ERROR
                  // ------------------------------------------------

                  if (_error != null)
                    Container(
                      padding:
                          const EdgeInsets.all(
                        14,
                      ),
                      margin:
                          const EdgeInsets.only(
                        bottom: 16,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.orange.shade50,
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                        border: Border.all(
                          color:
                              Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Icon(
                            Icons
                                .warning_amber_outlined,
                            color:
                                Colors.orange.shade800,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child: Text(
                              _error!,
                              style:
                                  TextStyle(
                                color:
                                    Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ------------------------------------------------
                  // PREVIEW
                  // ------------------------------------------------

                  Container(
                    width:
                        double.infinity,
                    height: 300,
                    decoration:
                        BoxDecoration(
                      color:
                          Colors.grey.shade100,
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                      border: Border.all(
                        color:
                            Colors.grey.shade300,
                      ),
                    ),
                    clipBehavior:
                        Clip.antiAlias,
                    child:
                        _buildLogoPreview(),
                  ),

                  const SizedBox(height: 12),

                  // ------------------------------------------------
                  // ESTADO DEL LOGO
                  // ------------------------------------------------

                  if (_selectedLogo != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.edit_outlined,
                          size: 18,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            'Vista previa del nuevo logo',
                            style:
                                theme
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (_logoSyncPending)
                    Text(
                      'Logo guardado localmente · pendiente de sincronización',
                      textAlign:
                          TextAlign.center,
                      style:
                          theme.textTheme
                              .bodySmall
                              ?.copyWith(
                        color:
                            Colors.orange.shade800,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    )
                  else if (_logoLoadedLocally)
                    Text(
                      'Logo disponible localmente',
                      textAlign:
                          TextAlign.center,
                      style:
                          theme.textTheme
                              .bodySmall
                              ?.copyWith(
                        color:
                            Colors.black54,
                      ),
                    )
                  else if (_currentLogoBytes !=
                          null &&
                      _currentLogoBytes!
                          .isNotEmpty)
                    Text(
                      'Logo actualmente configurado',
                      textAlign:
                          TextAlign.center,
                      style:
                          theme.textTheme
                              .bodySmall
                              ?.copyWith(
                        color:
                            Colors.black54,
                      ),
                    )
                  else
                    Text(
                      'No se encontró un logo disponible',
                      textAlign:
                          TextAlign.center,
                      style:
                          theme.textTheme
                              .bodySmall
                              ?.copyWith(
                        color:
                            Colors.black54,
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ------------------------------------------------
                  // SELECCIONAR
                  // ------------------------------------------------

                  OutlinedButton.icon(
                    onPressed:
                        _processing
                            ? null
                            : _selectLogo,
                    icon:
                        const Icon(
                      Icons
                          .photo_library_outlined,
                    ),
                    label:
                        Text(
                      _selectedLogo ==
                              null
                          ? 'Seleccionar logo'
                          : 'Cambiar logo',
                    ),
                  ),

                  // ------------------------------------------------
                  // CAMBIO PENDIENTE
                  // ------------------------------------------------

                  if (_selectedLogo != null) ...[
                    const SizedBox(
                      height: 12,
                    ),

                    OutlinedButton.icon(
                      onPressed:
                          _processing
                              ? null
                              : _cancelSelection,
                      icon:
                          const Icon(
                        Icons.close,
                      ),
                      label:
                          const Text(
                        'Cancelar cambio',
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    FilledButton.icon(
                      onPressed:
                          _processing
                              ? null
                              : _saveLogo,
                      icon:
                          _processing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                    color:
                                        Colors
                                            .white,
                                  ),
                                )
                              : const Icon(
                                  Icons
                                      .cloud_upload_outlined,
                                ),
                      label:
                          Text(
                        _processing
                            ? 'Guardando...'
                            : 'Guardar logo',
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ------------------------------------------------
                  // INFORMACION
                  // ------------------------------------------------

                  Container(
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          theme
                              .colorScheme
                              .primary
                              .withAlpha(
                        10,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    child:
                        const Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Icon(
                          Icons
                              .info_outline,
                          size: 20,
                        ),
                        SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child: Text(
                            'El logo se guarda primero en el dispositivo '
                            'para que pueda utilizarse sin conexión. '
                            'Después se intenta sincronizar con el servidor. '
                            'Si no hay Internet, el cambio permanece pendiente '
                            'y no se pierde.',
                            style:
                                TextStyle(
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}