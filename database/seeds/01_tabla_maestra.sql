-- =============================================================================
-- SEED: tabla_maestra
-- 56 catálogos · 318 filas
-- Estructura: Descripcion=nombre catálogo, Num1=id local (lo que guardan las otras tablas),
--             String1=texto visible al usuario, String2=código/símbolo/extra, String3=dato adicional
-- Ejecutar contra: total_weight_stg (y replicar a preprod/prod)
-- =============================================================================

USE total_weight_stg;

INSERT INTO tabla_maestra
    (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES

-- ── 1  MONEDA ────────────────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=símbolo · String3=código ISO
(1, 1, 'MONEDA', 1, NULL, NULL, 'Sol Peruano',      'S/',    'PEN'),
(1, 1, 'MONEDA', 2, NULL, NULL, 'Dólar Americano',  '$',     'USD'),
(1, 1, 'MONEDA', 3, NULL, NULL, 'Peso Colombiano',  'COP$',  'COP'),

-- ── 2  AREA ──────────────────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=código
(1, 2, 'AREA', 1, NULL, NULL, 'Comercial',         'COMERCIAL',        NULL),
(1, 2, 'AREA', 2, NULL, NULL, 'Operaciones',       'OPERACIONES',      NULL),
(1, 2, 'AREA', 3, NULL, NULL, 'SSOMA',             'SSOMA',            NULL),
(1, 2, 'AREA', 4, NULL, NULL, 'Servicio Técnico',  'SERVICIO_TECNICO', NULL),
(1, 2, 'AREA', 5, NULL, NULL, 'Metrología',        'METROLOGIA',       NULL),
(1, 2, 'AREA', 6, NULL, NULL, 'Facturación',       'FACTURACION',      NULL),
(1, 2, 'AREA', 7, NULL, NULL, 'Administración',    'ADMIN',            NULL),

-- ── 3  TIPO_SERVICIO ──────────────────────────────────────────────────────────
-- Num1=id · Num2=requiere_metrologia · String1=nombre · String2=código
(1, 3, 'TIPO_SERVICIO', 1, 0, NULL, 'Mantenimiento Preventivo', 'MANTENIMIENTO_PREV', NULL),
(1, 3, 'TIPO_SERVICIO', 2, 0, NULL, 'Mantenimiento Correctivo', 'MANTENIMIENTO_CORR', NULL),
(1, 3, 'TIPO_SERVICIO', 3, 1, NULL, 'Calibración',              'CALIBRACION',        NULL),
(1, 3, 'TIPO_SERVICIO', 4, 1, NULL, 'Verificación Metrológica', 'VERIFICACION',       NULL),
(1, 3, 'TIPO_SERVICIO', 5, 0, NULL, 'Reparación',               'REPARACION',         NULL),
(1, 3, 'TIPO_SERVICIO', 6, 0, NULL, 'Instalación',              'INSTALACION',        NULL),
(1, 3, 'TIPO_SERVICIO', 7, 0, NULL, 'Servicio en Taller',       'TALLER',             NULL),
(1, 3, 'TIPO_SERVICIO', 8, 0, NULL, 'Atención por Garantía',    'GARANTIA',           NULL),

-- ── 4  TIPO_EQUIPO ────────────────────────────────────────────────────────────
(1, 4, 'TIPO_EQUIPO', 1, NULL, NULL, 'Balanza Industrial',           'BALANZA_INDUSTRIAL',  NULL),
(1, 4, 'TIPO_EQUIPO', 2, NULL, NULL, 'Báscula',                      'BASCULA',             NULL),
(1, 4, 'TIPO_EQUIPO', 3, NULL, NULL, 'Celda de Carga',               'CELDA_CARGA',         NULL),
(1, 4, 'TIPO_EQUIPO', 4, NULL, NULL, 'Balanza de Laboratorio',       'BALANZA_LABORATORIO', NULL),
(1, 4, 'TIPO_EQUIPO', 5, NULL, NULL, 'Patrón de Masa',               'PATRON_MASA',         NULL),
(1, 4, 'TIPO_EQUIPO', 6, NULL, NULL, 'Indicador / Panel de control', 'INDICADOR',           NULL),
(1, 4, 'TIPO_EQUIPO', 7, NULL, NULL, 'Báscula Camionera',            'BASCULA_CAMIONERA',   NULL),
(1, 4, 'TIPO_EQUIPO', 8, NULL, NULL, 'Balanza Colgante',             'BALANZA_COLGANTE',    NULL),

-- ── 5  MARCA_EQUIPO ───────────────────────────────────────────────────────────
(1, 5, 'MARCA_EQUIPO', 1, NULL, NULL, 'Mettler Toledo',     'METTLER',   NULL),
(1, 5, 'MARCA_EQUIPO', 2, NULL, NULL, 'Ohaus',              'OHAUS',     NULL),
(1, 5, 'MARCA_EQUIPO', 3, NULL, NULL, 'Sartorius',          'SARTORIUS', NULL),
(1, 5, 'MARCA_EQUIPO', 4, NULL, NULL, 'Avery Weigh-Tronix', 'AVERY',     NULL),
(1, 5, 'MARCA_EQUIPO', 5, NULL, NULL, 'Fairbanks',          'FAIRBANKS', NULL),
(1, 5, 'MARCA_EQUIPO', 6, NULL, NULL, 'Toledo',             'TOLEDO',    NULL),
(1, 5, 'MARCA_EQUIPO', 7, NULL, NULL, 'Flintec',            'FLINTEC',   NULL),
(1, 5, 'MARCA_EQUIPO', 8, NULL, NULL, 'Otras marcas',       'OTRAS',     NULL),

-- ── 6  ORIGEN_REQUERIMIENTO ───────────────────────────────────────────────────
(1, 6, 'ORIGEN_REQUERIMIENTO', 1, NULL, NULL, 'Correo electrónico',      'EMAIL',     NULL),
(1, 6, 'ORIGEN_REQUERIMIENTO', 2, NULL, NULL, 'Llamada telefónica',      'TELEFONO',  NULL),
(1, 6, 'ORIGEN_REQUERIMIENTO', 3, NULL, NULL, 'Visita presencial',       'VISITA',    NULL),
(1, 6, 'ORIGEN_REQUERIMIENTO', 4, NULL, NULL, 'Portal Extranet cliente', 'EXTRANET',  NULL),
(1, 6, 'ORIGEN_REQUERIMIENTO', 5, NULL, NULL, 'WhatsApp',                'WHATSAPP',  NULL),
(1, 6, 'ORIGEN_REQUERIMIENTO', 6, NULL, NULL, 'Referido',                'REFERIDO',  NULL),
(1, 6, 'ORIGEN_REQUERIMIENTO', 7, NULL, NULL, 'Contrato marco vigente',  'CONTRATO',  NULL),

-- ── 7  PRIORIDAD ──────────────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=color HEX · String3=código
(1, 7, 'PRIORIDAD', 1, NULL, NULL, 'Baja',    '#28a745', 'BAJA'),
(1, 7, 'PRIORIDAD', 2, NULL, NULL, 'Media',   '#ffc107', 'MEDIA'),
(1, 7, 'PRIORIDAD', 3, NULL, NULL, 'Alta',    '#fd7e14', 'ALTA'),
(1, 7, 'PRIORIDAD', 4, NULL, NULL, 'Crítica', '#dc3545', 'CRITICA'),

-- ── 8  MOTIVO_DESCUENTO ───────────────────────────────────────────────────────
(1, 8, 'MOTIVO_DESCUENTO', 1, NULL, NULL, 'Descuento por volumen',            'VOLUMEN',          NULL),
(1, 8, 'MOTIVO_DESCUENTO', 2, NULL, NULL, 'Cliente frecuente / fidelización', 'CLIENTE_FRECUENTE',NULL),
(1, 8, 'MOTIVO_DESCUENTO', 3, NULL, NULL, 'Negociación comercial',            'NEGOCIACION',      NULL),
(1, 8, 'MOTIVO_DESCUENTO', 4, NULL, NULL, 'Campaña o promoción',              'CAMPANIA',         NULL),
(1, 8, 'MOTIVO_DESCUENTO', 5, NULL, NULL, 'Descuento por contrato marco',     'CONTRATO_MARCO',   NULL),
(1, 8, 'MOTIVO_DESCUENTO', 6, NULL, NULL, 'Otro motivo',                      'OTRO',             NULL),

-- ── 9  MOTIVO_ANULACION ───────────────────────────────────────────────────────
(1, 9, 'MOTIVO_ANULACION', 1, NULL, NULL, 'El cliente lo solicitó',         'CLIENTE_SOLICITO', NULL),
(1, 9, 'MOTIVO_ANULACION', 2, NULL, NULL, 'Registro duplicado',             'DUPLICADO',        NULL),
(1, 9, 'MOTIVO_ANULACION', 3, NULL, NULL, 'Error al registrar',             'ERROR_REGISTRO',   NULL),
(1, 9, 'MOTIVO_ANULACION', 4, NULL, NULL, 'Sin respuesta del cliente',      'SIN_RESPUESTA',    NULL),
(1, 9, 'MOTIVO_ANULACION', 5, NULL, NULL, 'Fuera del alcance del servicio', 'FUERA_ALCANCE',    NULL),
(1, 9, 'MOTIVO_ANULACION', 6, NULL, NULL, 'Otro motivo',                    'OTRO',             NULL),

-- ── 10 MOTIVO_RECHAZO ─────────────────────────────────────────────────────────
(1, 10, 'MOTIVO_RECHAZO', 1, NULL, NULL, 'Precio no competitivo',       'PRECIO',               NULL),
(1, 10, 'MOTIVO_RECHAZO', 2, NULL, NULL, 'Plazo de entrega',            'PLAZO',                NULL),
(1, 10, 'MOTIVO_RECHAZO', 3, NULL, NULL, 'Adjudicado a competencia',    'COMPETENCIA',          NULL),
(1, 10, 'MOTIVO_RECHAZO', 4, NULL, NULL, 'Sin presupuesto aprobado',    'SIN_PRESUPUESTO',      NULL),
(1, 10, 'MOTIVO_RECHAZO', 5, NULL, NULL, 'Postergado sin fecha',        'POSTERGADO',           NULL),
(1, 10, 'MOTIVO_RECHAZO', 6, NULL, NULL, 'Cambio en el requerimiento',  'CAMBIO_REQUERIMIENTO', NULL),
(1, 10, 'MOTIVO_RECHAZO', 7, NULL, NULL, 'Otro motivo',                 'OTRO',                 NULL),

-- ── 11 MOTIVO_NUEVA_VERSION ───────────────────────────────────────────────────
(1, 11, 'MOTIVO_NUEVA_VERSION', 1, NULL, NULL, 'Cambio de alcance del servicio',      'CAMBIO_ALCANCE',     NULL),
(1, 11, 'MOTIVO_NUEVA_VERSION', 2, NULL, NULL, 'Corrección de precios',               'ERROR_PRECIO',       NULL),
(1, 11, 'MOTIVO_NUEVA_VERSION', 3, NULL, NULL, 'Cambio en condiciones comerciales',   'CAMBIO_CONDICIONES', NULL),
(1, 11, 'MOTIVO_NUEVA_VERSION', 4, NULL, NULL, 'Solicitud explícita del cliente',     'SOLICITUD_CLIENTE',  NULL),
(1, 11, 'MOTIVO_NUEVA_VERSION', 5, NULL, NULL, 'Propuesta vencida, se renueva',       'VENCIMIENTO',        NULL),
(1, 11, 'MOTIVO_NUEVA_VERSION', 6, NULL, NULL, 'Otro motivo',                         'OTRO',               NULL),

-- ── 12 MOTIVO_CIERRE_SIN_VENTA ────────────────────────────────────────────────
(1, 12, 'MOTIVO_CIERRE_SIN_VENTA', 1, NULL, NULL, 'No se ajustó al precio',        'PRECIO',                NULL),
(1, 12, 'MOTIVO_CIERRE_SIN_VENTA', 2, NULL, NULL, 'Se fue con la competencia',     'COMPETENCIA',           NULL),
(1, 12, 'MOTIVO_CIERRE_SIN_VENTA', 3, NULL, NULL, 'Sin presupuesto',               'SIN_PRESUPUESTO',       NULL),
(1, 12, 'MOTIVO_CIERRE_SIN_VENTA', 4, NULL, NULL, 'Postergado sin nueva fecha',    'POSTERGADO_INDEFINIDO', NULL),
(1, 12, 'MOTIVO_CIERRE_SIN_VENTA', 5, NULL, NULL, 'Cliente dejó de responder',     'CLIENTE_INACTIVO',      NULL),
(1, 12, 'MOTIVO_CIERRE_SIN_VENTA', 6, NULL, NULL, 'Otro motivo',                   'OTRO',                  NULL),

-- ── 13 MOTIVO_REPROGRAMACION ──────────────────────────────────────────────────
(1, 13, 'MOTIVO_REPROGRAMACION', 1, NULL, NULL, 'Emergencia en planta del cliente', 'EMERGENCIA_CLIENTE',  NULL),
(1, 13, 'MOTIVO_REPROGRAMACION', 2, NULL, NULL, 'Sin acceso a planta',              'SIN_ACCESO',          NULL),
(1, 13, 'MOTIVO_REPROGRAMACION', 3, NULL, NULL, 'Técnico no disponible',            'FALTA_TECNICO',       NULL),
(1, 13, 'MOTIVO_REPROGRAMACION', 4, NULL, NULL, 'Condición climática adversa',      'CONDICION_CLIMATICA', NULL),
(1, 13, 'MOTIVO_REPROGRAMACION', 5, NULL, NULL, 'Falta de repuesto o insumo',       'FALTA_REPUESTO',      NULL),
(1, 13, 'MOTIVO_REPROGRAMACION', 6, NULL, NULL, 'Solicitud del cliente',            'SOLICITUD_CLIENTE',   NULL),
(1, 13, 'MOTIVO_REPROGRAMACION', 7, NULL, NULL, 'Otro motivo',                      'OTRO',                NULL),

-- ── 14 MOTIVO_OBSERVACION_OC ──────────────────────────────────────────────────
(1, 14, 'MOTIVO_OBSERVACION_OC', 1, NULL, NULL, 'Razón social no coincide',        'RAZON_SOCIAL',   NULL),
(1, 14, 'MOTIVO_OBSERVACION_OC', 2, NULL, NULL, 'RUC incorrecto o no coincide',    'RUC',            NULL),
(1, 14, 'MOTIVO_OBSERVACION_OC', 3, NULL, NULL, 'Monto no cubre el servicio',      'MONTO',          NULL),
(1, 14, 'MOTIVO_OBSERVACION_OC', 4, NULL, NULL, 'Moneda diferente a la propuesta', 'MONEDA',         NULL),
(1, 14, 'MOTIVO_OBSERVACION_OC', 5, NULL, NULL, 'No indica vigencia',              'SIN_VIGENCIA',   NULL),
(1, 14, 'MOTIVO_OBSERVACION_OC', 6, NULL, NULL, 'Sin firma o sello',               'FIRMA_FALTANTE', NULL),
(1, 14, 'MOTIVO_OBSERVACION_OC', 7, NULL, NULL, 'Otro motivo',                     'OTRO',           NULL),

-- ── 15 MOTIVO_DEMORA_RUTA ─────────────────────────────────────────────────────
(1, 15, 'MOTIVO_DEMORA_RUTA', 1, NULL, NULL, 'Tráfico',                            'TRAFICO',           NULL),
(1, 15, 'MOTIVO_DEMORA_RUTA', 2, NULL, NULL, 'Accidente en ruta',                  'ACCIDENTE_RUTA',    NULL),
(1, 15, 'MOTIVO_DEMORA_RUTA', 3, NULL, NULL, 'Problema mecánico del vehículo',     'PROBLEMA_VEHICULO', NULL),
(1, 15, 'MOTIVO_DEMORA_RUTA', 4, NULL, NULL, 'Acceso denegado en planta',          'ACCESO_DENEGADO',   NULL),
(1, 15, 'MOTIVO_DEMORA_RUTA', 5, NULL, NULL, 'Esperando coordinación del cliente', 'ESPERA_CLIENTE',    NULL),
(1, 15, 'MOTIVO_DEMORA_RUTA', 6, NULL, NULL, 'Condición climática',                'CLIMA',             NULL),
(1, 15, 'MOTIVO_DEMORA_RUTA', 7, NULL, NULL, 'Otro motivo',                        'OTRO',              NULL),

-- ── 16 MOTIVO_BLOQUEO_SSOMA ───────────────────────────────────────────────────
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 1, NULL, NULL, 'SCTR vencido',                    'SCTR_VENCIDO',        NULL),
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 2, NULL, NULL, 'Sin Análisis de Trabajo Seguro',  'SIN_ATS',             NULL),
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 3, NULL, NULL, 'EPP incompleto',                  'EPP_INCOMPLETO',      NULL),
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 4, NULL, NULL, 'Sin inducción de cliente',        'SIN_INDUCCION',       NULL),
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 5, NULL, NULL, 'Certificado médico vencido',      'CERT_MEDICO_VENCIDO', NULL),
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 6, NULL, NULL, 'Sin seguro de vida',              'SIN_SEGURO_VIDA',     NULL),
(1, 16, 'MOTIVO_BLOQUEO_SSOMA', 7, NULL, NULL, 'Otro motivo',                     'OTRO',                NULL),

