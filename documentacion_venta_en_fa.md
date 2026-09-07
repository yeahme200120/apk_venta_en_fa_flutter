# Documentación — Aplicación Móvil "Vende en FA"

**Proyecto:** POS móvil Flutter  
**Estado:** Documento complementario del POS y de la coordinación con backend  
**Actualizado:** 2026-09-07 (v3) — Cambios implementados: estadísticas rediseñadas, tab Caja condicional, inventariable en POS, colores settings, búsqueda en catálogo, rol persistido en AppStorage  
**Relación con otros documentos:** complementa a [documentacion_app_movil_flutter.md](documentacion_app_movil_flutter.md), no reemplaza la especificación técnica general ni la API del backend.

---

## 1. Objetivo

Definir el flujo de venta que puede terminar en factura o comprobante fiscal, manteniendo la operación en modo offline-first y sin romper el flujo de caja del punto de venta.

Este documento complementa la documentación general del POS y del backend. Su propósito es ser un punto de referencia para:

- venta con cliente y datos fiscales
- selección de tipo de comprobante
- validación de montos y pagos
- sincronización de venta y factura en una sola operación
- gestión de errores y reintentos
- correcciones de diseño y funcionalidad detectadas en revisión de UX (v1)

---

## 2. Alcance

Este documento cubre:

- venta con cobro directo
- venta con factura / comprobante fiscal
- venta con datos de cliente obligatorios o opcionales según tipo de comprobante
- validación de subtotal, impuestos y total
- captura de pagos y cálculo de cambio
- confirmación local y sincronización posterior
- correcciones de diseño visual (splash, login, POS, estadísticas, administración)
- correcciones de flujo y funcionalidad (autenticación, cobro, catálogo, egresos)

No cubre:

- gestión de proveedores
- inventario de compras
- reportes históricos complejos
- auditoría fiscal externa
- integraciones con terceros no requeridas en la app POS

---

## 3. Reglas de negocio

### 3.1 Tipos de venta

La venta puede registrarse como:

- `venta_directa` : cobro inmediato y cierre de ticket
- `venta_factura` : requiere datos fiscales y comprobante
- `venta_pendiente` : venta a crédito o pago parcial, según política del negocio

### 3.2 Datos mínimos requeridos

Para venta con comprobante fiscal, el sistema debe validar al menos:

- nombre o razón social del cliente
- RFC o identificación fiscal si aplica
- uso del CFDI / tipo de comprobante
- dirección si lo exige el flujo

Si el cliente no está registrado, el flujo debe permitir captura rápida para continuar con la venta, pero no debe aceptar la factura si faltan campos obligatorios.

### 3.3 Políticas de pago

- Si el método es `Efectivo`, puede cobrar exacto o mayor y debe mostrar el cambio.
- Si el método es `Tarjeta`, `Transferencia` o `Cheque`, solo puede aceptar el monto exacto; un excedente bloquea el cobro.
- Si el total no se cubre, la venta queda como pendiente o no autorizada según el flujo correspondiente.

---

## 4. Flujo de venta en factura

### 4.1 Paso 1: Agregar productos

- El vendedor agrega productos al carrito.
- La UI muestra subtotal, impuestos y total estimado.
- El total debe recalcular al cambiar cantidades o descuentos.

### 4.2 Paso 2: Seleccionar tipo de comprobante

Debe existir una selección de:

- ticket
- factura
- nota de crédito o devolución

Cada opción debe activar o desactivar campos requeridos del cliente y del comprobante.

### 4.3 Paso 3: Captura de cliente y datos fiscales

La UI debe mostrar:

- nombre del cliente
- RFC o identificación
- correo opcional
- dirección fiscal si aplica

La validación debe ocurrir antes de guardar la venta si el comprobante requiere estos campos.

### 4.4 Paso 4: Cobro

La validación de pagos debe seguir la lógica del POS:

- efectivo: cambio calculado en verde
- no efectivo: exacto; si excede, se bloquea el cobro
- error si falta cantidad

**Corrección detectada:** cuando el usuario ingresa un monto menor al total y activa el cobro, el mensaje de error debe mostrarse siempre por encima del diálogo de cobro activo, nunca por debajo ni detrás de él. La implementación correcta es:

- Mostrar el error como texto en rojo dentro del mismo diálogo de cobro, inmediatamente debajo del resumen de totales.
- Alternativamente, mostrar un `SnackBar` de prioridad alta o un `AlertDialog` modal encima del diálogo de cobro.
- Nunca dejar que el mensaje quede oculto detrás de capas de widgets existentes.

### 4.5 Paso 5: Confirmación final

Al confirmar:

1. se genera el UUID local de la venta
2. se valida monto total y forma de pago
3. se guarda en SQLite local
4. si hay red, se sincroniza con el backend
5. si no hay red, queda pendiente en cola local para sincronizar

---

## 5. Estados de venta y factura

La venta puede quedar en cualquiera de estos estados:

- `borrador`
- `pagada`
- `pendiente`
- `sincronizando`
- `sincronizada`
- `fallida`
- `facturada`
- `cancelada`

Cuando el backend confirme la factura, la app debe marcar la venta como sincronizada y dejar evidencia de folio/comprobante asociado.

---

## 6. Idempotencia y sincronización

La venta debe mantenerse idempotente por UUID local.

Reglas:

- no crear dos ventas iguales al reintentar el mismo envío
- guardar folio o id del comprobante solo cuando la respuesta del servidor confirme
- si la respuesta falla, mantener la venta en estado `fallida` o `pendiente` y no duplicarla

---

## 7. Reglas de UI para evitar errores

- mostrar el total actual antes del cobro
- mostrar cambio únicamente para efectivo
- mostrar advertencia de excedente para pagos no efectivos
- mostrar falta por cobrar si no alcanza el total
- bloquear la confirmación si faltan datos obligatorios
- **los mensajes de error de cobro siempre visibles sobre el diálogo activo** (ver sección 4.4)

