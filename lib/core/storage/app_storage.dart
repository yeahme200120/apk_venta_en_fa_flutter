import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppStorage {
  static final AppStorage _instance = AppStorage._internal();

  factory AppStorage() => _instance;

  AppStorage._internal();

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> saveSession({
    required String token,
    required int userId,
    required int empresaId,
    required String userName,
    required bool isLoggedIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setInt('user_id', userId);
    await prefs.setInt('empresa_id', empresaId);
    await prefs.setString('user_name', userName);
    await prefs.setBool('is_logged_in', isLoggedIn);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  Future<int?> getEmpresaId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('empresa_id');
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  Future<void> saveCompanyName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_name', name);
  }

  Future<String?> getCompanyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('company_name');
  }

  Future<void> saveTicketConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ticket_config', jsonEncode(config));
  }

  Future<Map<String, dynamic>> getTicketConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('ticket_config');
    if (value == null) return {};
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_logged_in') ?? false;
  }

  Future<void> logOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('empresa_id');
    await prefs.remove('user_name');
    await prefs.remove('company_name');
    await prefs.setBool('is_logged_in', false);
  }

  Future<void> saveLastBusinessDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_business_date', date.toIso8601String().substring(0, 10));
  }

  Future<String?> getLastBusinessDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_business_date');
  }
}