-- ── 17 MOTIVO_EXCEPCION_EXPEDIENTE ───────────────────────────────────────────
(1, 17, 'MOTIVO_EXCEPCION_EXPEDIENTE', 1, NULL, NULL, 'Sin OC formal (solo correo de autorización)', 'SIN_OC_FORMAL',          NULL),
(1, 17, 'MOTIVO_EXCEPCION_EXPEDIENTE', 2, NULL, NULL, 'Urgencia operativa del cliente',               'URGENCIA_OPERATIVA',     NULL),
(1, 17, 'MOTIVO_EXCEPCION_EXPEDIENTE', 3, NULL, NULL, 'Cliente estratégico aprobado por gerencia',    'CLIENTE_ESTRATEGICO',    NULL),
(1, 17, 'MOTIVO_EXCEPCION_EXPEDIENTE', 4, NULL, NULL, 'Autorización directa de gerencia',             'AUTORIZACION_GERENCIAL', NULL),
(1, 17, 'MOTIVO_EXCEPCION_EXPEDIENTE', 5, NULL, NULL, 'Otro motivo',                                  'OTRO',                   NULL),

-- ── 18 MOTIVO_OVERRIDE_EVIDENCIA ──────────────────────────────────────────────
(1, 18, 'MOTIVO_OVERRIDE_EVIDENCIA', 1, NULL, NULL, 'Falla de cámara del dispositivo',        'FALLA_CAMARA',       NULL),
(1, 18, 'MOTIVO_OVERRIDE_EVIDENCIA', 2, NULL, NULL, 'El cliente restringe fotos en planta',   'RESTRICCION_PLANTA', NULL),
(1, 18, 'MOTIVO_OVERRIDE_EVIDENCIA', 3, NULL, NULL, 'Emergencia operativa',                   'EMERGENCIA',         NULL),
(1, 18, 'MOTIVO_OVERRIDE_EVIDENCIA', 4, NULL, NULL, 'Evidencia ya fue aceptada previamente',  'EVIDENCIA_PREVIA',   NULL),
(1, 18, 'MOTIVO_OVERRIDE_EVIDENCIA', 5, NULL, NULL, 'Otro motivo',                            'OTRO',               NULL),