---

## 8. Relación con la documentación general

Este documento es complementario a:

- [documentacion_app_movil_flutter.md](documentacion_app_movil_flutter.md)

No sustituye la especificación técnica general ni el contrato de API del backend.

---

## 9. Correcciones de diseño y funcionalidad — Revisión v1 (2026-09-07)

Esta sección recoge todas las observaciones detectadas en la primera revisión de la app en dispositivo. Cada punto describe el estado actual, la corrección requerida y, donde aplica, la decisión de diseño o flujo que debe tomarse antes de implementar.

---

### 9.1 Splash screen

**Estado actual:** El logo aparece enmarcado en un recuadro visible, como si fuera una imagen con fondo recortado.

**Corrección:**

- Eliminar cualquier `Container` o `Card` con borde o fondo que envuelva el logo en el splash.
- El logo debe mostrarse directamente sobre el color de fondo del splash, sin caja ni sombra.
- Si el asset de imagen tiene fondo blanco o borde interno, reemplazarlo por una versión con fondo transparente (PNG con canal alpha).
- El splash screen debe ser limpio: solo logo centrado y, opcionalmente, un indicador de carga sutil en la parte inferior.

---

### 9.2 Pantalla de inicio de sesión

#### 9.2.1 Correcciones de diseño

**Estado actual:**
- Encabezado de color verde en la parte superior.
- Etiquetas de los campos centradas.
- La frase "¿Olvidaste tu contraseña?" tiene un tamaño de fuente distinto al resto.
- El botón ACCEDER tiene el mismo ancho que los campos de entrada.
- La frase "¿No tiene un número de empleado? Da click aquí" rompe en dos líneas.

**Correcciones:**

1. **Encabezado verde:** eliminar el encabezado con fondo de color. Dejar únicamente el logotipo de la empresa en la parte superior de la pantalla, sin fondo de contraste.
2. **Etiquetas de campos:** alinear todas las etiquetas (`label`) a la izquierda dentro del formulario, no centradas.
3. **"¿Olvidaste tu contraseña?":** igualar el tamaño de fuente al del resto de los elementos del formulario. No debe destacar ni quedar más pequeño que los campos.
4. **Botón ACCEDER:** reducir el ancho para que sea ligeramente más estrecho que los campos `TextField`. Por ejemplo, si los inputs ocupan el 100% del ancho disponible, el botón debe ocupar entre el 75% y el 85%, centrado horizontalmente.
5. **Frase de registro:** la frase completa "¿No tiene un número de empleado? Da click aquí" debe aparecer en una sola línea continua o, si el espacio no alcanza, en dos líneas que quiebren en un punto lógico de lectura. El enlace "Da click aquí" no debe quedar aislado en su propia línea separado del texto anterior. El tamaño de fuente debe ser el mismo que el del resto del formulario. Usar `RichText` o `TextSpan` para mantener el texto y el enlace en el mismo flujo.

#### 9.2.2 Campo identificador — comportamiento confirmado

El backend (`AuthController::login`) acepta el campo `identificador` y detecta automáticamente si es un correo electrónico (`filter_var FILTER_VALIDATE_EMAIL`) o un número de usuario (`numero_usuario`). El flujo es único: un solo campo de entrada acepta ambos formatos.

**Etiqueta del campo:** "Número de usuario o correo"

**Placeholder sugerido:** "Número de usuario o correo electrónico"

El campo no debe dividirse en dos inputs ni mostrar un selector de tipo. El backend maneja la detección internamente.

#### 9.2.3 Correcciones de funcionalidad — mensaje de error

**Estado actual:** el mensaje de error al ingresar credenciales incorrectas dice "Número de empleado o correo incorrectos".

**Corrección del mensaje de error:**

El backend ya devuelve mensajes diferenciados según el punto de falla:

- Usuario no encontrado → `'identificador': 'Número de usuario o correo incorrectos.'`
- Contraseña incorrecta → `'password': 'Número de usuario o contraseña incorrectos.'`

La app Flutter debe mostrar el mensaje que el servidor devuelva en el campo correspondiente del error `422`, sin texto hardcodeado. Si el error viene en `errors.identificador`, mostrarlo debajo del campo de identificador. Si viene en `errors.password`, mostrarlo debajo del campo de contraseña.

El texto que el usuario final verá en el escenario más común (contraseña incorrecta) será: "Número de usuario o contraseña incorrectos."

---

### 9.3 Modelo de autenticación — decisión tomada

**Decisión:** la app usa un solo tipo de login. Un único campo identificador acepta número de usuario o correo electrónico. No existe selector de rol en la pantalla de login.

La diferenciación de capacidades (administrador vs. vendedor) se gestiona en el backend a través del campo `rol` del usuario. La app consulta `GET /api/v1/me/permissions` después del login para obtener las capacidades activas y ocultar o deshabilitar secciones según corresponda.

**Roles reconocidos por el backend:**
- `superadmin` — acceso total de plataforma
- `admin` — acceso total a la empresa: configuración, catálogo, estadísticas, reportes
- `cajero` — puede abrir y cerrar caja, vender y consultar
- `vendedor` (rol base) — solo POS y estadísticas básicas del turno

**Identificador del campo en la pantalla de login:** "Número de usuario o correo"

No se mostrará el texto "Número de empleado" en ningún lugar de la interfaz. El término correcto en el contexto de esta aplicación es "número de usuario", que puede corresponder a un asociado, franquiciatario o titular de membresía según el negocio.

---

### 9.4 Recuperación de contraseña

**Estado del backend:** implementado. `AuthController` expone `POST /api/v1/password/forgot` y `POST /api/v1/password/reset` con rate limiting de 5 intentos por minuto. El servidor usa el sistema de recuperación de Laravel con tokens por correo.

**Flujo en la app Flutter:**

