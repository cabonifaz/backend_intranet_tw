-- ============================================================
-- SP_ObtenerFotoGastoMovil  (App Mobile HU-27 — foto n de un gasto del propio técnico · lectura)
-- El técnico sale del token: solo sus gastos. n = orden de la foto (1 a 5). Si el gasto no tiene fotos en gasto_viatico_foto (gasto anterior a la
-- migración 114), n = 1 es url_comprobante. Resultados: 1 mensaje · 2 ruta (1 fila).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFotoGastoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFotoGastoMovil(
    IN p_id_usuario BIGINT,
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

    IF IFNULL(p_id_gasto, 0) <= 0 OR IFNULL(p_n, 0) NOT BETWEEN 1 AND 5 THEN
        SELECT 1 AS IdTipoMensaje, 'La foto indicada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(url_comprobante) INTO v_n, v_url
    FROM gasto_viatico
    WHERE id_gasto = p_id_gasto AND id_usuario = p_id_usuario AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT url INTO v_ruta FROM gasto_viatico_foto WHERE id_gasto = p_id_gasto AND orden = p_n AND eliminado_en IS NULL ORDER BY id_foto DESC LIMIT 1;
    IF v_ruta IS NULL AND p_n = 1 AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto WHERE id_gasto = p_id_gasto AND eliminado_en IS NULL) THEN
        SET v_ruta = NULLIF(TRIM(IFNULL(v_url, '')), '');
    END IF;
    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no tiene esa foto.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;
