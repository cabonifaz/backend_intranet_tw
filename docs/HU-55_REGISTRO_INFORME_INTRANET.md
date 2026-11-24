# HU-55 — Registrar el informe de un equipo desde la intranet

Para: frontend de la intranet (Angular). Contrato de la API del backend.

La Asistente de Seguimiento o el Jefe de Operaciones registran, en la intranet, el trabajo que haría el técnico en un equipo cuando la planta no deja usar celular. El flujo es el mismo del móvil
(variables ambientales, evidencias, ensayos, cabecera, correlativo, cierre y generar informe) en rutas aparte.

- El informe queda **a nombre del técnico asignado** a la OS. Se guarda quién lo registró de verdad (`id_registrado_por`, `via = 'intranet'`, `registrado_en`).
- **No se envía GPS ni hora de captura** en ningún cuerpo.
- La IA valida las fotos igual que en el móvil.
- Permiso: acción **`seg_registrar_informe`** en todas las rutas (nivel editar, módulo `operaciones`).
- El frontend **no manda el id del técnico**: el servidor lo toma de la OS.

## Convenciones

Base: `/api/intranet/servicios/{idOs}`. Las rutas de equipo son `.../equipos/{idOsEquipo}/...`. Todas las respuestas llevan el sobre `{ idTipoMensaje, mensaje, datos }`.

| HTTP | Cuándo |
|---|---|
| 200 | `idTipoMensaje = 2`. |
| 400 | `idTipoMensaje = 1`: regla de negocio. Muestra `mensaje` tal cual. |
| 403 | Sin el permiso `seg_registrar_informe`. |
| **409** | **Otra persona tiene el equipo abierto** (`mensaje` dice quién). Deja el formulario en solo lectura. |
| 500 | `idTipoMensaje = 3`: error del sistema (mensaje genérico). |

No uses el texto genérico "No tienes permiso para ver la revisión…" para un 403 de este módulo: muestra el `mensaje` del backend.

## Orden de uso

1. `GET contexto-registro` al abrir la pantalla (solo lee).
2. Si `puedeIniciar`, `POST iniciar-registro` ("Comenzar registro"): marca la llegada y el inicio del equipo y toma el bloqueo.
3. Cargar, en este orden: variables → evidencias → ensayos → cabecera → correlativo. Cada paso se habilita cuando el anterior está `conforme` (`etapas[].estado`).
4. `GET cierre` y `POST informe` (genera el informe y libera el bloqueo).
5. Firma y constancia (a nivel de la OS): solo formato físico o cliente ausente.
6. Al salir sin generar: `POST liberar-registro`.

El bloqueo caduca solo a los **30 minutos sin actividad**; cada guardado lo renueva.

## 1. Lectura

### `GET /equipos/{idOsEquipo}/contexto-registro`
Solo lectura: no marca llegada, no inicia el equipo, no toma el bloqueo. `datos`:

- `contexto`: `idOs`, `numeroOs`, `tipoOrden` (OS/OM), `numeroRq`, `estadoOs`, `cliente`, `ruc`, `planta`, `direccionPlanta`, `idOsEquipo`, `idEquipo`, `equipoNombre`, `numeroEquipo`,
  `numeroSerie`, `codigoCliente`, `codigoTw`, `marca`, `modelo`, `idTecnico`, `tecnico`, `informeFisico`, `estadoEquipo`, `iniciado`, `informeGenerado`, `numeroInforme`, `idInforme`,
  `puedeIniciar`, `motivoNoPuede`, `registroActivo`, `registradorId`, `registradorNombre`, `registroPropio`, `registroUltimaActividad`, `actividadPreviaTecnico`, `otroEquipoAbierto`.
- `etapas[]`: `{ orden, codigo, nombre, estado, detalle }` con `codigo` ∈ variables · fotos · ensayos · cabecera · correlativo y `estado` ∈ conforme · en_curso · pendiente · bloqueado · no_conforme.
- `catalogos`: objeto con listas `{ codigo, nombre, clasificacion, orden }` para `procedencia`, `tipo_equipo`, `forma_plato`, `checklist_os`, `checklist_om`, `severidad`, `estado_equipo`,
  `clasificacion_falla`, `componente_falla` y `motivo_manual`.