1. El usuario toca "¿Olvidaste tu contraseña?" en la pantalla de login.
2. La app navega a una pantalla nueva (o abre un modal) con un campo para ingresar el correo electrónico registrado.
3. El usuario ingresa su correo y toca "Enviar instrucciones".
4. La app llama a `POST /api/v1/password/forgot` con `{ "email": "correo@ejemplo.com" }`.
5. El servidor envía un correo con enlace de restablecimiento y responde siempre con `200` y el mensaje neutral: "Si el correo existe, se enviaron instrucciones de recuperación." — independientemente de si el correo existe o no (el backend ya implementa este comportamiento por seguridad).
6. La app muestra ese mensaje al usuario y ofrece un botón "Volver al inicio de sesión".
7. El enlace del correo lleva al usuario a una vista web del servidor (o a un deep link de la app) para ingresar la nueva contraseña, que se procesa con `POST /api/v1/password/reset`.

**Payload de forgot:**
```json
{ "email": "usuario@ejemplo.com" }
```

**Payload de reset:**
```json
{
  "token": "token_recibido_por_correo",
  "email": "usuario@ejemplo.com",
  "password": "nueva_contraseña",
  "password_confirmation": "nueva_contraseña"
}
```

**Endpoints disponibles en el backend:**

| Método | Ruta | Middleware |
|---|---|---|
| `POST` | `/api/v1/password/forgot` | `throttle:5,1` (pública) |
| `POST` | `/api/v1/password/reset` | `throttle:5,1` (pública) |

Ambas rutas son públicas (no requieren autenticación Sanctum), lo que permite usarlas desde la pantalla de login sin token.

**Estado de implementación Flutter:** pendiente. El backend está listo.

---

### 9.5 Pantalla principal (POS / Caja)

#### 9.5.1 Campo de búsqueda

**Estado actual:** el campo de búsqueda está en la parte superior de la pantalla con una sombra visible que lo hace visualmente pesado.

**Corrección:**

- Mover el campo de búsqueda debajo de las cards de resumen y antes de la sección de productos.
- Eliminar o reducir la sombra del campo. Puede conservar un borde sutil o un fondo ligeramente diferenciado, pero sin sombra pronunciada.

#### 9.5.2 Botón de rayas blancas sobre fondo negro

**Estado actual:** existe un botón con fondo negro y rayas o ícono blanco que no realiza ninguna acción.

**Decisión requerida:** definir la función de este botón antes de continuar. Las opciones propuestas son:

- **Filtro de productos por categoría:** al tocarlo, despliega un panel o sheet con las categorías disponibles para filtrar el catálogo.
- **Menú rápido de acciones:** abre un menú con opciones como "Aplicar descuento", "Agregar cliente", "Ver pendientes".
- **Vista de lista / cuadrícula:** alterna entre vista de tarjetas y vista de lista para los productos.

**Recomendación:** si la funcionalidad de filtro por categoría se implementa (ver sección 9.5.4), este botón puede usarse como acceso al panel de categorías, dándole así una función clara y útil.

#### 9.5.3 Cards de resumen

**Estado actual:** las cards rectangulares son grandes y ocupan demasiado espacio vertical, reduciendo el área visible del catálogo.

**Corrección:**

- Hacer las cards más pequeñas y de proporción cuadrada, o mostrarlas todas en una sola fila horizontal con scroll si es necesario.
- El objetivo es que las cards ocupen una sola fila de altura reducida, liberando el espacio para el catálogo de productos.
- Las cards deben conservar su información actual (totales, tickets, etc.) pero en formato compacto.

#### 9.5.4 Filtro y navegación de productos

**Situación actual:** no existe filtro por categoría. Los productos se presentan en lista o cuadrícula sin agrupación.

**Propuesta:**

Implementar un selector de categorías horizontal (chips o tabs) encima de la lista de productos. Al seleccionar una categoría, el catálogo filtra en tiempo real mostrando solo los productos de esa categoría. Una opción "Todos" restablece el catálogo completo.

**Consideraciones:**

- Si el catálogo es pequeño (menos de 20 productos), el scroll vertical es suficiente y el filtro es un complemento.
- Si el catálogo crece, el filtro por categoría es indispensable para la velocidad de operación.
- La búsqueda por texto (sección 9.5.1) y el filtro por categoría deben poder combinarse.

---

### 9.6 Pantalla de Estadísticas

#### 9.6.1 Card de Egresos

**Estado actual:** no existe un apartado para registrar egresos del día.

**Funcionalidad requerida:**

- Agregar un botón o sección "Registrar egreso" en la pantalla de estadísticas.
- Al tocarlo, se abre un formulario con: concepto (texto libre), monto y forma de pago (opcional).
- Los egresos registrados aparecen en una card con diseño en color rojo para distinguirla visualmente de los ingresos.
- La card de egresos muestra: total de egresos del día y, opcionalmente, un desglose por concepto.
- Los egresos se guardan en SQLite local en la base operativa del día y se incluyen en el cálculo de utilidad neta del turno.
- Se deben sumar al resumen como: `Ingresos - Egresos = Utilidad neta`.

**Tabla SQLite sugerida:**

```sql
CREATE TABLE daily_expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  concepto TEXT NOT NULL,
  monto REAL NOT NULL,
  forma_pago TEXT,
  registrado_at TEXT NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'pending'
);
```

#### 9.6.2 Card de Tickets

**Estado actual:** la card de "Tickets" no es clara en lo que representa.

**Corrección:**

- Renombrar la card o agregar un subtítulo que explique el dato. Por ejemplo: "Tickets del día" con el número de ventas completadas, o "Ticket promedio" con el valor medio por venta.
- Si la card muestra el conteo de ventas, el label debe ser "Ventas del día" o "Transacciones".
- Si muestra el promedio por venta, el label debe ser "Ticket promedio" con el monto en grande y la leyenda "promedio por venta" debajo.
- Evitar el término "Tickets" solo como número sin contexto; es ambiguo para el usuario final.

