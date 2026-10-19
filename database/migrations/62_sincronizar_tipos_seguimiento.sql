-- ============================================================
-- Migración 62 — HU-19: Sincronizar catálogos CANAL_COMUNICACION y TIPO_ACCION_SEGUIMIENTO
--
--   Hoy existen 2 catálogos distintos con conceptos parecidos:
--     CANAL_COMUNICACION      (IdMaestro=26): LLAMADA, CORREO, WHATSAPP, REUNION, VISITA, SMS, INAPP, EXTRANET
--     TIPO_ACCION_SEGUIMIENTO (IdMaestro=93): LLAMADA, CORREO, REUNION, VISITA, REENVIO_AJUSTES, GENERAR_OC, OTRO
--
--   Al user le parece el mismo concepto. Para dar una UX unificada sin cambiar modelo
--   de datos, sincronizamos los códigos String2 en ambos catálogos:
--     Añadimos a TIPO_ACCION_SEGUIMIENTO: WHATSAPP
--     Añadimos a CANAL_COMUNICACION:      REENVIO_AJUSTES, OTRO (con Num2=1 = aptos para registro)
--     GENERAR_OC permanece solo en TIPO_ACCION (no se registra como seguimiento, es un milestone)
--     SMS/INAPP/EXTRANET permanecen solo en CANAL con Num2=0 (son canales internos del sistema de notificaciones)
--
--   Así cuando el user programa una tarea "WhatsApp" y luego ejecuta esa tarea,
--   el modal registra automáticamente con tipo "WhatsApp" (mismo código String2).
--
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. Añadir WHATSAPP a TIPO_ACCION_SEGUIMIENTO
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, 93, 'TIPO_ACCION_SEGUIMIENTO',
       (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE IdMaestro = 93 AND IdEmpresa = 1),
       0, 'WhatsApp', 'WHATSAPP'
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM tabla_maestra
    WHERE IdMaestro = 93 AND IdEmpresa = 1 AND String2 = 'WHATSAPP'
);

-- 2. Añadir REENVIO_AJUSTES a CANAL_COMUNICACION (apto para registro, Num2=1)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, 26, 'CANAL_COMUNICACION',
       (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE IdMaestro = 26 AND IdEmpresa = 1),
       1, 'Reenvío de ajustes', 'REENVIO_AJUSTES'
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM tabla_maestra
    WHERE IdMaestro = 26 AND IdEmpresa = 1 AND String2 = 'REENVIO_AJUSTES'
);

-- 3. Añadir OTRO a CANAL_COMUNICACION
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, 26, 'CANAL_COMUNICACION',
       (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE IdMaestro = 26 AND IdEmpresa = 1),
       1, 'Otra acción', 'OTRO'
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM tabla_maestra
    WHERE IdMaestro = 26 AND IdEmpresa = 1 AND String2 = 'OTRO'
);
