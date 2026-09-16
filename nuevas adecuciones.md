Especificación — Registro con licencia de prueba de 7 días
Fecha: 2026-09-15
Última actualización: 2026-09-16 (post offline-first + password + ubicación GPS)
Estado: Backend completo (incluye ubicación GPS). Flutter: todos los screens con licencia offline-first. GPS en Flutter en progreso.
Alcance: Backend Laravel + Flutter (solo Android)
Licencia: semana (7 días)

════════════════════════════════════════════════════════════════
0. PRINCIPIO RECTOR: OFFLINE-FIRST
════════════════════════════════════════════════════════════════

El POS debe funcionar SIN internet.

1. El POS NUNCA se bloquea por licencia si hay snapshot
   válido en local. Solo bloquea crear nuevas ventas.

2. sinSnapshot NUNCA bloquea. Solo advierte.

3. bloqueada (vencida > 3 días) NO bloquea:
     • Ver historial
     • Cerrar caja
     • Sincronizar pendientes
     • Cambiar contraseña
   SÍ bloquea:
     • Crear nuevas ventas
     • Abrir nueva caja

4. enGracia advierte pero NO bloquea.

5. El estado de licencia se calcula con tiempo local
   (server_checked_at como ancla), sin llamada al servidor.

6. Solo el login online exitoso renueva la licencia.

════════════════════════════════════════════════════════════════
1. ESTADO DE IMPLEMENTACIÓN
════════════════════════════════════════════════════════════════

BACKEND — ✅ 100% COMPLETO Y PROBADO

  Registro con licencia de prueba:
  ✅ Migración registros_prueba
  ✅ Migración mac_address + mac_vinculada + origen_registro +
     requiere_cambio_password en users
  ✅ Migración licencia_tipo enum incluye 'prueba'
  ✅ Modelo RegistroPrueba
  ✅ Modelo User (fillable, casts, esCreadoDesdeApp, macCoincide)
  ✅ RegisterController (register, checkEmail, checkEmpresa)
  ✅ AuthController@login con validación MAC
  ✅ AuthController@changePassword limpia requiere_cambio_password
  ✅ AuthController@forgotPassword valida email existente
  ✅ Rutas públicas /register, /register/check-email, /register/check-empresa

  Recuperación de contraseña web (Laravel):
  ✅ ResetPasswordWebController (showResetForm, reset)
  ✅ Vista resources/views/auth/reset-password.blade.php
  ✅ Vista resources/views/auth/reset-success.blade.php
  ✅ routes/web.php con 3 rutas ANTES del catch-all
  ✅ ResetPasswordNotification personalizada (correo en español)
  ✅ User::sendPasswordResetNotification
  ✅ Mail Hostinger configurado y probado (SMTP funciona)
  ✅ Flujo E2E probado: forgot → correo → link → reset → success

  Ubicación GPS en auditoría:
  ✅ Migración add_ubicacion_to_logs_auditoria_table
       (latitud, longitud, precision_metros, ubicacion_provider,
        ubicacion_at + índice)
  ✅ Modelo LogAuditoria con fillable/casts/appends
  ✅ Accessor tiene_ubicacion
  ✅ AuditoriaService con extractUbicacion()
  ✅ 3 métodos (registrar, registrarUsuario, registrarSistema)
     guardan ubicación automáticamente
  ✅ RegisterController con validación de ubicación
  ✅ AuthController@login con validación de ubicación
  ✅ CajaController con validación de ubicación
     (abrir, cerrar, registrarMovimiento) — fix aplicado a
     Empresa::usaCajas()/usaMesas() pero prueba E2E pendiente
  ✅ AuditoriaController@exportar con columnas de ubicación en CSV