-- ── 19 CLASE_METROLOGICA ──────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=descripción precisión · String3=código
(1, 19, 'CLASE_METROLOGICA', 1, NULL, NULL, 'Clase I — Especial',     'Alta precisión',  'CLASE_I'),
(1, 19, 'CLASE_METROLOGICA', 2, NULL, NULL, 'Clase II — Fina',        'Buena precisión', 'CLASE_II'),
(1, 19, 'CLASE_METROLOGICA', 3, NULL, NULL, 'Clase III — Media',      'Uso industrial',  'CLASE_III'),
(1, 19, 'CLASE_METROLOGICA', 4, NULL, NULL, 'Clase IIII — Ordinaria', 'Uso básico',      'CLASE_IIII'),

-- ── 20 UNIDAD_MEDIDA ──────────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=símbolo · String3=código
(1, 20, 'UNIDAD_MEDIDA', 1, NULL, NULL, 'Kilogramo',       'kg', 'KG'),
(1, 20, 'UNIDAD_MEDIDA', 2, NULL, NULL, 'Gramo',           'g',  'G'),
(1, 20, 'UNIDAD_MEDIDA', 3, NULL, NULL, 'Miligramo',       'mg', 'MG'),
(1, 20, 'UNIDAD_MEDIDA', 4, NULL, NULL, 'Tonelada métrica','t',  'TON'),
(1, 20, 'UNIDAD_MEDIDA', 5, NULL, NULL, 'Libra',           'lb', 'LB'),
(1, 20, 'UNIDAD_MEDIDA', 6, NULL, NULL, 'Onza',            'oz', 'OZ'),

