-- ============================================================
-- SP_ObtenerJornadaMovil  (App Mobile HU-20 — pantalla «Reloj marcador» · lectura)
-- La jornada de HOY (hora de Lima) del técnico del token: estado, el único paso habilitado, el horario programado, las marcaciones hechas
-- (hora, lugar GPS, a tiempo / tardanza) y, con la jornada finalizada, el resumen (trabajado, refrigerio, ingreso).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 cabecera · 3 marcaciones · 4 resumen (una fila; vacío si la jornada no terminó).
-- Las horas se devuelven en ISO 8601 UTC («…Z») para que la app las descuente con su reloj; las de pantalla ya vienen en hora de Lima («HH:mm»).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerJornadaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_fecha     DATE;
    DECLARE v_n         INT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima    DATETIME;
    DECLARE v_ini_min   DECIMAL(18,6);
    DECLARE v_fin_min   DECIMAL(18,6);
    DECLARE v_tol       DECIMAL(18,6);
    DECLARE v_refri     DECIMAL(18,6);
    DECLARE v_t_ini     DATETIME;
    DECLARE v_t_fin     DATETIME;
    DECLARE v_r_ini     DATETIME;
    DECLARE v_r_fin     DATETIME;
    DECLARE v_punt      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tard      INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_fecha     = DATE(CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00'));
    CALL SP_EstadoJornadaMovil(p_id_usuario, v_fecha, v_n, v_estado, v_sig, v_ultima);
    CALL SP_LeerParametroProgramacion('JORNADA_INICIO_MIN',      465,  v_ini_min);
    CALL SP_LeerParametroProgramacion('JORNADA_FIN_MIN',         1020, v_fin_min);
    CALL SP_LeerParametroProgramacion('JORNADA_TOLERANCIA_MIN',  5,    v_tol);
    CALL SP_LeerParametroProgramacion('JORNADA_REFRIGERIO_MIN',  60,   v_refri);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Cabecera
    SELECT DATE_FORMAT(v_fecha, '%Y-%m-%d')                              AS fecha,
           DATE_FORMAT(v_ahora_utc, '%Y-%m-%dT%H:%i:%sZ')                AS ahora_utc,
           v_estado                                                      AS estado,
           v_sig                                                         AS siguiente,
           TIME_FORMAT(SEC_TO_TIME(v_ini_min * 60), '%H:%i')             AS inicio_programado,
           TIME_FORMAT(SEC_TO_TIME(v_fin_min * 60), '%H:%i')             AS fin_programado,
           CAST(v_tol AS SIGNED)                                         AS tolerancia_min,
           CAST(v_refri AS SIGNED)                                       AS refrigerio_max_min;

    -- 3 Marcaciones del día
    SELECT j.tipo AS tipo, DATE_FORMAT(CONVERT_TZ(j.marcado_utc, '+00:00', '-05:00'), '%H:%i') AS hora,
           DATE_FORMAT(j.marcado_utc, '%Y-%m-%dT%H:%i:%sZ') AS marcado_utc, j.lugar AS lugar, j.latitud AS latitud, j.longitud AS longitud,
           j.precision_m AS precision_m, j.puntualidad AS puntualidad, j.minutos_diferencia AS minutos_diferencia, j.sin_conexion AS sin_conexion
    FROM   jornada_marcacion j
    WHERE  j.id_usuario = p_id_usuario AND j.fecha = v_fecha
    ORDER BY j.marcado_utc, j.id_marcacion;

    -- 4 Resumen de la jornada finalizada
    IF v_estado = 'finalizada' THEN
        SELECT MAX(IF(j.tipo = 'inicio_labores', j.marcado_utc, NULL)), MAX(IF(j.tipo = 'fin_labores', j.marcado_utc, NULL)),
               MAX(IF(j.tipo = 'inicio_refrigerio', j.marcado_utc, NULL)), MAX(IF(j.tipo = 'fin_refrigerio', j.marcado_utc, NULL)),
               MAX(IF(j.tipo = 'inicio_labores', j.puntualidad, NULL)), MAX(IF(j.tipo = 'inicio_labores', j.minutos_diferencia, NULL))
          INTO v_t_ini, v_t_fin, v_r_ini, v_r_fin, v_punt, v_tard
        FROM jornada_marcacion j WHERE j.id_usuario = p_id_usuario AND j.fecha = v_fecha;
        SELECT GREATEST(0, TIMESTAMPDIFF(MINUTE, v_t_ini, v_t_fin) - IFNULL(TIMESTAMPDIFF(MINUTE, v_r_ini, v_r_fin), 0)) AS trabajado_min,
               IFNULL(TIMESTAMPDIFF(MINUTE, v_r_ini, v_r_fin), 0)                                                       AS refrigerio_min,
               v_punt AS ingreso, v_tard AS minutos_tardanza;
    ELSE
        SELECT NULL AS trabajado_min, NULL AS refrigerio_min, NULL AS ingreso, NULL AS minutos_tardanza FROM DUAL WHERE 1 = 0;
    END IF;
END$$

DELIMITER ;
