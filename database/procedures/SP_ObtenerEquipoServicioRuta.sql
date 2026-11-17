-- HU-52 (Sprint 5) Drill-down de un equipo: sub-pestañas Fotos / Ensayos / Documentos / Observaciones / Mediciones. SOLO LECTURA.
-- p_seccion: fotos | ensayos | documentos | observaciones | mediciones (lista cerrada). El equipo debe pertenecer a la OS (anti-IDOR).
-- Resultados: 1 mensaje · 2 filas con forma común: Id, Titulo, Detalle, Fecha, Url, Resultado, UltimaHaceMin, IdEvidencia.
-- Incluye lo que el técnico guarda en la app: fotos del registro fotográfico y de las fallas (evidencia_fotografica; IdEvidencia sirve para pedir la imagen),
-- ensayos y lecturas de pesaje / excentricidad (informe_ensayo) y las fallas de la cabecera del informe (informe_observacion, con su foto). Los ids negativos son del informe
-- (no chocan con los de la metrología).
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
        SELECT f.id_evidencia AS Id,
               COALESCE(t.String1, CASE f.codigo WHEN 'qr' THEN 'QR del equipo' WHEN 'placa' THEN 'Placa del equipo' WHEN 'informe' THEN 'Informe a mano' WHEN 'falla' THEN 'Falla del informe' ELSE 'Foto' END) AS Titulo,
               CONCAT_WS(' · ', IF(f.override_aprobado = 1, 'Forzada por el técnico', NULL), f.validacion_ia) AS Detalle,
               DATE_FORMAT(CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00'), '%H:%i') AS Fecha, f.url_archivo AS Url, NULL AS Resultado,
               TIMESTAMPDIFF(MINUTE, f.timestamp_captura, UTC_TIMESTAMP()) AS UltimaHaceMin, f.id_evidencia AS IdEvidencia
        FROM evidencia_fotografica f LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_EVIDENCIA' AND t.Num1 = f.id_tipo_evidencia
        WHERE f.id_os = p_id_os AND f.id_equipo = p_id_equipo AND f.eliminado_en IS NULL AND IFNULL(f.vigente, 1) = 1
        ORDER BY f.timestamp_captura DESC, f.id_evidencia DESC LIMIT 200;
    ELSEIF p_seccion = 'ensayos' THEN
        SELECT x.Id, x.Titulo, x.Detalle, x.Fecha, x.Url, x.Resultado, x.UltimaHaceMin, NULL AS IdEvidencia FROM (
            SELECT MIN(mm.id_medicion) AS Id, COALESCE(t.String1, CONCAT('Prueba ', mm.id_tipo_prueba)) AS Titulo,
                   CONCAT(COUNT(*), ' mediciones') AS Detalle, DATE_FORMAT(CONVERT_TZ(MAX(mm.creado_en), '+00:00', '-05:00'), '%H:%i') AS Fecha, NULL AS Url,
                   IF(SUM(mm.resultado = 'no_cumple') > 0, 'no_cumple', 'cumple') AS Resultado, TIMESTAMPDIFF(MINUTE, MAX(mm.creado_en), UTC_TIMESTAMP()) AS UltimaHaceMin
            FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om AND om.eliminado_en IS NULL
            LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_PRUEBA_METROLOGICA' AND t.Num1 = mm.id_tipo_prueba
            WHERE om.id_os = p_id_os AND mm.id_equipo = p_id_equipo AND mm.eliminado_en IS NULL
            GROUP BY mm.id_tipo_prueba, t.String1
            UNION ALL
            SELECT -MIN(ie.id_ensayo), IF(ie.tipo = 'pesaje', 'Pesaje', 'Excentricidad'),
                   CONCAT(COUNT(*), IF(COUNT(*) = 1, ' lectura', ' lecturas'), IF(SUM(ie.resultado = 'no_conforme') > 0, ' · hay lecturas fuera del EMP', ' · todas dentro del EMP')),
                   DATE_FORMAT(CONVERT_TZ(MAX(ie.creado_en), '+00:00', '-05:00'), '%H:%i'), NULL,
                   IF(SUM(ie.resultado = 'no_conforme') > 0, 'no_cumple', 'cumple'), TIMESTAMPDIFF(MINUTE, MAX(ie.creado_en), UTC_TIMESTAMP())
            FROM informe_ensayo ie
            WHERE ie.eliminado_en IS NULL AND ie.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = p_id_os AND i2.id_equipo = p_id_equipo AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)
            GROUP BY ie.tipo
        ) x ORDER BY x.Titulo;
    ELSEIF p_seccion = 'documentos' THEN
        SELECT d.id_documento AS Id, COALESCE(t.String1, 'Documento') AS Titulo, d.nombre_archivo AS Detalle,
               DATE_FORMAT(CONVERT_TZ(d.fecha_carga, '+00:00', '-05:00'), '%H:%i') AS Fecha, d.url_archivo AS Url, CONCAT('v', d.version) AS Resultado,
               TIMESTAMPDIFF(MINUTE, d.fecha_carga, UTC_TIMESTAMP()) AS UltimaHaceMin, NULL AS IdEvidencia
        FROM documento_adjunto d LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_DOCUMENTO_ADJUNTO' AND t.Num1 = d.id_tipo_documento
        WHERE d.eliminado_en IS NULL AND d.entidad_tipo IN ('orden_servicio', 'orden_metrologia')
          AND ((d.entidad_tipo = 'orden_servicio' AND d.id_entidad = p_id_os)
            OR (d.entidad_tipo = 'orden_metrologia' AND d.id_entidad IN (SELECT om.id_om FROM orden_metrologia om WHERE om.id_os = p_id_os AND om.eliminado_en IS NULL)))
        ORDER BY d.fecha_carga DESC, d.id_documento DESC LIMIT 100;
    ELSEIF p_seccion = 'observaciones' THEN
        SELECT x.Id, x.Titulo, x.Detalle, x.Fecha, NULL AS Url, x.Resultado, x.Min AS UltimaHaceMin, x.IdEvidencia FROM (
            SELECT b.id_observacion AS Id, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS Titulo, b.texto AS Detalle,
                   DATE_FORMAT(CONVERT_TZ(b.fecha_utc, '+00:00', '-05:00'), '%H:%i') AS Fecha, NULL AS Resultado,
                   TIMESTAMPDIFF(MINUTE, b.fecha_utc, UTC_TIMESTAMP()) AS Min, b.fecha_utc AS f, NULL AS IdEvidencia
            FROM os_equipo_observacion b LEFT JOIN usuario u ON u.id_usuario = b.id_usuario
            WHERE b.id_os = p_id_os AND b.id_equipo = p_id_equipo AND b.eliminado_en IS NULL
            UNION ALL
            SELECT 0, 'Observación de ejecución', oe.observacion_ejecucion, DATE_FORMAT(CONVERT_TZ(oe.fecha_ejecucion, '+00:00', '-05:00'), '%H:%i'), NULL,
                   TIMESTAMPDIFF(MINUTE, oe.fecha_ejecucion, UTC_TIMESTAMP()), oe.fecha_ejecucion, NULL
            FROM os_equipo oe WHERE oe.id_os = p_id_os AND oe.id_equipo = p_id_equipo AND oe.eliminado_en IS NULL AND NULLIF(oe.observacion_ejecucion, '') IS NOT NULL
            UNION ALL
            SELECT -io.id_observacion, io.titulo,
                   CONCAT_WS(' · ', NULLIF(io.descripcion, ''), IF(NULLIF(io.ubicacion, '') IS NULL, NULL, CONCAT('Ubicación: ', io.ubicacion)),
                             IF(io.nivel_afectacion IS NULL, NULL, CONCAT('Nivel: ', io.nivel_afectacion))),
                   DATE_FORMAT(CONVERT_TZ(io.creado_en, '+00:00', '-05:00'), '%H:%i'), io.nivel_afectacion,
                   TIMESTAMPDIFF(MINUTE, io.creado_en, UTC_TIMESTAMP()), io.creado_en, io.id_evidencia
            FROM informe_observacion io
            WHERE io.eliminado_en IS NULL AND io.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = p_id_os AND i2.id_equipo = p_id_equipo AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)
        ) x ORDER BY x.f DESC LIMIT 100;
    ELSE
        SELECT x.Id, x.Titulo, x.Detalle, x.Fecha, x.Url, x.Resultado, x.UltimaHaceMin, NULL AS IdEvidencia FROM (
            SELECT mm.id_medicion AS Id, CONCAT(COALESCE(t.String1, CONCAT('Prueba ', mm.id_tipo_prueba)), ' #', mm.numero_prueba) AS Titulo,
                   CONCAT('Carga ', IFNULL(mm.carga_aplicada, '-'), ' · Lectura ', IFNULL(mm.lectura_instrumento, '-'), ' · Error ', IFNULL(mm.error, '-'), ' · MPE ', IFNULL(mm.tolerancia_mpe, '-')) AS Detalle,
                   DATE_FORMAT(CONVERT_TZ(mm.creado_en, '+00:00', '-05:00'), '%H:%i') AS Fecha, NULL AS Url, mm.resultado AS Resultado,
                   TIMESTAMPDIFF(MINUTE, mm.creado_en, UTC_TIMESTAMP()) AS UltimaHaceMin, mm.creado_en AS f
            FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om AND om.eliminado_en IS NULL
            LEFT JOIN tabla_maestra t ON t.IdEmpresa = 1 AND t.Descripcion = 'TIPO_PRUEBA_METROLOGICA' AND t.Num1 = mm.id_tipo_prueba
            WHERE om.id_os = p_id_os AND mm.id_equipo = p_id_equipo AND mm.eliminado_en IS NULL
            UNION ALL
            SELECT -ie.id_ensayo,
                   CONCAT(IF(ie.tipo = 'pesaje', 'Pesaje', 'Excentricidad'), ' · ', ie.punto, IF(ie.tipo = 'excentricidad' AND ie.grupo IS NOT NULL, CONCAT(' (carga ', ie.grupo, ')'), '')),
                   CONCAT('Carga ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.carga AS CHAR))), '-'),
                          ' · Lectura ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.lectura AS CHAR))), '-'),
                          ' · Error ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.error AS CHAR))), '-'),
                          ' · EMP ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.tolerancia AS CHAR))), '-')),
                   DATE_FORMAT(CONVERT_TZ(ie.creado_en, '+00:00', '-05:00'), '%H:%i'), NULL, IF(ie.resultado = 'no_conforme', 'no_cumple', 'cumple'),
                   TIMESTAMPDIFF(MINUTE, ie.creado_en, UTC_TIMESTAMP()), ie.creado_en
            FROM informe_ensayo ie
            WHERE ie.eliminado_en IS NULL AND ie.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = p_id_os AND i2.id_equipo = p_id_equipo AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)
        ) x ORDER BY x.f DESC, x.Id DESC LIMIT 500;
    END IF;
END$$

DELIMITER ;
