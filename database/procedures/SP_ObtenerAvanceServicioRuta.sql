-- HU-52 (Sprint 5) Pestaña "Avance por Equipos": por equipo, mini-checklist Limpieza → Desmontaje → Pruebas → Montaje → Cierre con hora y estado
-- (pendiente | en_curso | completada) y chips de conteo (fotos, ensayos, certificado preliminar, observaciones, mediciones). SOLO LECTURA.
-- Resultados: 1 mensaje · 2 equipos (una fila por equipo) · 3 etapas (una fila por equipo y etapa; las 5 siempre).
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
             WHERE om.id_os = oe.id_os AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL) AS Ensayos,
           (SELECT COUNT(*) FROM orden_metrologia om WHERE om.id_os = oe.id_os AND om.eliminado_en IS NULL AND om.estado IN ('pendiente_certificado', 'finalizada')
               AND EXISTS (SELECT 1 FROM medicion_metrologica mm WHERE mm.id_om = om.id_om AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL)) AS CertificadoPreliminar,
           (SELECT COUNT(*) FROM os_equipo_observacion b WHERE b.id_os = oe.id_os AND b.id_equipo = oe.id_equipo AND b.eliminado_en IS NULL)
             + IF(NULLIF(oe.observacion_ejecucion, '') IS NULL, 0, 1) AS Observaciones,
           (SELECT COUNT(*) FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om
             WHERE om.id_os = oe.id_os AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL) AS Mediciones,
           (SELECT DATE_FORMAT(CONVERT_TZ(MIN(g.inicio_utc), '+00:00', '-05:00'), '%H:%i') FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Iniciado,
           (SELECT DATE_FORMAT(CONVERT_TZ(MAX(g.fin_utc), '+00:00', '-05:00'), '%H:%i') FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL
              AND oe.estado_ejecucion = 'ejecutado') AS Finalizado,
           (SELECT IF(MIN(g.inicio_utc) IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, MIN(g.inicio_utc),
                      IF(oe.estado_ejecucion = 'ejecutado', MAX(g.fin_utc), UTC_TIMESTAMP()))))
              FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Minutos
    FROM os_equipo oe JOIN (SELECT ec.id_equipo, ec.codigo_tw, ec.modelo, ec.num_serie AS numero_serie, ec.estado_operativo FROM equipo_cliente ec) e ON e.id_equipo = oe.id_equipo
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    ORDER BY oe.orden, oe.id;

    SELECT oe.id_equipo AS IdEquipo, s.etapa AS Etapa, s.n AS Orden,
           CASE WHEN g.fin_utc IS NOT NULL THEN 'completada' WHEN g.inicio_utc IS NOT NULL THEN 'en_curso' ELSE 'pendiente' END AS Estado,
           DATE_FORMAT(CONVERT_TZ(COALESCE(g.fin_utc, g.inicio_utc), '+00:00', '-05:00'), '%H:%i') AS Hora
    FROM os_equipo oe
    JOIN (SELECT 1 AS n, 'limpieza' AS etapa UNION ALL SELECT 2, 'desmontaje' UNION ALL SELECT 3, 'pruebas' UNION ALL SELECT 4, 'montaje' UNION ALL SELECT 5, 'cierre') s
    LEFT JOIN os_equipo_etapa g ON g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.etapa = s.etapa AND g.eliminado_en IS NULL
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    ORDER BY oe.orden, oe.id, s.n;
END$$

DELIMITER ;
