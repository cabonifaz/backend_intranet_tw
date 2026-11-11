-- ============================================================
-- Migración 105 — Firma de informes y constancia de servicio para la app móvil (App Mobile HU-17)
--   El técnico hace firmar los informes técnicos generados (HU-15 / HU-16) a sus RESPONSABLES ("Quién atiende en planta": informe_tecnico.responsable_*),
--   y la constancia de servicio al cliente. La firma del dispositivo se guarda como TRAZOS normalizados (JSON, puntos de 0 a 1) más su hash; no hay imagen.
--   1. os_firma_responsable: una fila por responsable y OS (UNIQUE id_os + clave). modo = dispositivo (trazos) · fisico (foto del formato en papel) ·
--      ausente (cliente ausente: queda constancia de la aceptación tácita, la firma sigue pendiente). "Editar firma" actualiza la fila (version + 1) y la
--      anterior queda en auditoria_evento.
--   2. os_constancia: una fila por OS: firma del cliente (dispositivo o formato físico), cuándo se generó, cuándo se cerró el servicio, el PDF y el envío.
--   3. Parámetros (tabla_maestra PARAMETRO_PROGRAMACION, columna Num2): FIRMA_ACEPTACION_TACITA_HORAS (48), FIRMA_SIMILITUD_MAXIMA_PCT (90: una firma igual o
--      más parecida que esto a la de OTRO responsable de la misma OS se rechaza) y CONSTANCIA_ENVIO_CORREO (0 = no envía correos; 1 = envía la constancia al cliente).
--   Requiere la migración de la HU-15 (informe_tecnico: numero_informe, generado_en, responsable_*). No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. os_firma_responsable ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_firma_responsable (
    id_firma         BIGINT        NOT NULL AUTO_INCREMENT,
    id_os            BIGINT        NOT NULL,
    clave            CHAR(32)      NOT NULL,
    nombre           VARCHAR(150)  NOT NULL,
    cargo            VARCHAR(100)  NULL,
    telefono         VARCHAR(30)   NULL,
    modo             ENUM('dispositivo','fisico','ausente') NOT NULL,
    trazos           JSON          NULL,
    hash_firma       CHAR(64)      NULL,
    nombre_firmante  VARCHAR(150)  NULL,
    ruta_foto        VARCHAR(300)  NULL,
    motivo           VARCHAR(300)  NULL,
    version          INT           NOT NULL DEFAULT 1,
    firmado_en       DATETIME      NOT NULL,
    firmado_por      BIGINT        NOT NULL,
    -- AUDITORÍA
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    PRIMARY KEY (id_firma),
    UNIQUE KEY ux_firma_os_clave (id_os, clave)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. os_constancia ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_constancia (
    id_constancia    BIGINT        NOT NULL AUTO_INCREMENT,
    id_os            BIGINT        NOT NULL,
    modo             ENUM('dispositivo','fisico') NULL,
    firmante_nombre  VARCHAR(150)  NULL,
    trazos           JSON          NULL,
    hash_firma       CHAR(64)      NULL,
    ruta_foto        VARCHAR(300)  NULL,
    firmado_en       DATETIME      NULL,
    firmado_por      BIGINT        NULL,
    generada_en      DATETIME      NULL,
    generada_por     BIGINT        NULL,
    cerrada_en       DATETIME      NULL,
    ruta_pdf         VARCHAR(300)  NULL,
    envio_estado     ENUM('en_espera','enviado','error','desactivado','sin_correo') NOT NULL DEFAULT 'en_espera',
    envio_destino    VARCHAR(200)  NULL,
    envio_en         DATETIME      NULL,
    envio_detalle    VARCHAR(300)  NULL,
    -- AUDITORÍA
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    PRIMARY KEY (id_constancia),
    UNIQUE KEY ux_constancia_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Parámetros ──────────────────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @num_param := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', @num_param + v.n, v.valor, v.texto, v.codigo
FROM (SELECT 1 AS n, 48 AS valor, 'Horas de aceptación tácita de los informes desde que se genera el primero (HU-17)' AS texto, 'FIRMA_ACEPTACION_TACITA_HORAS' AS codigo
      UNION ALL SELECT 2, 90, 'Similitud máxima (%) entre las firmas de responsables distintos de una misma orden (HU-17)', 'FIRMA_SIMILITUD_MAXIMA_PCT'
      UNION ALL SELECT 3, 0,  'Enviar la constancia de servicio al correo del cliente al cerrar (1 = sí, 0 = no)', 'CONSTANCIA_ENVIO_CORREO') v
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.String2 = v.codigo);
