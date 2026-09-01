# Documentación de venta en factura (FA)

**Proyecto:** POS móvil Flutter  
**Estado:** Documento complementario del POS y de la coordinación con backend  
**Relación con otros documentos:** complementa a [documentacion_app_movil_flutter.md](documentacion_app_movil_flutter.md), no reemplaza la especificación técnica general ni la API del backend.

## 1. Objetivo

Definir el flujo de venta que puede terminar en factura o comprobante fiscal, manteniendo la operación en modo offline-first y sin romper el flujo de caja del punto de venta.

Este documento complementa la documentación general del POS y del backend. Su propósito es ser un punto de referencia para:

- venta con cliente y datos fiscales
- selección de tipo de comprobante
- validación de montos y pagos
- sincronización de venta y factura en una sola operación
- gestión de errores y reintentos

## 2. Alcance

Este documento cubre:

- venta con cobro directo
- venta con factura / comprobante fiscal
- venta con datos de cliente obligatorios o opcionales según tipo de comprobante
- validación de subtotal, impuestos y total
- captura de pagos y cálculo de cambio
- confirmación local y sincronización posterior

No cubre:

- gestión de proveedores
- inventario de compras
- reportes históricos complejos
- auditoría fiscal externa
- integraciones con terceros no requeridas en la app POS

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

La validación debe ocurrir antes de guardar la venta si el comprobante require estos campos.

### 4.4 Paso 4: Cobro

La validación de pagos debe seguir la lógica del POS:

- efectivo: cambia calculado en verde
- no efectivo: exacto; si excede, se bloquea el cobro
- error si falta cantidad

### 4.5 Paso 5: Confirmación final

Al confirmar:

1. se genera el UUID local de la venta
2. se valida monto total y forma de pago
3. se guarda en SQLite local
4. si hay red, se sincroniza con el backend
5. si no hay red, queda pendiente en cola local para sincronizar

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

## 6. Idempotencia y sincronización

La venta debe mantenerse idempotente por UUID local.

Reglas:

- no crear dos ventas iguales al reintentar el mismo envío
- guardar folio o id del comprobante solo cuando la respuesta del servidor confirme
- si la respuesta falla, mantener la venta en estado `fallida` o `pendiente` y no duplicarla

## 7. Reglas de UI para evitar errores

- mostrar el total actual antes del cobro
- mostrar cambio únicamente para efectivo
- mostrar advertencia de excedente para pagos no efectivos
- mostrar falta por cobrar si no alcanza el total
- bloquear la confirmación si faltan datos obligatorios

## 8. Relación con la documentación general

Este documento es complementario a:

- [documentacion_app_movil_flutter.md](documentacion_app_movil_flutter.md)
- [documentacion_app_movil_flutter.md](../pos-backend/documentacion_app_movil_flutter.md)

No sustituye la especificación técnica general ni el contrato de API del backend. Se usa para mantener un punto de referencia claro del flujo de venta con factura y comprobante fiscal dentro del mismo proyecto.

## Anexo sincronizado: cajas, mesas, permisos y auditoría (2026-08-31)

Esta sección es normativa y se mantiene con el mismo contenido en `punto_venta_flutter/documentacion_venta_en_fa.md` y `pos-backend/documentacion_venta_en_fa.md`.

### 9.1 Reglas nuevas

- La funcionalidad de caja es opcional por empresa. Se habilita exclusivamente con `empresa.configuracion.cajas_activas = true`. Si está deshabilitada, el POS conserva el flujo de venta normal y no exige ni muestra una caja.
- Si `empresa.configuracion.mesas_activas = true`, la aplicación muestra los apartados **Caja** y **Mesas**. Mesas requiere también que cajas esté activa; si la configuración heredada activa mesas sin cajas, el backend la rechaza como inválida y la UI muestra el motivo.
- Con cajas activas, ninguna venta puede confirmarse ni cobrarse hasta que exista una única caja abierta para la empresa y fecha comercial. La caja no pertenece al vendedor: todos los vendedores de esa empresa usan la misma caja abierta.
- Solo un usuario con rol `cajero` (o un rol explícitamente autorizado por la política de la empresa) puede abrir o cerrar caja. Cualquier vendedor puede crear, cobrar y consultar ventas propias y de otros vendedores de su empresa.
- Los cambios sobre una venta creada por otro vendedor requieren motivo y generan auditoría inmutable: empresa, venta, actor, propietario original, acción, antes/después, motivo, fecha y UUID/idempotency key.
- Una venta puede dividirse en cuentas a petición del cliente. Las cuentas hijas conservan el vínculo con la venta raíz, sus productos y pagos; la suma de sus importes no puede superar el total de la raíz. Cada cuenta se cobra, anula o audita independientemente.
- Con mesas activas, una venta pendiente se asocia a una mesa activa de la misma empresa y la mesa pasa a `ocupada`; al liquidar o cancelar la última cuenta pendiente vuelve a `libre`. Sin mesas activas, `mesa_id` se rechaza y el flujo de pendientes directo sigue disponible.
- Las validaciones se aplican en servidor y en cliente, pero el servidor es la autoridad final. En modo offline no se permite eludir una caja requerida: se necesita una instantánea válida de caja abierta para la fecha comercial y la sincronización vuelve a validar su estado.

### 9.2 Contrato mínimo de API

