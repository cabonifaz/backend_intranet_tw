-- Observaciones que se registraron durante el servicio en el Seguimiento Operativo, para la pestaña Observaciones del Detalle del Servicio Técnico (Revisión de Informes). SOLO LECTURA.
--   asistente  notas del Asistente en «Registrar › Observación» (registro_asistente, modo observacion) con su fuente (llamada, WhatsApp, contacto en planta, observación directa)
--   equipo     observaciones guardadas sobre el equipo del informe en esa OS (os_equipo_observacion)
--   ejecucion  observación de ejecución del equipo (os_equipo.observacion_ejecucion)
-- Acceso: rt_bandeja y el informe en el alcance del usuario (SP_ResolverOsInformeViaticos). Resultados: 1 mensaje · 2 filas (clave, origen, registrador, fuente, texto, fecha en hora de Lima), la más reciente primero.
DROP PROCEDURE IF EXISTS SP_ObtenerObservacionesSeguimientoInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerObservacionesSeguimientoInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os     BIGINT;
    DECLARE v_id_equipo BIGINT DEFAULT NULL;

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
    SELECT it.id_equipo INTO v_id_equipo FROM informe_tecnico it WHERE it.id_informe = p_id_informe;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT x.clave, x.origen, x.registrador, x.fuente, x.texto, x.fecha
    FROM (
        SELECT CONCAT('a', ra.id_registro) AS clave, 'asistente' AS origen,
               NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS registrador,
               CASE ra.fuente WHEN 'llamada_telefonica' THEN 'Llamada telefónica' WHEN 'whatsapp' THEN 'WhatsApp'
                              WHEN 'contacto_planta' THEN 'Contacto en planta' WHEN 'observacion_directa' THEN 'Observación directa' ELSE NULL END AS fuente,
               ra.descripcion AS texto, CONVERT_TZ(ra.fecha_utc, '+00:00', '-05:00') AS fecha
        FROM   registro_asistente ra
        LEFT JOIN usuario u ON u.id_usuario = ra.id_usuario
        WHERE  ra.id_os = v_id_os AND ra.modo = 'observacion'
        UNION ALL
        SELECT CONCAT('e', b.id_observacion), 'equipo',
               COALESCE(NULLIF(TRIM(CONCAT(IFNULL(u2.nombre, ''), ' ', IFNULL(u2.apellido, ''))), ''), 'Técnico'),
               'Observación del equipo', b.texto, CONVERT_TZ(b.fecha_utc, '+00:00', '-05:00')
        FROM   os_equipo_observacion b
        LEFT JOIN usuario u2 ON u2.id_usuario = b.id_usuario
        WHERE  b.id_os = v_id_os AND b.id_equipo = v_id_equipo AND b.eliminado_en IS NULL
        UNION ALL
        SELECT 'x0', 'ejecucion', 'Técnico', 'Observación de ejecución', oe.observacion_ejecucion, CONVERT_TZ(oe.fecha_ejecucion, '+00:00', '-05:00')
        FROM   os_equipo oe
        WHERE  oe.id_os = v_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL AND NULLIF(oe.observacion_ejecucion, '') IS NOT NULL
    ) x
    ORDER BY x.fecha DESC, x.clave;
END$$

DELIMITER ;
