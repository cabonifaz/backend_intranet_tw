-- ============================================================
-- SP_ObtenerTecnicosReasignacionMovil  (App Mobile HU-32 — "Reasignar técnico en ruta": candidatos · lectura)
-- Técnicos a los que el jefe puede pasar un servicio de su área: de la MISMA especialidad (el área del técnico actual), cercanos a la planta y con SSOMA conforme.
--   - Candidato = usuario activo de servicio técnico o metrología, sin jefaturas ni asistentes, distinto del técnico actual.
--   - Distancia: última posición GPS de hoy (ubicacion_tecnico) a la planta (sede de la OS), en línea recta; llega_min = distancia a 30 km/h (referencial).
--     Sin posición o sin sede ubicada, distancia y llegada salen NULL.
--   - Carga: servicios de hoy del técnico (principal o personal) frente a SERVICIOS_MAX_DIA (parámetro de programación, 4 por defecto), en %.
--   - SSOMA: SP_EvaluarSsomaProgramacion contra los requisitos del cliente / zona de la OS (conforme · por_vencer habilitan; incompleto · pendiente · bloqueado no).
--   - disponible = SSOMA conforme o por vencer, con cupo en su día y no es el técnico actual. motivo_no = por qué no está habilitado.
--   - Orden: habilitados primero, por cercanía.
-- La OS debe estar en el alcance del jefe. Resultados: 1 mensaje · 2 OS y técnico actual (1 fila) · 3 candidatos.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTecnicosReasignacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTecnicosReasignacionMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_hoy       DATE;
    DECLARE v_param     DECIMAL(18,6);
    DECLARE v_max_dia   INT DEFAULT 4;
    DECLARE v_tec       BIGINT DEFAULT NULL;
    DECLARE v_area_tec  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_lat       DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lon       DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_fecha_os  DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_rea_cand;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    CALL SP_LeerParametroProgramacion('SERVICIOS_MAX_DIA', 4, v_param);
    SET v_max_dia = GREATEST(1, IFNULL(v_param, 4));

    SELECT os.id_tecnico_principal, os.fecha_ejecucion, COALESCE(sc.latitud, s.latitud), COALESCE(sc.longitud, s.longitud)
    INTO   v_tec, v_fecha_os, v_lat, v_lon
    FROM   orden_servicio os
    LEFT JOIN sede_cliente sc ON sc.id_sede = os.id_sede
    LEFT JOIN sede s ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    WHERE  os.id_os = p_id_os;
    SELECT u.area INTO v_area_tec FROM usuario u WHERE u.id_usuario = v_tec;

    DROP TEMPORARY TABLE IF EXISTS tmp_rea_cand;
    CREATE TEMPORARY TABLE tmp_rea_cand (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_rea_cand (id_usuario)
    SELECT u.id_usuario
    FROM   usuario u
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area IN ('servicio_tecnico', 'metrologia')
      AND  (v_area_tec IS NULL OR u.area = v_area_tec)
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
      AND  u.id_usuario <> IFNULL(v_tec, 0);

    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_rea_cand;
    CALL SP_EvaluarSsomaProgramacion(p_id_os, IFNULL(v_fecha_os, v_hoy));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os, os.numero AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente, v_tec AS id_tecnico_actual,
           (SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) FROM usuario u WHERE u.id_usuario = v_tec) AS tecnico_actual,
           v_lat AS planta_latitud, v_lon AS planta_longitud
    FROM   orden_servicio os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os;

    SELECT x.id_usuario, x.nombre, x.iniciales, x.latitud, x.longitud, x.distancia_km,
           IF(x.distancia_km IS NULL, NULL, CEIL(x.distancia_km / 30 * 60)) AS llega_min,
           x.servicios_hoy, LEAST(100, ROUND(x.servicios_hoy * 100 / v_max_dia)) AS carga_pct, x.ssoma,
           IF(x.ssoma IN ('conforme', 'por_vencer') AND x.servicios_hoy < v_max_dia, 1, 0) AS disponible,
           CASE WHEN x.ssoma = 'bloqueado'  THEN 'SSOMA bloqueado'
                WHEN x.ssoma = 'pendiente'  THEN 'Falta documento SSOMA'
                WHEN x.ssoma = 'incompleto' THEN 'SSOMA incompleto'
                WHEN x.servicios_hoy >= v_max_dia THEN 'Sin cupo hoy'
                ELSE NULL END AS motivo_no
    FROM (
        SELECT t.id_usuario,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS nombre,
               UPPER(CONCAT(LEFT(IFNULL(u.nombre, '?'), 1), LEFT(IFNULL(u.apellido, ''), 1))) AS iniciales,
               p.latitud, p.longitud,
               IF(p.latitud IS NULL OR v_lat IS NULL OR v_lon IS NULL, NULL,
                  ROUND(6371 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat - p.latitud) / 2), 2)
                        + COS(RADIANS(p.latitud)) * COS(RADIANS(v_lat)) * POW(SIN(RADIANS(v_lon - p.longitud) / 2), 2))), 1)) AS distancia_km,
               (SELECT COUNT(*) FROM orden_servicio o2
                WHERE o2.eliminado_en IS NULL AND o2.fecha_ejecucion = IFNULL(v_fecha_os, v_hoy)
                  AND o2.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
                  AND (o2.id_tecnico_principal = t.id_usuario
                       OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = o2.id_os AND op.id_usuario = t.id_usuario AND op.eliminado_en IS NULL))) AS servicios_hoy,
               IFNULL(s.estado, 'conforme') AS ssoma
        FROM   tmp_rea_cand t
        JOIN   usuario u ON u.id_usuario = t.id_usuario
        LEFT JOIN ubicacion_tecnico p ON p.id_ubicacion = (SELECT MAX(y.id_ubicacion) FROM ubicacion_tecnico y
                                                            WHERE y.id_usuario = t.id_usuario AND y.timestamp_utc >= UTC_TIMESTAMP() - INTERVAL 1 DAY)
        LEFT JOIN tmp_ssoma_res s ON s.id_usuario = t.id_usuario
    ) x
    ORDER BY IF(x.ssoma IN ('conforme', 'por_vencer') AND x.servicios_hoy < v_max_dia, 0, 1), IFNULL(x.distancia_km, 9999), x.nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_rea_cand;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;
