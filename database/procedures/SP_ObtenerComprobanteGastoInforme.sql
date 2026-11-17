-- Comprobante n (1 a 5) de un gasto rendido, para verlo desde la pestaña Viáticos y Gastos del Detalle del Servicio Técnico (Revisión de Informes).
--   Acceso: rt_bandeja y el informe en el alcance del usuario (SP_ResolverOsInformeViaticos). Anti-IDOR: el gasto debe ser un gasto rendido de la OS del informe.
--   n = orden de la foto en gasto_viatico_foto; un gasto antiguo sin fotos en esa tabla tiene solo n = 1 (url_comprobante). Solo devuelve la ruta; la API abre el archivo con autenticación.
-- Resultados: 1 mensaje · 2 ruta (1 fila).
DROP PROCEDURE IF EXISTS SP_ObtenerComprobanteGastoInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerComprobanteGastoInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_n          INT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os BIGINT;
    DECLARE v_n     INT DEFAULT 0;
    DECLARE v_url   VARCHAR(500);
    DECLARE v_ruta  VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverOsInformeViaticos(p_id_usuario, p_id_informe, v_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 OR IFNULL(p_n, 0) NOT BETWEEN 1 AND 5 THEN
        SELECT 1 AS IdTipoMensaje, 'El comprobante indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(g.url_comprobante) INTO v_n, v_url
    FROM gasto_viatico g
    WHERE g.id_gasto = p_id_gasto AND g.id_os = v_id_os AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a la orden de servicio de este informe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT url INTO v_ruta FROM gasto_viatico_foto WHERE id_gasto = p_id_gasto AND orden = p_n AND eliminado_en IS NULL ORDER BY id_foto DESC LIMIT 1;
    IF v_ruta IS NULL AND p_n = 1 AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto WHERE id_gasto = p_id_gasto AND eliminado_en IS NULL) THEN
        SET v_ruta = NULLIF(TRIM(IFNULL(v_url, '')), '');
    END IF;
    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no tiene ese comprobante.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;
