-- HU-59 (Sprint 5) Revisión Técnica: modal "Registrar Revisión del Informe" — checklist de cumplimiento automático.
-- Acceso: rt_revisar. Solo informes no revisados del alcance del usuario.
-- Checklist (obligatorio = bloquea "Confirmar Revisión" si no se cumple):
--   fotos          Fotos registradas por el técnico (al menos una)                                  obligatorio
--   ensayos        Ensayos metrológicos completos (sin lecturas sin resultado; "No aplica" si no hay) obligatorio
--   observaciones  Observaciones registradas (informativo)
--   precotizacion  Precotización completada (obligatoria solo si hay observaciones)                  obligatorio
--   procedimiento  Procedimiento ejecutado (al menos un paso realizado)                              obligatorio
-- Resultados: 1 mensaje, 2 cabecera (puede_confirmar, verificados / total e impacto tras el cierre), 3 checklist.
DROP PROCEDURE IF EXISTS SP_PrepararRevisionInforme;

DELIMITER $$

CREATE PROCEDURE SP_PrepararRevisionInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_estado VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_verificados INT DEFAULT 0;
    DECLARE v_total       INT DEFAULT 0;
    DECLARE v_faltan      INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'rt_revisar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar la revisión de informes.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
    SELECT COUNT(*), MAX(estado) INTO v_existe, v_estado FROM tmp_rt_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado IN ('revisado', 'aprobado') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_check;
    CREATE TEMPORARY TABLE tmp_rt_check (
        orden INT, codigo VARCHAR(20), titulo VARCHAR(100), detalle VARCHAR(300), cumple TINYINT, obligatorio TINYINT
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    INSERT INTO tmp_rt_check
    SELECT 1, 'fotos', 'Fotos registradas',
           CONCAT(n_fotos, IF(n_fotos = 1, ' foto subida', ' fotos subidas'), ' por el técnico',
                  IF(n_fotos_validas < n_fotos, CONCAT(' (', n_fotos - n_fotos_validas, ' observadas por la validación)'), '')),
           n_fotos > 0, 1
    FROM tmp_rt_base;
    INSERT INTO tmp_rt_check
    SELECT 2, 'ensayos', 'Ensayos metrológicos completos',
           CASE WHEN n_ensayos = 0 THEN 'No aplica: el informe no registra ensayos'
                ELSE CONCAT_WS(' + ',
                        (SELECT CONCAT('Pesaje (', COUNT(*), ' pts)') FROM informe_ensayo e WHERE e.id_informe = p_id_informe
                           AND e.eliminado_en IS NULL AND e.tipo = 'pesaje' HAVING COUNT(*) > 0),
                        (SELECT CONCAT('Excentricidad (', COUNT(*), ' pos)') FROM informe_ensayo e WHERE e.id_informe = p_id_informe
                           AND e.eliminado_en IS NULL AND e.tipo = 'excentricidad' HAVING COUNT(*) > 0),
                        IF(n_ensayos_sin_resultado > 0, CONCAT(n_ensayos_sin_resultado, ' lecturas sin resultado'), NULL)) END,
           n_ensayos_sin_resultado = 0, 1
    FROM tmp_rt_base;
    INSERT INTO tmp_rt_check
    SELECT 3, 'observaciones', 'Observaciones registradas',
           IF(n_observaciones = 0, 'Sin observaciones',
              CONCAT(n_observaciones, IF(n_observaciones = 1, ' observación (', ' observaciones ('),
                     (SELECT GROUP_CONCAT(o.codigo ORDER BY o.orden, o.id_observacion SEPARATOR ', ') FROM informe_observacion o
                      WHERE o.id_informe = p_id_informe AND o.eliminado_en IS NULL), ')')),
           1, 0
    FROM tmp_rt_base;
    INSERT INTO tmp_rt_check
    SELECT 4, 'precotizacion', 'Precotización completada',
           CASE WHEN n_observaciones = 0 THEN 'No aplica: el servicio no tiene observaciones'
                WHEN IFNULL(n_items_precot, 0) = 0 THEN 'Falta registrar la precotización (el servicio tiene observaciones)'
                ELSE CONCAT(n_items_precot, IF(n_items_precot = 1, ' concepto enviado', ' conceptos enviados'),
                            IF(numero_rq IS NULL, '', CONCAT(' — ', numero_rq))) END,
           n_observaciones = 0 OR IFNULL(n_items_precot, 0) > 0, 1
    FROM tmp_rt_base;
    INSERT INTO tmp_rt_check
    SELECT 5, 'procedimiento', 'Procedimiento ejecutado',
           IF(n_pasos = 0, 'El informe no registra el procedimiento ejecutado',
              CONCAT(n_pasos_realizados, ' / ', n_pasos, ' pasos completados')),
           n_pasos_realizados > 0, 1
    FROM tmp_rt_base;

    SELECT IFNULL(SUM(cumple), 0), COUNT(*), IFNULL(SUM(obligatorio = 1 AND cumple = 0), 0)
      INTO v_verificados, v_total, v_faltan
    FROM tmp_rt_check;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT b.id_informe, b.numero_os, b.razon_social, b.equipo, b.tecnico,
           v_verificados AS verificados, v_total AS total, (v_faltan = 0) AS puede_confirmar,
           'Al confirmar la revisión, el informe quedará cerrado e inmutable.'       AS aviso,
           -- Impacto tras el cierre
           'PDF final inmutable'                                                      AS impacto_informe,
           IF(b.id_precotizacion IS NULL, NULL, 'Auto-envío a Área Comercial')        AS impacto_precotizacion,
           'REVISADO'                                                                 AS impacto_estado,
           CONCAT_WS(' y ', b.tecnico,
                     (SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) FROM usuario u WHERE u.id_usuario = b.id_responsable_rq)) AS impacto_notificacion
    FROM tmp_rt_base b;

    SELECT orden, codigo, titulo, detalle, cumple, obligatorio FROM tmp_rt_check ORDER BY orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
END$$

DELIMITER ;
