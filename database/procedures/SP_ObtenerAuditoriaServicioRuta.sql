-- HU-54 (Sprint 5) "Auditoría del servicio" del cierre: historial completo del servicio para auditoría (acciones auditadas de la OS y los hitos del técnico). SOLO LECTURA.
-- Solo si el servicio está FINALIZADO. Permiso seg_bandeja y servicio de la jornada de hoy (igual que el resto del detalle).
-- Resultados: 1 mensaje · 2 filas (Fecha, Origen: auditoria|hito, Accion, Usuario, Descripcion), más recientes primero, máx. 300.
DROP PROCEDURE IF EXISTS SP_ObtenerAuditoriaServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAuditoriaServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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
    SELECT estado_seg INTO v_estado FROM tmp_sg_os WHERE id_os = p_id_os;
    CALL SP_LimpiarSeguimientoOperativo();
    IF v_estado <> 'finalizado' THEN
        SELECT 1 AS IdTipoMensaje, 'La auditoría del cierre solo está disponible cuando el servicio finalizó.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT DATE_FORMAT(x.fecha, '%Y-%m-%d %H:%i:%s') AS Fecha, x.origen AS Origen, x.accion AS Accion, x.usuario AS Usuario, x.descripcion AS Descripcion
    FROM (
        SELECT CONVERT_TZ(a.registrado_en, '+00:00', '-05:00') AS fecha, 'auditoria' AS origen, a.accion AS accion,
               (SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) FROM usuario u WHERE u.id_usuario = a.id_usuario) AS usuario, LEFT(a.descripcion, 400) AS descripcion
        FROM auditoria_evento a WHERE a.entidad_tipo = 'orden_servicio' AND a.id_entidad = p_id_os
        UNION ALL
        SELECT CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'), 'hito', m.String2,
               (SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) FROM usuario u WHERE u.id_usuario = e.id_usuario), LEFT(IFNULL(e.notas, m.String1), 400)
        FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
        WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL
    ) x ORDER BY x.fecha DESC, x.accion LIMIT 300;
END$$

DELIMITER ;
