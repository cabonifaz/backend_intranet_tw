-- HU-52 (Sprint 5) Pestaña condicional "Cierre del Servicio (HU-54)": resumen OBSERVACIONAL del cierre. Solo si el servicio está FINALIZADO. SOLO LECTURA.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 órdenes de metrología / certificados del servicio.
DROP PROCEDURE IF EXISTS SP_ObtenerCierreServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCierreServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ini    DATETIME;
    DECLARE v_fin    DATETIME;
    DECLARE v_eq     INT;
    DECLARE v_eq_ok  INT;
    DECLARE v_inc    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT estado_seg, COALESCE(inicio_dt, llegada_dt), fin_dt, n_equipos, n_ejecutados INTO v_estado, v_ini, v_fin, v_eq, v_eq_ok FROM tmp_sg_os WHERE id_os = p_id_os;
    SELECT COUNT(*) INTO v_inc FROM tmp_sg_inc WHERE id_os = p_id_os;
    CALL SP_LimpiarSeguimientoOperativo();
    IF v_estado <> 'finalizado' THEN
        SELECT 1 AS IdTipoMensaje, 'El cierre del servicio solo está disponible cuando el servicio finalizó.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT DATE_FORMAT(v_ini, '%H:%i') AS Inicio, DATE_FORMAT(v_fin, '%H:%i') AS Fin,
           IF(v_ini IS NULL OR v_fin IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_ini, v_fin))) AS DuracionMin,
           v_eq AS EquiposTotal, v_eq_ok AS EquiposEjecutados, v_inc AS DemorasIncidencias,
           (SELECT COUNT(*) FROM evidencia_fotografica f WHERE f.id_os = p_id_os AND f.eliminado_en IS NULL) AS Fotos,
           (SELECT COUNT(*) FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om WHERE om.id_os = p_id_os AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL) AS Mediciones,
           (SELECT osr.observaciones FROM orden_servicio osr WHERE osr.id_os = p_id_os) AS Observaciones;
    SELECT om.numero AS Numero, om.estado AS Estado, om.numero_certificado AS Certificado, DATE_FORMAT(om.fecha_emision_certificado, '%Y-%m-%d') AS FechaEmision
    FROM orden_metrologia om WHERE om.id_os = p_id_os AND om.eliminado_en IS NULL ORDER BY om.id_om;
END$$

DELIMITER ;
