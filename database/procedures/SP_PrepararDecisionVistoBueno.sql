-- HU-15 — Datos de los modales Aprobar, Rechazar y Solicitar Corrección.
--   No cambia nada. Indica si el usuario puede resolver el VB (misma regla que
--   SP_ResolverVistoBueno: jefe directo del comercial, su suplente vigente o
--   quien tenga propuesta_vb_todas, y nunca su propia propuesta).
--   Resultados: 1 header · 2 resumen · 3 validaciones requeridas (aprobar)
--               4 motivos de rechazo (MOTIVO_RECHAZO, tal cual) · 5 áreas a corregir
DROP PROCEDURE IF EXISTS SP_PrepararDecisionVistoBueno;

DELIMITER $$

CREATE PROCEDURE SP_PrepararDecisionVistoBueno(
    IN p_id_propuesta BIGINT,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_estado_p   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_autor      BIGINT;
    DECLARE v_jefe       BIGINT;
    DECLARE v_suplente   BIGINT;
    DECLARE v_id_vb      BIGINT;
    DECLARE v_puede      TINYINT DEFAULT 1;
    DECLARE v_bloqueo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_plazo      DECIMAL(10,2);

    SELECT estado, COALESCE(id_responsable, id_creador)
      INTO v_estado_p, v_autor
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado_p IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_vb INTO v_id_vb
    FROM visto_bueno
    WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente' AND eliminado_en IS NULL
    ORDER BY id_vb DESC LIMIT 1;

    -- Modelo nuevo: cualquier supervisor o administrador activo del área del comercial
    -- autor puede resolver (o Gerencia/TI con propuesta_vb_todas). v_jefe / v_suplente
    -- quedan en NULL por compatibilidad con el resto del SP.
    SET v_jefe     = NULL;
    SET v_suplente = NULL;

    IF v_id_vb IS NULL OR v_estado_p <> 'pendiente_vb' THEN
        SET v_puede = 0, v_bloqueo = 'La propuesta no tiene un visto bueno pendiente.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_resolver') = 0 THEN
        SET v_puede = 0, v_bloqueo = 'No tiene permiso para resolver visto bueno.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 0 AND NOT EXISTS (
        SELECT 1 FROM usuario u
        JOIN usuario a ON a.id_usuario = v_autor
        WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
          AND u.rol_sistema IN ('supervisor', 'administrador')
          AND u.area        = a.area
    ) THEN
        SET v_puede = 0, v_bloqueo = 'Solo supervisores o administradores del área del comercial pueden resolver este visto bueno.';
    ELSEIF p_id_usuario = v_autor AND FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 0 THEN
        SET v_puede = 0, v_bloqueo = 'No puede dar visto bueno a una propuesta propia.';
    END IF;

    SELECT IFNULL(MAX(Num2), 8) INTO v_plazo
    FROM tabla_maestra
    WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'CORRECCION_PLAZO_HORAS' AND eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT p.id_propuesta, p.numero, p.version, p.estado, p.total,
           tm_mon.String2                         AS moneda_simbolo,
           tm_mon.String3                         AS moneda_codigo,
           c.razon_social                         AS cliente,
           v_autor                                AS id_comercial,
           CONCAT(ua.nombre, ' ', ua.apellido)    AS nombre_comercial,
           v_id_vb                                AS id_visto_bueno,
           v_puede                                AS puede_resolver,
           v_bloqueo                              AS motivo_bloqueo,
           FN_SumarHorasHabiles(NOW(), v_plazo)   AS fecha_limite_sugerida
    FROM propuesta_comercial p
    JOIN cliente c                 ON c.id_cliente = p.id_cliente
    LEFT JOIN usuario ua           ON ua.id_usuario = v_autor
    LEFT JOIN tabla_maestra tm_mon ON tm_mon.IdMaestro = 1 AND tm_mon.IdEmpresa = 1 AND tm_mon.Num1 = p.id_moneda
    WHERE p.id_propuesta = p_id_propuesta;

    SELECT String2 AS codigo, String1 AS texto, IFNULL(Num2, 1) AS obligatoria
    FROM tabla_maestra
    WHERE Descripcion = 'VALIDACION_APROBACION_VB' AND eliminado_en IS NULL
    ORDER BY Num1;

    SELECT Num1 AS id, String1 AS nombre
    FROM tabla_maestra
    WHERE IdMaestro = 10 AND IdEmpresa = 1 AND eliminado_en IS NULL
    ORDER BY Num1;

    -- Áreas a corregir = secciones del wizard que REALMENTE tiene esta propuesta.
    -- Fijas (siempre presentes): configuracion, propuesta, forma_pago, listado_equipos.
    -- Opcionales: solo si están en propuesta_comercial.secciones_activas (JSON array).
    -- Si secciones_activas es NULL (propuestas viejas), se muestran todas las opcionales.
    SELECT codigo, etiqueta
    FROM (
        SELECT 1 AS orden, 'configuracion'       AS codigo, 'Configuración'       AS etiqueta, 1 AS incluir UNION ALL
        SELECT 2, 'propuesta',           'Ítems y precios',    1                                              UNION ALL
        SELECT 3, 'opcionales',          'Opcionales',         IF((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta) IS NULL
                                                                  OR JSON_CONTAINS((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), '"opcionales"'), 1, 0) UNION ALL
        SELECT 4, 'detalle',             'Detalle',            IF((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta) IS NULL
                                                                  OR JSON_CONTAINS((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), '"detalle"'), 1, 0) UNION ALL
        SELECT 5, 'recomendaciones',     'Recomendaciones',    IF((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta) IS NULL
                                                                  OR JSON_CONTAINS((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), '"recomendaciones"'), 1, 0) UNION ALL
        SELECT 6, 'forma_pago',          'Forma de Pago',      1                                              UNION ALL
        SELECT 7, 'suministros_cliente', 'Suministros Cliente',IF((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta) IS NULL
                                                                  OR JSON_CONTAINS((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), '"suministros_cliente"'), 1, 0) UNION ALL
        SELECT 8, 'condiciones',         'Condiciones',        IF((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta) IS NULL
                                                                  OR JSON_CONTAINS((SELECT secciones_activas FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), '"condiciones"'), 1, 0) UNION ALL
        SELECT 9, 'listado_equipos',     'Listado de Equipos', 1
    ) areas
    WHERE incluir = 1
    ORDER BY orden;
END$$

DELIMITER ;
