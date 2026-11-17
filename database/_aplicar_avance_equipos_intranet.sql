-- Avance por equipos en la intranet: etapas reales de la app, detalle y fotos. Ejecutar con Alt+X (No al aviso) y redesplegar la API.
-- Objetivos VISIBLES de cada OS (os_equipo): una fila (id_os_equipo) por cada equipo que ve el técnico en la lista de objetivos de la app.
-- Misma regla que SP_ArmarObjetivosMovil (si se cambia una, cambiar la otra): se ve si lo registró el técnico en campo (ingresado_en_campo = 1), si la programación
-- vigente de la OS no elige equipos (se trabajan todos) o si está entre los equipos de esa programación.
-- La usan los detalles de la intranet (Avance por equipos, detalle del servicio y contadores del seguimiento) para mostrar los mismos equipos que la app.
-- Es una vista (no una función) porque crear funciones exige el privilegio SUPER cuando el log binario está activo.
CREATE OR REPLACE VIEW vw_objetivo_visible AS
SELECT oe.id AS id_os_equipo
FROM   os_equipo oe
WHERE  oe.ingresado_en_campo = 1
   OR  NOT EXISTS (SELECT 1 FROM programacion_equipo pe
                   WHERE  pe.eliminado_en IS NULL
                     AND  pe.id_programacion = (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                WHERE  pr.id_os = oe.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL))
   OR  EXISTS     (SELECT 1 FROM programacion_equipo pe
                   WHERE  pe.eliminado_en IS NULL AND pe.id_equipo = oe.id_equipo
                     AND  pe.id_programacion = (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                WHERE  pr.id_os = oe.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL));

