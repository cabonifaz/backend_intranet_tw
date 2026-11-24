-- ============================================================
-- Migración 128 — App móvil sin señal: detalle de los registros enviados tarde (HU-18 · trazabilidad)
--   Cuando el técnico registra algo sin señal, la app lo guarda en el teléfono y lo envía solo al volver la conexión. Esta tabla deja constancia de CADA envío tardío:
--   qué fue (llegada, demora, variables, ensayos, cabecera, evidencia, acción de equipo, jornada, gasto…), de qué servicio y equipo, cuándo se tomó en campo (capturado_utc),
--   cuándo llegó al servidor (recibido_utc), cuánto tardó (retraso_seg), por qué se retrasó (motivo) y cuántos intentos hizo la app.
--   La API la llena sola cuando la app manda la hora de captura en la cabecera X-TW-Capturado-En (SP_RegistrarEnvioDiferidoMovil); la leen Jefatura y la intranet
--   (SP_ListarEnviosDiferidosMovil). No cambia ningún dato existente. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS envio_diferido_movil (
    id_envio      BIGINT       NOT NULL AUTO_INCREMENT,
    id_usuario    BIGINT       NOT NULL,
    id_os         BIGINT       NULL,
    id_os_equipo  BIGINT       NULL,
    tipo          VARCHAR(30)  NOT NULL,
    metodo        VARCHAR(6)   NOT NULL,
    ruta          VARCHAR(200) NOT NULL,
    capturado_utc DATETIME     NOT NULL,
    recibido_utc  DATETIME     NOT NULL,
    retraso_seg   INT          NOT NULL DEFAULT 0,
    motivo        VARCHAR(30)  NOT NULL DEFAULT 'sin_senal',
    intentos      INT          NOT NULL DEFAULT 0,
    creado_en     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_envio),
    KEY ix_edm_os (id_os, capturado_utc),
    KEY ix_edm_usuario (id_usuario, recibido_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Verificación (solo lectura): debe ser 1
SELECT 'Tabla envio_diferido_movil creada (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'envio_diferido_movil') AS valor;
