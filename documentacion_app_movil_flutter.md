# Especificación técnica — Aplicación móvil Flutter POS offline-first

**Fecha:** 2026-08-28  
**Estado:** Diseño funcional y técnico; no implementado.  
**Backend objetivo:** POS Backend Laravel, API bajo `/api/v1`.

## 1. Objetivo y alcance cerrado

La aplicación Flutter será un POS móvil para iOS y Android con operación offline-first. Solo tendrá las siguientes pantallas principales:

1. Inicio de sesión.
2. Punto de venta / ventas del día.
3. Estadísticas del día.
4. Administración y configuración.

Los selectores, confirmaciones, devolución, ticket, envío de reporte y reintento serán hojas modales o diálogos de estas pantallas, no vistas adicionales. No se incluirán compras, proveedores, facturación, notificaciones, reportes históricos, gestión de usuarios ni otras vistas fuera de este alcance.

La interfaz nunca hará llamadas HTTP directamente. Widgets, páginas, controladores de estado y diálogos dependen de casos de uso/repositorios; solo la capa de infraestructura invoca la API mediante un cliente HTTP centralizado. En Flutter no corresponde usar Axios (es una biblioteca JavaScript); se usará **Dio**, con una estructura equivalente de helpers/servicios.

## 2. Principios obligatorios

- La base de datos local es la fuente inmediata de lectura y escritura de la app.
- Toda venta se confirma localmente dentro de una transacción SQLite antes de intentar subirla.
- Cada venta offline tiene un UUID generado por el dispositivo; nunca se recrea en un reintento.
- El servidor es la fuente final para catálogos, licencia y resolución de conflictos.
- La fecha comercial se calcula en zona horaria de la empresa/configuración, no en UTC.
- Solo se muestran las ventas de la fecha comercial actual. Los datos de días previos se archivan en la base de backups local y se eliminan de la base operativa.
- La base de licencia nunca se borra por limpieza diaria, logout normal, actualización de catálogos ni rotación de la base del día.
- Si la licencia lleva más de tres días vencida, la app queda bloqueada para operar hasta recuperar Internet y realizar login exitoso.

## 3. Arquitectura propuesta

```text
Presentation
 ├─ LoginPage
 ├─ PosPage (ventas del día)
 ├─ DailyStatsPage
 └─ SettingsPage
        │  StateNotifier / Bloc / Riverpod providers
Domain
 ├─ Use cases: login, registrarVenta, sincronizar, cerrarDia, imprimir
 ├─ Entidades y reglas de licencia/estado
 └─ Interfaces de repositorio
Data
 ├─ Repositorios
 ├─ DioApiClient + interceptores
 ├─ SQLite (Drift recomendado)
 ├─ Secure storage
 ├─ NetworkMonitor global
 └─ Printer / PDF / Share adapters
```

### Estructura de proyecto

```text
lib/
  app/                    # Router, tema, bootstrap y observadores globales
  core/
    network/              # DioApiClient, NetworkMonitor, interceptores
    database/             # factories SQLite, migraciones y DAOs
    security/             # secure storage, cifrado y protección de secretos
    time/                 # reloj comercial y zonas horarias
    printing/             # PDF, Bluetooth/USB/red y adaptadores de ticket
  features/
    auth/
    pos/
    sync/
    statistics/
    settings/
    license/
  shared/
    widgets/              # componentes reutilizables; nunca consumen API
    models/
```

## 4. Pantallas y comportamiento

### 4.1 Inicio de sesión

Campos: identificador (email o número de usuario) y contraseña. Acciones: iniciar sesión, reintentar red y restablecer contraseña.

- Con Internet: llama a `POST /api/v1/login`, guarda token de forma segura, usuario, empresa, configuración y licencia; inicia la sincronización inicial diaria.
- Sin Internet: no permite un primer login. Puede mostrar **Reanudar operación offline** solo si existe una sesión local válida, la licencia local permite operar y ya existe una base diaria abierta para el mismo usuario/empresa.
- Si licencia vencida por más de tres días: muestra bloqueo total, deshabilita reanudar y solo permite “Reintentar conexión” e “Iniciar sesión”.
- Nunca guardar contraseña en SQLite ni en preferencias.

### 4.2 POS / ventas del día

Muestra catálogo local activo, búsqueda por nombre/código, carrito, cliente, pagos, descuentos permitidos, total, estado de red y vigencia de licencia.

