-- ============================================================
-- SP_ArmarAlcanceViaticosMovil  (App Mobile HU-35 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, los servicios (OS) cuyos viáticos y gastos puede ver y operar el jefe, en la tabla temporal `tmp_vi_alc` (id_os). Quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc. Solo lectura.
--   Regla Área + Rol (la misma de SP_ResolverAprobadorMovil y de las aprobaciones de la HU-31):
--     · Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y Administradores → TODOS los servicios.
--     · Supervisor de Servicio Técnico / Metrología → solo los servicios cuya RQ es de su área (area_servicio_rq.area_usuario); un servicio cuya RQ no indica área lo ven
--       todos los jefes (igual que en Aprobaciones).
--     · Usuario / Visor de Servicio Técnico o Metrología (o sin área) → p_sin_jefatura = 1 y ningún servicio.
--   Solo entran servicios con una programación no cancelada (los viáticos cuelgan de la programación).
--   p_id_os NULL → todos los del alcance;  p_id_os dado → solo ese (si está en el alcance), de cualquier fecha.
-- Lo usan: la lista y el detalle de "Viáticos y gastos del equipo", la asignación de viáticos, la revisión de un gasto (SP_RevisarGastoMovil) y el contador del menú de Jefatura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAlcanceViaticosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAlcanceViaticosMovil(
    IN  p_id_usuario   BIGINT,
    IN  p_id_os        BIGINT,
    OUT p_sin_jefatura TINYINT
)
BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_general   TINYINT DEFAULT 0;

    SET p_sin_jefatura = 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
    CREATE TEMPORARY TABLE tmp_vi_alc (id_os BIGINT NOT NULL, PRIMARY KEY (id_os));

    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

    IF IFNULL(v_general, 0) = 0 AND v_area_jefe IS NULL THEN
        SET p_sin_jefatura = 1;
    ELSE
        INSERT INTO tmp_vi_alc (id_os)
        SELECT os.id_os
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  (p_id_os IS NULL OR os.id_os = p_id_os)
          AND  EXISTS (SELECT 1 FROM programacion pr
                       WHERE pr.id_os = os.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL)
          AND  (v_general = 1
                OR NOT EXISTS (SELECT 1
                               FROM   expediente_digital ed
                               JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                               JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                               WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario IS NOT NULL)
                OR EXISTS (SELECT 1
                           FROM   expediente_digital ed
                           JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                           JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                           WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = v_area_jefe));
    END IF;
END$$

DELIMITER ;
