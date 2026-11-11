-- ============================================================
-- SP_ObtenerBandejaNotificaciones  (HU-90 Centro de Notificaciones — bandeja completa /notificaciones)
-- Lista del usuario que inició sesión (el id sale del token), con filtros y paginado. Solo lectura. Requiere la migración 102.
--   p_estado ..... activas (defecto: no archivadas) · no_leida · leida · archivada · todas
--   p_modulos .... lista separada por comas (propuestas,visto_bueno,…); NULL = todos. El caso de uso ya la validó.
--   p_tipos ...... lista separada por comas (alerta_operativa,recordatorio,…); NULL = todos.
--   p_rango ...... hoy · semana (desde el lunes) · mes (desde el día 1) · custom (p_desde / p_hasta) · NULL = sin límite.
--   p_remitente .. NULL = todos · 0 = Sistema (sin usuario) · id de usuario.
--   p_busqueda ... N° de documento, cliente, usuario o palabra clave (busca en título, mensaje y remitente).
-- Grupo de cada fila: hoy · ayer · semana · antiguas (hora de Lima, igual que NOW()).
-- Resultados: 1 mensaje · 2 filas de la página · 3 total · 4 no_leidas (contador del badge).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaNotificaciones;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaNotificaciones(
    IN p_id_usuario BIGINT,
    IN p_estado     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modulos    VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipos      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rango      VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_desde      DATE,
    IN p_hasta      DATE,
    IN p_remitente  BIGINT,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
proc: BEGIN
    DECLARE v_estado   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modulos  VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipos    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_patron   VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desde    DATE;
    DECLARE v_hasta    DATE;
    DECLARE v_por      INT;
    DECLARE v_offset   INT;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado  = IFNULL(NULLIF(TRIM(p_estado), ''), 'activas');
    IF v_estado NOT IN ('activas', 'no_leida', 'leida', 'archivada', 'todas') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use: activas, no_leida, leida, archivada o todas.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_modulos = NULLIF(TRIM(p_modulos), '');
    SET v_tipos   = NULLIF(TRIM(p_tipos), '');
    SET v_patron  = IF(NULLIF(TRIM(p_busqueda), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));

    CASE IFNULL(p_rango, '')
        WHEN 'hoy'    THEN SET v_desde = CURDATE();
        WHEN 'semana' THEN SET v_desde = CURDATE() - INTERVAL WEEKDAY(CURDATE()) DAY;
        WHEN 'mes'    THEN SET v_desde = CURDATE() - INTERVAL (DAYOFMONTH(CURDATE()) - 1) DAY;
        WHEN 'custom' THEN SET v_desde = p_desde; SET v_hasta = p_hasta;
        ELSE SET v_desde = NULL;
    END CASE;

    IF v_desde IS NOT NULL AND v_hasta IS NOT NULL AND v_desde > v_hasta THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha desde no puede ser posterior a la fecha hasta.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_por    = IF(IFNULL(p_por_pagina, 0) BETWEEN 1 AND 100, p_por_pagina, 30);
    SET v_offset = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Página
    SELECT n.id_notificacion,
           n.titulo,
           LEFT(n.cuerpo, 160)                                                                    AS resumen,
           n.modulo,
           n.tipo_notificacion                                                                    AS tipo,
           n.prioridad,
           n.leido                                                                                AS leida,
           n.archivado                                                                            AS archivada,
           r.id_usuario                                                                           AS id_remitente,
           IFNULL(TRIM(CONCAT(r.nombre, ' ', r.apellido)), 'Sistema TotalWeight')                 AS remitente,
           IF(r.id_usuario IS NULL, 'S', UPPER(CONCAT(LEFT(r.nombre, 1), LEFT(r.apellido, 1))))   AS iniciales,
           n.fecha_creacion,
           CASE WHEN n.fecha_creacion >= CURDATE()                                     THEN 'hoy'
                WHEN n.fecha_creacion >= CURDATE() - INTERVAL 1 DAY                    THEN 'ayer'
                WHEN n.fecha_creacion >= CURDATE() - INTERVAL WEEKDAY(CURDATE()) DAY   THEN 'semana'
                ELSE 'antiguas' END                                                               AS grupo,
           CASE WHEN n.entidad_tipo IS NULL OR n.id_entidad IS NULL                        THEN NULL
                WHEN n.entidad_tipo = 'orden_servicio' AND n.modulo = 'control_campo'      THEN 'seguimiento.servicio'
                WHEN n.entidad_tipo = 'orden_servicio' AND n.modulo = 'programacion'       THEN 'programacion.os'
                WHEN n.entidad_tipo = 'orden_servicio'                                     THEN 'os.detalle'
                WHEN n.entidad_tipo = 'propuesta' AND n.modulo = 'visto_bueno'             THEN 'vb.detalle'
                WHEN n.entidad_tipo = 'propuesta' AND n.modulo = 'seguimiento'             THEN 'seguimiento.propuesta'
                WHEN n.entidad_tipo = 'propuesta'                                          THEN 'propuesta.detalle'
                WHEN n.entidad_tipo = 'precotizacion'                                      THEN 'propuesta.precotizacion'
                WHEN n.entidad_tipo = 'orden_compra'                                       THEN 'oc.detalle'
                WHEN n.entidad_tipo = 'expediente'                                         THEN 'expediente.detalle'
                WHEN n.entidad_tipo = 'programacion'                                       THEN 'programacion.detalle'
                WHEN n.entidad_tipo = 'informe_tecnico'                                    THEN 'informe.detalle'
                WHEN n.entidad_tipo = 'equipo_cliente'                                     THEN 'equipo.detalle'
                WHEN n.entidad_tipo = 'cliente'                                            THEN 'cliente.detalle'
                ELSE NULL END                                                                     AS destino_accion,
           n.entidad_tipo,
           n.id_entidad,
           IF(n.tipo_notificacion = 'alerta_operativa' AND n.entidad_tipo = 'orden_servicio', 'mapa', NULL) AS destino_tab
    FROM   notificacion n
    LEFT JOIN usuario r ON r.id_usuario = n.creado_por
    WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
      AND  (v_estado = 'todas'
            OR (v_estado = 'activas'   AND n.archivado = 0)
            OR (v_estado = 'no_leida'  AND n.archivado = 0 AND n.leido = 0)
            OR (v_estado = 'leida'     AND n.archivado = 0 AND n.leido = 1)
            OR (v_estado = 'archivada' AND n.archivado = 1))
      AND  (v_modulos IS NULL OR FIND_IN_SET(n.modulo, v_modulos) > 0)
      AND  (v_tipos   IS NULL OR FIND_IN_SET(n.tipo_notificacion, v_tipos) > 0)
      AND  (v_desde   IS NULL OR n.fecha_creacion >= v_desde)
      AND  (v_hasta   IS NULL OR n.fecha_creacion <  v_hasta + INTERVAL 1 DAY)
      AND  (p_remitente IS NULL OR (p_remitente = 0 AND n.creado_por IS NULL) OR (p_remitente > 0 AND n.creado_por = p_remitente))
      AND  (v_patron  IS NULL OR n.titulo LIKE v_patron OR n.cuerpo LIKE v_patron
            OR CONCAT(r.nombre, ' ', r.apellido) LIKE v_patron)
    ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
    LIMIT v_offset, v_por;

    -- 3. Total con los mismos filtros
    SELECT COUNT(*) AS total
    FROM   notificacion n
    LEFT JOIN usuario r ON r.id_usuario = n.creado_por
    WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
      AND  (v_estado = 'todas'
            OR (v_estado = 'activas'   AND n.archivado = 0)
            OR (v_estado = 'no_leida'  AND n.archivado = 0 AND n.leido = 0)
            OR (v_estado = 'leida'     AND n.archivado = 0 AND n.leido = 1)
            OR (v_estado = 'archivada' AND n.archivado = 1))
      AND  (v_modulos IS NULL OR FIND_IN_SET(n.modulo, v_modulos) > 0)
      AND  (v_tipos   IS NULL OR FIND_IN_SET(n.tipo_notificacion, v_tipos) > 0)
      AND  (v_desde   IS NULL OR n.fecha_creacion >= v_desde)
      AND  (v_hasta   IS NULL OR n.fecha_creacion <  v_hasta + INTERVAL 1 DAY)
      AND  (p_remitente IS NULL OR (p_remitente = 0 AND n.creado_por IS NULL) OR (p_remitente > 0 AND n.creado_por = p_remitente))
      AND  (v_patron  IS NULL OR n.titulo LIKE v_patron OR n.cuerpo LIKE v_patron
            OR CONCAT(r.nombre, ' ', r.apellido) LIKE v_patron);

    -- 4. Contador del badge
    SELECT COUNT(*) AS no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0 AND leido = 0;
END$$

DELIMITER ;