- Lee solo el catálogo SQLite local.
- La vista de caja sigue un patrón de supermercado / tienda: catálogo y búsqueda prominente, con el carrito en una vista independiente accesible mediante botón flotante para evitar desbordamientos en móvil y orientación horizontal.
- El encabezado de la caja usa una composición más institucional, con estado de sesión y resumen financiero destacado para dar sensación de aplicación POS profesional.
- La UI conserva la paleta verde institucional y aplica sombras, bordes redondeados, tarjetas premium y chips de estado para mejorar legibilidad, velocidad de operación y percepción de marca.
- Se agregan métricas comerciales de ventas del día, pendientes y sincronizadas, con un resumen claro y compacto para la operación del turno.
- Al confirmar: genera `uuid_local`, registra venta/detalles/pagos y movimiento de stock local en una sola transacción.
- Estado visible por venta: **Actualizada** (confirmada por servidor), **En espera** (en cola por falta de red), **Error de actualización** (servidor rechazó; requiere acción), **Pagada / sin sincronizar** y **Pendiente** (borrador sin confirmar).
- La lista se limita a la fecha comercial actual; no es un historial general.
- Botón “Cargar pendientes” sincroniza solo `En espera` y `Error de actualización` seleccionadas para reintento; nunca reenvía ventas ya confirmadas.
- Las anulaciones/devoluciones deben seguir el mismo patrón de cola e idempotencia. Mientras el backend no exponga contrato offline para ellas, se mostrarán como “requiere conexión”.

### 4.3 Estadísticas del día

Calcula inmediatamente desde SQLite: total pagado, tickets, ticket promedio, ventas por forma de pago, ventas por hora, pendientes, errores y sincronizadas. Con Internet puede contrastar o refrescar con `GET /api/v1/estadisticas/dia`, pero la UI no debe bloquearse si falla.

### 4.4 Administración y configuración

Única pantalla con secciones internas:

- Colores de empresa: lectura/actualización mediante `PUT /api/v1/admin/empresa/config`; solo si el rol autorizado lo permite.
- Ticket: `GET/PUT /api/v1/ticket/config`; papel 58/80 mm, logo, QR, campos, cabecera y pie.
- Impresoras: alta local, prueba, selección predeterminada y configuración de Bluetooth/USB/red. La impresora es configuración del dispositivo, no del backend.
- Usuario: muestra datos de `GET /api/v1/user`, edición de perfil y restablecimiento/cambio de contraseña.
- Datos del día: conteos, sincronizar, generar PDF/Excel y archivar/cerrar el día.

## 4.5 Historial de ventas y estados de sincronización

- La pantalla de estadísticas del día actúa como historial local de la jornada y lista todas las ventas con su estado real: pendiente, pagada sin sincronizar, sincronizada o fallida.
- Una venta no cerrada conserva el estado `pending` y se mantiene en la lista hasta que el usuario la complete o la elimine manualmente.
- Cuando se cobra una venta correctamente, la base local guarda el estado `paid` con `sync_status = pending`; de este modo la venta se muestra como ya pagada pero aún pendiente de sincronización.
- El botón de sincronización manual reintenta todas las ventas con estado pendiente o fallido, usando la cola local y la sincronización directa del SQLite cuando no hay sesión activa o la API no está disponible.
- El backend solo contabiliza el efectivo recibido; los pagos en tarjeta, transferencia u otros medios se registran localmente para la vista de cobro, pero no alteran el importe efectivo que se envía al backend.
- El flujo de cobro soporta pagos múltiples: se puede combinar efectivo, tarjeta, transferencia o cheque; la vista calcula el cambio, el exceso y la diferencia restante, y presenta claramente lo que sí se envía al backend (solo efectivo).
- La vista de pago incluye un resumen financiero grande con monto a cobrar, descuento o ajuste, cantidades por forma de pago y la diferencia final de más o menos, con una representación clara del impacto real en caja.

#### Diálogo de cobro y tipo de pago

- Al confirmar una venta se abre el diálogo "Cobro y cambio" con un resumen destacado del total a cobrar.
- El selector de tipo de pago usa un `DropdownButton` robusto (sin form validation) dentro de un container con borde, evitando problemas de renderización con `StatefulBuilder` y actualizaciones rápidas.
- Cada fila de pago contiene: tipo de método (dropdown con opciones Efectivo, Tarjeta, Transferencia, Cheque), cantidad ingresada, y botón de eliminar (deshabilitado si es la única fila).
- Al cambiar tipo de pago, cantidad o agregar/quitar filas, la vista se actualiza inmediatamente sin parpadeos ni errores de estado.

**Lógica diferenciada por método de pago:**

1. **Efectivo:**
   - Permite cobrar el monto exacto o mayor
   - Si se sobrepasa, muestra el **cambio en verde** a devolver automáticamente
   - No requiere confirmación adicional; el cambio es obligatorio