-- ── 21 TIPO_PRUEBA_METROLOGICA ────────────────────────────────────────────────
(1, 21, 'TIPO_PRUEBA_METROLOGICA', 1, NULL, NULL, 'Prueba de Exactitud',     'EXACTITUD',     NULL),
(1, 21, 'TIPO_PRUEBA_METROLOGICA', 2, NULL, NULL, 'Prueba de Excentricidad', 'EXCENTRICIDAD', NULL),
(1, 21, 'TIPO_PRUEBA_METROLOGICA', 3, NULL, NULL, 'Prueba de Repetibilidad', 'REPETIBILIDAD', NULL),
(1, 21, 'TIPO_PRUEBA_METROLOGICA', 4, NULL, NULL, 'Prueba de Movilidad',     'MOVILIDAD',     NULL),

-- ── 22 RESULTADO_CALIBRACION ──────────────────────────────────────────────────
(1, 22, 'RESULTADO_CALIBRACION', 1, NULL, NULL, 'Conforme',                   'CONFORME',             NULL),
(1, 22, 'RESULTADO_CALIBRACION', 2, NULL, NULL, 'No conforme',                'NO_CONFORME',          NULL),
(1, 22, 'RESULTADO_CALIBRACION', 3, NULL, NULL, 'Requiere ajuste',            'REQUIERE_AJUSTE',      NULL),
(1, 22, 'RESULTADO_CALIBRACION', 4, NULL, NULL, 'Requiere nueva calibración', 'REQUIERE_NUEVA_CALIB', NULL),

-- ── 23 ORGANISMO_NORMA ────────────────────────────────────────────────────────
(1, 23, 'ORGANISMO_NORMA', 1, NULL, NULL, 'INACAL — Instituto Nacional de Calidad (Perú)',         'INACAL', NULL),
(1, 23, 'ORGANISMO_NORMA', 2, NULL, NULL, 'OIML — Organización Internacional de Metrología Legal', 'OIML',   NULL),
(1, 23, 'ORGANISMO_NORMA', 3, NULL, NULL, 'ISO — Organización Internacional de Normalización',     'ISO',    NULL),
(1, 23, 'ORGANISMO_NORMA', 4, NULL, NULL, 'ASTM International',                                    'ASTM',   NULL),
(1, 23, 'ORGANISMO_NORMA', 5, NULL, NULL, 'Otro organismo',                                        'OTRO',   NULL),

-- ── 24 TIPO_FORMATO_CONDICION ─────────────────────────────────────────────────
(1, 24, 'TIPO_FORMATO_CONDICION', 1, NULL, NULL, 'Título de sección', 'TITULO',     NULL),
(1, 24, 'TIPO_FORMATO_CONDICION', 2, NULL, NULL, 'Párrafo de texto',  'PARRAFO',    NULL),
(1, 24, 'TIPO_FORMATO_CONDICION', 3, NULL, NULL, 'Ítem de lista',     'VINETA',     NULL),
(1, 24, 'TIPO_FORMATO_CONDICION', 4, NULL, NULL, 'Nota legal',        'NOTA_LEGAL', NULL),

-- ── 25 CONCEPTO_GASTO ─────────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=tipo · String3=código
(1, 25, 'CONCEPTO_GASTO', 1, NULL, NULL, 'Movilidad / Transporte',  'viatico',         'MOVILIDAD'),
(1, 25, 'CONCEPTO_GASTO', 2, NULL, NULL, 'Alimentación',            'viatico',         'ALIMENTACION'),
(1, 25, 'CONCEPTO_GASTO', 3, NULL, NULL, 'Alojamiento',             'viatico',         'ALOJAMIENTO'),
(1, 25, 'CONCEPTO_GASTO', 4, NULL, NULL, 'Peaje',                   'gasto_operativo', 'PEAJE'),
(1, 25, 'CONCEPTO_GASTO', 5, NULL, NULL, 'Estacionamiento',         'gasto_operativo', 'ESTACIONAMIENTO'),
(1, 25, 'CONCEPTO_GASTO', 6, NULL, NULL, 'Insumo / Repuesto menor', 'gasto_operativo', 'INSUMO'),
(1, 25, 'CONCEPTO_GASTO', 7, NULL, NULL, 'Combustible',             'gasto_operativo', 'COMBUSTIBLE'),
(1, 25, 'CONCEPTO_GASTO', 8, NULL, NULL, 'Otro concepto',           'gasto_operativo', 'OTRO'),

-- ── 26 CANAL_COMUNICACION ─────────────────────────────────────────────────────
(1, 26, 'CANAL_COMUNICACION', 1, NULL, NULL, 'Correo electrónico',            'CORREO',   NULL),
(1, 26, 'CANAL_COMUNICACION', 2, NULL, NULL, 'WhatsApp',                      'WHATSAPP', NULL),
(1, 26, 'CANAL_COMUNICACION', 3, NULL, NULL, 'Llamada telefónica',            'LLAMADA',  NULL),
(1, 26, 'CANAL_COMUNICACION', 4, NULL, NULL, 'SMS',                           'SMS',      NULL),
(1, 26, 'CANAL_COMUNICACION', 5, NULL, NULL, 'Notificación en la plataforma', 'INAPP',    NULL),
(1, 26, 'CANAL_COMUNICACION', 6, NULL, NULL, 'Portal Extranet',               'EXTRANET', NULL),
(1, 26, 'CANAL_COMUNICACION', 7, NULL, NULL, 'Visita presencial',             'VISITA',   NULL),