FLUTTER — ✅ SCREENS + LICENCIA COMPLETOS · ⏳ GPS EN PROGRESO

  Licencia offline-first:
  ✅ license_service.dart
  ✅ pos_screen.dart (_licenseState + 3 banners + _puedeOperar
     + _addToCart + _canOperateSale)
  ✅ operation_screen.dart (_licenseState + 3 banners +
     _openCashDialog bloqueado + cierre/retiro/editTable permitidos)
  ✅ cash_management_screen.dart (_licenseState + 3 banners +
     _abrirCaja bloqueado + cierre/retiro permitidos + FAB adaptado)
  ✅ daily_stats_screen.dart (_licenseState + 3 banners informativos)
  ✅ settings_screen.dart (tile Cambiar contraseña + diálogo +
     banner persistente + validación + limpieza del flag)

  Registro con licencia de prueba:
  ✅ app_storage.dart (saveLicenseSnapshot + purga de catálogo +
     setRequiresPasswordChange/getRequiresPasswordChange/
     clearRequiresPasswordChange)
  ✅ api_client.dart (register, checkEmailAvailable,
     checkEmpresaAvailable, login con macAddress, forgotPassword,
     resetPassword)
  ✅ auth_service.dart (login con MAC, register,
     _saveOnlineSession con snapshot + flag password,
     logout limpia todo, _deviceIdentifier con device_info_plus)
  ✅ register_screen.dart
  ✅ login_screen.dart (botón Crear cuenta + verificación licencia
     + aviso password + integración RegisterScreen)
  ✅ forgot_password_screen.dart (manejo 404/500/429 + error red)
  ✅ pubspec.yaml (device_info_plus: ^13.2.0)

  Ubicación GPS (solo Android):
  ✅ pubspec.yaml + geolocator: ^13.0.1
  ✅ Permisos Android (ACCESS_FINE_LOCATION + COARSE)
  ✅ location_service.dart (con LocationSettings para geolocator 13.x)
  ⏳ ApiClient con parámetros de ubicación
  ⏳ AuthService con ubicación
  ⏳ RegisterScreen con ubicación obligatoria
  ⏳ SplashScreen con permiso al inicio
  ⏳ CashService con ubicación

════════════════════════════════════════════════════════════════
2. REGLAS DE NEGOCIO (CONSOLIDADAS)
════════════════════════════════════════════════════════════════

1. Registro disponible desde app Flutter y desde web.
2. Máximo 1 usuario por empresa si se registra desde la app.
3. El usuario creado desde la app solo puede ser rol vendedor.
4. El usuario queda vinculado al identificador único del dispositivo.
5. No puede iniciar sesión en otro dispositivo la cuenta creada
   desde la app (validación MAC).
6. Registro obligatorio con Internet.
7. El backend devuelve numero_usuario y password genérica (pos2026).
8. Anti-abuso: email único + IP rate limit + MAC única + empresa
   única + 1 usuario/empresa.
9. Empresas existentes no se modifican.
10. Mensaje: "empresa ya registrada, contacta al administrador".
11. Licencia tipo semana con fecha_fin = hoy + 7 días.
12. Recuperación de contraseña con verificación de email.
13. Empresas creadas desde la app NO pueden editar configuración
    salvo superadmin.
14. Al vencer los 7 días: bloqueo de NUEVAS VENTAS y
    NUEVAS APERTURAS DE CAJA (matizado por offline-first).

════════════════════════════════════════════════════════════════
3. TABLAS Y COLUMNAS CLAVE
════════════════════════════════════════════════════════════════

registros_prueba:
  id, email (unique), ip, mac_address, empresa_nombre,
  empresa_id, user_id, estado ('pendiente'|'aprobado'|'rechazado'),
  razon_rechazo, timestamps
  Índices: empresa_id, mac_address, ip

users (nuevas columnas):
  mac_address, mac_vinculada (bool), origen_registro,
  requiere_cambio_password (bool)
  Índices: mac_address, origen_registro

empresas:
  licencia_tipo enum incluye 'prueba'

logs_auditoria (nuevas columnas):
  latitud (decimal 10,7, nullable),
  longitud (decimal 10,7, nullable),
  precision_metros (decimal 8,2, nullable),
  ubicacion_provider (string 30, nullable),
  ubicacion_at (timestamp, nullable)
  Índice: ubicacion_at

════════════════════════════════════════════════════════════════
4. RUTAS API
════════════════════════════════════════════════════════════════

Públicas (sin auth):
  POST /api/v1/register
  POST /api/v1/register/check-email
  POST /api/v1/register/check-empresa
  POST /api/v1/login
  POST /api/v1/password/forgot       (throttle 5,1)
  POST /api/v1/password/reset        (throttle 5,1)