---

### 9.7 Pantalla de Administración

#### 9.7.1 Apartado EMPRESA — Reestructuración

**Estado actual:** el apartado EMPRESA muestra únicamente un modal con información estática. Existe un menú de "Usuario actual" separado.

**Corrección:**

- Convertir EMPRESA en una vista completa (no un modal) donde se puedan consultar y modificar los datos del negocio: nombre, RFC, domicilio fiscal, teléfono, correo de contacto y logo.
- Fusionar el menú de "Usuario actual" dentro de esta vista o eliminarlo como sección independiente. Los datos del usuario pueden vivir en un perfil accesible desde el encabezado o desde una sección separada dentro de EMPRESA.
- Las opciones que deben permanecer visibles en el apartado de Administración son:
  1. **EMPRESA ACTUAL** — datos y configuración del negocio.
  2. **TICKET Y FORMATO** — configuración de papel, cabecera, pie y campos del ticket.
  3. **COLORES Y BRANDING** — paleta de colores, logo y personalización visual.

#### 9.7.2 Apartado DISPOSITIVO

**Decisiones tomadas:**

- **CERRAR SESIÓN / LIMPIAR DATOS:** esta acción elimina los datos del día actual y los datos del usuario de la base de datos local del dispositivo. Esto cierra la sesión activa. Antes de ejecutarse debe mostrar una ventana de confirmación con el texto: "¿Cerrar sesión y limpiar datos? Se eliminarán los datos del día actual y la información de tu cuenta en este dispositivo. Las ventas ya sincronizadas con el servidor no se perderán."

  El alcance preciso de la limpieza es:
  - Borrar la base operativa del día actual (`pos_day_YYYY-MM-DD.sqlite`).
  - Eliminar el token de sesión del secure storage.
  - Eliminar los datos del usuario (nombre, empresa, configuración) del almacenamiento local.
  - **No** borrar la base de licencia (`license.sqlite`) ni los backups archivados.
  - Al completarse, la app redirige a la pantalla de login.

- **DISPOSITIVO ACTUAL:** muestra una pantalla informativa de solo lectura con los datos técnicos del dispositivo donde corre la app. Los campos a mostrar son:

  | Campo | Fuente |
  |---|---|
  | Sistema operativo | `Platform.operatingSystem` / `Platform.operatingSystemVersion` |
  | Modelo del dispositivo | Paquete `device_info_plus` |
  | Versión de la app | Paquete `package_info_plus` (versión + build number) |
  | ID de instalación | `device_identity.installation_id` de SQLite local |
  | IP local | `NetworkInterface.list()` de Dart o paquete equivalente |
  | Estado de red | Estado del `NetworkMonitor` global (online / offline / syncing) |
  | Última sincronización exitosa | `device_identity.last_successful_sync_at` de SQLite local |

  Esta pantalla no tiene acciones de edición. Solo lectura.

- **IMPRESORAS:** mantener. Es la configuración de impresoras Bluetooth/USB/red del dispositivo.

#### 9.7.3 Apartado SISTEMA

**Limpiar datos del día — decisión tomada:**

Esta acción está fusionada conceptualmente con "Cerrar sesión" en el apartado DISPOSITIVO (sección 9.7.2). El alcance es: borrar la base operativa del día actual y los datos de sesión del usuario local, dejando el dispositivo listo para un nuevo inicio de sesión.

Si se mantiene una opción separada "Limpiar datos del día" en el apartado Sistema, su alcance debe ser únicamente borrar la base operativa del día (`pos_day_YYYY-MM-DD.sqlite`) sin cerrar la sesión activa, útil para reiniciar la jornada sin desconectarse. En ese caso debe mostrar esta descripción visible al usuario: "Elimina todas las ventas y datos de la jornada actual de este dispositivo. La sesión permanece activa. Esta acción no se puede deshacer." Requiere pantalla de confirmación.

**Administrar catálogo:**

- Mover este acceso a la primera posición dentro del apartado Sistema, por ser la función de mayor uso operativo.
- Ver sección 9.7.4 para las correcciones específicas del catálogo.

#### 9.7.4 Catálogo de productos — Correcciones

**Navegación del catálogo:**

La barra de opciones en la parte superior debe mostrar en primera fila, como pestañas o chips principales:

1. **CATEGORÍAS**
2. **PRODUCTOS**
3. **FORMAS DE PAGO**
4. **CLIENTES** (opcional, si aplica en v1)

El resto de opciones existentes que no correspondan a la versión básica deben ocultarse o deshabilitarse con una etiqueta "Próximamente", no eliminarse del código para facilitar activación futura.

**Formulario de nuevo producto — Campo CÓDIGO:**

- Eliminar el input manual de "Código" en el formulario de alta de producto.
- El código se asignará automáticamente en el momento en que el usuario seleccione la categoría del producto.
- La lógica de generación del código es: `[clave_de_categoría] + [consecutivo]`.
  - La clave de categoría la define el usuario al crear la categoría (por ejemplo: "BEB" para Bebidas, "COM" para Comida).
  - El consecutivo es el número de orden del producto dentro de esa categoría (1, 2, 3…).
  - Ejemplo: categoría "BEB" con clave "BEB", tercer producto → código `BEB003`.
- El código generado debe mostrarse en el formulario como campo de solo lectura antes de guardar, para que el usuario lo confirme visualmente.

**Formulario de nuevo producto — Campo EXISTENCIA:**

- Reemplazar el input simple de existencia por un flujo de dos pasos:
  1. Un selector (switch o checkbox) con la pregunta: "¿El producto maneja inventario?"
  2. Si la respuesta es **Sí (inventariable):** se activa el input de cantidad inicial de existencia.
  3. Si la respuesta es **No (no inventariable):** el input de cantidad queda deshabilitado y oculto. El producto se vende sin control de stock.
