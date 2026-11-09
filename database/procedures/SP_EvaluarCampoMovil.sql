-- ============================================================
-- SP_EvaluarCampoMovil  (App Mobile HU-06 / HU-07 — apoyo, no es un endpoint)
-- Hard Stop de los objetivos, UNA sola vez: ¿el técnico ya registró su llegada a planta en este viaje y el servicio sigue en curso?
--   p_llegada_utc : llegada de ESTE viaje (último evento LLEGADA posterior a la última SALIDA_BASE); NULL = sin marca de llegada
--   p_habilitado  : 1 = se puede trabajar en los equipos (llegada registrada y OS en ruta, en ejecución o en pausa)
--   p_motivo      : por qué no (cuando p_habilitado = 0)
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EvaluarCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarCampoMovil(
    IN  p_id_os       BIGINT,
    OUT p_estado      VARCHAR(20),
    OUT p_salida_utc  DATETIME,
    OUT p_llegada_utc DATETIME,
    OUT p_habilitado  TINYINT,
    OUT p_motivo      VARCHAR(200)
)
BEGIN
    SET p_estado      = NULL;
    SET p_salida_utc  = NULL;
    SET p_llegada_utc = NULL;
    SET p_habilitado  = 0;
    SET p_motivo      = NULL;

    SELECT os.estado INTO p_estado FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;

    SELECT MAX(e.timestamp_utc) INTO p_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT MAX(e.timestamp_utc) INTO p_llegada_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(p_salida_utc, '1000-01-01');

    IF p_llegada_utc IS NULL THEN
        SET p_motivo = 'Sin marca de llegada: primero registra tu llegada a planta antes de acceder a los objetivos.';
    ELSEIF p_estado NOT IN ('en_ruta', 'en_ejecucion', 'pausada') THEN
        SET p_motivo = 'El servicio ya no está en curso: los equipos no se pueden modificar.';
    ELSE
        SET p_habilitado = 1;
    END IF;
END$$

DELIMITER ;