2. **Otros métodos (Tarjeta, Transferencia, Cheque):**
  - Solo permite cobrar el monto **exacto**
  - Si intenta cobrar más, muestra advertencia en **naranja** y bloquea el cobro

- **Resumen dinámico de cobro:** debajo de las filas de pago se visualiza en tiempo real:
  - Monto a cobrar (fijo).
  - Total cobrado (suma de todas las cantidades ingresadas).
  - Desglose por método de pago: Efectivo, Tarjeta, Transferencia, Cheque (solo si hay importes > 0).
  - **Cambio** (si el total es mayor y hay efectivo): diferencia entre efectivo recibido y total, mostrado en verde.
  - **⚠ Excedente sin cambio** (si el total es mayor y NO hay efectivo): diferencia cuando solo hay tarjeta/transferencia/cheque, en naranja con aclaración de que requiere confirmación.
  - **Falta por cobrar** (en rojo, si el total es menor): diferencia aún pendiente.
  - **Cobro exacto** (en verde, si coincide): confirmación de que se cubrió exactamente el monto.
- El botón “Agregar tipo de pago” permite múltiples métodos; el botón “Guardar cobro” valida que el total recolectado sea igual al monto a cobrar cuando no hay efectivo, e informa de falta si la suma es insuficiente.
- Un excedente solo es válido cuando proviene de efectivo, porque se registra como cambio; nunca se acepta excedente de métodos no monetarios.
- La venta se guarda localmente como estado "paid" con sync_status "pending" una vez validado el cobro; esto permite que una venta pagada se visualice inmediatamente en historial aunque no esté sincronizada.

## 4.6 UX del checkout y catálogo administrable

- El diseño del checkout está pensado como caja moderna de retail: encabezado institucional, búsqueda premium, tarjetas limpias, carrito independiente, precios destacados y botones de acción corporativos.
- Las tarjetas de productos y catálogos usan bordes, sombras y colores consistentes con la marca, manteniendo el tono verde institucional y evitando saturación visual.
- Las listas de catálogo son reutilizables y legibles en tablet o móvil, con indicadores de stock y precios claramente jerarquizados para acelerar la toma de pedido.
- La altura del carrito se mantiene compacta, con filas ajustadas para mejorar el flujo de cobro en una caja rápida y con alta frecuencia de uso.
- Los botones principales del POS están diseñados para sentirse como acciones de retail real, con contraste alto y jerarquía clara para confirmar ventas y manejo de pagos.
- El carrito se presenta en una pantalla propia con scroll; el detalle de venta y el diálogo de cobro también usan scroll cuando el contenido supera el alto disponible.
- Estadísticas ofrece sincronización manual de ventas pendientes y el detalle carga productos y pagos desde SQLite.
- Administración incluye consulta de empresa/dispositivo y CRUD local de productos, disponible sin conexión. La descarga online del catálogo sigue actualizando la base local.

## 5. Red y modo online/offline

Implementar un `NetworkMonitor` singleton observado desde el bootstrap de la app:

1. `connectivity_plus` detecta Wi-Fi, datos, Ethernet o ausencia de transporte.
2. `internet_connection_checker_plus` confirma acceso real a Internet; conectividad Wi-Fi sola no implica Internet.
3. Al recuperar Internet se programa sincronización con debounce, bloqueo de exclusión mutua y reintentos exponenciales.
4. La UI obtiene el estado desde un provider global: `online`, `offline`, `syncing`, `limited`.
5. Si el token recibe 401, se borra únicamente el token y se exige login; las ventas locales y licencia se preservan.

No usar polling agresivo. Debe existir un botón manual de sincronización y un indicador global persistente.

## 6. Licencia y ventana de gracia

### Almacenamiento permanente

Crear una base SQLite separada: `license.sqlite`. Sus tablas no participan en limpieza diaria. Complementar con `flutter_secure_storage` para token y material sensible.

```sql
CREATE TABLE license_snapshot (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  user_id INTEGER NOT NULL,
  empresa_id INTEGER NOT NULL,
  tipo TEXT,
  fecha_inicio TEXT,
  fecha_fin TEXT,
  server_checked_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  signature TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE device_identity (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  installation_id TEXT NOT NULL UNIQUE,
  first_seen_at TEXT NOT NULL,
  last_login_at TEXT,
  last_successful_sync_at TEXT
);
```

### Regla de acceso

```text
permanente                         → permitir
fecha_fin >= ahora                 → permitir
ahora - fecha_fin <= 3 días        → permitir con aviso “licencia en gracia”
ahora - fecha_fin > 3 días         → bloquear POS, estadísticas operativas y configuración remota
sin snapshot local                 → bloquear hasta login online
reloj local retrocede sospechosamente → bloquear/requerir validación online según política
```

