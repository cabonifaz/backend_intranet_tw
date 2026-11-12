-- HU-52 (Sprint 5) Comprobante n (1 a 5) de un gasto rendido, para mostrarlo desde la pestaña Viáticos del Detalle del Servicio en Ruta.
--   Acceso: seg_bandeja. Anti-IDOR: el gasto debe ser un gasto rendido de ESA OS. Solo devuelve la ruta; la API abre el archivo con autenticación.
--   n = orden de la foto en gasto_viatico_foto (migración 114). Un gasto antiguo sin fotos en esa tabla tiene solo n = 1 (url_comprobante).
-- Resultados: 1 mensaje · 2 ruta (1 fila).
DROP PROCEDURE IF EXISTS SP_ObtenerComprobanteGastoServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerComprobanteGastoServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_n          INT
)
proc: BEGIN
    DECLARE v_n    INT DEFAULT 0;
    DECLARE v_url  VARCHAR(500);
    DECLARE v_ruta VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver el seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_gasto, 0) <= 0 OR IFNULL(p_n, 0) NOT BETWEEN 1 AND 5 THEN
        SELECT 1 AS IdTipoMensaje, 'El comprobante indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(g.url_comprobante) INTO v_n, v_url
    FROM gasto_viatico g
    WHERE g.id_gasto = p_id_gasto AND g.id_os = p_id_os AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a este servicio.' AS Mensaje;
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
