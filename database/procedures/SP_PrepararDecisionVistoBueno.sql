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

    SELECT id_supervisor INTO v_jefe FROM usuario WHERE id_usuario = v_autor;
    SELECT us.id_suplente INTO v_suplente
    FROM usuario_suplente us
    JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
    WHERE us.id_titular = v_jefe AND us.SoftDelete = 0 AND us.activo = 1
      AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
    ORDER BY us.fecha_inicio DESC LIMIT 1;

    IF v_id_vb IS NULL OR v_estado_p <> 'pendiente_vb' THEN
        SET v_puede = 0, v_bloqueo = 'La propuesta no tiene un visto bueno pendiente.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_resolver') = 0
        OR FN_PuedeResolverVistoBueno(v_id_vb, p_id_usuario) = 0 THEN
        SET v_puede = 0, v_bloqueo = 'Solo el aprobador asignado (jefe directo, su suplente vigente o a quien se reasignó) puede resolver este visto bueno.';
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

    SELECT String2 AS codigo, String1 AS etiqueta
    FROM tabla_maestra
    WHERE Descripcion = 'AREA_CORRECCION_PROPUESTA' AND eliminado_en IS NULL
    ORDER BY Num1;
END$$

DELIMITER ;