| Necesidad | Endpoint | Regla |
|---|---|---|
| Estado operativo | `GET /api/v1/operacion/estado` | Devuelve configuración efectiva, rol y caja abierta de empresa. |
| Abrir/cerrar caja | `POST /api/v1/cajas/abrir`, `POST /api/v1/cajas/{id}/cerrar` | Solo cajero autorizado; una caja abierta por empresa/día. |
| Mesas | `GET/POST/PUT /api/v1/mesas` | Solo disponibles con mesas activas; aislamiento por empresa. |
| Cobrar venta | `POST /api/v1/ventas/{id}/pagar` | Exige caja abierta solo si cajas está activa. |
| Separar cuentas | `POST /api/v1/ventas/{id}/separar-cuentas` | Idempotente; valida productos/importes no asignados. |
| Auditoría de cambios | `POST /api/v1/ventas/{id}/cambios` | Requiere motivo si actor y vendedor original difieren. |

### 9.3 Observaciones detectadas antes de corregir

| ID | Severidad | Hallazgo y por qué importa | Resolución prevista |
|---|---|---|---|
| CA-01 | Crítica | El backend abre, consulta y cierra caja por `usuario_id`; por ello pueden existir varias cajas abiertas para la misma empresa y día. | Consultar/bloquear por empresa y fecha, añadir índice único de caja abierta y asignar `abierta_por_usuario_id` solo como auditoría. |
| CA-02 | Crítica | Cajas y mesas están expuestas aunque la empresa no las haya activado; el cobro no exige caja. | Crear estado operativo basado en configuración y proteger rutas/servicios; el cobro validará caja únicamente cuando `cajas_activas` sea verdadero. |
| CA-03 | Alta | Abrir/cerrar caja no valida el rol de cajero y los endpoints de mesas tampoco verifican que la funcionalidad esté habilitada. | Policy/middleware de operación por empresa y rol, con respuestas 403/422 claras. |
| CA-04 | Alta | El cliente Flutter no descarga configuración efectiva, no muestra caja/mesas y permite cobrar sin validar caja. | Incorporar cliente de operación, estado de sesión y UI condicional; deshabilitar cobro cuando aplique. |
| VE-01 | Alta | No hay modelo, transacción ni API para separar cuentas; intentar hacerlo en el cliente produciría totales e inventario inconsistentes. | Modelar relación venta raíz/cuentas, asignación de partidas y pagos; implementar servicio transaccional e idempotente. |
| AU-01 | Alta | No existe una regla de motivo y auditoría inmutable para cambios de un vendedor sobre venta ajena. | Centralizar mutaciones en servicio de ventas y registrar diff/auditoría con actor y propietario. |
| FL-01 | Alta | El diálogo de configuración de ticket libera `TextEditingController` inmediatamente después de `showDialog`; durante la animación de salida aún puede haber dependientes de widgets heredados y se dispara `'_dependents.isEmpty'`. | Mantener el estado/controladores dentro de un `StatefulWidget` de diálogo y liberarlos en `dispose`, una vez desmontado el árbol. |
| FL-02 | Media | `HomeShell` conserva páginas en una lista estática; el POS no puede reaccionar con seguridad a cambios de empresa/configuración/rol. | Construir las páginas desde el estado de sesión/operación y refrescar el estado al iniciar y al volver a primer plano. |
| DO-01 | Media | Los dos archivos `documentacion_venta_en_fa.md` tenían alcance y detalle distintos. | Mantener este anexo idéntico en ambos; la documentación general del backend continúa en `documentacion_app_movil_flutter.md`. |

### 9.4 Criterios de aceptación

1. Una empresa sin `cajas_activas` vende sin caja y no ve módulos de caja/mesas.
2. Una empresa con `cajas_activas` no permite cobrar sin la caja única abierta de ese día; solo el cajero autorizado puede abrir/cerrar.
3. Con `mesas_activas`, Caja y Mesas aparecen y no se puede cobrar antes de abrir caja.
4. Vendedores de la misma empresa pueden consultar y vender; toda modificación de venta ajena deja auditoría con motivo.
5. Las cuentas separadas nunca duplican artículos, pagos, stock ni total, incluso al reintentar la solicitud.
6. La edición de ticket no produce la aserción de Flutter y conserva el guardado local/offline.

### Estado de implementación en Flutter (2026-08-31)

- Aplicado: restauración de la documentación general de la app; edición de ticket con controladores liberados desde `dispose`; guardado local de ventas pendientes, carga, edición, eliminación y cobro posterior con descuento de inventario al pagar.
- Aplicado: altas, cobros y actualización de pendientes se ejecutan dentro de transacciones SQLite. Si no hay inventario suficiente, se revierte por completo la operación y no quedan ventas, partidas ni descuentos parciales.
- Aplicado: las ventas pendientes no alteran inventario; cancelar una pendiente tampoco lo restituye. El inventario solo se descuenta al cobrar y se repone al cancelar una venta ya pagada.
- Aplicado: los indicadores y el listado diario usan el rango de la fecha comercial actual, no todo el historial local. El detalle abierto después del cobro corresponde exactamente a la venta recién registrada.
- Aplicado: los pagos mixtos calculan el cambio únicamente sobre el efectivo restante después de acreditar los medios no efectivos. Tarjeta, transferencia y cheque no pueden exceder el total por sí solos.
- Aplicado: el POS consulta y conserva `GET /api/v1/operacion/estado`; si la empresa usa cajas y no existe una abierta, bloquea guardar y cobrar. Si cajas está desactivada, conserva el flujo de venta actual.
- Aplicado: la pantalla **Operación** permite al cajero abrir/cerrar la caja diaria y administrar el catálogo de mesas. El POS vuelve a consultar el estado al regresar de esta pantalla.
- Aplicado: una venta pendiente local puede asociarse a una mesa desde POS. SQLite conserva `mesa_id` y el nombre de mesa, el listado de pendientes lo muestra y Operación indica las pendientes locales por mesa. El `mesa_id` se incluye en el payload de sincronización.
- Pendiente: CRUD remoto de categorías y unidades desde Flutter. El backend ya expone las rutas necesarias, pero la app actual solo tiene CRUD local de productos.
