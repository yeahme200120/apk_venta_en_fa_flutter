import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// URLs oficiales del contenido legal.
class LegalUrls {
  LegalUrls._();

  static const String base =
      'https://cabosync.desarrollos-iaeh.org/id_software_house_legal';

  static const String terminos = '$base/terminos';
  static const String aviso = '$base/aviso';
}

class LegalDocument {
  const LegalDocument({
    required this.kind,
    required this.content,
    required this.version,
    required this.updatedAt,
    required this.fromCache,
  });

  /// 'terminos' | 'aviso'
  final String kind;
  final String content;
  final String version;
  final DateTime updatedAt;
  final bool fromCache;

  bool get isEmpty => content.trim().isEmpty;
}

class LegalService {
  LegalService({Dio? dio}) : _dio = dio ?? _buildDio();

  final Dio _dio;

  static const String _prefKeyTerminos = 'legal_terminos_v1';
  static const String _prefKeyAviso = 'legal_aviso_v1';
  static const String _prefKeyTerminosVersion = 'legal_terminos_version_v1';
  static const String _prefKeyAvisoVersion = 'legal_aviso_version_v1';
  static const String _prefKeyUpdatedAt = 'legal_updated_at_v1';

  static const String _prefKeyTerminosAccepted = 'legal_terminos_accepted_v1';
  static const String _prefKeyAvisoAccepted = 'legal_aviso_accepted_v1';

  static final Map<String, LegalDocument> _memory = {};

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        headers: const {'Accept': 'text/plain, text/markdown, text/html'},
      ),
    );
  }

  Future<LegalDocument> getDocument(
    String kind, {
    bool forceRefresh = false,
  }) async {
    assert(kind == 'terminos' || kind == 'aviso');

    if (!forceRefresh && _memory.containsKey(kind)) {
      unawaited(_refreshInBackground(kind));
      return _memory[kind]!;
    }

    final cached = await _readFromDisk(kind);

    if (!forceRefresh && cached != null && !cached.isEmpty) {
      _memory[kind] = cached;
      unawaited(_refreshInBackground(kind));
      return cached;
    }

    try {
      final fresh = await _download(kind);
      await _writeToDisk(fresh);
      _memory[kind] = fresh;
      return fresh;
    } catch (e) {
      debugPrint('[LegalService] Error descargando $kind: $e');

      if (cached != null && !cached.isEmpty) return cached;

      return LegalDocument(
        kind: kind,
        content: _fallbackContent(kind),
        version: 'desconocida',
        updatedAt: DateTime.now(),
        fromCache: false,
      );
    }
  }

  Future<void> markAccepted(String kind, String version) async {
    final prefs = await SharedPreferences.getInstance();
    final key = kind == 'terminos'
        ? _prefKeyTerminosAccepted
        : _prefKeyAvisoAccepted;

    await prefs.setString(key, version);
    await prefs.setString('${key}_at', DateTime.now().toIso8601String());
  }

  Future<String?> getAcceptedVersion(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    final key = kind == 'terminos'
        ? _prefKeyTerminosAccepted
        : _prefKeyAvisoAccepted;

    return prefs.getString(key);
  }

  static void clearMemory() => _memory.clear();

  Future<LegalDocument> _download(String kind) async {
    final url = kind == 'terminos' ? LegalUrls.terminos : LegalUrls.aviso;

    final response = await _dio.get<String>(url);

    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Respuesta inválida: ${response.statusCode}');
    }

    final raw = response.data!.trim();

    return LegalDocument(
      kind: kind,
      content: raw,
      version: _extractVersion(raw),
      updatedAt: DateTime.now(),
      fromCache: false,
    );
  }

  String _extractVersion(String content) {
    final match = RegExp(
      r'versi[oó]n\s+([0-9]+\.[0-9]+\.[0-9]+)',
      caseSensitive: false,
    ).firstMatch(content);

    return match?.group(1) ?? 'actual';
  }

  Future<void> _refreshInBackground(String kind) async {
    try {
      final fresh = await _download(kind);
      await _writeToDisk(fresh);
      _memory[kind] = fresh;
    } catch (_) {}
  }

  Future<LegalDocument?> _readFromDisk(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    final key = kind == 'terminos' ? _prefKeyTerminos : _prefKeyAviso;
    final versionKey = kind == 'terminos'
        ? _prefKeyTerminosVersion
        : _prefKeyAvisoVersion;

    final content = prefs.getString(key);
    if (content == null || content.trim().isEmpty) return null;

    final version = prefs.getString(versionKey) ?? 'actual';
    final updatedIso = prefs.getString(_prefKeyUpdatedAt);
    final updatedAt = DateTime.tryParse(updatedIso ?? '') ?? DateTime.now();

    return LegalDocument(
      kind: kind,
      content: content,
      version: version,
      updatedAt: updatedAt,
      fromCache: true,
    );
  }

  Future<void> _writeToDisk(LegalDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    final key = doc.kind == 'terminos' ? _prefKeyTerminos : _prefKeyAviso;
    final versionKey = doc.kind == 'terminos'
        ? _prefKeyTerminosVersion
        : _prefKeyAvisoVersion;

    await prefs.setString(key, doc.content);
    await prefs.setString(versionKey, doc.version);
    await prefs.setString(_prefKeyUpdatedAt, doc.updatedAt.toIso8601String());
  }

  String _fallbackContent(String kind) {
    if (kind == 'terminos') {
      return 'No fue posible cargar los Términos y Condiciones.\n\n'
          'Conéctate a Internet o ábrelos en:\n${LegalUrls.terminos}';
    }

    return 'No fue posible cargar el Aviso de Privacidad.\n\n'
        'Conéctate a Internet o ábrelo en:\n${LegalUrls.aviso}';
  }
}