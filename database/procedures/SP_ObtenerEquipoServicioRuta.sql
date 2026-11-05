-- HU-52 (Sprint 5) Drill-down de un equipo: sub-pestañas Fotos / Ensayos / Documentos / Observaciones / Mediciones. SOLO LECTURA.
-- p_seccion: fotos | ensayos | documentos | observaciones | mediciones (lista cerrada). El equipo debe pertenecer a la OS (anti-IDOR).
-- Resultados: 1 mensaje · 2 filas con forma común: Id, Titulo, Detalle, Fecha, Url, Resultado, UltimaHaceMin.
DROP PROCEDURE IF EXISTS SP_ObtenerEquipoServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEquipoServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_equipo  BIGINT,
    IN p_seccion    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_equipo, 0) <= 0 OR IFNULL(p_seccion, '') NOT IN ('fotos', 'ensayos', 'documentos', 'observaciones', 'mediciones') THEN
        SELECT 1 AS IdTipoMensaje, 'El equipo o la sección no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LimpiarSeguimientoOperativo();
    IF NOT EXISTS (SELECT 1 FROM os_equipo oe WHERE oe.id_os = p_id_os AND oe.id_equipo = p_id_equipo AND oe.eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    IF p_seccion = 'fotos' THEN
        SELECT f.id_evidencia AS Id, COALESCE(t.String1, 'Foto') AS Titulo, f.validacion_ia AS Detalle,
               DATE_FORMAT(CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00'), '%H:%i') AS Fecha, f.url_archivo AS Url, NULL AS Resultado,
               TIMESTAMPDIFF(MINUTE, f.timestamp_captura, UTC_TIMESTAMP()) AS UltimaHaceMin
        FROM evidencia_fotografica f LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_EVIDENCIA' AND t.Num1 = f.id_tipo_evidencia
        WHERE f.id_os = p_id_os AND f.id_equipo = p_id_equipo AND f.eliminado_en IS NULL ORDER BY f.timestamp_captura DESC, f.id_evidencia DESC LIMIT 200;
    ELSEIF p_seccion = 'ensayos' THEN
        SELECT MIN(mm.id_medicion) AS Id, COALESCE(t.String1, CONCAT('Prueba ', mm.id_tipo_prueba)) AS Titulo,
               CONCAT(COUNT(*), ' mediciones') AS Detalle, DATE_FORMAT(CONVERT_TZ(MAX(mm.creado_en), '+00:00', '-05:00'), '%H:%i') AS Fecha, NULL AS Url,
               IF(SUM(mm.resultado = 'no_cumple') > 0, 'no_cumple', 'cumple') AS Resultado, TIMESTAMPDIFF(MINUTE, MAX(mm.creado_en), UTC_TIMESTAMP()) AS UltimaHaceMin
        FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om AND om.eliminado_en IS NULL
        LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_PRUEBA_METROLOGICA' AND t.Num1 = mm.id_tipo_prueba
        WHERE om.id_os = p_id_os AND mm.id_equipo = p_id_equipo AND mm.eliminado_en IS NULL
        GROUP BY mm.id_tipo_prueba, t.String1 ORDER BY mm.id_tipo_prueba;
    ELSEIF p_seccion = 'documentos' THEN
        SELECT d.id_documento AS Id, COALESCE(t.String1, 'Documento') AS Titulo, d.nombre_archivo AS Detalle,
               DATE_FORMAT(CONVERT_TZ(d.fecha_carga, '+00:00', '-05:00'), '%H:%i') AS Fecha, d.url_archivo AS Url, CONCAT('v', d.version) AS Resultado,
               TIMESTAMPDIFF(MINUTE, d.fecha_carga, UTC_TIMESTAMP()) AS UltimaHaceMin
        FROM documento_adjunto d LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_DOCUMENTO_ADJUNTO' AND t.Num1 = d.id_tipo_documento
        WHERE d.eliminado_en IS NULL AND d.entidad_tipo IN ('orden_servicio', 'orden_metrologia')
          AND ((d.entidad_tipo = 'orden_servicio' AND d.id_entidad = p_id_os)
            OR (d.entidad_tipo = 'orden_metrologia' AND d.id_entidad IN (SELECT om.id_om FROM orden_metrologia om WHERE om.id_os = p_id_os AND om.eliminado_en IS NULL)))
        ORDER BY d.fecha_carga DESC, d.id_documento DESC LIMIT 100;
    ELSEIF p_seccion = 'observaciones' THEN
        SELECT x.Id, x.Titulo, x.Detalle, x.Fecha, NULL AS Url, NULL AS Resultado, x.Min AS UltimaHaceMin FROM (
            SELECT b.id_observacion AS Id, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS Titulo, b.texto AS Detalle,
                   DATE_FORMAT(CONVERT_TZ(b.fecha_utc, '+00:00', '-05:00'), '%H:%i') AS Fecha, TIMESTAMPDIFF(MINUTE, b.fecha_utc, UTC_TIMESTAMP()) AS Min, b.fecha_utc AS f
            FROM os_equipo_observacion b LEFT JOIN usuario u ON u.id_usuario = b.id_usuario
            WHERE b.id_os = p_id_os AND b.id_equipo = p_id_equipo AND b.eliminado_en IS NULL
            UNION ALL
            SELECT 0, 'Observación de ejecución', oe.observacion_ejecucion, DATE_FORMAT(CONVERT_TZ(oe.fecha_ejecucion, '+00:00', '-05:00'), '%H:%i'),
                   TIMESTAMPDIFF(MINUTE, oe.fecha_ejecucion, UTC_TIMESTAMP()), oe.fecha_ejecucion
            FROM os_equipo oe WHERE oe.id_os = p_id_os AND oe.id_equipo = p_id_equipo AND oe.eliminado_en IS NULL AND NULLIF(oe.observacion_ejecucion, '') IS NOT NULL
        ) x ORDER BY x.f DESC LIMIT 100;
    ELSE
        SELECT mm.id_medicion AS Id, CONCAT(COALESCE(t.String1, CONCAT('Prueba ', mm.id_tipo_prueba)), ' #', mm.numero_prueba) AS Titulo,
               CONCAT('Carga ', IFNULL(mm.carga_aplicada, '-'), ' · Lectura ', IFNULL(mm.lectura_instrumento, '-'), ' · Error ', IFNULL(mm.error, '-'), ' · MPE ', IFNULL(mm.tolerancia_mpe, '-')) AS Detalle,
               DATE_FORMAT(CONVERT_TZ(mm.creado_en, '+00:00', '-05:00'), '%H:%i') AS Fecha, NULL AS Url, mm.resultado AS Resultado,
               TIMESTAMPDIFF(MINUTE, mm.creado_en, UTC_TIMESTAMP()) AS UltimaHaceMin
        FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om AND om.eliminado_en IS NULL
        LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_PRUEBA_METROLOGICA' AND t.Num1 = mm.id_tipo_prueba
        WHERE om.id_os = p_id_os AND mm.id_equipo = p_id_equipo AND mm.eliminado_en IS NULL
        ORDER BY mm.creado_en DESC, mm.id_medicion DESC LIMIT 500;
    END IF;
END$$

DELIMITER ;