La fecha de referencia se debe calcular con la última hora confiable del servidor más un reloj monotónico local. Guardar `server_checked_at` evita que el usuario evada la vigencia cambiando hora del teléfono. El bloqueo solo se levanta tras Internet y `POST /login` exitoso; no basta una sincronización ni editar datos locales.

## 7. Bases SQLite y retención diaria

### 7.1 Base operativa del día: `pos_day_YYYY-MM-DD.sqlite`

Se crea por empresa, usuario y fecha comercial; el nombre final debe incluir identificadores o residir en directorio aislado:

```text
app-data/companies/{empresaId}/users/{userId}/pos_day_YYYY-MM-DD.sqlite
```

Tablas mínimas:

| Tabla | Propósito |
|---|---|
| `products`, `categories`, `units`, `clients`, `payment_methods`, `taxes` | Catálogos locales con versión, `deleted_at` y fecha de sync. |
| `sales` | UUID local, id/firma servidor, folio, fecha comercial, totales, estado sync, error y versión. |
| `sale_items`, `sale_payments` | Detalles locales de la venta. |
| `stock_movements` | Movimiento inmutable local para venta, ajuste, devolución o sync. |
| `sync_outbox` | Operaciones por enviar con UUID, tipo, payload JSON, hash, intentos, error, next_retry_at. |
| `sync_inbox` | Cursor/versión y aplicación de cambios recibidos. |
| `daily_metadata` | Usuario, empresa, fecha, cierre, última sincronización y esquema. |
| `printers` | Configuración no sensible de impresoras del dispositivo. |

Estados de `sales.sync_status`: `pending`, `queued`, `uploading`, `synced`, `failed`, `conflict`, `draft`. La transición debe ser validada por un caso de uso, no editada desde widgets.

### 7.2 Base de backups: `pos_backup.sqlite`

Nunca se usa para operar el día. Conserva días cerrados y pendientes de carga:

```sql
CREATE TABLE archived_days (
  id INTEGER PRIMARY KEY,
  empresa_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  business_date TEXT NOT NULL,
  archived_at TEXT NOT NULL,
  export_pdf_path TEXT,
  export_xlsx_path TEXT,
  upload_status TEXT NOT NULL,
  source_checksum TEXT NOT NULL,
  UNIQUE (empresa_id, user_id, business_date)
);

CREATE TABLE archived_sales (...);
CREATE TABLE archived_sale_items (...);
CREATE TABLE archived_sale_payments (...);
CREATE TABLE archived_outbox (...);
```

Copiar datos y outbox a backup dentro de una transacción antes de borrar la base diaria. No borrar un backup ni un outbox archivado hasta recibir confirmación del servidor y cumplir la política de retención definida por negocio.

### 7.3 Cambio de día y aviso

Al abrir la app en un nuevo día, o al iniciar sesión con fecha comercial distinta:

1. Detectar bases diarias anteriores no cerradas.
2. Mostrar diálogo: “Los datos offline del día anterior serán archivados localmente. Puede generar PDF/Excel y compartirlo por correo o WhatsApp antes de cerrar.”
3. Ofrecer: **Sincronizar y cerrar**, **Generar/compartir**, **Archivar sin conexión** o **Cancelar**.
4. Antes de eliminar el archivo operativo, copiar ventas, adjuntos y outbox a `pos_backup.sqlite`; verificar checksum y registrar cierre.
5. Si hay Internet, intentar subir pendientes antes y después del archivado. Si falla, el backup queda `upload_status=pending`.
6. Solo después de copia verificada, borrar la base operativa anterior y crear la nueva.

Nunca borrar de la base de licencia durante este proceso.

## 8. Sincronización e idempotencia

### Primer login del día

El primer login online de cada día debe ejecutar, en orden:

1. Validar usuario, token, empresa y licencia.
2. Archivar/cerrar el día anterior si corresponde.
3. Cargar catálogo local actual y cursor de cambios.
4. Solicitar catálogo completo o diferencial; añadir elementos ausentes y aplicar actualizaciones/bajas.
5. Subir outbox de la base diaria y backups pendientes, en orden de creación.
6. Confirmar cada UUID con el servidor y marcar únicamente esa operación como `synced`.
7. Descargar cambios posteriores a la marca de sincronización.
8. Guardar cursor y `last_successful_sync_at` solo al terminar sin errores.

### APIs existentes del backend