-- ── 27 RESULTADO_SEGUIMIENTO ──────────────────────────────────────────────────
(1, 27, 'RESULTADO_SEGUIMIENTO', 1, NULL, NULL, 'Contactado exitosamente',             'CONTACTADO',       NULL),
(1, 27, 'RESULTADO_SEGUIMIENTO', 2, NULL, NULL, 'No contesta',                         'NO_CONTESTA',      NULL),
(1, 27, 'RESULTADO_SEGUIMIENTO', 3, NULL, NULL, 'Enviado a buzón de voz',              'BUZON',            NULL),
(1, 27, 'RESULTADO_SEGUIMIENTO', 4, NULL, NULL, 'Reunión agendada',                    'REUNION_AGENDADA', NULL),
(1, 27, 'RESULTADO_SEGUIMIENTO', 5, NULL, NULL, 'Correo enviado, pendiente respuesta', 'CORREO_ENVIADO',   NULL),
(1, 27, 'RESULTADO_SEGUIMIENTO', 6, NULL, NULL, 'Pendiente de seguimiento',            'PENDIENTE',        NULL),

-- ── 28 ROL_EXTRANET ───────────────────────────────────────────────────────────
(1, 28, 'ROL_EXTRANET', 1, NULL, NULL, 'Administrador de cuenta',          'ADMIN_CUENTA', NULL),
(1, 28, 'ROL_EXTRANET', 2, NULL, NULL, 'Compras',                          'COMPRAS',      NULL),
(1, 28, 'ROL_EXTRANET', 3, NULL, NULL, 'Personal de planta / operaciones', 'PLANTA',       NULL),

-- ── 29 TIPO_EVENTO_CAMPO ──────────────────────────────────────────────────────
(1, 29, 'TIPO_EVENTO_CAMPO', 1,  NULL, NULL, 'Salida desde base',              'SALIDA_BASE',    NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 2,  NULL, NULL, 'En ruta al cliente',             'EN_RUTA',        NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 3,  NULL, NULL, 'Llegada a planta',               'LLEGADA',        NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 4,  NULL, NULL, 'Inicio de trabajo',              'INICIO_TRABAJO', NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 5,  NULL, NULL, 'Pausa',                          'PAUSA',          NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 6,  NULL, NULL, 'Reanudación de trabajo',         'REANUDA',        NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 7,  NULL, NULL, 'Hard stop — bloqueo de sistema', 'HARD_STOP',      NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 8,  NULL, NULL, 'Cierre del servicio',            'CIERRE',         NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 9,  NULL, NULL, 'Registro de demora',             'DEMORA',         NULL),
(1, 29, 'TIPO_EVENTO_CAMPO', 10, NULL, NULL, 'Incidencia operativa',           'INCIDENCIA',     NULL),

-- ── 30 TIPO_EVIDENCIA ─────────────────────────────────────────────────────────
(1, 30, 'TIPO_EVIDENCIA', 1, NULL, NULL, 'Foto antes del servicio',  'ANTES',        NULL),
(1, 30, 'TIPO_EVIDENCIA', 2, NULL, NULL, 'Foto durante el servicio', 'DURANTE',      NULL),
(1, 30, 'TIPO_EVIDENCIA', 3, NULL, NULL, 'Foto después del servicio','DESPUES',      NULL),
(1, 30, 'TIPO_EVIDENCIA', 4, NULL, NULL, 'Falla o daño identificado','FALLA',        NULL),
(1, 30, 'TIPO_EVIDENCIA', 5, NULL, NULL, 'Verificación de resultado','VERIFICACION', NULL),
(1, 30, 'TIPO_EVIDENCIA', 6, NULL, NULL, 'Captura de firma digital', 'FIRMA',        NULL),
(1, 30, 'TIPO_EVIDENCIA', 7, NULL, NULL, 'Microvideo de encendido',  'MICROVIDEO',   NULL),

-- ── 31 TIPO_INTERVENCION_EQUIPO ───────────────────────────────────────────────
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 1, NULL, NULL, 'Calibración',              'CALIBRACION',        NULL),
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 2, NULL, NULL, 'Mantenimiento preventivo', 'MANTENIMIENTO_PREV', NULL),
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 3, NULL, NULL, 'Mantenimiento correctivo', 'MANTENIMIENTO_CORR', NULL),
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 4, NULL, NULL, 'Reparación',               'REPARACION',         NULL),
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 5, NULL, NULL, 'Verificación',             'VERIFICACION',       NULL),
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 6, NULL, NULL, 'Instalación',              'INSTALACION',        NULL),
(1, 31, 'TIPO_INTERVENCION_EQUIPO', 7, NULL, NULL, 'Solo diagnóstico',         'DIAGNOSTICO',        NULL),

-- ── 32 SECTOR_CLIENTE ─────────────────────────────────────────────────────────
(1, 32, 'SECTOR_CLIENTE', 1, NULL, NULL, 'Industria alimentaria',    'ALIMENTOS',    NULL),
(1, 32, 'SECTOR_CLIENTE', 2, NULL, NULL, 'Minería y metalurgia',     'MINERIA',      NULL),
(1, 32, 'SECTOR_CLIENTE', 3, NULL, NULL, 'Laboratorio',              'LABORATORIO',  NULL),
(1, 32, 'SECTOR_CLIENTE', 4, NULL, NULL, 'Farmacéutico',             'FARMACEUTICO', NULL),
(1, 32, 'SECTOR_CLIENTE', 5, NULL, NULL, 'Logística y distribución', 'LOGISTICA',    NULL),
(1, 32, 'SECTOR_CLIENTE', 6, NULL, NULL, 'Retail y comercio',        'RETAIL',       NULL),
(1, 32, 'SECTOR_CLIENTE', 7, NULL, NULL, 'Industria pesquera',       'PESQUERO',     NULL),
(1, 32, 'SECTOR_CLIENTE', 8, NULL, NULL, 'Industria química',        'QUIMICO',      NULL),
(1, 32, 'SECTOR_CLIENTE', 9, NULL, NULL, 'Otro sector',              'OTRO',         NULL),

-- ── 33 TIPO_INCIDENCIA_OPERATIVA ──────────────────────────────────────────────
(1, 33, 'TIPO_INCIDENCIA_OPERATIVA', 1, NULL, NULL, 'Accidente de trabajo',              'ACCIDENTE',         NULL),
(1, 33, 'TIPO_INCIDENCIA_OPERATIVA', 2, NULL, NULL, 'Falla en equipo de TW',             'FALLA_EQUIPO_TW',   NULL),
(1, 33, 'TIPO_INCIDENCIA_OPERATIVA', 3, NULL, NULL, 'Acceso denegado en planta',         'ACCESO_DENEGADO',   NULL),
(1, 33, 'TIPO_INCIDENCIA_OPERATIVA', 4, NULL, NULL, 'Emergencia en planta del cliente',  'EMERGENCIA_PLANTA', NULL),
(1, 33, 'TIPO_INCIDENCIA_OPERATIVA', 5, NULL, NULL, 'Conflicto con personal del cliente','CONFLICTO_CLIENTE', NULL),
(1, 33, 'TIPO_INCIDENCIA_OPERATIVA', 6, NULL, NULL, 'Otro tipo',                         'OTRO',              NULL),

