-- ============================================================
-- Migración 121 — Revisión de informes técnicos desde la app (HU-33, Jefe de Área)
--   Tabla informe_correccion: la solicitud de corrección que el jefe le hace al técnico al OBSERVAR un informe (motivo, secciones afectadas, qué debe corregir y plazo).
--   Un informe tiene como máximo UNA corrección pendiente (lo asegura SP_ObservarInformeMovil con el informe bloqueado). Al observar, el informe pasa a estado 'observado'
--   (ya existe en el ENUM informe_tecnico.estado desde la migración 93) y el técnico recibe una notificación (y el push de la app).
--     motivo ....... evidencia_insuficiente | datos_incorrectos | ensayos_inconsistentes | firma_faltante | otro (catálogo fijo: SP_ArmarCatalogoRevisionInformeMovil)
--     secciones .... códigos separados por coma: registro_fotografico, cabecera, ensayos, firmas
--     plazo_en ..... fecha y hora límite (hora de Lima, igual que notificacion.fecha_creacion y el resto de los SP de la app)
--     estado ....... pendiente | atendida | cancelada (la atiende el técnico; esa pantalla es de otra HU)
--   Soft delete + auditoría. Sin FK ni UNIQUE (la regla de "una pendiente" la valida el SP). No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS informe_correccion (
    id_correccion  BIGINT        NOT NULL AUTO_INCREMENT,
    id_informe     BIGINT        NOT NULL,
    id_jefe        BIGINT        NOT NULL,
    motivo         VARCHAR(30)   NOT NULL,
    secciones      VARCHAR(200)  NOT NULL,
    instruccion    VARCHAR(1000) NOT NULL,
    plazo_en       DATETIME      NOT NULL,
    estado         ENUM('pendiente','atendida','cancelada') NOT NULL DEFAULT 'pendiente',
    atendida_en    DATETIME      NULL,
    -- AUDITORÍA
    creado_en      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT        NULL,
    modificado_en  DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por BIGINT        NULL,
    eliminado_en   DATETIME      NULL,
    eliminado_por  BIGINT        NULL,
    PRIMARY KEY (id_correccion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_correccion' AND INDEX_NAME = 'ix_informe_correccion_informe'),
    'ALTER TABLE informe_correccion ADD KEY ix_informe_correccion_informe (id_informe, estado, eliminado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 121 (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_correccion') AS valor;