Cómo usarlo:
- `registroActivo && !registroPropio` → otra persona (`registradorNombre`) lo tiene: avisa antes de entrar.
- `actividadPreviaTecnico` → el técnico ya cargó datos desde la app: avisa que se estaría mezclando.
- `otroEquipoAbierto` → el técnico tiene otro equipo en ejecución: ofrece `pausar-equipo-abierto`.
- `puedeIniciar = false` → muestra `motivoNoPuede`.

### `GET /equipos/{idOsEquipo}/informe-en-curso`
Lo ya cargado, para retomar si la Asistente cerró la pantalla: `{ trabajo, evidencias, ensayos, cabecera, avisos[] }`. Una parte que aún no se puede leer (por ejemplo, el equipo no está iniciado)
viene `null` y `avisos` dice por qué. Los datos tienen la misma forma que los GET de cada paso.

## 2. Sesión de registro

### `POST /equipos/{idOsEquipo}/iniciar-registro`
Cuerpo:
```json
{ "inicio": "2026-11-24T08:00", "fin": "2026-11-24T11:00", "motivo": "PLANTA_SIN_CELULAR", "comentario": "Opcional, hasta 300" }
```
- `inicio` y `fin` son la **hora de Lima** en que se hizo el trabajo (ISO 8601 sin zona; con `Z` u offset se respeta).
- Reglas: inicio anterior a fin, fin no futuro, duración menor a 7 días, motivo obligatorio (código de `catalogos.motivo_manual`).
- Estados de OS permitidos: programada, reprogramada, en_ruta, en_ejecucion y pausada. No: anulada, borrador, emitida, bloqueada ni finalizada.
- Por equipo: no se permite si ya tiene el informe generado (para corregirlo existe el complementario).
- **Idempotente**: si ya tienes la sesión, la renueva y no duplica nada (`idempotente: true`).
- `datos`: `{ idRegistro, idempotente, estadoOs, estadoEquipo, idTecnico, tiempoAplicadoMin }`.
- Responde **409** si otra persona lo tiene abierto. Responde 400 si el técnico tiene otro equipo en ejecución (usa `pausar-equipo-abierto`).

### `POST /equipos/{idOsEquipo}/pausar-equipo-abierto`
Cuerpo opcional `{ "motivo": "..." }` (hasta 200). Pausa el **otro** equipo que el técnico dejó en ejecución. `datos`: `{ idOs, idOsEquipo, equipo }`. 400 si no hay otro equipo en ejecución.

### `POST /equipos/{idOsEquipo}/liberar-registro`
Sin cuerpo. Libera el bloqueo al salir del asistente. Generar el informe también lo libera.

## 3. Variables, evidencias, ensayos y cabecera

| Paso | Ruta | Cuerpo / notas |
|---|---|---|
| Variables | `PUT /equipos/{eq}/variables-ambientales` | `{ temperatura, humedad, procedencia }`. Temperatura −20 a 60 °C y humedad 0 a 100 %, obligatorias. Procedencia opcional (hasta 100, "N.I" por defecto). Fecha y hora las pone el servidor. Devuelve el trabajo actualizado. |
| Evidencias | `GET /equipos/{eq}/evidencias` | Panel de 9 evidencias (8 si `informeFisico = false`) y adicionales. |
| | `POST /equipos/{eq}/evidencias` | `multipart/form-data`: `codigo`, `pagina` (solo informe, hasta 10), `duracionSeg` (solo encendido, 3 a 5 s), `qrTexto` (solo qr), `archivo` (JPEG, o MP4 para encendido), `cuadro` (JPEG del video). Sin GPS. |
| | `POST /equipos/{eq}/evidencias/{id}/forzar` | `{ "motivo": "3 a 300 caracteres" }`. Acepta una foto rechazada por la IA. Queda como excepción visible para Jefatura y **no cuenta contra el técnico**. Devuelve el panel. |
| | `DELETE /equipos/{eq}/evidencias/adicionales/{id}` | Quita una foto adicional (máximo 20 por equipo). Devuelve el panel. |
| | `GET /equipos/{eq}/evidencias/{id}/archivo?cuadro=true` | Foto o video. **Pide el archivo con `HttpClient` (blob) para enviar el token**; un `<img src>` directo no autentica. |
| Ensayos | `GET` y `PUT /equipos/{eq}/ensayos` | `{ formaPlato, pesaje: [{carga, indicacion}], excentricidad: [{carga, lecturas[]}], motivoErrorCritico, finalizar }`. **Solo se envían carga e indicación**: error, EMP y resultado los calcula el servidor. Hasta 12 cargas de pesaje y 10 de excentricidad (5 posiciones, o 4 si el plato es triangular). Con error crítico solo se finaliza con `motivoErrorCritico` (mínimo 3). |
| Cabecera | `GET` y `PUT /equipos/{eq}/cabecera-informe` | `PUT` parcial: una sección ausente no se toca. `datos.responsableNombre` obligatorio; `detalle`; `recomendaciones` (hasta 20) o `sinRecomendaciones`; `fallas` (hasta 15) o `sinFallas`; `diagnostico.severidadGeneral` y `estadoEquipo` obligatorios; `comentarioPruebas` (hasta 500). El checklist depende solo de OS u OM. |
| | `POST /equipos/{eq}/cabecera-informe/fotos` | `multipart/form-data`, campo `archivo` (JPEG). Devuelve `{ idEvidencia }` para enviarlo en `fotos` de la falla (hasta 5 por falla). |