-- ── 34 NIVEL_ALERTA ───────────────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=color HEX · String3=código
(1, 34, 'NIVEL_ALERTA', 1, NULL, NULL, 'Bajo',     '#28a745', 'BAJO'),
(1, 34, 'NIVEL_ALERTA', 2, NULL, NULL, 'Medio',    '#ffc107', 'MEDIO'),
(1, 34, 'NIVEL_ALERTA', 3, NULL, NULL, 'Alto',     '#fd7e14', 'ALTO'),
(1, 34, 'NIVEL_ALERTA', 4, NULL, NULL, 'Crítico',  '#dc3545', 'CRITICO'),

-- ── 35 VISIBILIDAD_DOCUMENTO ──────────────────────────────────────────────────
(1, 35, 'VISIBILIDAD_DOCUMENTO', 1, NULL, NULL, 'Solo interno TW',               'INTERNO',     NULL),
(1, 35, 'VISIBILIDAD_DOCUMENTO', 2, NULL, NULL, 'Área Comercial',                'COMERCIAL',   NULL),
(1, 35, 'VISIBILIDAD_DOCUMENTO', 3, NULL, NULL, 'Área Operaciones',              'OPERACIONES', NULL),
(1, 35, 'VISIBILIDAD_DOCUMENTO', 4, NULL, NULL, 'Área SSOMA',                    'SSOMA',       NULL),
(1, 35, 'VISIBILIDAD_DOCUMENTO', 5, NULL, NULL, 'Visible al cliente (Extranet)', 'CLIENTE',     NULL),

-- ── 36 TIPO_DOCUMENTO_SSOMA ───────────────────────────────────────────────────
-- Num1=id · Num2=requiere_vencimiento · String1=nombre · String2=código
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 1, 1, NULL, 'SCTR (Salud y Pensión)',              'SCTR',        NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 2, 0, NULL, 'Análisis de Trabajo Seguro',          'ATS',         NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 3, 0, NULL, 'Checklist de EPP',                    'EPP',         NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 4, 1, NULL, 'Certificado médico ocupacional',      'CERT_MEDICO', NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 5, 1, NULL, 'Constancia de inducción del cliente', 'INDUCCION',   NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 6, 1, NULL, 'Seguro de vida',                      'SEGURO_VIDA', NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 7, 0, NULL, 'Permiso de trabajo en altura',        'PETAR',       NULL),
(1, 36, 'TIPO_DOCUMENTO_SSOMA', 8, 0, NULL, 'Otro documento',                      'OTRO',        NULL),

-- ── 37 ESTADO_GARANTIA_EQUIPO ─────────────────────────────────────────────────
-- Num1=id · String1=nombre · String2=color HEX · String3=código
(1, 37, 'ESTADO_GARANTIA_EQUIPO', 1, NULL, NULL, 'Vigente',               '#28a745', 'VIGENTE'),
(1, 37, 'ESTADO_GARANTIA_EQUIPO', 2, NULL, NULL, 'Por vencer (< 30 días)','#ffc107', 'POR_VENCER'),
(1, 37, 'ESTADO_GARANTIA_EQUIPO', 3, NULL, NULL, 'Vencida',               '#dc3545', 'VENCIDA'),
(1, 37, 'ESTADO_GARANTIA_EQUIPO', 4, NULL, NULL, 'Sin garantía',          '#6c757d', 'SIN_GARANTIA'),

-- ── 38 ESTADO_PATRON ──────────────────────────────────────────────────────────
(1, 38, 'ESTADO_PATRON', 1, NULL, NULL, 'Vigente',               'VIGENTE',         NULL),
(1, 38, 'ESTADO_PATRON', 2, NULL, NULL, 'Por vencer (< 30 días)','POR_VENCER',      NULL),
(1, 38, 'ESTADO_PATRON', 3, NULL, NULL, 'Vencido',               'VENCIDO',         NULL),
(1, 38, 'ESTADO_PATRON', 4, NULL, NULL, 'En calibración externa','EN_CALIBRACION',  NULL),
(1, 38, 'ESTADO_PATRON', 5, NULL, NULL, 'Dado de baja',          'BAJA',            NULL),

-- ── 39 CONDICION_PAGO ─────────────────────────────────────────────────────────
(1, 39, 'CONDICION_PAGO', 1, NULL, NULL, 'Contado',                           'CONTADO',     NULL),
(1, 39, 'CONDICION_PAGO', 2, NULL, NULL, 'Crédito 15 días',                   'CREDITO_15',  NULL),
(1, 39, 'CONDICION_PAGO', 3, NULL, NULL, 'Crédito 30 días',                   'CREDITO_30',  NULL),
(1, 39, 'CONDICION_PAGO', 4, NULL, NULL, 'Crédito 45 días',                   'CREDITO_45',  NULL),
(1, 39, 'CONDICION_PAGO', 5, NULL, NULL, 'Crédito 60 días',                   'CREDITO_60',  NULL),
(1, 39, 'CONDICION_PAGO', 6, NULL, NULL, '50% adelanto + 50% contra entrega', 'ADELANTO_50', NULL),
(1, 39, 'CONDICION_PAGO', 7, NULL, NULL, 'Otro acuerdo',                      'OTRO',        NULL),

-- ── 40 CANAL_ORIGEN_TICKET ────────────────────────────────────────────────────
(1, 40, 'CANAL_ORIGEN_TICKET', 1, NULL, NULL, 'Asistente IA del portal', 'HELPDESK_IA', NULL),
(1, 40, 'CANAL_ORIGEN_TICKET', 2, NULL, NULL, 'Portal Extranet',         'EXTRANET',    NULL),
(1, 40, 'CANAL_ORIGEN_TICKET', 3, NULL, NULL, 'Correo electrónico',      'CORREO',      NULL),
(1, 40, 'CANAL_ORIGEN_TICKET', 4, NULL, NULL, 'Llamada telefónica',      'LLAMADA',     NULL),
(1, 40, 'CANAL_ORIGEN_TICKET', 5, NULL, NULL, 'WhatsApp',                'WHATSAPP',    NULL),

