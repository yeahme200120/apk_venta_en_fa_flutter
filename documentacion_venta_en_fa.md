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