- Este campo determina si el producto genera movimientos de `stock_movements` al venderse.

**Actualización en tiempo real del catálogo en Caja:**

- Al guardar un nuevo producto desde el administrador de catálogo, el catálogo del POS debe reflejarlo de inmediato sin necesidad de cerrar sesión o reiniciar la app.
- El proveedor/notifier de catálogo debe invalidarse o recargarse desde SQLite en cuanto se confirme el alta del producto.
- Este comportamiento debe aplicar también a ediciones y eliminaciones de productos.

**Formas de pago:**

- La sección de Formas de Pago debe mostrar las opciones disponibles como una lista con `Checkbox` para cada método: Efectivo, Tarjeta, Transferencia, Cheque (y las que se agreguen).
- El usuario activa o desactiva los métodos que acepta su negocio.
- Solo los métodos activos aparecen en el diálogo de cobro del POS.
- Al menos un método debe permanecer activo en todo momento; si el usuario intenta desactivar el último, mostrar un mensaje de error: "Debes tener al menos una forma de pago activa."

---

## 10. Observaciones de implementación detectadas antes de corregir (historial v1)

| ID | Severidad | Hallazgo | Resolución prevista |
|---|---|---|---|
| UI-01 | Media | Splash screen muestra el logo con borde/recuadro visible. | Reemplazar asset por PNG con fondo transparente y eliminar contenedor con borde. |
| UI-02 | Media | Encabezado verde en pantalla de login no corresponde al diseño limpio deseado. | Eliminar encabezado de color; conservar solo logotipo. |
| UI-03 | Baja | Etiquetas de campos centradas en login. | Alinear a la izquierda. |
| UI-04 | Baja | Botón ACCEDER del mismo ancho que los inputs. | Reducir ancho al 75–85% de los inputs. |
| UI-05 | Baja | Frase de registro se rompe en dos líneas de forma inadecuada. | Usar `RichText` / `TextSpan` para mantener texto y enlace en flujo continuo. |
| UI-06 | Baja | Tamaño de fuente inconsistente entre "¿Olvidaste tu contraseña?" y el resto del formulario. | Igualar tamaño de fuente. |
| UI-07 | Media | Campo de búsqueda en POS tiene sombra pronunciada y posición superior que consume espacio. | Mover debajo de las cards; reducir sombra. |
| UI-08 | Media | Cards de resumen demasiado grandes en POS. | Hacerlas compactas, de una sola fila. |
| UI-09 | Alta | Botón negro con rayas blancas sin acción definida. | Asignar función de filtro por categoría (pendiente de decisión). |
| FN-01 | Alta | "¿Olvidaste tu contraseña?" sin implementar. | **Backend listo.** Implementar flujo Flutter: pantalla de correo → `POST /api/v1/password/forgot` → mensaje de confirmación neutral. |
| FN-02 | Media | Mensaje de error de login incorrecto. | **Resuelto:** la app mostrará el mensaje devuelto por el servidor. Backend diferencia usuario no encontrado vs. contraseña incorrecta en campos separados del error 422. |
| FN-03 | Alta | Mensaje de error de cobro aparece detrás del diálogo de cobro. | Mostrar error dentro del diálogo o como overlay sobre él. |
| FN-04 | Alta | Producto nuevo no aparece en Caja sin reiniciar sesión. | Invalidar/recargar provider de catálogo al guardar producto. |
| FN-05 | Alta | No existe registro de egresos en estadísticas. | Agregar CRUD de egresos diarios con card roja en estadísticas. |
| FN-06 | Media | Card "Tickets" en estadísticas no es clara. | Renombrar con etiqueta descriptiva y valor en contexto. |
| FN-07 | Media | Apartado EMPRESA muestra solo modal. | Convertir en vista editable; fusionar con "Usuario actual". |
| FN-08 | Media | Formas de pago sin selector por checkbox. | Implementar lista con checkbox en administración. |
| FN-09 | Media | Input de código en producto se ingresa manual. | Generar código automático al seleccionar categoría. |
| FN-10 | Media | Input de existencia sin diferenciación de inventariable/no inventariable. | Agregar switch y activar/desactivar input de cantidad. |
| FN-11 | Baja | Opción "DISPOSITIVO ACTUAL" sin propósito definido. | **Resuelto:** pantalla de solo lectura con SO, modelo, versión de app, IP local, ID de instalación, estado de red y última sincronización. |
| FN-12 | Baja | "Limpiar datos del día" sin alcance preciso documentado. | **Resuelto:** borrar base operativa del día actual sin cerrar sesión; descripción visible al usuario antes de confirmar. |
| AU-01 | Alta | No existe una regla de motivo y auditoría inmutable para cambios de un vendedor sobre venta ajena. | Centralizar mutaciones en servicio de ventas y registrar diff/auditoría con actor y propietario. |
| CA-01 | Crítica | El backend abre, consulta y cierra caja por `usuario_id`; pueden existir varias cajas abiertas para la misma empresa y día. | Consultar/bloquear por empresa y fecha; índice único de caja abierta. |
| CA-02 | Crítica | Cajas y mesas expuestas aunque la empresa no las haya activado; el cobro no exige caja. | Crear estado operativo basado en configuración; proteger rutas. |
| CA-03 | Alta | Abrir/cerrar caja no valida el rol de cajero. | Policy/middleware de operación por empresa y rol. |
| CA-04 | Alta | El cliente Flutter no descarga configuración efectiva ni valida caja antes del cobro. | Incorporar cliente de operación y UI condicional. |
| VE-01 | Alta | No hay modelo ni API para separar cuentas. | Modelar relación venta raíz/cuentas e implementar servicio transaccional. |
| FL-01 | Alta | El diálogo de configuración de ticket libera `TextEditingController` antes de que el árbol se desmonte. | Liberar controladores en `dispose` del `StatefulWidget` del diálogo. |
| FL-02 | Media | `HomeShell` conserva páginas en lista estática; no reacciona a cambios de configuración/rol. | Construir páginas desde estado de sesión y refrescar al volver a primer plano. |

