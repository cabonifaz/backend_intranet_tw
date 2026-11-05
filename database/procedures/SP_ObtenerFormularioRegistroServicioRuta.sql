-- HU-53 (Sprint 5) Datos para armar la pestaña "Registrar" del detalle del servicio. SOLO LECTURA. Permiso seg_bandeja (ver); PuedeRegistrar indica si además tiene seg_registrar.
-- Resultados: 1 mensaje · 2 contexto (1 fila: quién registra, hora actual de Lima, servicio, estado actual y nivel) · 3 tipos de demora/incidente
--   · 4 motivos del cambio manual · 5 estados (Codigo, Nombre, Nivel, Permitido) · 6 eventos vinculables del día (Clave, Hora, Titulo)
--   · 7 "Mis registros de hoy" del usuario en este servicio (IdRegistro, Modo, Hora, Texto, Fuente, Badge, HaceMin).
-- Requiere la migración 92.
DROP PROCEDURE IF EXISTS SP_ObtenerFormularioRegistroServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFormularioRegistroServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora     DATETIME;
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_ini_utc   DATETIME;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nivel     INT DEFAULT 0;

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
    SELECT ahora, ahora_utc, ini_utc INTO v_ahora, v_ahora_utc, v_ini_utc FROM tmp_sg_cfg LIMIT 1;
    SELECT os_estado, numero, tecnico INTO v_estado, v_numero, v_tecnico FROM tmp_sg_os WHERE id_os = p_id_os;
    CALL SP_LimpiarSeguimientoOperativo();

    SET v_nivel = CASE v_estado
        WHEN 'en_ejecucion' THEN 5 WHEN 'pausada' THEN 5 WHEN 'finalizada' THEN 6
        WHEN 'en_ruta' THEN
            CASE WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                              WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'INGRESO_PLANTA') THEN 4
                 WHEN (SELECT hora_llegada_real FROM orden_servicio WHERE id_os = p_id_os) IS NOT NULL THEN 3
                 WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                              WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'EN_RUTA') THEN 2
                 ELSE 1 END
        ELSE 0 END;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT (SELECT TRIM(CONCAT(nombre, ' ', apellido)) FROM usuario WHERE id_usuario = p_id_usuario) AS RegistrandoComo,
           DATE_FORMAT(v_ahora, '%H:%i:%s') AS HoraActual, v_numero AS Numero, v_tecnico AS Tecnico, v_estado AS EstadoActual, v_nivel AS NivelActual,
           FN_PermisoAccion(p_id_usuario, 'seg_registrar') AS PuedeRegistrar;
    SELECT m.Num1 AS IdTipo, m.String1 AS Nombre, m.String2 AS Codigo FROM tabla_maestra m
    WHERE m.Descripcion = 'TIPO_DEMORA_INCIDENTE' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL ORDER BY m.Num1;
    SELECT m.Num1 AS IdMotivo, m.String1 AS Nombre, m.String2 AS Codigo FROM tabla_maestra m
    WHERE m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL ORDER BY m.Num1;
    SELECT x.codigo AS Codigo, x.nombre AS Nombre, x.nivel AS Nivel, IF(x.nivel > v_nivel AND v_estado <> 'finalizada', 1, 0) AS Permitido
    FROM (SELECT 'salida' codigo, 'Salida' nombre, 1 nivel UNION ALL SELECT 'en_ruta', 'En ruta', 2 UNION ALL SELECT 'llegada', 'Llegada', 3
          UNION ALL SELECT 'ingreso', 'Ingreso a planta', 4 UNION ALL SELECT 'inicio', 'Inicio de servicio', 5 UNION ALL SELECT 'finalizado', 'Finalizado', 6) x
    ORDER BY x.nivel;
    SELECT CONCAT('e', e.id_evento) AS Clave, DATE_FORMAT(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'), '%H:%i') AS Hora, m.String1 AS Titulo
    FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
    WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 NOT IN ('DEMORA', 'INCIDENCIA')
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 50;
    SELECT r.id_registro AS IdRegistro, r.modo AS Modo, DATE_FORMAT(CONVERT_TZ(r.fecha_utc, '+00:00', '-05:00'), '%H:%i') AS Hora, LEFT(r.descripcion, 200) AS Texto,
           r.fuente AS Fuente,
           CASE r.modo WHEN 'observacion' THEN '[NOTA DEL ASISTENTE]' WHEN 'demora' THEN '[DEMORA — REGISTRO DEL ASISTENTE]' ELSE '[CAMBIO MANUAL CRÍTICO — ASISTENTE]' END AS Badge,
           TIMESTAMPDIFF(MINUTE, r.fecha_utc, v_ahora_utc) AS HaceMin
    FROM registro_asistente r
    WHERE r.id_os = p_id_os AND r.id_usuario = p_id_usuario AND r.fecha_utc >= v_ini_utc
    ORDER BY r.fecha_utc DESC, r.id_registro DESC LIMIT 100;
END$$

DELIMITER ;