-- HU-52 (Sprint 5) Pestaña "Avance por Equipos": por equipo, mini-checklist Limpieza → Desmontaje → Pruebas → Montaje → Cierre con hora y estado
-- (pendiente | en_curso | completada) y chips de conteo (fotos, ensayos, certificado preliminar, observaciones, mediciones). SOLO LECTURA.
-- Resultados: 1 mensaje · 2 equipos (una fila por equipo) · 3 etapas (una fila por equipo y etapa; las 5 siempre).
-- Etapas = las 5 del trabajo en el equipo de la app (SP_ArmarEtapasEquipoMovil: Variables ambientales · Registro fotográfico · Ensayos y Calibración · Cabecera del informe · Correlativo y certificado),
-- con su estado (pendiente · en_curso · completada · observada · bloqueada) y el detalle de lo que lleva (p. ej. «0 de 9 · incluye foto del informe a mano»); se recalculan en cada consulta (tiempo real).
-- Los chips de Ensayos / Observaciones / Mediciones también cuentan lo que el técnico guarda en la app (informe_ensayo, informe_observacion).
-- Fix 06/11: los equipos de la OS son de equipo_cliente (os_equipo.id_equipo), no de la tabla equipo (activos TW).
DROP PROCEDURE IF EXISTS SP_ObtenerAvanceServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAvanceServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora DATETIME;
    DECLARE v_fin   TINYINT DEFAULT 0;
    DECLARE v_eq    BIGINT;
    DECLARE v_conf  INT DEFAULT 0;
    DECLARE c_eq CURSOR FOR
        SELECT oe.id_equipo FROM os_equipo oe
        WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = oe.id)
        ORDER BY oe.orden, oe.id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

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
    CALL SP_LimpiarSeguimientoOperativo();
    SET v_ahora = CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00');

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT e.id_equipo AS IdEquipo, e.codigo_tw AS Codigo, e.modelo AS Modelo, e.numero_serie AS Serie, oe.estado_ejecucion AS Estado,
           (SELECT COUNT(*) FROM evidencia_fotografica f WHERE f.id_os = oe.id_os AND f.id_equipo = oe.id_equipo AND f.eliminado_en IS NULL) AS Fotos,
           (SELECT COUNT(DISTINCT mm.id_tipo_prueba) FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om
             WHERE om.id_os = oe.id_os AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL)
             + (SELECT COUNT(DISTINCT ie.tipo) FROM informe_ensayo ie WHERE ie.eliminado_en IS NULL AND ie.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = oe.id_os AND i2.id_equipo = oe.id_equipo AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)) AS Ensayos,
           (SELECT COUNT(*) FROM orden_metrologia om WHERE om.id_os = oe.id_os AND om.eliminado_en IS NULL AND om.estado IN ('pendiente_certificado', 'finalizada')
               AND EXISTS (SELECT 1 FROM medicion_metrologica mm WHERE mm.id_om = om.id_om AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL)) AS CertificadoPreliminar,
           (SELECT COUNT(*) FROM os_equipo_observacion b WHERE b.id_os = oe.id_os AND b.id_equipo = oe.id_equipo AND b.eliminado_en IS NULL)
             + IF(NULLIF(oe.observacion_ejecucion, '') IS NULL, 0, 1)
             + (SELECT COUNT(*) FROM informe_observacion io WHERE io.eliminado_en IS NULL AND io.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = oe.id_os AND i2.id_equipo = oe.id_equipo AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)) AS Observaciones,
           (SELECT COUNT(*) FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om
             WHERE om.id_os = oe.id_os AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL)
             + (SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.eliminado_en IS NULL AND ie.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = oe.id_os AND i2.id_equipo = oe.id_equipo AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)) AS Mediciones,
           (SELECT DATE_FORMAT(CONVERT_TZ(MIN(g.inicio_utc), '+00:00', '-05:00'), '%H:%i') FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Iniciado,
           (SELECT DATE_FORMAT(CONVERT_TZ(MAX(g.fin_utc), '+00:00', '-05:00'), '%H:%i') FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL
              AND oe.estado_ejecucion = 'ejecutado') AS Finalizado,
           (SELECT IF(MIN(g.inicio_utc) IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, MIN(g.inicio_utc),
                      IF(oe.estado_ejecucion = 'ejecutado', MAX(g.fin_utc), UTC_TIMESTAMP()))))
              FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Minutos
    FROM os_equipo oe JOIN (SELECT ec.id_equipo, ec.codigo_tw, ec.modelo, ec.num_serie AS numero_serie, ec.estado_operativo FROM equipo_cliente ec) e ON e.id_equipo = oe.id_equipo
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = oe.id)   -- mismos equipos que ve el técnico en la app
    ORDER BY oe.orden, oe.id;

    -- Etapas reales de cada equipo (las mismas que ve el técnico en la app)
    DROP TEMPORARY TABLE IF EXISTS tmp_av_etapas;
    CREATE TEMPORARY TABLE tmp_av_etapas (
        id_equipo BIGINT NOT NULL, orden INT NOT NULL, etapa VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id_equipo, orden));
    SET v_fin = 0;
    OPEN c_eq;
    lazo: LOOP
        FETCH c_eq INTO v_eq;
        IF v_fin = 1 THEN LEAVE lazo; END IF;
        CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_eq, v_conf);
        SET v_fin = 0;   -- un aviso interno del cálculo de etapas no debe cortar el recorrido de equipos
        INSERT IGNORE INTO tmp_av_etapas (id_equipo, orden, etapa, estado, detalle)
        SELECT v_eq, e.orden, e.nombre,
               CASE e.estado WHEN 'conforme' THEN 'completada' WHEN 'en_curso' THEN 'en_curso' WHEN 'no_conforme' THEN 'observada'
                             WHEN 'notificado' THEN 'observada' WHEN 'bloqueado' THEN 'bloqueada' ELSE 'pendiente' END,
               e.detalle
        FROM tmp_etapas_mov e;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    END LOOP;
    CLOSE c_eq;

    SELECT a.id_equipo AS IdEquipo, a.etapa AS Etapa, a.orden AS Orden, a.estado AS Estado, NULL AS Hora, a.detalle AS Detalle
    FROM tmp_av_etapas a
    ORDER BY a.id_equipo, a.orden;
    DROP TEMPORARY TABLE IF EXISTS tmp_av_etapas;
END$$

DELIMITER ;

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