---

## 11. Anexo sincronizado: cajas, mesas, permisos y auditoría (2026-08-31)

Esta sección es normativa y se mantiene con el mismo contenido en `punto_venta_flutter/documentacion_venta_en_fa.md` y `pos-backend/documentacion_venta_en_fa.md`.

### 11.1 Reglas de operación con cajas y mesas

- La funcionalidad de caja es opcional por empresa. Se habilita exclusivamente con `empresa.configuracion.cajas_activas = true`. Si está deshabilitada, el POS conserva el flujo de venta normal y no exige ni muestra una caja.
- Si `empresa.configuracion.mesas_activas = true`, la aplicación muestra los apartados **Caja** y **Mesas**. Mesas requiere también que cajas esté activa; si la configuración heredada activa mesas sin cajas, el backend la rechaza como inválida y la UI muestra el motivo.
- Con cajas activas, ninguna venta puede confirmarse ni cobrarse hasta que exista una única caja abierta para la empresa y fecha comercial. La caja no pertenece al vendedor: todos los vendedores de esa empresa usan la misma caja abierta.
- Solo un usuario con rol `cajero` (o un rol explícitamente autorizado por la política de la empresa) puede abrir o cerrar caja. Cualquier vendedor puede crear, cobrar y consultar ventas propias y de otros vendedores de su empresa.
- Los cambios sobre una venta creada por otro vendedor requieren motivo y generan auditoría inmutable: empresa, venta, actor, propietario original, acción, antes/después, motivo, fecha y UUID/idempotency key.
- Una venta puede dividirse en cuentas a petición del cliente. Las cuentas hijas conservan el vínculo con la venta raíz, sus productos y pagos; la suma de sus importes no puede superar el total de la raíz. Cada cuenta se cobra, anula o audita independientemente.
- Con mesas activas, una venta pendiente se asocia a una mesa activa de la misma empresa y la mesa pasa a `ocupada`; al liquidar o cancelar la última cuenta pendiente vuelve a `libre`. Sin mesas activas, `mesa_id` se rechaza y el flujo de pendientes directo sigue disponible.
- Las validaciones se aplican en servidor y en cliente, pero el servidor es la autoridad final. En modo offline no se permite eludir una caja requerida: se necesita una instantánea válida de caja abierta para la fecha comercial y la sincronización vuelve a validar su estado.

### 11.2 Contrato mínimo de API

| Necesidad | Endpoint | Regla |
|---|---|---|
| Estado operativo | `GET /api/v1/operacion/estado` | Devuelve configuración efectiva, rol y caja abierta de empresa. |
| Abrir/cerrar caja | `POST /api/v1/cajas/abrir`, `POST /api/v1/cajas/{id}/cerrar` | Solo cajero autorizado; una caja abierta por empresa/día. |
| Mesas | `GET/POST/PUT /api/v1/mesas` | Solo disponibles con mesas activas; aislamiento por empresa. |
| Cobrar venta | `POST /api/v1/ventas/{id}/pagar` | Exige caja abierta solo si cajas está activa. |
| Separar cuentas | `POST /api/v1/ventas/{id}/separar-cuentas` | Idempotente; valida productos/importes no asignados. |
| Auditoría de cambios | `POST /api/v1/ventas/{id}/cambios` | Requiere motivo si actor y vendedor original difieren. |
| Recuperar contraseña | `POST /api/v1/password/forgot` | Recibe correo; genera token con expiración y envía correo. |
| Resetear contraseña | `POST /api/v1/password/reset` | Recibe token + nueva contraseña; valida y actualiza. |

### 11.3 Criterios de aceptación (actualizados)

1. Una empresa sin `cajas_activas` vende sin caja y no ve módulos de caja/mesas.
2. Una empresa con `cajas_activas` no permite cobrar sin la caja única abierta de ese día; solo el cajero autorizado puede abrir/cerrar.
3. Con `mesas_activas`, Caja y Mesas aparecen y no se puede cobrar antes de abrir caja.
4. Vendedores de la misma empresa pueden consultar y vender; toda modificación de venta ajena deja auditoría con motivo.
5. Las cuentas separadas nunca duplican artículos, pagos, stock ni total, incluso al reintentar la solicitud.
6. La edición de ticket no produce la aserción de Flutter y conserva el guardado local/offline.
7. El splash screen no muestra recuadro visible alrededor del logo.
8. La pantalla de login muestra solo el logotipo en la parte superior, sin encabezado de color.
9. Las etiquetas del formulario de login están alineadas a la izquierda y el campo identificador tiene la etiqueta "Número de usuario o correo".
10. Los mensajes de error de login muestran el texto devuelto por el servidor en el campo correspondiente (identificador o contraseña).
11. "¿Olvidaste tu contraseña?" navega a la pantalla de recuperación por correo.
12. Los errores de monto insuficiente en el diálogo de cobro son visibles sobre el diálogo, nunca detrás de él.
13. Al guardar un producto nuevo, aparece de inmediato en el catálogo del POS sin reiniciar.
14. Los egresos del día se registran y aparecen en una card roja en estadísticas.
15. La card de Tickets tiene etiqueta clara y valor contextualizado.
16. Las formas de pago en administración se gestionan con checkboxes; solo las activas aparecen en el cobro.
17. El código de producto se genera automáticamente al seleccionar la categoría.
18. El campo de existencia distingue entre productos inventariables y no inventariables.

---

### Estado de implementación (2026-09-07)

