-- HU-55: el tab Avance por Equipos trae los 7 datos del botón Registrar informe (+ IdOsEquipo). Ejecutar con Alt+X (No al aviso) y redesplegar la API.
-- Solo reemplaza SP_ObtenerAvanceServicioRuta (solo lectura): agrega columnas al final del 1.er resultado; las existentes no cambian. No toca datos.
-- Generado de database/procedures/SP_ObtenerAvanceServicioRuta.sql.

-- HU-52 (Sprint 5) Pestaña "Avance por Equipos": por equipo, mini-checklist Limpieza → Desmontaje → Pruebas → Montaje → Cierre con hora y estado
-- (pendiente | en_curso | completada) y chips de conteo (fotos, ensayos, certificado preliminar, observaciones, mediciones). SOLO LECTURA.
-- Resultados: 1 mensaje · 2 equipos (una fila por equipo) · 3 etapas (una fila por equipo y etapa; las 5 siempre).
-- Etapas = las 5 del trabajo en el equipo de la app (SP_ArmarEtapasEquipoMovil: Variables ambientales · Registro fotográfico · Ensayos y Calibración · Cabecera del informe · Correlativo y certificado),
-- con su estado (pendiente · en_curso · completada · observada · bloqueada) y el detalle de lo que lleva (p. ej. «0 de 9 · incluye foto del informe a mano»); se recalculan en cada consulta (tiempo real).
-- Los chips de Ensayos / Observaciones / Mediciones también cuentan lo que el técnico guarda en la app (informe_ensayo, informe_observacion).
-- HU-55 (24/11): cada equipo trae también InformeGenerado/NumeroInforme, RegistroActivo/RegistradorId/RegistradorNombre/RegistroPropio (bloqueo de 30 min) y OtroEquipoAbierto
-- (otro equipo del técnico en ejecución), más IdOsEquipo (el id que usan los endpoints de registro). RegistroPropio se compara con p_id_usuario.
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
    DECLARE v_limite  DATETIME;
    DECLARE v_tecnico BIGINT DEFAULT NULL;
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

    SET v_limite = UTC_TIMESTAMP() - INTERVAL 30 MINUTE;
    SELECT os.id_tecnico_principal INTO v_tecnico FROM orden_servicio os WHERE os.id_os = p_id_os;

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
              FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Minutos,
           -- HU-55: lo que necesita el botón "Registrar informe" (mismas reglas que SP_ContextoRegistroIntranet)
           IF(inf.generado_en IS NULL, 0, 1) AS InformeGenerado, IF(inf.generado_en IS NULL, NULL, inf.numero_informe) AS NumeroInforme,
           IF(reg.id_registrador IS NULL, 0, 1) AS RegistroActivo, reg.id_registrador AS RegistradorId,
           IF(reg.id_registrador IS NULL, NULL, NULLIF(TRIM(CONCAT(IFNULL(ur.nombre, ''), ' ', IFNULL(ur.apellido, ''))), '')) AS RegistradorNombre,
           IF(reg.id_registrador = p_id_usuario, 1, 0) AS RegistroPropio,
           (SELECT CONCAT(IFNULL(NULLIF(ec2.codigo_cliente, ''), ec2.codigo_tw), ' (', o2.numero, ')')
              FROM os_equipo x JOIN equipo_cliente ec2 ON ec2.id_equipo = x.id_equipo JOIN orden_servicio o2 ON o2.id_os = x.id_os
             WHERE v_tecnico IS NOT NULL AND x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
               AND x.id <> oe.id AND x.eliminado_en IS NULL LIMIT 1) AS OtroEquipoAbierto,
           oe.id AS IdOsEquipo
    FROM os_equipo oe JOIN (SELECT ec.id_equipo, ec.codigo_tw, ec.modelo, ec.num_serie AS numero_serie, ec.estado_operativo FROM equipo_cliente ec) e ON e.id_equipo = oe.id_equipo
    LEFT JOIN informe_tecnico inf ON inf.id_informe = (SELECT i3.id_informe FROM informe_tecnico i3 WHERE i3.id_os = oe.id_os AND i3.id_equipo = oe.id_equipo AND i3.eliminado_en IS NULL
                                                        ORDER BY i3.id_informe DESC LIMIT 1)
    LEFT JOIN registro_informe_intranet reg ON reg.id_registro = (SELECT r3.id_registro FROM registro_informe_intranet r3 WHERE r3.id_os_equipo = oe.id AND r3.estado = 'activo'
                                                                  ORDER BY r3.id_registro DESC LIMIT 1)
                                            AND reg.ultima_actividad >= v_limite
    LEFT JOIN usuario ur ON ur.id_usuario = reg.id_registrador
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

-- Verificación (no crea nada): debe dar 1

SELECT COUNT(*) AS sp_actualizado FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerAvanceServicioRuta' AND ROUTINE_DEFINITION LIKE '%OtroEquipoAbierto%';