## 4. Correlativo y certificado (etapa 5)

Sin esta etapa conforme no se puede generar el informe.

- `GET /equipos/{eq}/correlativo`: tipos de certificado, el ticket abierto y el correlativo asignado sin usar.
- `POST /equipos/{eq}/correlativo/solicitar`: `{ idTipoCertificado, observacion }`. Crea el ticket a nombre del **técnico**; Metrología lo asigna aparte.
- `PUT /equipos/{eq}/correlativo/certificado`: `{ numeroCertificado }` con el formato `CC-0000-2026`, el que asignó Metrología.

El cierre es en dos tiempos: tras solicitar, la etapa queda `en_curso` ("esperando el correlativo de Metrología") hasta que Metrología lo asigne. Muéstralo con el número de ticket.

## 5. Cierre y generar el informe

- `GET /equipos/{eq}/cierre` (Hard Stop): `puedeGenerar`, y las 5 etapas con sus `pendientes`. No escribe nada.
- `POST /equipos/{eq}/informe`: genera el informe `NNNN-AAAA` a nombre del técnico, deja el equipo completado y libera el bloqueo. Datos: `{ idInforme, numeroInforme, estadoEquipo, repetida }`.
  Repetir la llamada con el bloqueo ya liberado responde 400 ("primero inicia el registro"): consulta `contexto-registro` para ver `informeGenerado` y `numeroInforme`.

## 6. Firma y constancia (a nivel de la OS)

Solo **formato físico** (foto del papel firmado) y **cliente ausente**. No hay firma por dispositivo: no construyas canvas. Estas rutas exigen el permiso pero no la sesión del equipo, porque se cierra al generar.

| Ruta | Cuerpo |
|---|---|
| `GET /firma-informes` | Informes con sus responsables, plazo de aceptación tácita y avance de firmas. |
| `POST /firma-informes/{clave}/fisico` | `multipart/form-data`: `foto` (JPEG) y `nombre` (3 a 150). `clave` son 32 caracteres (la trae `GET firma-informes`). |
| `POST /firma-informes/{clave}/ausente` | `{ "motivo": "5 a 300 caracteres" }`. |
| `GET /constancia` | Cliente, equipos intervenidos, responsables que faltan firmar. |
| `POST /constancia/fisico` | `multipart/form-data`: `foto` y `nombre`. |
| `POST /constancia/generar` | Sin cuerpo. Exige la firma del cliente; si todo está firmado cierra el servicio. |
| `GET /constancia/archivo?tipo=pdf\|foto` | PDF o foto del formato físico (blob con token). |

## Informes ya registrados

En la intranet verás `via` (`app` o `intranet`) e `idRegistradoPor`. El valor de `origen` en las tablas hijas del informe sigue siendo `tecnico`; no lo uses para distinguir el registro desde intranet.
