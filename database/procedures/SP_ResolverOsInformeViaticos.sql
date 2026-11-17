-- Ayuda interna (NO es un endpoint): de un informe técnico de la Revisión de Informes saca su orden de servicio, con las mismas reglas de acceso que el detalle del informe
-- (permiso rt_bandeja y el informe dentro del alcance del usuario, SP_ArmarBaseInformes). Si no se puede, devuelve el mensaje en p_msg y p_id_os queda NULL.
DROP PROCEDURE IF EXISTS SP_ResolverOsInformeViaticos;

DELIMITER $$

CREATE PROCEDURE SP_ResolverOsInformeViaticos(
    IN  p_id_usuario BIGINT,
    IN  p_id_informe BIGINT,
    OUT p_id_os      BIGINT,
    OUT p_msg        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SET p_id_os = NULL;
    SET p_msg = NULL;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SET p_msg = 'No tienes permiso para ver la revisión de informes técnicos.';
    ELSEIF IFNULL(p_id_informe, 0) <= 0 THEN
        SET p_msg = 'El informe no existe o no está en tu alcance.';
    ELSE
        CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
        SELECT COUNT(*), MAX(id_os) INTO v_existe, p_id_os FROM tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        IF v_existe = 0 THEN
            SET p_id_os = NULL;
            SET p_msg = 'El informe no existe o no está en tu alcance.';
        ELSEIF p_id_os IS NULL THEN
            SET p_msg = 'El informe no está vinculado a una orden de servicio.';
        END IF;
    END IF;
END$$

DELIMITER ;
