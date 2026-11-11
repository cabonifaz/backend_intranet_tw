-- ============================================================
-- SP_ResumenEvidenciasMovil  (App Mobile HU-11 / HU-08 — apoyo, no es un endpoint)
-- Avance del registro fotográfico de un equipo, UNA sola vez. Lo usan el panel de evidencias y la etapa "Registro fotográfico" del trabajo en el equipo.
--   Evidencia COMPLETA = su última captura (vigente, página 1) está aprobada por la IA, fue forzada por el técnico (HU-12) o no se pudo validar con la IA
--   ("omitida": no cuenta como rechazo). Una toma rechazada y no forzada NO completa la evidencia.
-- Deja la tabla temporal tmp_cat_evid armada, con completa / forzada / rechazada por evidencia (quien llama la borra; HU-16 lista las que faltan). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResumenEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResumenEvidenciasMovil(
    IN  p_id_os          BIGINT,
    IN  p_id_equipo      BIGINT,
    OUT p_total          INT,
    OUT p_completas      INT,
    OUT p_forzadas       INT,
    OUT p_rechazadas     INT,
    OUT p_oblig_faltan   INT
)
BEGIN
    CALL SP_CatalogoEvidenciasMovil();

    -- Última toma vigente (página 1) de cada evidencia: completa = aprobada por la IA, forzada o sin validar ('omitida'); una rechazada y no forzada NO completa
    UPDATE tmp_cat_evid c
    JOIN  (SELECT f2.codigo, MAX(f2.id_evidencia) AS id_ultima
           FROM   evidencia_fotografica f2
           WHERE  f2.id_os = p_id_os AND f2.id_equipo = p_id_equipo AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL
           GROUP BY f2.codigo) u ON u.codigo = c.codigo
    JOIN   evidencia_fotografica f ON f.id_evidencia = u.id_ultima
    SET    c.completa  = IF(f.override_aprobado = 1 OR f.validacion_ia IN ('aprobada', 'omitida'), 1, 0),
           c.forzada   = IF(f.override_aprobado = 1, 1, 0),
           c.rechazada = IF(f.override_aprobado = 0 AND f.validacion_ia = 'rechazada', 1, 0);

    SELECT COUNT(*), IFNULL(SUM(completa), 0), IFNULL(SUM(forzada), 0), IFNULL(SUM(rechazada), 0), IFNULL(SUM(obligatoria = 1 AND completa = 0), 0)
    INTO   p_total, p_completas, p_forzadas, p_rechazadas, p_oblig_faltan
    FROM   tmp_cat_evid;
END$$

DELIMITER ;
