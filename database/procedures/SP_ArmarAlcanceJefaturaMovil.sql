-- ============================================================
-- SP_ArmarAlcanceJefaturaMovil  (App Mobile HU-28 / HU-29 / HU-30 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, los servicios (OS) que el jefe puede ver, en la tabla temporal `tmp_jf_alc` (id_os). Quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc. Solo lectura.
--   · Servicio Técnico y Metrología: solo los servicios cuya RQ es de su área (orden_servicio → expediente_digital → requerimiento.id_area
--     → area_servicio_rq.area_usuario = área del jefe).
--   · Las demás áreas (Operaciones, TI, Gerencia, Comercial…) no tienen área en la RQ: ven TODOS los servicios.
--   · p_area NULL (no es jefe) → ningún servicio.
--   p_id_os NULL → los servicios de HOY (fecha de Lima, UTC-5);  p_id_os dado → solo ese servicio (si está en el alcance), de cualquier fecha.
-- Lo usan el menú de Jefatura (contadores), el Panel de Campo, la lista de servicios, el detalle, la ruta y el registro del cambio de estado.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAlcanceJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAlcanceJefaturaMovil(
    IN p_area  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os BIGINT
)
BEGIN
    DECLARE v_hoy DATE;
    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CREATE TEMPORARY TABLE tmp_jf_alc (id_os BIGINT NOT NULL, PRIMARY KEY (id_os));

    INSERT INTO tmp_jf_alc (id_os)
    SELECT os.id_os
    FROM   orden_servicio os
    WHERE  p_area IS NOT NULL
      AND  os.eliminado_en IS NULL
      AND  ((p_id_os IS NULL AND os.fecha_ejecucion = v_hoy) OR os.id_os = p_id_os)
      AND  (p_area NOT IN ('metrologia', 'servicio_tecnico')
            OR EXISTS (SELECT 1
                       FROM   expediente_digital ed
                       JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                       JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                       WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = p_area));
END$$

DELIMITER ;