-- ── 41 TIPO_JORNADA ───────────────────────────────────────────────────────────
(1, 41, 'TIPO_JORNADA', 1, NULL, NULL, 'Jornada normal de trabajo',           'NORMAL',       NULL),
(1, 41, 'TIPO_JORNADA', 2, NULL, NULL, 'Jornada de guardia / turno especial', 'GUARDIA',      NULL),
(1, 41, 'TIPO_JORNADA', 3, NULL, NULL, 'Jornada en comisión de servicios',    'COMISION',     NULL),
(1, 41, 'TIPO_JORNADA', 4, NULL, NULL, 'Jornada de capacitación interna',     'CAPACITACION', NULL),
(1, 41, 'TIPO_JORNADA', 5, NULL, NULL, 'Horas extra fuera de jornada normal', 'HORAS_EXTRA',  NULL),

-- ── 42 TIPO_FORMULARIO_CAMPO ──────────────────────────────────────────────────
(1, 42, 'TIPO_FORMULARIO_CAMPO', 1, NULL, NULL, 'Registro de evento GPS / hito de campo', 'EVENTO_CAMPO',       NULL),
(1, 42, 'TIPO_FORMULARIO_CAMPO', 2, NULL, NULL, 'Datos de medición metrológica',          'MEDICION',           NULL),
(1, 42, 'TIPO_FORMULARIO_CAMPO', 3, NULL, NULL, 'Registro de evidencia fotográfica',      'EVIDENCIA',          NULL),
(1, 42, 'TIPO_FORMULARIO_CAMPO', 4, NULL, NULL, 'Registro de demora en ruta',             'DEMORA',             NULL),
(1, 42, 'TIPO_FORMULARIO_CAMPO', 5, NULL, NULL, 'Condiciones ambientales de calibración', 'VARIABLE_AMBIENTAL', NULL),
(1, 42, 'TIPO_FORMULARIO_CAMPO', 6, NULL, NULL, 'Firma de conformidad del cliente',       'CONFORMIDAD',        NULL),

-- ── 43 CANAL_ACCESO ───────────────────────────────────────────────────────────
(1, 43, 'CANAL_ACCESO', 1, NULL, NULL, 'Back-office web (escritorio)', 'INTRANET', NULL),
(1, 43, 'CANAL_ACCESO', 2, NULL, NULL, 'App móvil de campo',           'MOVIL',    NULL),
(1, 43, 'CANAL_ACCESO', 3, NULL, NULL, 'Portal web del cliente',       'EXTRANET', NULL),

-- ── 44 ESTADO_DOCUMENTO ───────────────────────────────────────────────────────
(1, 44, 'ESTADO_DOCUMENTO', 1, NULL, NULL, 'En elaboración, no publicado',         'BORRADOR',    NULL),
(1, 44, 'ESTADO_DOCUMENTO', 2, NULL, NULL, 'Aprobado y en uso activo',             'VIGENTE',     NULL),
(1, 44, 'ESTADO_DOCUMENTO', 3, NULL, NULL, 'Bajo revisión para nueva versión',     'EN_REVISION', NULL),
(1, 44, 'ESTADO_DOCUMENTO', 4, NULL, NULL, 'Reemplazado por versión más reciente', 'OBSOLETO',    NULL),
(1, 44, 'ESTADO_DOCUMENTO', 5, NULL, NULL, 'Retirado del sistema',                 'ANULADO',     NULL),

-- ── 45 TIPO_EXPORTACION_ERP ───────────────────────────────────────────────────
(1, 45, 'TIPO_EXPORTACION_ERP', 1, NULL, NULL, 'Datos de OS/OM para generar facturas',  'FACTURACION',         NULL),
(1, 45, 'TIPO_EXPORTACION_ERP', 2, NULL, NULL, 'Estado de cobros y cuentas por cobrar', 'COBRANZA',            NULL),
(1, 45, 'TIPO_EXPORTACION_ERP', 3, NULL, NULL, 'Liquidación de haberes y comisiones',   'PERSONAL',            NULL),
(1, 45, 'TIPO_EXPORTACION_ERP', 4, NULL, NULL, 'Gastos y viáticos rendidos',            'VIATICOS',            NULL),
(1, 45, 'TIPO_EXPORTACION_ERP', 5, NULL, NULL, 'Estado de instrumentos patrón',         'INVENTARIO_PATRONES', NULL),

-- ── 46 NORMA_METROLOGICA ──────────────────────────────────────────────────────
-- Num1=id · String1=nombre completo · String2=código · String3=url (NULL por ahora)
(1, 46, 'NORMA_METROLOGICA', 1, NULL, NULL, 'OIML R76 — Instrumentos de pesaje no automáticos', 'OIML-R76',     NULL),
(1, 46, 'NORMA_METROLOGICA', 2, NULL, NULL, 'OIML R111 — Pesas clase E1 a M3',                  'OIML-R111',    NULL),
(1, 46, 'NORMA_METROLOGICA', 3, NULL, NULL, 'ISO 8655 — Instrumentos de medición de volumen',   'ISO-8655',     NULL),
(1, 46, 'NORMA_METROLOGICA', 4, NULL, NULL, 'NTP-OIML R76 — Versión peruana',                   'NTP-OIML-R76', NULL),
(1, 46, 'NORMA_METROLOGICA', 5, NULL, NULL, 'NTP-INDECOPI 019',                                 'INDECOPI-019', NULL),

-- ── 47 METODO_CALIBRACION ─────────────────────────────────────────────────────
-- Num1=id · Num2=id_norma_ref (IdMaestro=46) · String1=nombre · String2=código
(1, 47, 'METODO_CALIBRACION', 1, 1, NULL, 'Calibración gravimétrica',    'CAL-GRAVIM', NULL),
(1, 47, 'METODO_CALIBRACION', 2, 1, NULL, 'Calibración por comparación', 'CAL-COMP',   NULL),
(1, 47, 'METODO_CALIBRACION', 3, 2, NULL, 'Método de sustitución',       'CAL-SUSTIT', NULL),
(1, 47, 'METODO_CALIBRACION', 4, 3, NULL, 'Calibración volumétrica',     'CAL-VOLUM',  NULL),

-- ── 48 REQUISITO_SSOMA ────────────────────────────────────────────────────────
-- Num1=id · Num2=vencimiento_dias · Num3=es_obligatorio · String1=nombre · String2=aplica_rol · String3=bloquea_servicio
(1, 48, 'REQUISITO_SSOMA', 1, 365, 1, 'Seguro Complementario de Trabajo de Riesgo (SCTR)', 'ambos',   '1'),
(1, 48, 'REQUISITO_SSOMA', 2, 365, 1, 'Examen médico ocupacional',                         'ambos',   '1'),
(1, 48, 'REQUISITO_SSOMA', 3, 365, 1, 'Certificado de aptitud para trabajo en altura',     'tecnico', '1'),
(1, 48, 'REQUISITO_SSOMA', 4, 180, 1, 'EPP actualizado (foto)',                            'ambos',   '0'),
(1, 48, 'REQUISITO_SSOMA', 5,   0, 0, 'Inducción SSOMA cliente',                          'ambos',   '0'),