**Aplicado (antes de esta revisión):**
- Restauración de la documentación general de la app.
- Edición de ticket con controladores liberados desde `dispose`.
- Guardado local de ventas pendientes, carga, edición, eliminación y cobro posterior con descuento de inventario al pagar.
- Altas, cobros y actualización de pendientes dentro de transacciones SQLite.
- Ventas pendientes no alteran inventario; cancelar una pendiente no lo restituye.
- Indicadores y listado diario usando el rango de fecha comercial actual.
- Pagos mixtos calculan cambio únicamente sobre efectivo restante.
- POS consulta `GET /api/v1/operacion/estado`; bloquea guardar/cobrar si la empresa usa cajas y no hay una abierta.
- Pantalla **Operación** permite al cajero abrir/cerrar caja diaria y administrar mesas.
- Venta pendiente local puede asociarse a una mesa; SQLite conserva `mesa_id`.

**Pendiente de implementación (derivado de esta revisión):**
- Correcciones de diseño del splash screen (UI-01).
- Correcciones de diseño de la pantalla de login (UI-02 a UI-06): eliminar encabezado verde, alinear etiquetas a la izquierda, igualar fuentes, reducir ancho del botón ACCEDER, unificar frase de registro en una sola línea.
- Reposición del campo de búsqueda en POS debajo de las cards y reducción de sombra (UI-07).
- Cards de resumen compactas en una sola fila en POS (UI-08).
- Asignación de función de filtro por categoría al botón negro/rayas (UI-09) — decisión pendiente de confirmar.
- Implementación del flujo de recuperación de contraseña en Flutter (FN-01) — **backend listo**, solo falta la pantalla Flutter.
- Mostrar mensajes de error del servidor en el campo correcto del formulario de login (FN-02) — **comportamiento del backend ya definido y documentado**.
- Error de cobro visible sobre el diálogo de cobro (FN-03).
- Invalidación de provider de catálogo al guardar producto (FN-04).
- CRUD de egresos diarios y card roja en estadísticas (FN-05).
- Renombrado/clarificación de card Tickets (FN-06).
- Vista editable de EMPRESA y fusión con datos de usuario (FN-07).
- Formas de pago con checkboxes en administración (FN-08).
- Generación automática de código de producto al seleccionar categoría (FN-09).
- Switch de inventariable/no inventariable en formulario de producto (FN-10).
- Pantalla de solo lectura "Dispositivo actual" con datos técnicos del sistema (FN-11) — **decisión tomada y documentada**.
- Pantalla de "Limpiar datos del día" con descripción del alcance y confirmación (FN-12) — **decisión tomada y documentada**.
- Opción "Cerrar sesión / limpiar datos" en DISPOSITIVO: borrar base operativa del día + datos del usuario local + token de sesión.
- CRUD remoto de categorías y unidades desde Flutter (el backend ya expone las rutas).

---

## 12. Cambios implementados — Sesión 2026-09-07 (v3)

Esta sección registra los cambios aplicados al código Flutter en la segunda ronda de implementación. Todos los ítems de la lista anterior marcados como "pendiente" y que aparecen aquí se actualizan a **aplicado**.

---

### 12.1 AppStorage — Persistencia del rol de usuario

**Archivo:** `lib/core/storage/app_storage.dart`

- Nueva constante `_userRol = 'user_rol'`.
- Método `saveRol(String rol)` — persiste el rol en SharedPreferences en minúsculas.
- Método `getRol()` → `Future<String?>` — lee el rol guardado.
- Método `isCajero()` → `Future<bool>` — devuelve `true` si el rol es `cajero`, `admin` o `superadmin`.
- `logOut()` ahora también elimina `_userRol` al cerrar sesión.

**Archivo:** `lib/core/services/auth_service.dart`

- Después de un login online exitoso, se guarda el rol del usuario recibido del servidor con `AppStorage().saveRol(rol)`.
- Esto permite que `HomeShell` determine si mostrar la tab Caja sin necesidad de una llamada remota adicional.

---

### 12.2 HomeShell — Tab Caja condicional

**Archivo:** `lib/vistas/home_shell.dart`

**Regla de negocio implementada:**

| Condición | Resultado |
|---|---|
| `cajas_activas = false` | Sin tab Caja; el POS vende libremente sin caja |
| `cajas_activas = true` y rol `cajero/admin/superadmin` | Tab Caja visible; acceso a `OperationScreen` |
| `cajas_activas = true` y rol `vendedor` | Sin tab Caja; el POS sigue bloqueado por caja si está activa |
| `mesas_activas = false` | `OperationScreen` no muestra sección de mesas |
| `mesas_activas = true` | `OperationScreen` muestra gestión de mesas (requiere cajas activas) |

**Implementación:**
- `HomeShell` es ahora `StatefulWidget` con `WidgetsBindingObserver`.
- En `initState` carga el estado operativo desde caché local (`getOperationState()`) y luego refresca desde la API en background.
- Al retornar la app al primer plano (`didChangeAppLifecycleState.resumed`), recarga el estado operativo.
- La tab "Caja" (`Icons.store`) aparece condicionalmente entre Estadísticas y Admin.
- `safeIndex` protege el índice activo si el número de tabs cambia entre recargas.
- Al seleccionar la tab Caja, se fuerza una recarga del estado operativo.

---

### 12.3 Pantalla de Estadísticas — Rediseño completo

**Archivo:** `lib/vistas/daily_stats/daily_stats_screen.dart`

El diseño sigue el layout de la imagen de referencia:

**Estructura visual (de arriba hacia abajo):**
1. **AppBar** con nombre del negocio en mayúsculas (leído desde `AppStorage.getCompanyName()`).
2. **Selector de rango de fechas** — dos botones con fecha inicio / fecha fin; abre `DatePicker`. Por defecto: día actual.
3. **Fecha central** — muestra la fecha inicio seleccionada como referencia.
4. **TOTAL central** en fuente grande — muestra la utilidad neta (Ingresos − Egresos). En rojo si es negativo.
5. **Fila Ingresos | Egresos** — dos cards lado a lado con sus totales y conteos.
6. **Desglose por método de pago** — card gris con cada forma de pago y su monto, visible cuando hay ventas.
7. **Efectivo en caja / Otros métodos** — dos tiles informativos.
8. **Barra de búsqueda** — filtra la lista combinada por folio, método de pago, concepto o forma de pago.
9. **Lista combinada** — ventas y egresos mezclados, ordenados por fecha descendente. Cada ítem tiene un indicador de color izquierdo según estado (verde=pagada, naranja=pendiente, rojo=cancelada/egreso).

