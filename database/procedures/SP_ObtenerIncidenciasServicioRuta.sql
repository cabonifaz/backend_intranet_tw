-- HU-52 (Sprint 5) Pestaña "Demoras / Incidencias" (solo de esta OS, de hoy): mini-KPIs, tabla y detalle de un registro. SOLO LECTURA.
-- p_clave (opcional): 'd<id>' demora, 'i<id>' incidencia, 'a<id>' demora registrada por el Asistente (HU-53) o 'c<id>' ensayo y calibración guardado con error crítico (motivo y lecturas fuera del EMP); con clave devuelve solo ese registro con la descripción completa y la foto.
-- Impacto: retrasa | detiene (incidencia crítica = detiene). Origen: tecnico | asistente. La tabla alimenta también la exportación CSV.
-- Momento (demoras de la app): "En ruta (llegar a planta)" o "Ingreso a planta"; Latitud/Longitud = GPS desde donde el técnico la registró.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 filas.
DROP PROCEDURE IF EXISTS SP_ObtenerIncidenciasServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIncidenciasServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NULLIF(p_clave, '') IS NOT NULL AND p_clave NOT REGEXP '^[diac][0-9]{1,18}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El registro indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_clave, '') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tmp_sg_inc i WHERE i.id_os = p_id_os AND i.clave = p_clave) THEN
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El registro no existe en este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT COUNT(*) AS Total, IFNULL(SUM(impacto = 'retrasa'), 0) AS Retrasan, IFNULL(SUM(impacto = 'detiene'), 0) AS Detienen,
           IFNULL(SUM(origen = 'tecnico'), 0) AS PorTecnico, IFNULL(SUM(origen = 'asistente'), 0) AS PorAsistente
    FROM tmp_sg_inc WHERE id_os = p_id_os;

    SELECT i.clave AS Clave, DATE_FORMAT(i.fecha, '%H:%i') AS Hora, i.tipo_codigo AS TipoCodigo, i.tipo AS Tipo,
           IF(NULLIF(p_clave, '') IS NULL, i.descripcion, COALESCE(d.descripcion, n.descripcion, ra.descripcion, (SELECT CONCAT(IFNULL(CONCAT('Equipo ', ec.codigo_tw, CHAR(10)), ''), 'Motivo del técnico: ', it.error_critico_motivo,
                        IFNULL((SELECT CONCAT(CHAR(10), CHAR(10), 'Lecturas fuera del EMP:', CHAR(10),
                                       GROUP_CONCAT(CONCAT('• ', IF(ie.tipo = 'pesaje', 'Pesaje', 'Excentricidad'), ' · ', ie.punto,
                                                           IF(ie.tipo = 'excentricidad' AND ie.grupo IS NOT NULL, CONCAT(' (carga ', ie.grupo, ')'), ''),
                                                           ': carga ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.carga AS CHAR))), '-'), ' kg · lectura ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.lectura AS CHAR))), '-'), ' kg · error ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.error AS CHAR))), '-'),
                                                           ' kg · EMP ±', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.tolerancia AS CHAR))), '-'), ' kg') ORDER BY ie.tipo, ie.orden SEPARATOR '\n'))
                                FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL), ''))
                 FROM informe_tecnico it LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
                 WHERE i.clave = CONCAT('c', it.id_informe)), i.descripcion)) AS Descripcion,
           i.duracion_min AS DuracionMin, i.impacto AS Impacto, i.origen AS Origen, COALESCE((SELECT TRIM(CONCAT(ua.nombre, ' ', ua.apellido)) FROM usuario ua WHERE ua.id_usuario = ra.id_usuario), i.tecnico) AS Registrador,
           IF(NULLIF(p_clave, '') IS NULL, NULL, COALESCE(d.fotografia_url, ra.evidencia_url)) AS Evidencia, IF(COALESCE(d.fotografia_url, ra.evidencia_url) IS NULL, 0, 1) AS TieneEvidencia,
           CASE i.fase WHEN 'llegada' THEN 'En ruta (llegar a planta)' WHEN 'ingreso' THEN 'Ingreso a planta' END AS Momento,
           d.latitud AS Latitud, d.longitud AS Longitud
    FROM tmp_sg_inc i
    LEFT JOIN demora_registro d ON i.clave = CONCAT('d', d.id_demora)
    LEFT JOIN incidencia_operativa n ON i.clave = CONCAT('i', n.id_incidencia)
    LEFT JOIN registro_asistente ra ON i.clave = CONCAT('a', ra.id_registro)
    WHERE i.id_os = p_id_os AND (NULLIF(p_clave, '') IS NULL OR i.clave = p_clave)
    ORDER BY i.fecha DESC, i.clave;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
