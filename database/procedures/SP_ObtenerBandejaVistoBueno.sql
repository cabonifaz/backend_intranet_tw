-- Bandeja de Visto Bueno (HU-13).
-- MODELO: Bandeja compartida por área + rol.
--   El usuario logueado ve las propuestas cuyo comercial autor pertenece a la MISMA ÁREA,
--   siempre que el usuario sea supervisor o administrador en esa área. No depende de un
--   "jefe directo" asignado — todos los sup/admin del área ven las mismas propuestas.
--   Con la acción propuesta_vb_todas (admins de Gerencia y TI) se ven todas las áreas.
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
    DECLARE v_todas         TINYINT DEFAULT 0;
    DECLARE v_resolver      TINYINT DEFAULT 0;
    DECLARE v_pct           DECIMAL(10,2);
    DECLARE v_por_pagina    INT;
    DECLARE v_offset        INT;
    DECLARE v_rol_logueado  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_logueado VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_todas      = FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas');
    SET v_resolver   = FN_PermisoAccion(p_id_usuario, 'propuesta_vb_resolver');
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    SELECT IFNULL(MAX(Num2), 25) INTO v_pct
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'VB_PROXIMO_VENCER_PCT';

    -- Rol + área del usuario logueado — base del alcance (jerarquía automática por rol + área).
    SELECT rol_sistema, area INTO v_rol_logueado, v_area_logueado
    FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo' LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. KPIs
    WITH base AS (
        SELECT
            vb.id_vb, vb.id_propuesta, vb.estado AS estado_vb, vb.sla_horas,
            vb.fecha_solicitud, vb.fecha_respuesta, vb.resuelto_por, vb.comentario AS comentario_solicitud,
            vb.comentario_respuesta,
            p.numero, p.version, p.id_requerimiento, p.id_cliente, p.referencia, p.total, p.id_moneda,
            p.descuento_pct, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, CONCAT(a.nombre, ' ', a.apellido) AS comercial,
            a.area AS area_comercial
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
               (v_todas = 1
                OR (v_rol_logueado IN ('supervisor','administrador') AND v_area_logueado = b.area_comercial)
               ) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW())) AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                   AS vence_en
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
            a.area AS area_comercial
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
               (v_todas = 1
                OR (v_rol_logueado IN ('supervisor','administrador') AND v_area_logueado = b.area_comercial)
               ) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, COALESCE(b.fecha_respuesta, NOW())) AS horas_transcurridas,
               FN_SumarHorasHabiles(b.fecha_solicitud, b.sla_horas)                   AS vence_en
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
        -- En el nuevo modelo no hay "aprobador asignado individual": las propuestas pendientes
        -- están disponibles para todo el equipo del área. Para resueltas se muestra quien resolvió.
        b.resuelto_por                             AS id_aprobador,
        (SELECT CONCAT(u.nombre, ' ', u.apellido) FROM usuario u
         WHERE u.id_usuario = b.resuelto_por)      AS aprobador,
        0                                          AS aprobador_es_suplente,
        0                                          AS reasignado,
        b.estado_vb, b.fecha_solicitud, b.fecha_respuesta, b.vence_en,
        b.sla_horas, b.horas_transcurridas,
        GREATEST(b.sla_horas - b.horas_transcurridas, 0) AS horas_restantes,
        b.sla_estado,
        b.comentario_solicitud, b.comentario_respuesta,
        -- Puede resolver cualquier supervisor/administrador del área del comercial autor.
        (b.estado_vb = 'pendiente' AND v_resolver = 1
         AND (v_todas = 1
              OR (v_rol_logueado IN ('supervisor','administrador')
                  AND v_area_logueado = b.area_comercial))) AS puede_resolver
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
            vb.fecha_solicitud,
            p.id_moneda, p.estado AS estado_propuesta,
            a.id_usuario AS id_comercial, a.area AS area_comercial
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
               (v_todas = 1
                OR (v_rol_logueado IN ('supervisor','administrador') AND v_area_logueado = b.area_comercial)
               ) AS en_alcance,
               FN_HorasHabiles(b.fecha_solicitud, NOW()) AS horas_transcurridas
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

    -- 5. Comerciales en alcance (para el filtro)
    SELECT DISTINCT
        a.id_usuario                     AS id,
        CONCAT(a.nombre, ' ', a.apellido) AS nombre,
        NULL                             AS codigo
    FROM usuario a
    WHERE a.eliminado_en IS NULL AND a.estado = 'activo'
      AND (v_todas = 1
           OR (v_rol_logueado IN ('supervisor','administrador') AND v_area_logueado = a.area))
    ORDER BY nombre;

    -- 6. Monedas disponibles (todas las usadas en VB del alcance)
    SELECT DISTINCT
        m.Num1    AS id,
        m.String3 AS nombre,
        m.String2 AS codigo
    FROM visto_bueno vb
    JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
    JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    WHERE vb.eliminado_en IS NULL
      AND (v_todas = 1
           OR (v_rol_logueado IN ('supervisor','administrador') AND v_area_logueado = a.area))
    ORDER BY nombre;

    -- 7. Políticas
    SELECT
        IFNULL((SELECT CAST(Num2 AS DECIMAL(10,2)) FROM tabla_maestra WHERE Descripcion='PARAMETRO_PROPUESTA' AND String2='DESCUENTO_APROBACION_ESPECIAL' LIMIT 1), 15) AS descuento_aprobacion_especial_pct,
        IFNULL((SELECT CAST(Num2 AS DECIMAL(10,2)) FROM tabla_maestra WHERE Descripcion='PARAMETRO_PROPUESTA' AND String2='MARGEN_MINIMO_PCT'             LIMIT 1), 15) AS margen_minimo_pct,
        IFNULL((SELECT CAST(Num2 AS DECIMAL(10,2)) FROM tabla_maestra WHERE Descripcion='PARAMETRO_PROPUESTA' AND String2='VB_SLA_HORAS_HABILES'          LIMIT 1), 4)  AS sla_horas_habiles,
        IFNULL((SELECT CAST(Num2 AS SIGNED)        FROM tabla_maestra WHERE Descripcion='PARAMETRO_PROPUESTA' AND String2='JORNADA_INICIO'                LIMIT 1), 9)  AS jornada_inicio,
        IFNULL((SELECT CAST(Num2 AS SIGNED)        FROM tabla_maestra WHERE Descripcion='PARAMETRO_PROPUESTA' AND String2='JORNADA_FIN'                   LIMIT 1), 18) AS jornada_fin,
        v_pct AS proximo_vencer_pct;
END$$

DELIMITER ;