Autenticadas (auth:sanctum + check.license):
  POST   /api/v1/logout
  GET    /api/v1/user
  PATCH  /api/v1/user/profile
  POST   /api/v1/user/password
  GET    /api/v1/me/permissions
  GET    /api/v1/operacion/estado
  POST   /api/v1/cajas/abrir
  POST   /api/v1/cajas/{id}/cerrar
  POST   /api/v1/cajas/movimientos
  POST   /api/v1/cajas/{id}/movimientos
  GET    /api/v1/cajas/actual
  GET    /api/v1/cajas/operaciones
  GET    /api/v1/cajas/{id}/operaciones
  GET    /api/v1/auditoria
  GET    /api/v1/auditoria/{id}
  GET    /api/v1/auditoria/exportar

Rutas web (fuera del catch-all SPA):
  GET  /reset-password/{token}      → password.reset
  POST /reset-password              → password.update
  GET  /reset-password-success      → password.reset.success

════════════════════════════════════════════════════════════════
5. PARÁMETROS DE UBICACIÓN
════════════════════════════════════════════════════════════════

Todos los endpoints que registran auditoría aceptan
OPCIONALMENTE estos 4 parámetros en el body:

  latitud            numeric entre -90 y 90
  longitud           numeric entre -180 y 180
  precision_metros   numeric entre 0 y 10000
  ubicacion_provider string max 30 ('gps', 'network', ...)

Si alguno falta o es inválido → se guarda null.
Si latitud+longitud están presentes → se guarda
  ubicacion_at = now().

El AuditoriaService::extractUbicacion() los procesa
automáticamente. NO se necesita código extra en los
controladores más allá de agregar las reglas de validación.

Reglas de captura en Flutter:
  • Precisión máxima aceptada: 100 m
  • Timeout: 15 s
  • Cache: 5 min
  • Si denegado o deshabilitado → null (el caller decide)

════════════════════════════════════════════════════════════════
6. INTEGRACIÓN OFFLINE-FIRST POR SCREEN
════════════════════════════════════════════════════════════════

┌─────────────────────────┬───────────┬─────────────┬──────────┐
│ Screen                  │ bloqueada │ sinSnapshot │ enGracia │
├─────────────────────────┼───────────┼─────────────┼──────────┤
│ login_screen            │ ❌ bloquea │ ❌ bloquea   │ ✅ permite│
│ pos_screen              │ ⚠️ parcial │ ✅ permite   │ ✅ permite│
│ operation_screen        │ ⚠️ parcial │ ✅ permite   │ ✅ permite│
│ cash_management_screen  │ ⚠️ parcial │ ✅ permite   │ ✅ permite│
│ daily_stats_screen      │ ✅ permite │ ✅ permite   │ ✅ permite│
│ settings_screen         │ ✅ permite │ ✅ permite   │ ✅ permite│
└─────────────────────────┴───────────┴─────────────┴──────────┘

Bloqueos parciales (pos, operation, cash):
  bloqueada SÍ bloquea:
    • Agregar productos al carrito
    • Cobrar ventas
    • Abrir nueva caja
  bloqueada NO bloquea:
    • Ver POS (catálogo, métricas)
    • Ver historial de ventas
    • Cerrar caja
    • Registrar movimientos de caja
    • Editar mesas
    • Sincronizar pendientes
    • Cambiar contraseña
    • Ver estadísticas (día/mes)
    • Abrir detalle de venta

════════════════════════════════════════════════════════════════
7. BANNERS DE LICENCIA (DISEÑO — OFFLINE-FIRST)
════════════════════════════════════════════════════════════════

Mismo estilo que el banner de "Caja cerrada", variando solo
el color de acento y el ícono.

1) bloqueada (rojo, SÍ bloquea nuevas ventas):
   🚫  Licencia vencida
       Ya no puedes registrar nuevas ventas. Conecta a Internet
       e inicia sesión para reactivar.
       Mientras tanto: consultar ventas, cerrar caja,
       sincronizar pendientes.

