-- =============================================================================
-- SEED: tabla_maestra
-- 56 catálogos · ~230 filas
-- Ejecutar contra: total_weight_stg (y replicar a preprod/prod)
-- =============================================================================

USE total_weight_stg;

INSERT INTO tabla_maestra
    (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES

-- ── 1  MONEDA ────────────────────────────────────────────────────────────────
(1, 1, 'Sol Peruano',       NULL, NULL, NULL, 'PEN', 'S/',    NULL),
(1, 1, 'Dólar Americano',   NULL, NULL, NULL, 'USD', '$',     NULL),
(1, 1, 'Peso Colombiano',   NULL, NULL, NULL, 'COP', 'COP$',  NULL),

-- ── 2  AREA ──────────────────────────────────────────────────────────────────
(1, 2, 'Comercial',         NULL, NULL, NULL, 'COMERCIAL',       NULL, NULL),
(1, 2, 'Operaciones',       NULL, NULL, NULL, 'OPERACIONES',     NULL, NULL),
(1, 2, 'SSOMA',             NULL, NULL, NULL, 'SSOMA',           NULL, NULL),
(1, 2, 'Servicio Técnico',  NULL, NULL, NULL, 'SERVICIO_TECNICO',NULL, NULL),
(1, 2, 'Metrología',        NULL, NULL, NULL, 'METROLOGIA',      NULL, NULL),
(1, 2, 'Facturación',       NULL, NULL, NULL, 'FACTURACION',     NULL, NULL),
(1, 2, 'Administración',    NULL, NULL, NULL, 'ADMIN',           NULL, NULL),

-- ── 3  TIPO_SERVICIO ──────────────────────────────────────────────────────────
(1, 3, 'Mantenimiento Preventivo',  0, NULL, NULL, 'MANTENIMIENTO_PREV', NULL, NULL),
(1, 3, 'Mantenimiento Correctivo',  0, NULL, NULL, 'MANTENIMIENTO_CORR', NULL, NULL),
(1, 3, 'Calibración',               1, NULL, NULL, 'CALIBRACION',        NULL, NULL),
(1, 3, 'Verificación Metrológica',  1, NULL, NULL, 'VERIFICACION',       NULL, NULL),
(1, 3, 'Reparación',                0, NULL, NULL, 'REPARACION',         NULL, NULL),
(1, 3, 'Instalación',               0, NULL, NULL, 'INSTALACION',        NULL, NULL),
(1, 3, 'Servicio en Taller',        0, NULL, NULL, 'TALLER',             NULL, NULL),
(1, 3, 'Atención por Garantía',     0, NULL, NULL, 'GARANTIA',           NULL, NULL),

-- ── 4  TIPO_EQUIPO ────────────────────────────────────────────────────────────
(1, 4, 'Balanza Industrial',        NULL, NULL, NULL, 'BALANZA_INDUSTRIAL',  NULL, NULL),
(1, 4, 'Báscula',                   NULL, NULL, NULL, 'BASCULA',             NULL, NULL),
(1, 4, 'Celda de Carga',            NULL, NULL, NULL, 'CELDA_CARGA',         NULL, NULL),
(1, 4, 'Balanza de Laboratorio',    NULL, NULL, NULL, 'BALANZA_LABORATORIO', NULL, NULL),
(1, 4, 'Patrón de Masa',            NULL, NULL, NULL, 'PATRON_MASA',         NULL, NULL),
(1, 4, 'Indicador / Panel de control', NULL, NULL, NULL, 'INDICADOR',        NULL, NULL),
(1, 4, 'Báscula Camionera',         NULL, NULL, NULL, 'BASCULA_CAMIONERA',   NULL, NULL),
(1, 4, 'Balanza Colgante',          NULL, NULL, NULL, 'BALANZA_COLGANTE',    NULL, NULL),

-- ── 5  MARCA_EQUIPO ───────────────────────────────────────────────────────────
(1, 5, 'Mettler Toledo',    NULL, NULL, NULL, 'METTLER',   NULL, NULL),
(1, 5, 'Ohaus',             NULL, NULL, NULL, 'OHAUS',     NULL, NULL),
(1, 5, 'Sartorius',         NULL, NULL, NULL, 'SARTORIUS', NULL, NULL),
(1, 5, 'Avery Weigh-Tronix',NULL, NULL, NULL, 'AVERY',     NULL, NULL),
(1, 5, 'Fairbanks',         NULL, NULL, NULL, 'FAIRBANKS', NULL, NULL),
(1, 5, 'Toledo',            NULL, NULL, NULL, 'TOLEDO',    NULL, NULL),
(1, 5, 'Flintec',           NULL, NULL, NULL, 'FLINTEC',   NULL, NULL),
(1, 5, 'Otras marcas',      NULL, NULL, NULL, 'OTRAS',     NULL, NULL),

-- ── 6  ORIGEN_REQUERIMIENTO ───────────────────────────────────────────────────
(1, 6, 'Correo electrónico',          NULL, NULL, NULL, 'EMAIL',     NULL, NULL),
(1, 6, 'Llamada telefónica',          NULL, NULL, NULL, 'TELEFONO',  NULL, NULL),
(1, 6, 'Visita presencial',           NULL, NULL, NULL, 'VISITA',    NULL, NULL),
(1, 6, 'Portal Extranet cliente',     NULL, NULL, NULL, 'EXTRANET',  NULL, NULL),
(1, 6, 'WhatsApp',                    NULL, NULL, NULL, 'WHATSAPP',  NULL, NULL),
(1, 6, 'Referido',                    NULL, NULL, NULL, 'REFERIDO',  NULL, NULL),
(1, 6, 'Contrato marco vigente',      NULL, NULL, NULL, 'CONTRATO',  NULL, NULL),

-- ── 7  PRIORIDAD ──────────────────────────────────────────────────────────────
(1, 7, 'Baja',    NULL, NULL, NULL, 'BAJA',    '#28a745', NULL),
(1, 7, 'Media',   NULL, NULL, NULL, 'MEDIA',   '#ffc107', NULL),
(1, 7, 'Alta',    NULL, NULL, NULL, 'ALTA',    '#fd7e14', NULL),
(1, 7, 'Crítica', NULL, NULL, NULL, 'CRITICA', '#dc3545', NULL),

-- ── 8  MOTIVO_DESCUENTO ───────────────────────────────────────────────────────
(1, 8, 'Descuento por volumen',             NULL, NULL, NULL, 'VOLUMEN',          NULL, NULL),
(1, 8, 'Cliente frecuente / fidelización',  NULL, NULL, NULL, 'CLIENTE_FRECUENTE',NULL, NULL),
(1, 8, 'Negociación comercial',             NULL, NULL, NULL, 'NEGOCIACION',      NULL, NULL),
(1, 8, 'Campaña o promoción',               NULL, NULL, NULL, 'CAMPANIA',         NULL, NULL),
(1, 8, 'Descuento por contrato marco',      NULL, NULL, NULL, 'CONTRATO_MARCO',   NULL, NULL),
(1, 8, 'Otro motivo',                       NULL, NULL, NULL, 'OTRO',             NULL, NULL),

-- ── 9  MOTIVO_ANULACION ───────────────────────────────────────────────────────
(1, 9, 'El cliente lo solicitó',            NULL, NULL, NULL, 'CLIENTE_SOLICITO', NULL, NULL),
(1, 9, 'Registro duplicado',                NULL, NULL, NULL, 'DUPLICADO',        NULL, NULL),
(1, 9, 'Error al registrar',                NULL, NULL, NULL, 'ERROR_REGISTRO',   NULL, NULL),
(1, 9, 'Sin respuesta del cliente',         NULL, NULL, NULL, 'SIN_RESPUESTA',    NULL, NULL),
(1, 9, 'Fuera del alcance del servicio',    NULL, NULL, NULL, 'FUERA_ALCANCE',    NULL, NULL),
(1, 9, 'Otro motivo',                       NULL, NULL, NULL, 'OTRO',             NULL, NULL),

-- ── 10 MOTIVO_RECHAZO ─────────────────────────────────────────────────────────
(1, 10, 'Precio no competitivo',            NULL, NULL, NULL, 'PRECIO',                  NULL, NULL),
(1, 10, 'Plazo de entrega',                 NULL, NULL, NULL, 'PLAZO',                   NULL, NULL),
(1, 10, 'Adjudicado a competencia',         NULL, NULL, NULL, 'COMPETENCIA',             NULL, NULL),
(1, 10, 'Sin presupuesto aprobado',         NULL, NULL, NULL, 'SIN_PRESUPUESTO',         NULL, NULL),
(1, 10, 'Postergado sin fecha',             NULL, NULL, NULL, 'POSTERGADO',              NULL, NULL),
(1, 10, 'Cambio en el requerimiento',       NULL, NULL, NULL, 'CAMBIO_REQUERIMIENTO',    NULL, NULL),
(1, 10, 'Otro motivo',                      NULL, NULL, NULL, 'OTRO',                    NULL, NULL),

-- ── 11 MOTIVO_NUEVA_VERSION ───────────────────────────────────────────────────
(1, 11, 'Cambio de alcance del servicio',           NULL, NULL, NULL, 'CAMBIO_ALCANCE',     NULL, NULL),
(1, 11, 'Corrección de precios',                    NULL, NULL, NULL, 'ERROR_PRECIO',       NULL, NULL),
(1, 11, 'Cambio en condiciones comerciales',        NULL, NULL, NULL, 'CAMBIO_CONDICIONES', NULL, NULL),
(1, 11, 'Solicitud explícita del cliente',          NULL, NULL, NULL, 'SOLICITUD_CLIENTE',  NULL, NULL),
(1, 11, 'Propuesta vencida, se renueva',            NULL, NULL, NULL, 'VENCIMIENTO',        NULL, NULL),
(1, 11, 'Otro motivo',                              NULL, NULL, NULL, 'OTRO',               NULL, NULL),

-- ── 12 MOTIVO_CIERRE_SIN_VENTA ────────────────────────────────────────────────
(1, 12, 'No se ajustó al precio',                   NULL, NULL, NULL, 'PRECIO',               NULL, NULL),
(1, 12, 'Se fue con la competencia',                NULL, NULL, NULL, 'COMPETENCIA',          NULL, NULL),
(1, 12, 'Sin presupuesto',                          NULL, NULL, NULL, 'SIN_PRESUPUESTO',      NULL, NULL),
(1, 12, 'Postergado sin nueva fecha',               NULL, NULL, NULL, 'POSTERGADO_INDEFINIDO',NULL, NULL),
(1, 12, 'Cliente dejó de responder',                NULL, NULL, NULL, 'CLIENTE_INACTIVO',     NULL, NULL),
(1, 12, 'Otro motivo',                              NULL, NULL, NULL, 'OTRO',                 NULL, NULL),

-- ── 13 MOTIVO_REPROGRAMACION ──────────────────────────────────────────────────
(1, 13, 'Emergencia en planta del cliente',     NULL, NULL, NULL, 'EMERGENCIA_CLIENTE',  NULL, NULL),
(1, 13, 'Sin acceso a planta',                  NULL, NULL, NULL, 'SIN_ACCESO',          NULL, NULL),
(1, 13, 'Técnico no disponible',                NULL, NULL, NULL, 'FALTA_TECNICO',       NULL, NULL),
(1, 13, 'Condición climática adversa',          NULL, NULL, NULL, 'CONDICION_CLIMATICA', NULL, NULL),
(1, 13, 'Falta de repuesto o insumo',           NULL, NULL, NULL, 'FALTA_REPUESTO',      NULL, NULL),
(1, 13, 'Solicitud del cliente',                NULL, NULL, NULL, 'SOLICITUD_CLIENTE',   NULL, NULL),
(1, 13, 'Otro motivo',                          NULL, NULL, NULL, 'OTRO',                NULL, NULL),

-- ── 14 MOTIVO_OBSERVACION_OC ──────────────────────────────────────────────────
(1, 14, 'Razón social no coincide',             NULL, NULL, NULL, 'RAZON_SOCIAL',    NULL, NULL),
(1, 14, 'RUC incorrecto o no coincide',         NULL, NULL, NULL, 'RUC',             NULL, NULL),
(1, 14, 'Monto no cubre el servicio',           NULL, NULL, NULL, 'MONTO',           NULL, NULL),
(1, 14, 'Moneda diferente a la propuesta',      NULL, NULL, NULL, 'MONEDA',          NULL, NULL),
(1, 14, 'No indica vigencia',                   NULL, NULL, NULL, 'SIN_VIGENCIA',    NULL, NULL),
(1, 14, 'Sin firma o sello',                    NULL, NULL, NULL, 'FIRMA_FALTANTE',  NULL, NULL),
(1, 14, 'Otro motivo',                          NULL, NULL, NULL, 'OTRO',            NULL, NULL),

-- ── 15 MOTIVO_DEMORA_RUTA ─────────────────────────────────────────────────────
(1, 15, 'Tráfico',                              NULL, NULL, NULL, 'TRAFICO',           NULL, NULL),
(1, 15, 'Accidente en ruta',                    NULL, NULL, NULL, 'ACCIDENTE_RUTA',    NULL, NULL),
(1, 15, 'Problema mecánico del vehículo',       NULL, NULL, NULL, 'PROBLEMA_VEHICULO', NULL, NULL),
(1, 15, 'Acceso denegado en planta',            NULL, NULL, NULL, 'ACCESO_DENEGADO',   NULL, NULL),
(1, 15, 'Esperando coordinación del cliente',   NULL, NULL, NULL, 'ESPERA_CLIENTE',    NULL, NULL),
(1, 15, 'Condición climática',                  NULL, NULL, NULL, 'CLIMA',             NULL, NULL),
(1, 15, 'Otro motivo',                          NULL, NULL, NULL, 'OTRO',              NULL, NULL),

-- ── 16 MOTIVO_BLOQUEO_SSOMA ───────────────────────────────────────────────────
(1, 16, 'SCTR vencido',                         NULL, NULL, NULL, 'SCTR_VENCIDO',        NULL, NULL),
(1, 16, 'Sin Análisis de Trabajo Seguro',       NULL, NULL, NULL, 'SIN_ATS',             NULL, NULL),
(1, 16, 'EPP incompleto',                       NULL, NULL, NULL, 'EPP_INCOMPLETO',      NULL, NULL),
(1, 16, 'Sin inducción de cliente',             NULL, NULL, NULL, 'SIN_INDUCCION',       NULL, NULL),
(1, 16, 'Certificado médico vencido',           NULL, NULL, NULL, 'CERT_MEDICO_VENCIDO', NULL, NULL),
(1, 16, 'Sin seguro de vida',                   NULL, NULL, NULL, 'SIN_SEGURO_VIDA',     NULL, NULL),
(1, 16, 'Otro motivo',                          NULL, NULL, NULL, 'OTRO',                NULL, NULL),

-- ── 17 MOTIVO_EXCEPCION_EXPEDIENTE ───────────────────────────────────────────
(1, 17, 'Sin OC formal (solo correo de autorización)', NULL, NULL, NULL, 'SIN_OC_FORMAL',         NULL, NULL),
(1, 17, 'Urgencia operativa del cliente',               NULL, NULL, NULL, 'URGENCIA_OPERATIVA',    NULL, NULL),
(1, 17, 'Cliente estratégico aprobado por gerencia',    NULL, NULL, NULL, 'CLIENTE_ESTRATEGICO',   NULL, NULL),
(1, 17, 'Autorización directa de gerencia',             NULL, NULL, NULL, 'AUTORIZACION_GERENCIAL',NULL, NULL),
(1, 17, 'Otro motivo',                                  NULL, NULL, NULL, 'OTRO',                  NULL, NULL),

-- ── 18 MOTIVO_OVERRIDE_EVIDENCIA ──────────────────────────────────────────────
(1, 18, 'Falla de cámara del dispositivo',              NULL, NULL, NULL, 'FALLA_CAMARA',      NULL, NULL),
(1, 18, 'El cliente restringe fotos en planta',         NULL, NULL, NULL, 'RESTRICCION_PLANTA',NULL, NULL),
(1, 18, 'Emergencia operativa',                         NULL, NULL, NULL, 'EMERGENCIA',        NULL, NULL),
(1, 18, 'Evidencia ya fue aceptada previamente',        NULL, NULL, NULL, 'EVIDENCIA_PREVIA',  NULL, NULL),
(1, 18, 'Otro motivo',                                  NULL, NULL, NULL, 'OTRO',              NULL, NULL),

-- ── 19 CLASE_METROLOGICA ──────────────────────────────────────────────────────
(1, 19, 'Clase I — Especial',    NULL, NULL, NULL, 'CLASE_I',    'Alta precisión',    NULL),
(1, 19, 'Clase II — Fina',       NULL, NULL, NULL, 'CLASE_II',   'Buena precisión',   NULL),
(1, 19, 'Clase III — Media',     NULL, NULL, NULL, 'CLASE_III',  'Uso industrial',     NULL),
(1, 19, 'Clase IIII — Ordinaria',NULL, NULL, NULL, 'CLASE_IIII', 'Uso básico',        NULL),

-- ── 20 UNIDAD_MEDIDA ──────────────────────────────────────────────────────────
(1, 20, 'Kilogramo',      NULL, NULL, NULL, 'KG',  'kg', NULL),
(1, 20, 'Gramo',          NULL, NULL, NULL, 'G',   'g',  NULL),
(1, 20, 'Miligramo',      NULL, NULL, NULL, 'MG',  'mg', NULL),
(1, 20, 'Tonelada métrica',NULL, NULL, NULL, 'TON', 't',  NULL),
(1, 20, 'Libra',          NULL, NULL, NULL, 'LB',  'lb', NULL),
(1, 20, 'Onza',           NULL, NULL, NULL, 'OZ',  'oz', NULL),

-- ── 21 TIPO_PRUEBA_METROLOGICA ────────────────────────────────────────────────
(1, 21, 'Prueba de Exactitud',        NULL, NULL, NULL, 'EXACTITUD',     NULL, NULL),
(1, 21, 'Prueba de Excentricidad',    NULL, NULL, NULL, 'EXCENTRICIDAD', NULL, NULL),
(1, 21, 'Prueba de Repetibilidad',    NULL, NULL, NULL, 'REPETIBILIDAD', NULL, NULL),
(1, 21, 'Prueba de Movilidad',        NULL, NULL, NULL, 'MOVILIDAD',     NULL, NULL),

-- ── 22 RESULTADO_CALIBRACION ──────────────────────────────────────────────────
(1, 22, 'Conforme',                   NULL, NULL, NULL, 'CONFORME',              NULL, NULL),
(1, 22, 'No conforme',                NULL, NULL, NULL, 'NO_CONFORME',           NULL, NULL),
(1, 22, 'Requiere ajuste',            NULL, NULL, NULL, 'REQUIERE_AJUSTE',       NULL, NULL),
(1, 22, 'Requiere nueva calibración', NULL, NULL, NULL, 'REQUIERE_NUEVA_CALIB',  NULL, NULL),

-- ── 23 ORGANISMO_NORMA ────────────────────────────────────────────────────────
(1, 23, 'INACAL — Instituto Nacional de Calidad (Perú)',        NULL, NULL, NULL, 'INACAL', NULL, NULL),
(1, 23, 'OIML — Organización Internacional de Metrología Legal',NULL, NULL, NULL, 'OIML',   NULL, NULL),
(1, 23, 'ISO — Organización Internacional de Normalización',    NULL, NULL, NULL, 'ISO',    NULL, NULL),
(1, 23, 'ASTM International',                                   NULL, NULL, NULL, 'ASTM',   NULL, NULL),
(1, 23, 'Otro organismo',                                       NULL, NULL, NULL, 'OTRO',   NULL, NULL),

-- ── 24 TIPO_FORMATO_CONDICION ─────────────────────────────────────────────────
(1, 24, 'Título de sección',  NULL, NULL, NULL, 'TITULO',     NULL, NULL),
(1, 24, 'Párrafo de texto',   NULL, NULL, NULL, 'PARRAFO',    NULL, NULL),
(1, 24, 'Ítem de lista',      NULL, NULL, NULL, 'VINETA',     NULL, NULL),
(1, 24, 'Nota legal',         NULL, NULL, NULL, 'NOTA_LEGAL', NULL, NULL),

-- ── 25 CONCEPTO_GASTO ─────────────────────────────────────────────────────────
(1, 25, 'Movilidad / Transporte',  NULL, NULL, NULL, 'MOVILIDAD',      'viatico',           NULL),
(1, 25, 'Alimentación',            NULL, NULL, NULL, 'ALIMENTACION',   'viatico',           NULL),
(1, 25, 'Alojamiento',             NULL, NULL, NULL, 'ALOJAMIENTO',    'viatico',           NULL),
(1, 25, 'Peaje',                   NULL, NULL, NULL, 'PEAJE',          'gasto_operativo',   NULL),
(1, 25, 'Estacionamiento',         NULL, NULL, NULL, 'ESTACIONAMIENTO','gasto_operativo',   NULL),
(1, 25, 'Insumo / Repuesto menor', NULL, NULL, NULL, 'INSUMO',         'gasto_operativo',   NULL),
(1, 25, 'Combustible',             NULL, NULL, NULL, 'COMBUSTIBLE',    'gasto_operativo',   NULL),
(1, 25, 'Otro concepto',           NULL, NULL, NULL, 'OTRO',           'gasto_operativo',   NULL),

-- ── 26 CANAL_COMUNICACION ─────────────────────────────────────────────────────
(1, 26, 'Correo electrónico',               NULL, NULL, NULL, 'CORREO',    NULL, NULL),
(1, 26, 'WhatsApp',                         NULL, NULL, NULL, 'WHATSAPP',  NULL, NULL),
(1, 26, 'Llamada telefónica',               NULL, NULL, NULL, 'LLAMADA',   NULL, NULL),
(1, 26, 'SMS',                              NULL, NULL, NULL, 'SMS',       NULL, NULL),
(1, 26, 'Notificación en la plataforma',    NULL, NULL, NULL, 'INAPP',     NULL, NULL),
(1, 26, 'Portal Extranet',                  NULL, NULL, NULL, 'EXTRANET',  NULL, NULL),
(1, 26, 'Visita presencial',                NULL, NULL, NULL, 'VISITA',    NULL, NULL),

-- ── 27 RESULTADO_SEGUIMIENTO ──────────────────────────────────────────────────
(1, 27, 'Contactado exitosamente',              NULL, NULL, NULL, 'CONTACTADO',       NULL, NULL),
(1, 27, 'No contesta',                          NULL, NULL, NULL, 'NO_CONTESTA',      NULL, NULL),
(1, 27, 'Enviado a buzón de voz',               NULL, NULL, NULL, 'BUZON',            NULL, NULL),
(1, 27, 'Reunión agendada',                     NULL, NULL, NULL, 'REUNION_AGENDADA', NULL, NULL),
(1, 27, 'Correo enviado, pendiente respuesta',  NULL, NULL, NULL, 'CORREO_ENVIADO',   NULL, NULL),
(1, 27, 'Pendiente de seguimiento',             NULL, NULL, NULL, 'PENDIENTE',        NULL, NULL),

-- ── 28 ROL_EXTRANET ───────────────────────────────────────────────────────────
(1, 28, 'Administrador de cuenta',              NULL, NULL, NULL, 'ADMIN_CUENTA', NULL, NULL),
(1, 28, 'Compras',                              NULL, NULL, NULL, 'COMPRAS',      NULL, NULL),
(1, 28, 'Personal de planta / operaciones',     NULL, NULL, NULL, 'PLANTA',       NULL, NULL),

-- ── 29 TIPO_EVENTO_CAMPO ──────────────────────────────────────────────────────
(1, 29, 'Salida desde base',                    NULL, NULL, NULL, 'SALIDA_BASE',    NULL, NULL),
(1, 29, 'En ruta al cliente',                   NULL, NULL, NULL, 'EN_RUTA',        NULL, NULL),
(1, 29, 'Llegada a planta',                     NULL, NULL, NULL, 'LLEGADA',        NULL, NULL),
(1, 29, 'Inicio de trabajo',                    NULL, NULL, NULL, 'INICIO_TRABAJO', NULL, NULL),
(1, 29, 'Pausa',                                NULL, NULL, NULL, 'PAUSA',          NULL, NULL),
(1, 29, 'Reanudación de trabajo',               NULL, NULL, NULL, 'REANUDA',        NULL, NULL),
(1, 29, 'Hard stop — bloqueo de sistema',       NULL, NULL, NULL, 'HARD_STOP',      NULL, NULL),
(1, 29, 'Cierre del servicio',                  NULL, NULL, NULL, 'CIERRE',         NULL, NULL),
(1, 29, 'Registro de demora',                   NULL, NULL, NULL, 'DEMORA',         NULL, NULL),
(1, 29, 'Incidencia operativa',                 NULL, NULL, NULL, 'INCIDENCIA',     NULL, NULL),

-- ── 30 TIPO_EVIDENCIA ─────────────────────────────────────────────────────────
(1, 30, 'Foto antes del servicio',              NULL, NULL, NULL, 'ANTES',        NULL, NULL),
(1, 30, 'Foto durante el servicio',             NULL, NULL, NULL, 'DURANTE',      NULL, NULL),
(1, 30, 'Foto después del servicio',            NULL, NULL, NULL, 'DESPUES',      NULL, NULL),
(1, 30, 'Falla o daño identificado',            NULL, NULL, NULL, 'FALLA',        NULL, NULL),
(1, 30, 'Verificación de resultado',            NULL, NULL, NULL, 'VERIFICACION', NULL, NULL),
(1, 30, 'Captura de firma digital',             NULL, NULL, NULL, 'FIRMA',        NULL, NULL),
(1, 30, 'Microvideo de encendido',              NULL, NULL, NULL, 'MICROVIDEO',   NULL, NULL),

-- ── 31 TIPO_INTERVENCION_EQUIPO ───────────────────────────────────────────────
(1, 31, 'Calibración',                          NULL, NULL, NULL, 'CALIBRACION',       NULL, NULL),
(1, 31, 'Mantenimiento preventivo',             NULL, NULL, NULL, 'MANTENIMIENTO_PREV',NULL, NULL),
(1, 31, 'Mantenimiento correctivo',             NULL, NULL, NULL, 'MANTENIMIENTO_CORR',NULL, NULL),
(1, 31, 'Reparación',                           NULL, NULL, NULL, 'REPARACION',        NULL, NULL),
(1, 31, 'Verificación',                         NULL, NULL, NULL, 'VERIFICACION',      NULL, NULL),
(1, 31, 'Instalación',                          NULL, NULL, NULL, 'INSTALACION',       NULL, NULL),
(1, 31, 'Solo diagnóstico',                     NULL, NULL, NULL, 'DIAGNOSTICO',       NULL, NULL),

-- ── 32 SECTOR_CLIENTE ─────────────────────────────────────────────────────────
(1, 32, 'Industria alimentaria',                NULL, NULL, NULL, 'ALIMENTOS',   NULL, NULL),
(1, 32, 'Minería y metalurgia',                 NULL, NULL, NULL, 'MINERIA',     NULL, NULL),
(1, 32, 'Laboratorio',                          NULL, NULL, NULL, 'LABORATORIO', NULL, NULL),
(1, 32, 'Farmacéutico',                         NULL, NULL, NULL, 'FARMACEUTICO',NULL, NULL),
(1, 32, 'Logística y distribución',             NULL, NULL, NULL, 'LOGISTICA',   NULL, NULL),
(1, 32, 'Retail y comercio',                    NULL, NULL, NULL, 'RETAIL',      NULL, NULL),
(1, 32, 'Industria pesquera',                   NULL, NULL, NULL, 'PESQUERO',    NULL, NULL),
(1, 32, 'Industria química',                    NULL, NULL, NULL, 'QUIMICO',     NULL, NULL),
(1, 32, 'Otro sector',                          NULL, NULL, NULL, 'OTRO',        NULL, NULL),

-- ── 33 TIPO_INCIDENCIA_OPERATIVA ──────────────────────────────────────────────
(1, 33, 'Accidente de trabajo',                 NULL, NULL, NULL, 'ACCIDENTE',        NULL, NULL),
(1, 33, 'Falla en equipo de TW',                NULL, NULL, NULL, 'FALLA_EQUIPO_TW',  NULL, NULL),
(1, 33, 'Acceso denegado en planta',            NULL, NULL, NULL, 'ACCESO_DENEGADO',  NULL, NULL),
(1, 33, 'Emergencia en planta del cliente',     NULL, NULL, NULL, 'EMERGENCIA_PLANTA',NULL, NULL),
(1, 33, 'Conflicto con personal del cliente',   NULL, NULL, NULL, 'CONFLICTO_CLIENTE',NULL, NULL),
(1, 33, 'Otro tipo',                            NULL, NULL, NULL, 'OTRO',             NULL, NULL),

-- ── 34 NIVEL_ALERTA ───────────────────────────────────────────────────────────
(1, 34, 'Bajo',     NULL, NULL, NULL, 'BAJO',    '#28a745', NULL),
(1, 34, 'Medio',    NULL, NULL, NULL, 'MEDIO',   '#ffc107', NULL),
(1, 34, 'Alto',     NULL, NULL, NULL, 'ALTO',    '#fd7e14', NULL),
(1, 34, 'Crítico',  NULL, NULL, NULL, 'CRITICO', '#dc3545', NULL),

-- ── 35 VISIBILIDAD_DOCUMENTO ──────────────────────────────────────────────────
(1, 35, 'Solo interno TW',          NULL, NULL, NULL, 'INTERNO',     NULL, NULL),
(1, 35, 'Área Comercial',           NULL, NULL, NULL, 'COMERCIAL',   NULL, NULL),
(1, 35, 'Área Operaciones',         NULL, NULL, NULL, 'OPERACIONES', NULL, NULL),
(1, 35, 'Área SSOMA',               NULL, NULL, NULL, 'SSOMA',       NULL, NULL),
(1, 35, 'Visible al cliente (Extranet)', NULL, NULL, NULL, 'CLIENTE', NULL, NULL),

-- ── 36 TIPO_DOCUMENTO_SSOMA ───────────────────────────────────────────────────
(1, 36, 'SCTR (Salud y Pensión)',               1, NULL, NULL, 'SCTR',       NULL, NULL),
(1, 36, 'Análisis de Trabajo Seguro',           0, NULL, NULL, 'ATS',        NULL, NULL),
(1, 36, 'Checklist de EPP',                     0, NULL, NULL, 'EPP',        NULL, NULL),
(1, 36, 'Certificado médico ocupacional',        1, NULL, NULL, 'CERT_MEDICO',NULL, NULL),
(1, 36, 'Constancia de inducción del cliente',  1, NULL, NULL, 'INDUCCION',  NULL, NULL),
(1, 36, 'Seguro de vida',                        1, NULL, NULL, 'SEGURO_VIDA',NULL, NULL),
(1, 36, 'Permiso de trabajo en altura',          0, NULL, NULL, 'PETAR',      NULL, NULL),
(1, 36, 'Otro documento',                        0, NULL, NULL, 'OTRO',       NULL, NULL),

-- ── 37 ESTADO_GARANTIA_EQUIPO ─────────────────────────────────────────────────
(1, 37, 'Vigente',              NULL, NULL, NULL, 'VIGENTE',     '#28a745', NULL),
(1, 37, 'Por vencer (< 30 días)',NULL, NULL, NULL, 'POR_VENCER', '#ffc107', NULL),
(1, 37, 'Vencida',              NULL, NULL, NULL, 'VENCIDA',     '#dc3545', NULL),
(1, 37, 'Sin garantía',         NULL, NULL, NULL, 'SIN_GARANTIA','#6c757d', NULL),

-- ── 38 ESTADO_PATRON ──────────────────────────────────────────────────────────
(1, 38, 'Vigente',              NULL, NULL, NULL, 'VIGENTE',          NULL, NULL),
(1, 38, 'Por vencer (< 30 días)',NULL, NULL, NULL, 'POR_VENCER',      NULL, NULL),
(1, 38, 'Vencido',              NULL, NULL, NULL, 'VENCIDO',          NULL, NULL),
(1, 38, 'En calibración externa',NULL, NULL, NULL, 'EN_CALIBRACION',  NULL, NULL),
(1, 38, 'Dado de baja',         NULL, NULL, NULL, 'BAJA',             NULL, NULL),

-- ── 39 CONDICION_PAGO ─────────────────────────────────────────────────────────
(1, 39, 'Contado',                              NULL, NULL, NULL, 'CONTADO',     NULL, NULL),
(1, 39, 'Crédito 15 días',                      NULL, NULL, NULL, 'CREDITO_15',  NULL, NULL),
(1, 39, 'Crédito 30 días',                      NULL, NULL, NULL, 'CREDITO_30',  NULL, NULL),
(1, 39, 'Crédito 45 días',                      NULL, NULL, NULL, 'CREDITO_45',  NULL, NULL),
(1, 39, 'Crédito 60 días',                      NULL, NULL, NULL, 'CREDITO_60',  NULL, NULL),
(1, 39, '50% adelanto + 50% contra entrega',    NULL, NULL, NULL, 'ADELANTO_50', NULL, NULL),
(1, 39, 'Otro acuerdo',                          NULL, NULL, NULL, 'OTRO',        NULL, NULL),

-- ── 40 CANAL_ORIGEN_TICKET ────────────────────────────────────────────────────
(1, 40, 'Asistente IA del portal',  NULL, NULL, NULL, 'HELPDESK_IA', NULL, NULL),
(1, 40, 'Portal Extranet',          NULL, NULL, NULL, 'EXTRANET',    NULL, NULL),
(1, 40, 'Correo electrónico',       NULL, NULL, NULL, 'CORREO',      NULL, NULL),
(1, 40, 'Llamada telefónica',       NULL, NULL, NULL, 'LLAMADA',     NULL, NULL),
(1, 40, 'WhatsApp',                 NULL, NULL, NULL, 'WHATSAPP',    NULL, NULL),

-- ── 41 TIPO_JORNADA ───────────────────────────────────────────────────────────
(1, 41, 'Jornada normal de trabajo',                NULL, NULL, NULL, 'NORMAL',      NULL, NULL),
(1, 41, 'Jornada de guardia / turno especial',      NULL, NULL, NULL, 'GUARDIA',     NULL, NULL),
(1, 41, 'Jornada en comisión de servicios',         NULL, NULL, NULL, 'COMISION',    NULL, NULL),
(1, 41, 'Jornada de capacitación interna',          NULL, NULL, NULL, 'CAPACITACION',NULL, NULL),
(1, 41, 'Horas extra fuera de jornada normal',      NULL, NULL, NULL, 'HORAS_EXTRA', NULL, NULL),

-- ── 42 TIPO_FORMULARIO_CAMPO ──────────────────────────────────────────────────
(1, 42, 'Registro de evento GPS / hito de campo',   NULL, NULL, NULL, 'EVENTO_CAMPO',      NULL, NULL),
(1, 42, 'Datos de medición metrológica',            NULL, NULL, NULL, 'MEDICION',          NULL, NULL),
(1, 42, 'Registro de evidencia fotográfica',        NULL, NULL, NULL, 'EVIDENCIA',         NULL, NULL),
(1, 42, 'Registro de demora en ruta',               NULL, NULL, NULL, 'DEMORA',            NULL, NULL),
(1, 42, 'Condiciones ambientales de calibración',   NULL, NULL, NULL, 'VARIABLE_AMBIENTAL',NULL, NULL),
(1, 42, 'Firma de conformidad del cliente',         NULL, NULL, NULL, 'CONFORMIDAD',       NULL, NULL),

-- ── 43 CANAL_ACCESO ───────────────────────────────────────────────────────────
(1, 43, 'Back-office web (escritorio)', NULL, NULL, NULL, 'INTRANET', NULL, NULL),
(1, 43, 'App móvil de campo',           NULL, NULL, NULL, 'MOVIL',    NULL, NULL),
(1, 43, 'Portal web del cliente',       NULL, NULL, NULL, 'EXTRANET', NULL, NULL),

-- ── 44 ESTADO_DOCUMENTO ───────────────────────────────────────────────────────
(1, 44, 'En elaboración, no publicado',             NULL, NULL, NULL, 'BORRADOR',    NULL, NULL),
(1, 44, 'Aprobado y en uso activo',                 NULL, NULL, NULL, 'VIGENTE',     NULL, NULL),
(1, 44, 'Bajo revisión para nueva versión',         NULL, NULL, NULL, 'EN_REVISION', NULL, NULL),
(1, 44, 'Reemplazado por versión más reciente',     NULL, NULL, NULL, 'OBSOLETO',    NULL, NULL),
(1, 44, 'Retirado del sistema',                     NULL, NULL, NULL, 'ANULADO',     NULL, NULL),

-- ── 45 TIPO_EXPORTACION_ERP ───────────────────────────────────────────────────
(1, 45, 'Datos de OS/OM para generar facturas',     NULL, NULL, NULL, 'FACTURACION',         NULL, NULL),
(1, 45, 'Estado de cobros y cuentas por cobrar',    NULL, NULL, NULL, 'COBRANZA',            NULL, NULL),
(1, 45, 'Liquidación de haberes y comisiones',      NULL, NULL, NULL, 'PERSONAL',            NULL, NULL),
(1, 45, 'Gastos y viáticos rendidos',               NULL, NULL, NULL, 'VIATICOS',            NULL, NULL),
(1, 45, 'Estado de instrumentos patrón',            NULL, NULL, NULL, 'INVENTARIO_PATRONES', NULL, NULL),

-- ── 46 NORMA_METROLOGICA ──────────────────────────────────────────────────────
(1, 46, 'OIML R76 — Instrumentos de pesaje no automáticos',  1, NULL, NULL, 'OIML-R76',      'OIML R76',      NULL),
(1, 46, 'OIML R111 — Pesas clase E1 a M3',                   2, NULL, NULL, 'OIML-R111',     'OIML R111',     NULL),
(1, 46, 'ISO 8655 — Instrumentos de medición de volumen',    3, NULL, NULL, 'ISO-8655',      'ISO 8655',      NULL),
(1, 46, 'NTP-OIML R76 — Versión peruana',                    4, NULL, NULL, 'NTP-OIML-R76',  'NTP-OIML R76',  NULL),
(1, 46, 'NTP-INDECOPI 019',                                  5, NULL, NULL, 'INDECOPI-019',  'NTP-INDECOPI 019', NULL),

-- ── 47 METODO_CALIBRACION ─────────────────────────────────────────────────────
(1, 47, 'Calibración gravimétrica',     1, 1, NULL, 'CAL-GRAVIM', NULL, NULL),
(1, 47, 'Calibración por comparación',  2, 1, NULL, 'CAL-COMP',   NULL, NULL),
(1, 47, 'Método de sustitución',        3, 2, NULL, 'CAL-SUSTIT', NULL, NULL),
(1, 47, 'Calibración volumétrica',      4, 3, NULL, 'CAL-VOLUM',  NULL, NULL),

-- ── 48 REQUISITO_SSOMA ────────────────────────────────────────────────────────
-- Num1=vencimiento_dias · Num2=es_obligatorio · Num3=bloquea_servicio · String1=aplica_rol
(1, 48, 'Seguro Complementario de Trabajo de Riesgo (SCTR)', 365, 1, 1, 'ambos',    NULL, NULL),
(1, 48, 'Examen médico ocupacional',                         365, 1, 1, 'ambos',    NULL, NULL),
(1, 48, 'Certificado de aptitud para trabajo en altura',     365, 1, 1, 'tecnico',  NULL, NULL),
(1, 48, 'EPP actualizado (foto)',                            180, 1, 0, 'ambos',    NULL, NULL),
(1, 48, 'Inducción SSOMA cliente',                             0, 0, 0, 'ambos',    NULL, NULL),

-- ── 49 CONFIG_SLA ─────────────────────────────────────────────────────────────
-- Num1=horas_limite · Num2=horas_alerta · Num3=aplica_dias_habiles · String1=entidad · String2=etapa
(1, 49, 'SLA: propuesta — pendiente visto bueno',    24,  4, 1, 'propuesta',     'pendiente_vb',         NULL),
(1, 49, 'SLA: orden de compra — pendiente validación',48, 8, 1, 'orden_compra',  'pendiente_validacion', NULL),
(1, 49, 'SLA: expediente — SSOMA',                   72, 24, 1, 'expediente',    'ssoma',                NULL),
(1, 49, 'SLA: informe — pendiente revisión',         48, 12, 1, 'informe',       'pendiente_revision',   NULL),
(1, 49, 'SLA: orden de servicio — programada',      168, 24, 1, 'orden_servicio','programada',           NULL),

-- ── 50 PERMISO ────────────────────────────────────────────────────────────────
-- Num1=id_permiso · String1=codigo · String2=nombre legible · String3=modulo
(1, 50, 'Crear propuesta comercial',    1, NULL, NULL, 'propuesta.crear',    'Crear propuesta comercial',    'comercial'),
(1, 50, 'Aprobar propuesta',            2, NULL, NULL, 'propuesta.aprobar',  'Aprobar propuesta (visto bueno)','comercial'),
(1, 50, 'Validar orden de compra',      3, NULL, NULL, 'oc.validar',         'Validar orden de compra',      'comercial'),
(1, 50, 'Anular orden de servicio',     4, NULL, NULL, 'os.anular',          'Anular orden de servicio',     'operaciones'),
(1, 50, 'Revisar informe técnico',      5, NULL, NULL, 'informe.revisar',    'Revisar informe técnico',      'operaciones'),
(1, 50, 'Aprobar documentos SSOMA',     6, NULL, NULL, 'ssoma.aprobar',      'Aprobar documentos SSOMA',     'ssoma'),
(1, 50, 'Emitir certificado metrológico',7,NULL, NULL, 'om.emitir',          'Emitir certificado metrológico','metrologia'),
(1, 50, 'Administrar usuarios',         8, NULL, NULL, 'usuario.administrar','Administrar usuarios',         'administracion'),

-- ── 51 TIPO_ITEM_CATALOGO ─────────────────────────────────────────────────────
(1, 51, 'Repuesto o pieza',     NULL, NULL, NULL, 'REPUESTO',   NULL, NULL),
(1, 51, 'Servicio técnico',     NULL, NULL, NULL, 'SERVICIO',   NULL, NULL),
(1, 51, 'Mano de obra',         NULL, NULL, NULL, 'MANO_OBRA',  NULL, NULL),
(1, 51, 'Consumible',           NULL, NULL, NULL, 'CONSUMIBLE', NULL, NULL),

-- ── 52 TIPO_ITEM_PRESALIDA ────────────────────────────────────────────────────
(1, 52, 'Repuesto a llevar',            NULL, NULL, NULL, 'REPUESTO',  NULL, NULL),
(1, 52, 'Alerta predictiva a resolver', NULL, NULL, NULL, 'ALERTA',    NULL, NULL),
(1, 52, 'Documento requerido',          NULL, NULL, NULL, 'DOCUMENTO', NULL, NULL),
(1, 52, 'Otro ítem',                    NULL, NULL, NULL, 'OTRO',      NULL, NULL),

-- ── 53 TIPO_ALERTA_PREDICTIVA ─────────────────────────────────────────────────
(1, 53, 'Desgaste proyectado por uso acumulado',            NULL, NULL, NULL, 'DESGASTE',       NULL, NULL),
(1, 53, 'Calibración próxima a vencer',                     NULL, NULL, NULL, 'VENCIMIENTO_CAL',NULL, NULL),
(1, 53, 'Falla probable detectada por patrón histórico',    NULL, NULL, NULL, 'FALLA_PROBABLE', NULL, NULL),
(1, 53, 'Equipo sin servicio en período mayor al esperado', NULL, NULL, NULL, 'SIN_SERVICIO',   NULL, NULL),

-- ── 54 RESOLUCION_ALERTA ──────────────────────────────────────────────────────
(1, 54, 'El técnico atendió la alerta en campo',    NULL, NULL, NULL, 'ATENDIDA',    NULL, NULL),
(1, 54, 'Descartada — no aplica al caso concreto',  NULL, NULL, NULL, 'DESCARTADA',  NULL, NULL),
(1, 54, 'Queda pendiente para la próxima visita',   NULL, NULL, NULL, 'POSTERGADA',  NULL, NULL),

-- ── 55 TIPO_SEDE ──────────────────────────────────────────────────────────────
(1, 55, 'Sede principal / casa matriz',     NULL, NULL, NULL, 'PRINCIPAL',  NULL, NULL),
(1, 55, 'Sucursal comercial',               NULL, NULL, NULL, 'SUCURSAL',   NULL, NULL),
(1, 55, 'Planta de producción / industrial',NULL, NULL, NULL, 'PLANTA',     NULL, NULL),
(1, 55, 'Almacén o depósito',               NULL, NULL, NULL, 'ALMACEN',    NULL, NULL),
(1, 55, 'Laboratorio',                      NULL, NULL, NULL, 'LABORATORIO',NULL, NULL),
(1, 55, 'Otro tipo de sede',                NULL, NULL, NULL, 'OTRO',       NULL, NULL),

-- ── 56 TIPO_DOC_IDENTIDAD ─────────────────────────────────────────────────────
(1, 56, 'Documento Nacional de Identidad (Perú)',   NULL, NULL, NULL, 'DNI',      NULL, NULL),
(1, 56, 'Carnet de Extranjería',                    NULL, NULL, NULL, 'CE',       NULL, NULL),
(1, 56, 'Pasaporte',                                NULL, NULL, NULL, 'PASAPORTE',NULL, NULL),
(1, 56, 'RUC (persona natural con negocio)',         NULL, NULL, NULL, 'RUC',      NULL, NULL);
