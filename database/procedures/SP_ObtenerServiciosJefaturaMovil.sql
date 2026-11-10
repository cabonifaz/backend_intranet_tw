-- ============================================================
-- SP_ObtenerServiciosJefaturaMovil  (App Mobile HU-29 — "Servicios activos" · vista lista del Panel de Campo · solo lectura)
-- Servicios de HOY dentro del alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil), con el estado y el avance del motor de la bandeja
-- de Seguimiento Operativo (HU-51). Búsqueda por N° de OS/OM, cliente, RUC o técnico (hasta 100 caracteres).
--   p_filtro: activos (por defecto; no finalizados) · demora · incidencias · finalizados.
-- Resultados: 1 mensaje · 2 contadores de los chips (siempre sobre todo el alcance, sin búsqueda ni filtro) · 3 servicios (máx. 100).
--   estado (de la bandeja HU-51): sin_salir · en_ruta · en_planta · en_ejecucion · con_demora · con_incidente · finalizado.
--   llegada (HH:MM) = llegada validada por GPS (HU-06).  eta (HH:MM) = solo en ruta: la hora esperada de llegada de la bandeja (hora programada + demoras en ruta).
--   lugar = sede/planta del cliente (o su dirección).
--   avance_pct = ESTIMACIÓN POR HITOS, no un dato medido: sin salir 0 · en ruta 15 · en planta 30 · en ejecución 30 + 60 × (equipos ejecutados / equipos) · finalizado 100.
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerServiciosJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerServiciosJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_filtro     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_filtro      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_filtro = IFNULL(NULLIF(TRIM(p_filtro), ''), 'activos');
    IF v_filtro NOT IN ('activos', 'demora', 'incidencias', 'finalizados') THEN
        SELECT 1 AS IdTipoMensaje, 'El filtro de servicios no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda no puede superar los 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Chips: sobre todo el alcance del jefe
    SELECT IFNULL(SUM(o.fase <> 'finalizado'), 0)                                                       AS activos,
           IFNULL(SUM(o.fase <> 'finalizado' AND (o.n_demoras > 0 OR o.os_estado = 'pausada')), 0)       AS con_demora,
           IFNULL(SUM(o.fase <> 'finalizado' AND o.crit = 1), 0)                                         AS incidencias,
           IFNULL(SUM(o.fase = 'finalizado'), 0)                                                         AS finalizados,
           DATE_FORMAT(MAX(c.ahora), '%H:%i')                                                            AS actualizado,
           IFNULL(MAX(c.refresco), 30)                                                                   AS refresco_segundos
    FROM   tmp_sg_os o
    JOIN   tmp_jf_alc a ON a.id_os = o.id_os
    JOIN   tmp_sg_cfg c;

    CALL SP_FiltrarServiciosJefaturaMovil(p_busqueda, v_filtro);

    -- 3 Servicios
    SELECT o.id_os AS id_os, o.numero AS numero, o.razon_social AS cliente, o.estado_seg AS estado,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico,
           UPPER(CONCAT(LEFT(IFNULL(o.nombre_pila, ''), 1), LEFT(IFNULL(SUBSTRING_INDEX(o.tecnico, ' ', -1), ''), 1))) AS iniciales,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS lugar,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS hora_programada,
           DATE_FORMAT(o.llegada_dt, '%H:%i') AS llegada,
           IF(o.fase = 'en_ruta', DATE_FORMAT(h.esperado, '%H:%i'), NULL) AS eta,
           CASE o.fase WHEN 'finalizado'   THEN 100
                       WHEN 'en_ejecucion' THEN 30 + ROUND(60 * IF(o.n_equipos = 0, 0, o.n_ejecutados / o.n_equipos))
                       WHEN 'en_planta'    THEN 30
                       WHEN 'en_ruta'      THEN 15
                       ELSE 0 END AS avance_pct,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion
    FROM   tmp_sg_f f
    JOIN   tmp_sg_os o ON o.id_os = f.id_os
    LEFT JOIN tmp_sg_pos  p ON p.id_usuario = o.id_tecnico
    LEFT JOIN tmp_sg_hito h ON h.id_os = o.id_os
    JOIN   tmp_sg_cfg c
    ORDER BY o.prio, o.hora_inicio, o.id_os
    LIMIT 100;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