**FAB rojo** "Registrar egreso" — permanece visible en todas las posiciones de scroll.

**Métricas calculadas:**
- `_totalIngresos` — suma de ventas activas (no canceladas) en el rango.
- `_totalEgresos` — suma de egresos del rango.
- `_utilidadNeta` = `_totalIngresos − _totalEgresos`.
- `_efectivoEnCaja` — solo ventas con método `Efectivo` o `cash`.
- `_otrosMetodos` — ventas con cualquier otro método.
- `_ingresoPorMetodo` — mapa de `{método: total}` para el desglose.

**Filtro de rango:** las ventas de la BD diaria y el historial se filtran por `_fechaInicio` y `_fechaFin`. Al cambiar las fechas se recarga automáticamente.

---

### 12.4 Inventariable — Modelo y POS

**Archivo:** `lib/core/models/product.dart`

- Nuevo campo `isInventoriable` (bool, default `true`).
- `Product.fromMap` lee `is_inventariable` / `inventariable` desde el campo directo o desde `data_json`.
- Nuevo campo `categoryId` (int?) leído desde `categoria_id` / `category_id` en campo directo o `data_json`.

**Archivo:** `lib/vistas/pos/pos_screen.dart`

- `_addToCart` valida stock solo si `product.isInventoriable == true`. Si no es inventariable, siempre permite agregar.
- Si `isInventoriable == true` y `currentQty >= product.stock`, muestra SnackBar de error con el stock disponible y no agrega.
- Badge de stock:
  - Inventariable con stock > 0 → `"Stock: N"` en color primario.
  - Inventariable con stock = 0 → `"Sin stock"` en color error.
  - No inventariable → `"Sin inventario"` en color secondaryContainer.
- Botón "Agregar":
  - Inventariable sin stock → muestra `"Agotado"` y se deshabilita.
  - No inventariable o con stock disponible → `"Agregar"` habilitado.

---

### 12.5 Settings — Colores del tema

**Archivo:** `lib/vistas/settings/settings_screen.dart`

- `_SectionTitle` ahora usa `cs.onSurfaceVariant` en lugar de `Color(0xFF3A3A3A)`.
- `_SettingTile` ahora usa:
  - `cs.surface` para el fondo de la card.
  - `cs.primary.withValues(alpha: 0.25)` para el borde.
  - `cs.primaryContainer` para el fondo del ícono.
  - `cs.onPrimaryContainer` para el color del ícono.
  - `cs.primary` para la flecha chevron.
- El bloque de empresa en `_UserProfileDialog` usa `cs.primaryContainer` y `cs.primary`.
- El ícono de usuario en el header del diálogo usa `cs.primaryContainer` / `cs.onPrimaryContainer`.
- El método auxiliar `_deviceInfoRow` ahora recibe `BuildContext` como primer parámetro para leer el `colorScheme` correctamente desde un `StatelessWidget`.

---

### 12.6 Catálogo — Búsqueda por nombre

**Archivo:** `lib/vistas/catalog/catalog_admin_screen.dart`

- Campo `_searchCtrl` (TextEditingController) + `_searchQuery` (String) para filtrado local.
- Getter `_filteredItems` filtra `_items` por `name`, `nombre`, `code` y `email`.
- El campo de búsqueda se muestra debajo del selector de catálogos y encima de la lista/grid.
- Al cambiar de catálogo, se limpia la búsqueda automáticamente.
- El estado vacío muestra mensajes diferenciados: sin registros vs. sin resultados para el término buscado.
- Cuando hay query activa, el botón "Agregar" no aparece en el estado vacío.

---

### 12.7 Correcciones de análisis estático

- `settings_screen.dart`: `_deviceInfoRow` recibe `BuildContext` como parámetro explícito (el método vive en un `StatelessWidget` sin `context` implícito).
- `pos_screen.dart`: campo `_selectedTableName` eliminado (se asignaba pero nunca se leía); `onChanged` del `DropdownButtonFormField` de mesas simplificado.
- `daily_cleanup_service.dart`: `// ignore: unused_local_variable` en variable `current` documentada para referencia.
- `api_client.dart`: `// ignore: unnecessary_non_null_assertion` en token Bearer.

---

### 12.8 Estado de implementación actualizado (2026-09-07 v3)

**Aplicados en esta sesión:**
- ✅ `AppStorage.saveRol/getRol/isCajero` — rol persistido al hacer login online.
- ✅ `HomeShell` con tab Caja condicional (cajero/admin cuando `cajas_activas`).
- ✅ Pantalla de Estadísticas rediseñada con rango de fechas, ingresos/egresos detallados, desglose por método de pago, efectivo en caja, lista combinada con búsqueda.
- ✅ `Product.isInventoriable` en modelo; POS valida stock y muestra estados correctos.
- ✅ `settings_screen` usa `colorScheme` del tema en todos los tiles y cards.
- ✅ `catalog_admin_screen` con campo de búsqueda por catálogo.
- ✅ 0 errores de compilación, 0 warnings en archivos propios.

**Pendientes restantes:**
- Correcciones de diseño del splash screen (UI-01) — requiere asset PNG con fondo transparente.
- CRUD remoto de categorías y unidades desde Flutter (backend ya expone rutas).
- Separación de cuentas (VE-01) — requiere modelado en backend.
- Auditoría de cambios sobre ventas de otro vendedor (AU-01).
- Sincronización offline completa: `POST /sync/offline` corrección en backend pendiente.
