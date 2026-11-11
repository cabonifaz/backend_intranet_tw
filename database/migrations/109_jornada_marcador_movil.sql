-- ============================================================
-- Migración 109 — Reloj Marcador de jornada de la app móvil (HU-20)
--   1. jornada_marcacion: las 5 marcaciones del día del técnico, en orden estricto (inicio de labores → inicio de refrigerio → fin de refrigerio →
--      salida de planta → fin de labores). Una por tipo y día (índice único): reenviar una marcación guardada sin conexión no duplica nada.
--      La hora es la del teléfono validada por el servidor (no se puede editar); guarda GPS, lugar, puntualidad (solo el ingreso) y si se marcó sin conexión.
--   2. Parámetros (PARAMETRO_PROGRAMACION): horario programado de la jornada, tolerancia del ingreso, tope de refrigerio y minutos sin movimiento para alertar.
--      El horario es general (07:45 a 17:00); si más adelante hace falta por técnico, se agrega una tabla de horarios y el SP la lee.
--   Las posiciones GPS de la jornada se guardan en ubicacion_tecnico (migración 90): el Seguimiento Operativo de la intranet ya las lee.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS jornada_marcacion (
    id_marcacion       BIGINT        NOT NULL AUTO_INCREMENT,
    id_usuario         BIGINT        NOT NULL,
    fecha              DATE          NOT NULL,
    tipo               VARCHAR(20)   NOT NULL,
    marcado_utc        DATETIME      NOT NULL,
    latitud            DECIMAL(10,7) NULL,
    longitud           DECIMAL(10,7) NULL,
    precision_m        INT           NULL,
    lugar              VARCHAR(200)  NULL,
    puntualidad        VARCHAR(10)   NULL,
    minutos_diferencia INT           NULL,
    sin_conexion       TINYINT       NOT NULL DEFAULT 0,
    creado_en          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_marcacion),
    UNIQUE KEY ux_jornada_usuario_dia_tipo (id_usuario, fecha, tipo),
    KEY ix_jornada_fecha (fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', x.n, x.valor, x.nombre, x.codigo
FROM (SELECT 120 AS n, 465 AS valor, 'Inicio programado de la jornada (minutos desde las 00:00; 465 = 07:45)'                      AS nombre, 'JORNADA_INICIO_MIN'       AS codigo UNION ALL
      SELECT 121,      1020,          'Fin programado de la jornada (minutos desde las 00:00; 1020 = 17:00)',                                'JORNADA_FIN_MIN'                  UNION ALL
      SELECT 122,      5,             'Minutos de tolerancia sobre el inicio programado para marcar el ingreso "a tiempo"',                  'JORNADA_TOLERANCIA_MIN'           UNION ALL
      SELECT 123,      60,            'Minutos de refrigerio permitidos',                                                                    'JORNADA_REFRIGERIO_MIN'           UNION ALL
      SELECT 124,      10,            'Minutos sin movimiento del técnico (con la jornada en curso) para alertar a Jefatura',                'SEG_SIN_MOVIMIENTO_MIN') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── Verificación (debe ser 6) ─────────────────────────────────────────────────
SELECT 'Migración 109 (debe ser 6)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jornada_marcacion')
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1
          AND String2 IN ('JORNADA_INICIO_MIN', 'JORNADA_FIN_MIN', 'JORNADA_TOLERANCIA_MIN', 'JORNADA_REFRIGERIO_MIN', 'SEG_SIN_MOVIMIENTO_MIN')) AS valor;
