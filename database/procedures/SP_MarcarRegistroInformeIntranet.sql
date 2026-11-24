-- ============================================================
-- SP_MarcarRegistroInformeIntranet  (HU-55 — estampa quién registró el informe desde la intranet · escritura)
-- La API la llama después de cada escritura que crea o cambia el informe del equipo (ensayos, cabecera, foto de falla y generar): deja en informe_tecnico
--   id_registrado_por = quien registra (si registraron dos personas en distintos momentos, queda la última), via = 'intranet' y registrado_en = la PRIMERA vez (UTC).
-- El informe sigue a nombre del técnico (id_tecnico no se toca). NO cambia el `origen` de las tablas hijas. Si el equipo aún no tiene informe (p. ej. solo se guardaron las variables
-- ambientales o fotos), no hace nada y responde éxito: la siguiente llamada, cuando el informe exista, lo estampa.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_MarcarRegistroInformeIntranet;

DELIMITER $$

CREATE PROCEDURE SP_MarcarRegistroInformeIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_id_equipo BIGINT DEFAULT NULL;
    DECLARE v_informe   BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_equipo INTO v_id_equipo FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL;
    IF v_id_equipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT it.id_informe INTO v_informe
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    IF v_informe IS NOT NULL THEN
        UPDATE informe_tecnico
        SET    id_registrado_por = p_id_registrador, via = 'intranet', registrado_en = IFNULL(registrado_en, UTC_TIMESTAMP())
        WHERE  id_informe = v_informe;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(v_informe IS NULL, 'El equipo aún no tiene informe: nada que marcar.', 'Informe marcado como registrado desde la intranet.') AS Mensaje;
END$$

DELIMITER ;