| Necesidad Flutter | API actual | Observación |
|---|---|---|
| Login/licencia | `POST /login`, `GET /licencia/estado` | Login devuelve usuario, empresa y licencia. |
| Usuario actual | `GET /user` | Solo lectura. |
| Catálogo | `GET /catalogos?desde=...`, `GET /catalogos/productos` | Actualmente no cubre todas las bajas/catálogos; ver APIs requeridas. |
| Ventas online | `POST /ventas` | Contrato difiere del offline y debe unificarse antes de usarlo como fallback. |
| Ventas offline | `POST /sync/offline` | No está listo: hoy no genera folio y falla; no activar hasta corregir backend. |
| Sync general | `POST /sync` | Actualmente no regresa cambios remotos; requiere corrección. |
| Estadísticas | `GET /estadisticas/dia` | Complemento de cálculo local. |
| Ticket | `GET/PUT /ticket/config`, `GET /ventas/{id}/ticket` | PDF servidor solo para venta ya sincronizada. |
| Colores empresa | `PUT /admin/empresa/config` | Debe protegerse por rol. |

### Conflictos

- El servidor responde con confirmación que incluya `uuid_local`, `venta_id`, `folio`, totales calculados y versión.
- Un reintento con el mismo UUID debe devolver la venta existente, nunca crear otra.
- No sobrescribir automáticamente cambios de stock/precio que afecten una venta ya capturada; registrar conflicto y mostrar diálogo de resolución.
- El catálogo puede ser “última versión del servidor”; ventas y movimientos son inmutables.

## 9. Usuarios de prueba offline para validación sin Internet

Para pruebas funcionales del flujo sin acceso a red, la app incluye dos usuarios demo con licencia permanente y catálogo de prueba local para cualquier día. Estos usuarios no dependen del backend ni de Internet para iniciar sesión ni operar en la app:

| Identificador | Contraseña | Nombre | Tipo de licencia | Observación |
|---|---|---|---|---|
| `1000000003` | `yesy2001` | Yesenia López | permanente | Acceso local sin conexión |
| `1000000002` | `prueba2026` | Prueba Usuario | permanente | Acceso local sin conexión |

### Catálogos de prueba offline

Estos usuarios tienen un catálogo precargado para validar ventas, pagos y flujo de sincronización sin acceso a Internet en cualquier fecha comercial, incluso sin vigencia de día o cierre automático:

#### Usuario `1000000003`
- Café Americano — $38.00
- Té Verde — $32.00
- Sándwich Club — $120.00
- Refresco Cola — $28.00
- Agua Mineral — $22.00
- Tostadas de Frijol — $65.00
- Pastel de Chocolate — $75.00
- Helado Vainilla — $58.00

#### Usuario `1000000002`
- Papas Fritas — $52.00
- Hamburguesa Doble — $165.00
- Hot Dog — $88.00
- Galletas — $35.00
- Jugo de Naranja — $42.00
- Ensalada César — $140.00
- Brownie — $68.00
- Smoothie Fresa — $78.00

### Reglas de uso
- Ambas cuentas son para pruebas locales y no tienen restricción de vigencia.
- La licencia se considera permanente para evaluación del flujo operativo.
- La app debe permitir el inicio de sesión, el pos y la sincronización aunque haya caído la red.
- Si se requiere verificar el cambio de día, el usuario puede seguir operando sin reiniciar el catálogo porque los catálogos de prueba son persistentes y no caducan.

## 10. APIs que deben agregarse o corregirse en POS Backend

La validación del punto 10 de `documentacion_venta_en_fa.md` queda cubierta en el cliente para pagos, estados, cola local e idempotencia básica. Las APIs de esta sección siguen siendo responsabilidad del proyecto POS Backend; no se simulan en Flutter y requieren validación en ese repositorio.

La app no debe simular estas funciones en el cliente. Antes de desarrollar el flujo completo, el backend necesita:

| Prioridad | Método y ruta propuesta | Función |
|---|---|---|
| Crítica | Corregir `POST /sync/offline` | Generar folio/UUID, validar datos, guardar idempotentemente y responder mapeo UUID → venta/folio. |
| Crítica | Corregir `POST /sync` o crear `GET /sync/pull?cursor=` | Devolver cambios, tombstones y cursor transaccional. |
| Alta | `PATCH /user/profile` | Actualizar nombre, teléfono y datos permitidos del usuario autenticado. |
| Alta | `POST /user/password` | Cambio autenticado: contraseña actual, nueva contraseña y revocación de otros tokens. |
| Alta | `POST /password/forgot`, `POST /password/reset` | Restablecimiento seguro por correo/OTP; rate limiting y tokens con expiración. |
| Alta | `POST /sync/archive` o ampliar sync | Recepción idempotente de ventas archivadas/backups pendientes. |
| Media | `POST /reports/daily/share` | Envío por correo o integración WhatsApp Business del PDF/XLSX; validar autorización y destinatario. |
| Media | `GET /catalogos?desde=` mejorado | Incluir categorías, promociones, cupones y bajas de todas las entidades. |
| Media | `GET /me/permissions` | Capacidades por rol para ocultar/inhabilitar secciones administrativas de forma consistente. |

