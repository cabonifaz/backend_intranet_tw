-- Bandeja de Visto Bueno (HU-13).
-- Muestra el último VB de cada propuesta cuyo comercial tiene como jefe directo al usuario,
-- o cuyo jefe tiene al usuario como suplente vigente (HU-84). Con la acción propuesta_vb_todas
-- (administradores de Gerencia y TI) se ven todas.
-- SLA en horas hábiles (FN_HorasHabiles). Pendientes: en_plazo, proximo o vencido.
-- Resueltos: cumplido o fuera_de_plazo.
-- Filtros: comercial, estado del VB (pendiente, aprobado, devuelto, rechazado), moneda,
-- estado del SLA y días hacia atrás (los pendientes se muestran siempre).
-- Resultados: 1 mensaje, 2 KPIs, 3 filas, 4 total, 5 comerciales, 6 monedas, 7 políticas.
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaVistoBueno;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaVistoBueno(
    IN p_id_usuario   BIGINT,
    IN p_id_comercial BIGINT,
    IN p_estado       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_moneda    INT,
    IN p_sla          VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_dias         INT,
    IN p_pagina       INT,
    IN p_por_pagina   INT
)
BEGIN
    DECLARE v_todas      TINYINT DEFAULT 0;
    DECLARE v_resolver   TINYINT DEFAULT 0;
    DECLARE v_pct        DECIMAL(10,2);
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;

    SET v_todas      = FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas');
    SET v_resolver   = FN_PermisoAccion(p_id_usuario, 'propuesta_vb_resolver');
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    SELECT IFNULL(MAX(Num2), 25) INTO v_pct
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'VB_PROXIMO_VENCER_PCT';

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. KPIs (respetan comercial y moneda, no el resto de filtros)
    WITH base AS (
        SELECT
            vb.id_vb, vb.id_propuesta, vb.estado AS estado_vb, vb.sla_horas,
            vb.fecha_solicitud, vb.fecha_respuesta, vb.resuelto_por, vb.comentario AS comentario_solicitud,
            vb.comentario_respuesta,
            p.numero, p.version, p.id_requerimiento, p.id_cliente, p.referencia, p.total, p.id_moneda,
            p.descuento_pct, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, CONCAT(a.nombre, ' ', a.apellido) AS comercial,
            a.id_supervisor AS id_jefe,
            (SELECT us.id_suplente FROM usuario_suplente us
             JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
             WHERE us.id_titular = a.id_supervisor AND us.SoftDelete = 0 AND us.activo = 1
               AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
             ORDER BY us.fecha_inicio DESC LIMIT 1) AS id_suplente_vigente
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
        JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
        WHERE vb.eliminado_en IS NULL
          AND vb.estado IN ('pendiente', 'aprobado', 'devuelto', 'rechazado')
          AND vb.id_vb = (SELECT MAX(x.id_vb) FROM visto_bueno x
                          WHERE x.id_propuesta = vb.id_propuesta AND x.eliminado_en IS NULL
                            AND x.estado <> 'cancelado')
    ),
    alcance AS (
        SELECT b.*,
               (v_todas = 1 OR b.id_jefe = p_id_usuario OR b.id_suplente_vigente = p_id_usuario) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW()))            AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                               AS vence_en
        FROM base b
    ),
    bandeja AS (
        SELECT a.*,
               CASE
                   WHEN a.estado_vb <> 'pendiente' THEN
                       IF(a.horas_transcurridas <= a.sla_horas, 'cumplido', 'fuera_de_plazo')
                   WHEN a.horas_transcurridas >= a.sla_horas THEN 'vencido'
                   WHEN a.sla_horas - a.horas_transcurridas <= a.sla_horas * v_pct / 100 THEN 'proximo'
                   ELSE 'en_plazo'
               END AS sla_estado
        FROM alcance a
        WHERE a.en_alcance = 1
          AND (IFNULL(p_id_comercial, 0) = 0 OR a.id_comercial = p_id_comercial)
          AND (IFNULL(p_id_moneda, 0)    = 0 OR a.id_moneda    = p_id_moneda)
    )
    SELECT
        IFNULL(SUM(estado_vb = 'pendiente'), 0)                                        AS pendientes,
        IFNULL(SUM(estado_vb = 'pendiente' AND sla_estado = 'proximo'), 0)             AS proximos_vencer,
        IFNULL(SUM(estado_vb = 'pendiente' AND sla_estado = 'vencido'), 0)             AS vencidos,
        IFNULL(SUM(estado_vb = 'aprobado'  AND DATE(fecha_respuesta) = CURDATE()), 0)  AS aprobadas_hoy,
        IFNULL(SUM(estado_vb = 'devuelto'  AND estado_propuesta = 'borrador'), 0)      AS devueltas
    FROM bandeja;

    -- 3. Filas
    WITH base AS (
        SELECT
            vb.id_vb, vb.id_propuesta, vb.estado AS estado_vb, vb.sla_horas,
            vb.fecha_solicitud, vb.fecha_respuesta, vb.resuelto_por, vb.comentario AS comentario_solicitud,
            vb.comentario_respuesta,
            p.numero, p.version, p.id_requerimiento, p.id_cliente, p.referencia, p.total, p.id_moneda,
            p.descuento_pct, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, CONCAT(a.nombre, ' ', a.apellido) AS comercial,
            a.id_supervisor AS id_jefe,
            (SELECT us.id_suplente FROM usuario_suplente us
             JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
             WHERE us.id_titular = a.id_supervisor AND us.SoftDelete = 0 AND us.activo = 1
               AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
             ORDER BY us.fecha_inicio DESC LIMIT 1) AS id_suplente_vigente
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
        JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
        WHERE vb.eliminado_en IS NULL
          AND vb.estado IN ('pendiente', 'aprobado', 'devuelto', 'rechazado')
          AND vb.id_vb = (SELECT MAX(x.id_vb) FROM visto_bueno x
                          WHERE x.id_propuesta = vb.id_propuesta AND x.eliminado_en IS NULL
                            AND x.estado <> 'cancelado')
    ),
    alcance AS (
        SELECT b.*,
               (v_todas = 1 OR b.id_jefe = p_id_usuario OR b.id_suplente_vigente = p_id_usuario) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW()))            AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                               AS vence_en
        FROM base b
    ),
    bandeja AS (
        SELECT a.*,
               CASE
                   WHEN a.estado_vb <> 'pendiente' THEN
                       IF(a.horas_transcurridas <= a.sla_horas, 'cumplido', 'fuera_de_plazo')
                   WHEN a.horas_transcurridas >= a.sla_horas THEN 'vencido'
                   WHEN a.sla_horas - a.horas_transcurridas <= a.sla_horas * v_pct / 100 THEN 'proximo'
                   ELSE 'en_plazo'
               END AS sla_estado
        FROM alcance a
        WHERE a.en_alcance = 1
          AND (IFNULL(p_id_comercial, 0) = 0 OR a.id_comercial = p_id_comercial)
          AND (IFNULL(p_id_moneda, 0)    = 0 OR a.id_moneda    = p_id_moneda)
    )
    SELECT
        b.id_vb, b.id_propuesta, b.numero, b.version, b.id_requerimiento,
        r.numero                                   AS numero_rq,
        b.id_cliente, c.razon_social, c.ruc, b.referencia,
        b.total, b.id_moneda, m.String3            AS moneda, m.String2 AS moneda_simbolo,
        b.descuento_pct,
        b.id_comercial, b.comercial,
        CASE WHEN b.estado_vb = 'pendiente' THEN COALESCE(b.id_suplente_vigente, b.id_jefe)
             ELSE b.resuelto_por END               AS id_aprobador,
        (SELECT CONCAT(u.nombre, ' ', u.apellido) FROM usuario u
         WHERE u.id_usuario = CASE WHEN b.estado_vb = 'pendiente' THEN COALESCE(b.id_suplente_vigente, b.id_jefe)
                                   ELSE b.resuelto_por END) AS aprobador,
        (b.estado_vb = 'pendiente' AND b.id_suplente_vigente IS NOT NULL) AS aprobador_es_suplente,
        b.estado_vb, b.fecha_solicitud, b.fecha_respuesta, b.vence_en,
        b.sla_horas, b.horas_transcurridas,
        GREATEST(b.sla_horas - b.horas_transcurridas, 0) AS horas_restantes,
        b.sla_estado,
        b.comentario_solicitud, b.comentario_respuesta,
        (b.estado_vb = 'pendiente' AND v_resolver = 1
         AND (v_todas = 1 OR b.id_jefe = p_id_usuario OR b.id_suplente_vigente = p_id_usuario)) AS puede_resolver
    FROM bandeja b
    JOIN cliente c        ON c.id_cliente = b.id_cliente
    LEFT JOIN requerimiento r ON r.id_requerimiento = b.id_requerimiento
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = b.id_moneda
    WHERE 1 = 1 
      AND (IFNULL(p_estado, '') = '' OR b.estado_vb = p_estado)
      AND (IFNULL(p_sla, '') = '' OR b.sla_estado = p_sla)
      AND (b.estado_vb = 'pendiente' OR IFNULL(p_dias, 0) = 0
           OR b.fecha_solicitud >= DATE_SUB(NOW(), INTERVAL p_dias DAY))
    ORDER BY (b.estado_vb = 'pendiente') DESC,
             FIELD(b.sla_estado, 'vencido', 'proximo', 'en_plazo') ,
             b.vence_en, b.fecha_solicitud DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 4. Total
    WITH base AS (
        SELECT
            vb.id_vb, vb.id_propuesta, vb.estado AS estado_vb, vb.sla_horas,
            vb.fecha_solicitud, vb.fecha_respuesta, vb.resuelto_por, vb.comentario AS comentario_solicitud,
            vb.comentario_respuesta,
            p.numero, p.version, p.id_requerimiento, p.id_cliente, p.referencia, p.total, p.id_moneda,
            p.descuento_pct, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, CONCAT(a.nombre, ' ', a.apellido) AS comercial,
            a.id_supervisor AS id_jefe,
            (SELECT us.id_suplente FROM usuario_suplente us
             JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
             WHERE us.id_titular = a.id_supervisor AND us.SoftDelete = 0 AND us.activo = 1
               AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
             ORDER BY us.fecha_inicio DESC LIMIT 1) AS id_suplente_vigente
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
        JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
        WHERE vb.eliminado_en IS NULL
          AND vb.estado IN ('pendiente', 'aprobado', 'devuelto', 'rechazado')
          AND vb.id_vb = (SELECT MAX(x.id_vb) FROM visto_bueno x
                          WHERE x.id_propuesta = vb.id_propuesta AND x.eliminado_en IS NULL
                            AND x.estado <> 'cancelado')
    ),
    alcance AS (
        SELECT b.*,
               (v_todas = 1 OR b.id_jefe = p_id_usuario OR b.id_suplente_vigente = p_id_usuario) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW()))            AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                               AS vence_en
        FROM base b
    ),
    bandeja AS (
        SELECT a.*,
               CASE
                   WHEN a.estado_vb <> 'pendiente' THEN
                       IF(a.horas_transcurridas <= a.sla_horas, 'cumplido', 'fuera_de_plazo')
                   WHEN a.horas_transcurridas >= a.sla_horas THEN 'vencido'
                   WHEN a.sla_horas - a.horas_transcurridas <= a.sla_horas * v_pct / 100 THEN 'proximo'
                   ELSE 'en_plazo'
               END AS sla_estado
        FROM alcance a
        WHERE a.en_alcance = 1
          AND (IFNULL(p_id_comercial, 0) = 0 OR a.id_comercial = p_id_comercial)
          AND (IFNULL(p_id_moneda, 0)    = 0 OR a.id_moneda    = p_id_moneda)
    )
    SELECT COUNT(*) AS total FROM bandeja b WHERE 1 = 1 
      AND (IFNULL(p_estado, '') = '' OR b.estado_vb = p_estado)
      AND (IFNULL(p_sla, '') = '' OR b.sla_estado = p_sla)
      AND (b.estado_vb = 'pendiente' OR IFNULL(p_dias, 0) = 0
           OR b.fecha_solicitud >= DATE_SUB(NOW(), INTERVAL p_dias DAY));

    -- 5. Comerciales del equipo (para el filtro, tal cual)
    WITH base AS (
        SELECT
            vb.id_vb, vb.id_propuesta, vb.estado AS estado_vb, vb.sla_horas,
            vb.fecha_solicitud, vb.fecha_respuesta, vb.resuelto_por, vb.comentario AS comentario_solicitud,
            vb.comentario_respuesta,
            p.numero, p.version, p.id_requerimiento, p.id_cliente, p.referencia, p.total, p.id_moneda,
            p.descuento_pct, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, CONCAT(a.nombre, ' ', a.apellido) AS comercial,
            a.id_supervisor AS id_jefe,
            (SELECT us.id_suplente FROM usuario_suplente us
             JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
             WHERE us.id_titular = a.id_supervisor AND us.SoftDelete = 0 AND us.activo = 1
               AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
             ORDER BY us.fecha_inicio DESC LIMIT 1) AS id_suplente_vigente
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
        JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
        WHERE vb.eliminado_en IS NULL
          AND vb.estado IN ('pendiente', 'aprobado', 'devuelto', 'rechazado')
          AND vb.id_vb = (SELECT MAX(x.id_vb) FROM visto_bueno x
                          WHERE x.id_propuesta = vb.id_propuesta AND x.eliminado_en IS NULL
                            AND x.estado <> 'cancelado')
    ),
    alcance AS (
        SELECT b.*,
               (v_todas = 1 OR b.id_jefe = p_id_usuario OR b.id_suplente_vigente = p_id_usuario) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW()))            AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                               AS vence_en
        FROM base b
    ),
    bandeja AS (
        SELECT a.*,
               CASE
                   WHEN a.estado_vb <> 'pendiente' THEN
                       IF(a.horas_transcurridas <= a.sla_horas, 'cumplido', 'fuera_de_plazo')
                   WHEN a.horas_transcurridas >= a.sla_horas THEN 'vencido'
                   WHEN a.sla_horas - a.horas_transcurridas <= a.sla_horas * v_pct / 100 THEN 'proximo'
                   ELSE 'en_plazo'
               END AS sla_estado
        FROM alcance a
        WHERE a.en_alcance = 1
          AND (IFNULL(p_id_comercial, 0) = 0 OR a.id_comercial = p_id_comercial)
          AND (IFNULL(p_id_moneda, 0)    = 0 OR a.id_moneda    = p_id_moneda)
    )
    SELECT DISTINCT id_comercial AS id, comercial AS nombre FROM bandeja ORDER BY comercial;

    -- 6. Monedas presentes (para el filtro)
    WITH base AS (
        SELECT
            vb.id_vb, vb.id_propuesta, vb.estado AS estado_vb, vb.sla_horas,
            vb.fecha_solicitud, vb.fecha_respuesta, vb.resuelto_por, vb.comentario AS comentario_solicitud,
            vb.comentario_respuesta,
            p.numero, p.version, p.id_requerimiento, p.id_cliente, p.referencia, p.total, p.id_moneda,
            p.descuento_pct, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, CONCAT(a.nombre, ' ', a.apellido) AS comercial,
            a.id_supervisor AS id_jefe,
            (SELECT us.id_suplente FROM usuario_suplente us
             JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
             WHERE us.id_titular = a.id_supervisor AND us.SoftDelete = 0 AND us.activo = 1
               AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
             ORDER BY us.fecha_inicio DESC LIMIT 1) AS id_suplente_vigente
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
        JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
        WHERE vb.eliminado_en IS NULL
          AND vb.estado IN ('pendiente', 'aprobado', 'devuelto', 'rechazado')
          AND vb.id_vb = (SELECT MAX(x.id_vb) FROM visto_bueno x
                          WHERE x.id_propuesta = vb.id_propuesta AND x.eliminado_en IS NULL
                            AND x.estado <> 'cancelado')
    ),
    alcance AS (
        SELECT b.*,
               (v_todas = 1 OR b.id_jefe = p_id_usuario OR b.id_suplente_vigente = p_id_usuario) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW()))            AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                               AS vence_en
        FROM base b
    ),
    bandeja AS (
        SELECT a.*,
               CASE
                   WHEN a.estado_vb <> 'pendiente' THEN
                       IF(a.horas_transcurridas <= a.sla_horas, 'cumplido', 'fuera_de_plazo')
                   WHEN a.horas_transcurridas >= a.sla_horas THEN 'vencido'
                   WHEN a.sla_horas - a.horas_transcurridas <= a.sla_horas * v_pct / 100 THEN 'proximo'
                   ELSE 'en_plazo'
               END AS sla_estado
        FROM alcance a
        WHERE a.en_alcance = 1
          AND (IFNULL(p_id_comercial, 0) = 0 OR a.id_comercial = p_id_comercial)
          AND (IFNULL(p_id_moneda, 0)    = 0 OR a.id_moneda    = p_id_moneda)
    )
    SELECT DISTINCT b.id_moneda AS id, m.String3 AS codigo, m.String1 AS nombre
    FROM bandeja b
    JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = b.id_moneda
    ORDER BY b.id_moneda;

    -- 7. Políticas (tarjetas informativas)
    SELECT
        (SELECT Num2 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'DESCUENTO_APROBACION_ESPECIAL' LIMIT 1) AS descuento_aprobacion_especial_pct,
        (SELECT Num2 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'MARGEN_MINIMO_PCT' LIMIT 1)             AS margen_minimo_pct,
        (SELECT Num2 FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'propuesta' AND String2 = 'pendiente_vb' LIMIT 1) AS sla_horas_habiles,
        (SELECT Num2 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'JORNADA_INICIO' LIMIT 1)                AS jornada_inicio,
        (SELECT Num2 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'JORNADA_FIN' LIMIT 1)                   AS jornada_fin,
        v_pct                                                                                                                             AS proximo_vencer_pct;
END$$

DELIMITER ;