2) sinSnapshot (ámbar, NO bloquea):
   ⚠️  Sin información de licencia
       Conéctate e inicia sesión para validar.
       Mientras tanto puedes seguir operando.

3) enGracia (naranja, NO bloquea):
   ⚠️  Licencia vencida hace N días
       Regulariza antes de que se bloquee.

════════════════════════════════════════════════════════════════
8. BANNER DE REQUIERE_CAMBIO_PASSWORD (SETTINGS)
════════════════════════════════════════════════════════════════

Aparece SOLO en SettingsScreen, al inicio del ListView, cuando
el flag `requires_password_change` es true.

🔒  Cambia tu contraseña
    Estás usando la contraseña genérica. Por seguridad,
    cámbiala ahora.
                                          [Cambiar]

Botón "Cambiar" abre el diálogo _ChangePasswordDialog.

════════════════════════════════════════════════════════════════
9. DIÁLOGO DE CAMBIO DE CONTRASEÑA (SETTINGS)
════════════════════════════════════════════════════════════════

Campos:
  • Contraseña actual (obligatoria)
  • Nueva contraseña (mín 8, mayúscula + minúscula + número)
  • Confirmar nueva contraseña (debe coincidir)

Validaciones locales + flujo online + limpieza del flag.

Backend (AuthController@changePassword):
  • Verifica contraseña actual.
  • Verifica que la nueva sea distinta.
  • Actualiza contraseña.
  • requiere_cambio_password = false.
  • Revoca tokens anteriores.
  • Audita password.cambiada.

════════════════════════════════════════════════════════════════
10. DEPENDENCIAS FLUTTER
════════════════════════════════════════════════════════════════

✅ device_info_plus: ^13.2.0
✅ geolocator: ^13.0.1

════════════════════════════════════════════════════════════════
11. PRUEBAS E2E — ESTADO
════════════════════════════════════════════════════════════════

✅ Registro desde app → credenciales mostradas → login automático
✅ Cerrar sesión → login con numero_usuario + password genérica
✅ Cambiar contraseña → requiere_cambio_password = false
✅ Login desde otro dispositivo (MAC distinta) → MAC_MISMATCH
✅ Recuperar contraseña con email existente → correo enviado
✅ Recuperar contraseña con email inexistente → 404 EMAIL_NOT_FOUND
✅ Flujo web reset → cambio real → login con nueva contraseña
✅ Cambio de contraseña desde Settings → flag limpiado
✅ Banner persistente en Settings si requiere_cambio_password = true
✅ Auditoría registro.creado con ubicación (curl probado)
✅ Auditoría login.exitoso con ubicación (curl probado)

⏳ Abrir caja con ubicación (curl en local) — fix aplicado, pendiente prueba
⏳ Cerrar caja con ubicación (curl en local)
⏳ Registrar movimiento con ubicación (curl en local)
⏳ Exportar CSV con columnas de ubicación
⏳ Esperar 8 días → bloqueo por licencia vencida
⏳ Prueba E2E completa del registro desde la app con GPS

════════════════════════════════════════════════════════════════
12. PENDIENTES — LISTA ÚNICA CONSOLIDADA
════════════════════════════════════════════════════════════════

A) BACKEND (pendientes menores):
   1. Probar abrir caja, cerrar caja y registrar movimiento con
      ubicación en local (Thunder Client + curl).
   2. Probar exportar CSV con columnas de ubicación.

B) FLUTTER — INTEGRACIÓN GPS (bloque principal):
   1. ✅ Agregar geolocator: ^13.0.1 a pubspec.yaml
   2. ✅ Permisos Android (ACCESS_FINE_LOCATION + COARSE)
   3. ✅ Crear LocationService
   4. ⏳ Modificar ApiClient (parámetros lat/lng/accuracy/provider)
   5. ⏳ Modificar AuthService (login y register)
   6. ⏳ Modificar RegisterScreen (ubicación obligatoria)
   7. ⏳ Modificar SplashScreen (pedir permiso al inicio)
   8. ⏳ Modificar CashService (abrir/cerrar caja)

C) PRUEBAS E2E PENDIENTES:
   1. Registro desde app con GPS (crear cuenta real).
   2. Abrir caja, cerrar caja, movimiento desde app con GPS.
   3. Esperar 8 días → bloqueo por licencia vencida.