Para correo/WhatsApp sin endpoint servidor, la alternativa inicial es generar PDF/XLSX local y usar el selector nativo de compartir. No garantiza entrega ni permite envío silencioso; WhatsApp con adjuntos se resuelve mediante share sheet. Envío automatizado requiere integración backend y consentimiento.

## 11. Impresión, PDF, Excel y compartición

- La configuración local del ticket (papel, cabecera y pie) se guarda en preferencias y se envía a `GET/PUT /api/v1/ticket/config` cuando hay conexión.
- Generar ticket local desde plantilla y datos SQLite para operar sin red; al sincronizar puede reemplazarse por el PDF oficial del servidor si negocio lo exige.
- Soportar 58 mm y 80 mm, impresora Bluetooth, red TCP y USB cuando la plataforma/paquete lo permita.
- Persistir por dispositivo: tipo de conexión, dirección, tamaño de papel, código de caracteres, impresora predeterminada y última prueba. No guardar secretos Wi-Fi.
- La conexión física Bluetooth/WiFi requiere un adaptador de impresión compatible con el modelo de hardware; el backend actual no expone APIs de descubrimiento ni conexión de impresoras.
- Generar resumen diario PDF y XLSX desde backup/base diaria antes del borrado. Confirmar que se creó archivo antes de ofrecer compartir.
- Compartir usando selector nativo para correo y WhatsApp. Registrar localmente fecha, formato y resultado de intento; no afirmar entrega si el sistema operativo no la confirma.

## 12. Configuración global de endpoints

La app debe usar un único punto de configuración para el dominio base del backend. Esto evita que cada endpoint tenga una URL fija y facilita subir la app a producción con un nuevo host.

### Regla base

- El valor central se declara en `AppConfig.apiBaseUrl`
- Todos los endpoints usan esa base para construir la ruta final
- Cuando cambia el dominio, solo se actualiza ese valor y el resto de la API queda consistente

### Ejemplo de configuración

```dart
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
```

### Ejemplos de uso por entorno

- Desarrollo local: `http://127.0.0.1:8000`
- Emulador Android / backend local: `http://10.0.2.2:8000`
- Producción: `https://miserver.com.mx`

Con este patrón, las rutas quedan así:

- `https://miserver.com.mx/api/v1/login`
- `https://miserver.com.mx/api/v1/user`
- `https://miserver.com.mx/api/v1/sync/offline`

Esto asegura que el cambio del dominio no requiera tocar cada endpoint individualmente.

### Recomendación de despliegue

