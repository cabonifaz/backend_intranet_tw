-- ============================================================
-- SP_ObtenerRecepcionesOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — lista «Por recibir» y «Recibidos hoy» · lectura)
-- Las OM del técnico de Metrología (SP_ArmarOmTecnicoMovil: técnico principal u os_personal) con el avance de la recepción de sus instrumentos (SP_ArmarInstrumentosRecepcionOmMovil).
--   p_busqueda (opcional, hasta 80 caracteres): filtra por N° de OM, cliente o N° de guía de alguna de sus recepciones.
--   Por recibir  = OM activa con al menos un instrumento pendiente. estado: por_recibir (ninguno recibido) | parcial (ya recibió algunos). Primero las parciales, luego por id descendente.
--   Recibidos hoy = OM con una recepción registrada HOY (día de Lima) por cualquiera de sus técnicos; estado = el de la ÚLTIMA recepción de hoy (conforme | observado | parcial),
--                   hora y guía son los de esa recepción. Orden: hora descendente.
--   hora = HH:mm de Lima de la última recepción de la OM (null si no tiene); guia = su N° de guía; pendientes = nombres de los instrumentos sin recibir (hasta 5, separados por «|»).
--   Máximo 50 por lista.
-- Resultados: 1 mensaje · 2 Por recibir · 3 Recibidos hoy (mismas columnas). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRecepcionesOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRecepcionesOmMovil(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_b       VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_like    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ini_utc DATETIME;
    DECLARE v_fin_utc DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_res;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_b = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');
    IF CHAR_LENGTH(IFNULL(v_b, '')) > 80 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda puede tener hasta 80 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_b IS NOT NULL THEN
        SET v_like = CONCAT('%', REPLACE(REPLACE(REPLACE(v_b, '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;

    -- Hoy en Lima (UTC-5, sin horario de verano) expresado en UTC
    SET v_ini_utc = TIMESTAMP(DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'))) + INTERVAL 5 HOUR;
    SET v_fin_utc = v_ini_utc + INTERVAL 1 DAY;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, NULL);
    CALL SP_ArmarInstrumentosRecepcionOmMovil();

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_res;
    CREATE TEMPORARY TABLE tmp_rom_res (
        id_os BIGINT NOT NULL,
        numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        cliente VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        activa TINYINT NOT NULL,
        total INT NOT NULL DEFAULT 0,
        recibidos INT NOT NULL DEFAULT 0,
        pendientes TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        ult_utc DATETIME NULL, ult_guia VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        hoy_utc DATETIME NULL, hoy_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, hoy_guia VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id_os));

    INSERT INTO tmp_rom_res (id_os, numero, cliente, numero_rq, servicio, activa)
    SELECT o.id_os, o.numero, o.cliente, o.numero_rq, o.servicio, o.activa FROM tmp_rom_os o;

    -- Avance de la recepción por OM
    UPDATE tmp_rom_res r
    JOIN  (SELECT i.id_os, COUNT(*) AS total, SUM(i.recibido) AS recibidos FROM tmp_rom_inst i GROUP BY i.id_os) x ON x.id_os = r.id_os
    SET    r.total = x.total, r.recibidos = x.recibidos;

    UPDATE tmp_rom_res r
    JOIN  (SELECT i.id_os, SUBSTRING_INDEX(GROUP_CONCAT(CONCAT_WS(' ', i.nombre, i.marca, i.modelo) ORDER BY i.numero SEPARATOR '|'), '|', 5) AS nombres
           FROM   tmp_rom_inst i WHERE i.recibido = 0 GROUP BY i.id_os) x ON x.id_os = r.id_os
    SET    r.pendientes = x.nombres;

    -- Última recepción de cada OM, y la última de HOY
    UPDATE tmp_rom_res r
    JOIN  (SELECT q.id_os, q.recibido_utc, q.numero_guia
           FROM   om_recepcion q
           WHERE  q.eliminado_en IS NULL
             AND  q.id_recepcion = (SELECT MAX(y.id_recepcion) FROM om_recepcion y WHERE y.id_os = q.id_os AND y.eliminado_en IS NULL)) x ON x.id_os = r.id_os
    SET    r.ult_utc = x.recibido_utc, r.ult_guia = x.numero_guia;

    UPDATE tmp_rom_res r
    JOIN  (SELECT q.id_os, q.recibido_utc, q.estado, q.numero_guia
           FROM   om_recepcion q
           WHERE  q.eliminado_en IS NULL AND q.recibido_utc >= v_ini_utc AND q.recibido_utc < v_fin_utc
             AND  q.id_recepcion = (SELECT MAX(y.id_recepcion) FROM om_recepcion y
                                    WHERE y.id_os = q.id_os AND y.eliminado_en IS NULL AND y.recibido_utc >= v_ini_utc AND y.recibido_utc < v_fin_utc)) x ON x.id_os = r.id_os
    SET    r.hoy_utc = x.recibido_utc, r.hoy_estado = x.estado, r.hoy_guia = x.numero_guia;

    IF v_like IS NOT NULL THEN
        DELETE FROM tmp_rom_res
        WHERE  NOT (numero LIKE v_like OR IFNULL(cliente, '') LIKE v_like
                    OR EXISTS (SELECT 1 FROM om_recepcion g WHERE g.id_os = tmp_rom_res.id_os AND g.eliminado_en IS NULL AND g.numero_guia LIKE v_like));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Por recibir (parciales primero)
    SELECT r.id_os, r.numero, r.cliente, r.numero_rq, r.servicio, r.total AS total_instrumentos, r.recibidos,
           IF(r.recibidos = 0, 'por_recibir', 'parcial') AS estado,
           DATE_FORMAT(CONVERT_TZ(r.ult_utc, '+00:00', '-05:00'), '%H:%i') AS hora, r.ult_guia AS guia, r.pendientes
    FROM   tmp_rom_res r
    WHERE  r.activa = 1 AND r.recibidos < r.total
    ORDER BY (r.recibidos > 0) DESC, r.id_os DESC
    LIMIT 50;

    -- 3. Recibidos hoy
    SELECT r.id_os, r.numero, r.cliente, r.numero_rq, r.servicio, r.total AS total_instrumentos, r.recibidos,
           r.hoy_estado AS estado,
           DATE_FORMAT(CONVERT_TZ(r.hoy_utc, '+00:00', '-05:00'), '%H:%i') AS hora, r.hoy_guia AS guia, r.pendientes
    FROM   tmp_rom_res r
    WHERE  r.hoy_utc IS NOT NULL
    ORDER BY r.hoy_utc DESC, r.id_os DESC
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_res;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
END$$

DELIMITER ;