D) LIMPIEZA (opcional, no rompe nada):
   1. Corregir 7 warnings cosméticos de flutter analyze.
   2. Migrar prints a debugPrint.
   3. Migrar Share.shareXFiles a SharePlus.instance.share.
   4. Migrar tokens Sanctum a flutter_secure_storage.

════════════════════════════════════════════════════════════════
13. MEJORAS FUTURAS (BACKLOG)
════════════════════════════════════════════════════════════════

1  CAPTCHA en el registro                             Media
2  Confirmación de email obligatoria                  Media
3  Rate limiting por email además de IP               Baja
4  Notificación al superadmin al crear prueba         Baja
5  Panel web aprobar/rechazar pruebas                 Baja
6  Email de bienvenida con credenciales                Media
7  Gráfica de uso por empresa                          Baja
8  Eliminación automática de cuentas vencidas > 30d   Baja
9  Geocercas por ubicación                            Baja
10 Reportes de ubicaciones por rango de fechas        Baja

════════════════════════════════════════════════════════════════
14. ARCHIVOS MODIFICADOS — BACKEND
════════════════════════════════════════════════════════════════

database/migrations/
  ✅ create_registros_prueba_table
  ✅ add_mac_address_to_users_table
  ✅ change_licencia_tipo_enum_in_empresas
  ✅ add_ubicacion_to_logs_auditoria_table

app/Models/
  ✅ RegistroPrueba.php
  ✅ User.php (fillable/casts/métodos)
  ✅ Empresa.php (usaCajas/usaMesas con compatibilidad)
  ✅ LogAuditoria.php (ubicación)

app/Http/Controllers/Api/V1/
  ✅ RegisterController.php
  ✅ AuthController.php (login MAC + password flag + ubicación)
  ✅ CajaController.php (validación ubicación)
  ✅ AuditoriaController.php (CSV con ubicación)

app/Services/
  ✅ AuditoriaService.php (extractUbicacion + 3 métodos)

app/Http/Controllers/Auth/
  ✅ ResetPasswordWebController.php

app/Notifications/
  ✅ ResetPasswordNotification.php

resources/views/auth/
  ✅ reset-password.blade.php
  ✅ reset-success.blade.php

routes/
  ✅ api.php (register, check-email, check-empresa)
  ✅ web.php (rutas reset ANTES del catch-all)

.env
  ✅ Mail Hostinger configurado

════════════════════════════════════════════════════════════════
15. ARCHIVOS MODIFICADOS — FLUTTER
════════════════════════════════════════════════════════════════

lib/core/services/
  ✅ license_service.dart
  ✅ sync_service.dart (banners + null-aware)
  ✅ auth_service.dart (MAC + register + snapshot + flag pwd)
  ✅ location_service.dart (con LocationSettings geolocator 13.x)

lib/core/storage/
  ✅ app_storage.dart (snapshot licencia + purga + flag pwd)

lib/core/network/
  ✅ api_client.dart (register, check-email, check-empresa,
     login MAC, forgot, reset)
  ⏳ api_client.dart (parámetros ubicación)

lib/vistas/auth/
  ✅ register_screen.dart
  ✅ login_screen.dart
  ✅ forgot_password_screen.dart
  ⏳ splash_screen.dart (permiso ubicación)

lib/vistas/pos/
  ✅ pos_screen.dart (offline-first + 3 banners)

lib/vistas/operacion/
  ✅ operation_screen.dart (offline-first + 3 banners)

lib/vistas/caja/
  ✅ cash_management_screen.dart (offline-first + 3 banners)

lib/vistas/estadisticas/
  ✅ daily_stats_screen.dart (offline-first + 3 banners)

lib/vistas/settings/
  ✅ settings_screen.dart (password + banner)

lib/core/services/
  ⏳ cash_service.dart (parámetros ubicación)

android/app/src/main/
  ✅ AndroidManifest.xml (ACCESS_FINE_LOCATION + COARSE)

pubspec.yaml
  ✅ device_info_plus: ^13.2.0
  ✅ geolocator: ^13.0.1