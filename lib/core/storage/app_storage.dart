import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static final AppStorage _instance = AppStorage._internal();
  factory AppStorage() => _instance;
  AppStorage._internal();
  SharedPreferences? _prefs;

  static const _token='token', _userId='user_id', _empresaId='empresa_id', _userName='user_name', _companyName='company_name', _logged='is_logged_in';
  static const _offlineIdentifier='offline_identifier', _offlinePassword='offline_password', _offlineEnabled='offline_enabled';
  static const _lastBusinessDate='last_business_date', _serverBusinessDate='server_business_date', _lastOnlineAt='last_online_at', _lastOnlineUserId='last_online_user_id', _lastOnlineEmpresaId='last_online_empresa_id';
  static const _ticketConfig='ticket_config', _operationState='operation_state';
  static const _userRol='user_rol';

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  Future<void> saveSession({required String token, required int userId, required int empresaId, required String userName, required bool isLoggedIn, String? offlineIdentifier, String? offlinePassword, DateTime? serverBusinessDate}) async {
    final p=await _p; await p.setString(_token,token); await p.setInt(_userId,userId); await p.setInt(_empresaId,empresaId); await p.setString(_userName,userName); await p.setBool(_logged,isLoggedIn); await p.setInt(_lastOnlineUserId,userId); await p.setInt(_lastOnlineEmpresaId,empresaId); await p.setBool(_offlineEnabled,true);
    if(offlineIdentifier!=null && offlinePassword!=null) await saveOfflineCredentials(offlineIdentifier,offlinePassword);
    if(serverBusinessDate!=null){final d=_dateOnly(serverBusinessDate); await p.setString(_serverBusinessDate,d); await p.setString(_lastBusinessDate,d); await p.setString(_lastOnlineAt,DateTime.now().toIso8601String());}
  }
  Future<String?> getToken()=>_p.then((p)=>p.getString(_token));
  Future<int?> getUserId()=>_p.then((p)=>p.getInt(_userId));
  Future<int?> getEmpresaId()=>_p.then((p)=>p.getInt(_empresaId));
  Future<String?> getUserName()=>_p.then((p)=>p.getString(_userName));
  Future<void> saveCompanyName(String v)=>_p.then((p)=>p.setString(_companyName,v));
  Future<String?> getCompanyName()=>_p.then((p)=>p.getString(_companyName));
  Future<bool> isLoggedIn()=>_p.then((p)=>p.getBool(_logged)??false);
  Future<void> saveOfflineCredentials(String id,String pass) async {final p=await _p; await p.setString(_offlineIdentifier,id.trim()); await p.setString(_offlinePassword,pass); await p.setBool(_offlineEnabled,true);}
  Future<String?> getOfflineIdentifier()=>_p.then((p)=>p.getString(_offlineIdentifier));
  Future<String?> getOfflinePassword()=>_p.then((p)=>p.getString(_offlinePassword));
  Future<int?> getLastOnlineUserId()=>_p.then((p)=>p.getInt(_lastOnlineUserId));
  Future<int?> getLastOnlineEmpresaId()=>_p.then((p)=>p.getInt(_lastOnlineEmpresaId));
  Future<bool> isOfflineLoginAvailable() async {final p=await _p; return (p.getBool(_offlineEnabled)??false)&&(p.getString(_offlineIdentifier)?.isNotEmpty??false)&&(p.getString(_offlinePassword)?.isNotEmpty??false)&&(p.getInt(_lastOnlineUserId)??0)>0&&(p.getInt(_lastOnlineEmpresaId)??0)>0;}
  Future<bool> hasOfflineAccount()=>isOfflineLoginAvailable();
  Future<void> saveBusinessDate(DateTime d)=>_p.then((p)=>p.setString(_lastBusinessDate,_dateOnly(d)));
  Future<String?> getBusinessDate()=>_p.then((p)=>p.getString(_lastBusinessDate));
  Future<void> saveLastBusinessDate(DateTime d)=>saveBusinessDate(d);
  Future<String?> getLastBusinessDate()=>getBusinessDate();
  Future<void> saveServerBusinessDate(DateTime d)=>_p.then((p)=>p.setString(_serverBusinessDate,_dateOnly(d)));
  Future<String?> getServerBusinessDate()=>_p.then((p)=>p.getString(_serverBusinessDate));
  Future<String?> getLastOnlineAt()=>_p.then((p)=>p.getString(_lastOnlineAt));
  Future<bool> isOfflineSession()=>_p.then((p)=>(p.getString(_token) ?? '') == 'offline-session');
  Future<void> saveTicketConfig(Map<String,dynamic> c)=>_p.then((p)=>p.setString(_ticketConfig,jsonEncode(c)));
  Future<Map<String, dynamic>> getTicketConfig() async { final s = (await _p).getString(_ticketConfig); if (s == null) return {}; try { final d = jsonDecode(s); return d is Map ? Map<String, dynamic>.from(d) : {}; } catch (_) { return {}; } }
  Future<void> saveOperationState(Map<String,dynamic> c)=>_p.then((p)=>p.setString(_operationState,jsonEncode(c)));
  Future<Map<String,dynamic>> getOperationState() async {final s=(await _p).getString(_operationState);if(s==null)return{};try{final d=jsonDecode(s);return d is Map?Map<String,dynamic>.from(d):{};}catch(_){return{};}}
  Future<void> saveRol(String rol)=>_p.then((p)=>p.setString(_userRol,rol));
  Future<String?> getRol()=>_p.then((p)=>p.getString(_userRol));
  /// Comprueba si el rol guardado tiene permisos de cajero (cajero, admin, superadmin).
  Future<bool> isCajero() async {
    final rol = (await getRol())?.toLowerCase().trim() ?? '';
    return rol == 'cajero' || rol == 'admin' || rol == 'superadmin';
  }
  Future<void> logOut() async {final p=await _p; await p.remove(_token); await p.remove(_userId); await p.remove(_empresaId); await p.remove(_userRol); await p.setBool(_logged,false);}
  Future<void> clearCurrentSession()=>logOut();
  Future<void> clearOfflineCredentials() async {final p=await _p; for(final k in [_offlineIdentifier,_offlinePassword,_offlineEnabled,_lastOnlineUserId,_lastOnlineEmpresaId,_userName,_companyName,_token,_userId,_empresaId,_logged]) {
    await p.remove(k);
  }}
  Future<void> clear() async=>(await _p).clear();
  String _dateOnly(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}