-- ── 49 CONFIG_SLA ─────────────────────────────────────────────────────────────
-- Num1=id · Num2=horas_limite · Num3=horas_alerta · String1=entidad · String2=etapa · String3=aplica_dias_habiles
(1, 49, 'CONFIG_SLA', 1,  24,  4, 'propuesta',      'pendiente_vb',          '1'),
(1, 49, 'CONFIG_SLA', 2,  48,  8, 'orden_compra',   'pendiente_validacion',  '1'),
(1, 49, 'CONFIG_SLA', 3,  72, 24, 'expediente',     'ssoma',                 '1'),
(1, 49, 'CONFIG_SLA', 4,  48, 12, 'informe',        'pendiente_revision',    '1'),
(1, 49, 'CONFIG_SLA', 5, 168, 24, 'orden_servicio', 'programada',            '1'),

-- ── 50 PERMISO ────────────────────────────────────────────────────────────────
-- Num1=id · String1=nombre legible · String2=módulo · String3=código
(1, 50, 'PERMISO', 1, NULL, NULL, 'Crear propuesta comercial',     'comercial',     'propuesta.crear'),
(1, 50, 'PERMISO', 2, NULL, NULL, 'Aprobar propuesta (visto bueno)','comercial',    'propuesta.aprobar'),
(1, 50, 'PERMISO', 3, NULL, NULL, 'Validar orden de compra',       'comercial',     'oc.validar'),
(1, 50, 'PERMISO', 4, NULL, NULL, 'Anular orden de servicio',      'operaciones',   'os.anular'),
(1, 50, 'PERMISO', 5, NULL, NULL, 'Revisar informe técnico',       'operaciones',   'informe.revisar'),
(1, 50, 'PERMISO', 6, NULL, NULL, 'Aprobar documentos SSOMA',      'ssoma',         'ssoma.aprobar'),
(1, 50, 'PERMISO', 7, NULL, NULL, 'Emitir certificado metrológico','metrologia',    'om.emitir'),
(1, 50, 'PERMISO', 8, NULL, NULL, 'Administrar usuarios',          'administracion','usuario.administrar'),

-- ── 51 TIPO_ITEM_CATALOGO ─────────────────────────────────────────────────────
(1, 51, 'TIPO_ITEM_CATALOGO', 1, NULL, NULL, 'Repuesto o pieza',  'REPUESTO',   NULL),
(1, 51, 'TIPO_ITEM_CATALOGO', 2, NULL, NULL, 'Servicio técnico',  'SERVICIO',   NULL),
(1, 51, 'TIPO_ITEM_CATALOGO', 3, NULL, NULL, 'Mano de obra',      'MANO_OBRA',  NULL),
(1, 51, 'TIPO_ITEM_CATALOGO', 4, NULL, NULL, 'Consumible',        'CONSUMIBLE', NULL),

-- ── 52 TIPO_ITEM_PRESALIDA ────────────────────────────────────────────────────
(1, 52, 'TIPO_ITEM_PRESALIDA', 1, NULL, NULL, 'Repuesto a llevar',            'REPUESTO',  NULL),
(1, 52, 'TIPO_ITEM_PRESALIDA', 2, NULL, NULL, 'Alerta predictiva a resolver', 'ALERTA',    NULL),
(1, 52, 'TIPO_ITEM_PRESALIDA', 3, NULL, NULL, 'Documento requerido',          'DOCUMENTO', NULL),
(1, 52, 'TIPO_ITEM_PRESALIDA', 4, NULL, NULL, 'Otro ítem',                    'OTRO',      NULL),

-- ── 53 TIPO_ALERTA_PREDICTIVA ─────────────────────────────────────────────────
(1, 53, 'TIPO_ALERTA_PREDICTIVA', 1, NULL, NULL, 'Desgaste proyectado por uso acumulado',           'DESGASTE',        NULL),
(1, 53, 'TIPO_ALERTA_PREDICTIVA', 2, NULL, NULL, 'Calibración próxima a vencer',                    'VENCIMIENTO_CAL', NULL),
(1, 53, 'TIPO_ALERTA_PREDICTIVA', 3, NULL, NULL, 'Falla probable detectada por patrón histórico',   'FALLA_PROBABLE',  NULL),
(1, 53, 'TIPO_ALERTA_PREDICTIVA', 4, NULL, NULL, 'Equipo sin servicio en período mayor al esperado','SIN_SERVICIO',    NULL),

-- ── 54 RESOLUCION_ALERTA ──────────────────────────────────────────────────────
(1, 54, 'RESOLUCION_ALERTA', 1, NULL, NULL, 'El técnico atendió la alerta en campo',   'ATENDIDA',   NULL),
(1, 54, 'RESOLUCION_ALERTA', 2, NULL, NULL, 'Descartada — no aplica al caso concreto', 'DESCARTADA', NULL),
(1, 54, 'RESOLUCION_ALERTA', 3, NULL, NULL, 'Queda pendiente para la próxima visita',  'POSTERGADA', NULL),

-- ── 55 TIPO_SEDE ──────────────────────────────────────────────────────────────
(1, 55, 'TIPO_SEDE', 1, NULL, NULL, 'Sede principal / casa matriz',      'PRINCIPAL',   NULL),
(1, 55, 'TIPO_SEDE', 2, NULL, NULL, 'Sucursal comercial',                'SUCURSAL',    NULL),
(1, 55, 'TIPO_SEDE', 3, NULL, NULL, 'Planta de producción / industrial', 'PLANTA',      NULL),
(1, 55, 'TIPO_SEDE', 4, NULL, NULL, 'Almacén o depósito',               'ALMACEN',     NULL),
(1, 55, 'TIPO_SEDE', 5, NULL, NULL, 'Laboratorio',                       'LABORATORIO', NULL),
(1, 55, 'TIPO_SEDE', 6, NULL, NULL, 'Otro tipo de sede',                 'OTRO',        NULL),

-- ── 56 TIPO_DOC_IDENTIDAD ─────────────────────────────────────────────────────
(1, 56, 'TIPO_DOC_IDENTIDAD', 1, NULL, NULL, 'Documento Nacional de Identidad (Perú)', 'DNI',       NULL),
(1, 56, 'TIPO_DOC_IDENTIDAD', 2, NULL, NULL, 'Carnet de Extranjería',                  'CE',        NULL),
(1, 56, 'TIPO_DOC_IDENTIDAD', 3, NULL, NULL, 'Pasaporte',                              'PASAPORTE', NULL),
(1, 56, 'TIPO_DOC_IDENTIDAD', 4, NULL, NULL, 'RUC (persona natural con negocio)',      'RUC',       NULL);
