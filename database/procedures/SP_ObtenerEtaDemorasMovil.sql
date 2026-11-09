-- ============================================================
-- SP_ObtenerEtaDemorasMovil  (App Mobile HU-05 — apoyo, no es un endpoint)
-- Reglas de la hora estimada de llegada (ETA) y del inicio del trabajo, UNA sola vez (las usan la consulta y el registro de demoras).
-- Todas las horas son de Lima (UTC-5).
--   p_eta_original   : hora programada del servicio (fecha_ejecucion + hora_inicio). Es la ETA de llegada original.
--   p_minutos_llegada: suma de las demoras de tipo "llegada" ya registradas. ETA vigente = ETA original + estos minutos.
--   p_llegada_en     : cuándo el técnico registró su llegada a la planta (evento LLEGADA, HU-06) en este viaje (posterior a la última
--                      SALIDA_BASE); NULL si aún no la registró.
--   p_inicio_vigente : hora de inicio del trabajo prevista tras la última demora de tipo "ingreso"; NULL si no hay.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEtaDemorasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEtaDemorasMovil(
    IN  p_id_os           BIGINT,
    OUT p_eta_original    DATETIME,
    OUT p_minutos_llegada INT,
    OUT p_llegada_en      DATETIME,
    OUT p_inicio_vigente  DATETIME
)
BEGIN
    SET p_eta_original    = NULL;
    SET p_minutos_llegada = 0;
    SET p_llegada_en      = NULL;
    SET p_inicio_vigente  = NULL;

    SELECT TIMESTAMP(os.fecha_ejecucion, os.hora_inicio) INTO p_eta_original
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;

    SELECT IFNULL(SUM(d.duracion_minutos), 0) INTO p_minutos_llegada
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL;

    SELECT MAX(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00')) INTO p_llegada_en
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL
      AND  e.timestamp_utc >= IFNULL((SELECT MAX(s.timestamp_utc) FROM evento_campo s
                                      JOIN tabla_maestra ms ON ms.IdMaestro = 29 AND ms.IdEmpresa = 1 AND ms.Num1 = s.id_tipo_evento AND ms.String2 = 'SALIDA_BASE'
                                      WHERE s.id_os = p_id_os AND s.eliminado_en IS NULL), '1000-01-01');

    SELECT d.eta_recalculada INTO p_inicio_vigente
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.tipo = 'ingreso' AND d.eliminado_en IS NULL
    ORDER BY d.id_demora DESC LIMIT 1;
END$$

DELIMITER ;