Para producción se recomienda pasar el valor desde variable de entorno o build-time config, por ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=https://miserver.com.mx
flutter build apk --dart-define=API_BASE_URL=https://miserver.com.mx
```

La app no debe hardcodear el dominio en cada llamada HTTP.

## 13. Dependencias Flutter iniciales

| Paquete | Uso |
|---|---|
| `flutter_riverpod` o `flutter_bloc` | Estado y reglas fuera de vistas. |
| `dio` | Cliente HTTP centralizado, interceptores y reintentos. |
| `drift` + `sqlite3_flutter_libs` | SQLite tipada, migraciones y transacciones. |
| `path_provider` | Directorios aislados para bases y exportaciones. |
| `flutter_secure_storage` | Token, claves y datos sensibles. |
| `connectivity_plus` + `internet_connection_checker_plus` | Estado global de red y acceso real. |
| `workmanager` | Intentos en segundo plano, sujeto a restricciones de iOS/Android. |
| `uuid` | Idempotencia de ventas/operaciones. |
| `pdf`, `printing`, `share_plus` | PDF, impresión y compartir. |
| Paquete XLSX mantenido | Exportación diaria Excel compatible. |
| `timezone` | Fecha comercial y vigencia correctas. |
| Paquete de impresora compatible | Adaptador Bluetooth/USB/TCP, elegido tras prueba de hardware. |

## 13. Seguridad, backups y APK

- Cifrar bases SQLite o, como mínimo, proteger archivos con cifrado a nivel de aplicación; evaluar SQLCipher conforme a la sensibilidad de datos.
- Token en secure storage; limpiar token al logout, pero nunca licencia/backups sin confirmación del usuario y política definida.
- No registrar contraseñas, tokens, RFC, correos, payloads completos de venta ni datos personales en logs de producción.
- Validar certificado TLS, timeouts, reintentos y errores 401/403/422/429/500 de forma centralizada.
- Usar `applicationId` definitivo, firma de release, keystore/Play App Signing, iconos adaptativos, permisos mínimos y ofuscación/minificación de release.
- Android: declarar Internet, Bluetooth y ubicación solo si la versión de Bluetooth/hardware lo exige; solicitar permisos en tiempo de ejecución. iOS: añadir descripciones de uso en `Info.plist`.
- Configurar CI para `flutter analyze`, pruebas unitarias, pruebas de repositorios SQLite, pruebas de integración offline y build Android release.

## 12.1 Documento complementario: venta en factura (FA)

Este proyecto incluye un documento complementario para el flujo de venta con factura o comprobante fiscal:

- [documentacion_venta_en_fa.md](documentacion_venta_en_fa.md)

Ese archivo describe reglas específicas de venta, cliente, comprobante, validación de pagos, sincronización e idempotencia. No reemplaza la documentación principal del POS; solo complementa la especificación del flujo de caja y comprobantes.

## 13. Criterios de aceptación

1. Sin red, una venta se guarda, imprime y queda visible como “En espera”; al reconectar se sube una sola vez.
2. Un reintento no duplica ventas aunque la respuesta se haya perdido.
3. El primer login online del día actualiza catálogo, aplica bajas, sube pendientes y persiste licencia.
4. Al exceder tres días desde vencimiento, no es posible vender ni reanudar offline; solo un login online exitoso puede desbloquear.
5. Un cambio de día archiva y verifica datos antes de borrar la base operativa; la licencia permanece intacta.
6. Solo se visualizan ventas del día comercial vigente en el POS móvil.
7. Las vistas no importan Dio ni repositorios de infraestructura; solo consumen estado/casos de uso.
8. PDF/XLSX puede generarse y compartirse antes de cerrar el día, aun sin Internet.
9. La aplicación release compila, pasa análisis estático y maneja de forma visible los estados offline, sincronizando, error y bloqueado.

## 15. Orden recomendado de implementación

1. Corregir contratos críticos de backend (sync offline, sync pull, auditoría y autorización).
2. Crear shell Flutter, tema inicial, navegación de cuatro pantallas, Dio y secure storage.
3. Implementar licencia persistente, reloj confiable y bloqueo/gracia.
4. Implementar SQLite diaria, backup y catálogos; pruebas de migración/rotación de día.
5. Implementar POS local, outbox e idempotencia; después sincronización.
6. Añadir estadísticas, tickets/impresoras, PDF/XLSX y compartir.
7. Añadir configuración/perfil cuando los endpoints backend requeridos existan.
8. Endurecer seguridad, pruebas de red y preparar APK firmada.

## 16. Subir a Play Store correctamente

Para publicar la app en Google Play con un flujo seguro y profesional:

1. Crear el proyecto de la app en Google Play Console.
2. Generar una keystore real para release y mantenerla segura.
3. Configurar la firma de Android en `android/key.properties` y `android/app/build.gradle.kts`.
4. Ejecutar la release build:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

5. Subir el archivo `.aab` generado a Play Console.
6. Completar la información obligatoria de la tienda:
   - nombre y descripción,
   - política de privacidad,
   - categoría,
   - capturas, vídeo y iconos,
   - permisos necesarios,
   - soporte y contacto.
7. Publicar primero en Internal Testing o Closed Testing.
8. Hacer rollout gradual y validar rendimiento, compra de app, sincronización y estado offline.
9. Revisar políticas de Google Play para apps con POS, ventas y almacenamiento local.

### Recomendaciones para una app POS

- Usar Play App Signing para evitar pérdida de claves.
- Mantener un `applicationId` estable.
- No publicar con usuarios demo ni credenciales reales visibles.
- Separar entorno de desarrollo y producción.
- Documentar permisos mínimos y el funcionamiento offline.
- Mantener la política de privacidad accesible desde la app y desde la Play Console.

### Checklist de lanzamiento

- La app compila en release.
- No hay errores críticos de `flutter analyze`.
- El login demo offline funciona sin Internet.
- La sincronización guarda ventas en outbox y reintenta al recuperar red.
- El flujo de catálogo del día funciona sin conexión.
- Las políticas, permisos y privacidad están resueltos.
- Hay una versión de prueba antes de producción.

### Cuentas de prueba recomendadas

Estas cuentas están diseñadas para validar la app sin Internet y sin depender del backend real:

| Usuario | Contraseña | Licencia |
|---|---|---|
| `1000000003` | `yesy2001` | Permanente |
| `1000000002` | `prueba2026` | Permanente |

Los catálogos de prueba para estas cuentas quedaron definidos en la etapa de validación local y se pueden reutilizar para pruebas de ventas, búsquedas y sincronización.

## 17. Compilación y publicación para iOS

La compilación iOS requiere macOS y Xcode. Windows puede editar, analizar y probar el código Flutter, pero no puede ejecutar `flutter build ios` ni generar un archivo `.ipa` porque Apple solo permite esa cadena de compilación con Xcode en macOS.

### Requisitos

- macOS compatible con la versión de Xcode instalada.
- Xcode actualizado y sus Command Line Tools configuradas.
- CocoaPods instalado y actualizado.
- Cuenta de Apple Developer para instalar en dispositivo o publicar.
- Certificados, provisioning profiles y Bundle Identifier configurados en Xcode.
- Dispositivo iPhone/iPad registrado para pruebas físicas, si aplica.

### Preparación en macOS

Desde la raíz del proyecto:

```bash
flutter doctor -v
flutter pub get
cd ios
pod install
cd ..
flutter analyze
flutter test
```

Abrir `ios/Runner.xcworkspace` en Xcode, seleccionar el equipo de desarrollo en **Signing & Capabilities**, revisar el Bundle Identifier y confirmar las capacidades requeridas.

### Permisos iOS

`ios/Runner/Info.plist` incluye:

- `NSBluetoothAlwaysUsageDescription` para impresoras térmicas Bluetooth.
- `NSLocalNetworkUsageDescription` para impresoras térmicas WiFi/TCP.

El usuario debe aceptar estos permisos en el primer uso. La impresora Bluetooth debe estar vinculada o ser visible según el modelo y el adaptador utilizado. La impresión WiFi requiere que el iPhone y la impresora estén en la misma red y que el puerto TCP de la impresora esté accesible.

### Build y distribución

```bash
flutter build ios --release
flutter build ipa --release
```

El primer comando prepara la aplicación iOS; el segundo genera el paquete distribuible cuando la firma y el archivado están configurados. Para pruebas internas se recomienda usar TestFlight antes de publicar en App Store Connect.

### Validación iOS

- Probar login online y reanudación offline.
- Confirmar rotación y scroll en iPhone y iPad.
- Probar permisos y conexión Bluetooth con una impresora térmica real.
- Probar impresión TCP con la IP y puerto de la impresora.
- Confirmar ticket de 58/80 mm y caracteres acentuados.
- Verificar sincronización, cancelación y devolución de stock.
- Revisar que no se incluyan credenciales demo en una compilación de producción.

El mensaje `packages have newer versions incompatible with dependency constraints` es informativo: indica que existen actualizaciones que no caben en las restricciones actuales de `pubspec.yaml`; no significa por sí mismo que la APK o la preparación iOS fallen. Se puede revisar con `flutter pub outdated` y actualizar de forma controlada después de validar compatibilidad.

## 18. Ajustes recientes del POS (2026-08-31)

- Las ventas en espera se guardan sin descontar existencias y pueden recuperarse, editarse, eliminarse o cobrarse posteriormente. Al cobrarlas, el descuento de inventario y el registro de pago son atómicos.
- Toda venta pagada se guarda de forma transaccional: ante inventario insuficiente se revierte la operación completa, evitando registros parciales.
- La pantalla de caja muestra únicamente las ventas de la fecha comercial actual; los indicadores ya no mezclan ventas de días anteriores.
- El detalle posterior al cobro se abre con la venta exacta que se acaba de persistir.
- En pagos mixtos, los medios distintos de efectivo se acreditan primero y el cambio se calcula solo contra el efectivo excedente. Un pago no efectivo no puede exceder por sí mismo el total de la venta.
- La configuración de ticket administra sus controladores dentro del ciclo de vida del diálogo, evitando liberarlos mientras Flutter aún desmonta la interfaz.
- Cuando la empresa exige caja, el POS consulta el estado operativo y bloquea el guardado o cobro mientras no haya una caja abierta; en modo offline aplica la última instantánea válida almacenada.
- El módulo **Operación** está disponible desde el estado de Caja en POS. Un usuario con rol `cajero`, `admin` o `superadmin` puede abrir y cerrar caja; con mesas activas también puede crear y editar mesas.
- Con mesas activas, POS permite elegir una mesa antes de guardar una venta pendiente. La asociación sobrevive al modo offline, aparece en los listados y viaja como `mesa_id` durante la sincronización.
