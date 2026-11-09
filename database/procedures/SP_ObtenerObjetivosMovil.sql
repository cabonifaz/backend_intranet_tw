-- ============================================================
-- SP_ObtenerObjetivosMovil  (App Mobile HU-07 — Lista de objetivos y selección de equipos · lectura)
-- Objetivos de la OS del técnico que inició sesión (el id sale del token), numerados y con su estado.
--   - Hard Stop (HU-06): sin llegada registrada en este viaje NO se entregan los objetivos (responde la regla de negocio con el motivo).
--   - p_buscar (opcional, máx. 100): filtra la LISTA por N/S, código del cliente, COD TW, marca, modelo, ubicación o tipo de equipo
--     (sin comodines: se busca el texto tal cual). Los contadores y el tiempo estimado siempre son de TODOS los objetivos.
--   - Los objetivos los arma SP_ArmarObjetivosMovil (una sola vez); aquí solo se leen.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 contadores (1 fila) · 4 equipos (con puede_iniciar/pausar/reanudar) ·
--             5 cambios (historial del equipo y cambios de estado desde la app, el más reciente primero, máx. 300 de la OS).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerObjetivosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerObjetivosMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_buscar     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado TINYINT;
    DECLARE v_motivo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_buscar     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estimado   INT DEFAULT 0;
    DECLARE v_ahora_utc  DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_existe
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_buscar = LOWER(TRIM(IFNULL(p_buscar, '')));
    IF CHAR_LENGTH(v_buscar) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda puede tener hasta 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);

    -- Hard Stop: sin llegada no hay objetivos
    IF v_llegada_utc IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    SELECT IFNULL(SUM(tiempo_estimado_min), 0) INTO v_estimado FROM tmp_obj_mov;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           sc.nombre                                                         AS sede,
           CONVERT_TZ(v_salida_utc, '+00:00', '-05:00')                      AS salida_en,
           CONVERT_TZ(v_llegada_utc, '+00:00', '-05:00')                     AS llegada_en,
           IF(v_salida_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_salida_utc, v_llegada_utc))) AS traslado_min,
           GREATEST(0, TIMESTAMPDIFF(MINUTE, v_llegada_utc, v_ahora_utc))    AS en_planta_min,
           v_estimado                                                        AS estimado_min
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede   = os.id_sede
    WHERE  os.id_os = p_id_os;

    -- 3. Contadores (de todos los objetivos)
    SELECT IFNULL(SUM(estado = 'completado'), 0)                                  AS completados,
           IFNULL(SUM(estado <> 'completado' AND observado_cuenta = 0), 0)        AS pendientes,
           IFNULL(SUM(estado <> 'completado' AND observado_cuenta = 1), 0)        AS observados,
           COUNT(*)                                                               AS total
    FROM   tmp_obj_mov;

    -- 4. Equipos (con el filtro de búsqueda)
    SELECT t.id_os_equipo, t.id_equipo, t.numero, t.tipo_intervencion, t.tipo_corto, t.nombre, t.codigo_tw, t.codigo_cliente, t.marca, t.modelo,
           t.num_serie, t.ubicacion, t.estado_equipo, t.bloqueado, t.en_campo, t.falta_equipo, t.estado, t.tiempo_estimado_min, t.tiempo_real_min,
           CONVERT_TZ(t.iniciado_utc, '+00:00', '-05:00') AS iniciado_en, t.motivo_pausa, t.requiere_aprobacion, t.ultima_intervencion, t.ultima_parte,
           t.alertas_pendientes, t.puede_iniciar, t.puede_pausar, t.puede_reanudar
    FROM   tmp_obj_mov t
    WHERE  v_buscar = ''
       OR  LOCATE(v_buscar, LOWER(CONCAT_WS(' ', t.num_serie, t.codigo_cliente, t.codigo_tw, t.marca, t.modelo, t.ubicacion, t.nombre))) > 0
    ORDER BY t.numero;

    -- 5. Cambios: historial del equipo (intranet) y cambios de estado hechos desde la app
    SELECT x.id_os_equipo, x.fecha, x.campo, x.valor_anterior, x.valor_nuevo, x.detalle, x.usuario
    FROM (
        SELECT oe.id AS id_os_equipo, h.registrado_en AS fecha, h.campo_modificado AS campo, h.valor_anterior, h.valor_nuevo,
               LEFT(IFNULL(h.motivo, ''), 300) AS detalle, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS usuario
        FROM   os_equipo oe
        JOIN   equipo_historial h ON h.id_equipo = oe.id_equipo
        LEFT JOIN usuario u ON u.id_usuario = h.registrado_por
        WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
        UNION ALL
        SELECT a.id_entidad, a.registrado_en, 'Estado', a.estado_anterior, a.estado_nuevo, LEFT(IFNULL(a.descripcion, ''), 300),
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
        FROM   auditoria_evento a
        LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
        WHERE  a.entidad_tipo = 'os_equipo'
          AND  a.id_entidad IN (SELECT o2.id FROM os_equipo o2 WHERE o2.id_os = p_id_os AND o2.eliminado_en IS NULL)
    ) x
    ORDER BY x.fecha DESC
    LIMIT 300;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;
