-- Resolver el visto bueno pendiente de una propuesta (HU-13 / HU-14).
--   p_accion: aprobar  → VB 'aprobado',  propuesta 'aprobado' (lista para enviar al cliente)
--             corregir → VB 'devuelto',  propuesta vuelve a 'borrador' (comentario obligatorio)
--             rechazar → VB 'rechazado', propuesta 'rechazado', queda cerrada (comentario obligatorio)
-- Puede resolver: el jefe directo del comercial, su suplente vigente (HU-84), o quien tenga la
-- acción propuesta_vb_todas. Además se exige la acción propuesta_vb_resolver.
-- Notifica al comercial y deja historial y auditoría.
-- HU-15 — Emisión de decisiones:
--   aprobar  → exige confirmar todas las VALIDACION_APROBACION_VB obligatorias
--              (p_validaciones = JSON con los códigos marcados), comentario opcional.
--   rechazar → exige motivo (MOTIVO_RECHAZO, IdMaestro 10) y justificación.
--   corregir → exige áreas (AREA_CORRECCION_PROPUESTA, JSON de códigos), observaciones
--              y fecha límite futura. Crea propuesta_correccion (responsable = comercial).
DROP PROCEDURE IF EXISTS SP_ResolverVistoBueno;

DELIMITER $$

CREATE PROCEDURE SP_ResolverVistoBueno(
    IN p_id_propuesta BIGINT,
    IN p_accion       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario   TEXT        CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_validaciones TEXT        CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo_rechazo INT,
    IN p_areas        TEXT        CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_limite DATETIME,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_id_vb        BIGINT;
    DECLARE v_estado_p     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version      INT;
    DECLARE v_id_rq        BIGINT;
    DECLARE v_autor        BIGINT;
    DECLARE v_jefe         BIGINT;
    DECLARE v_suplente     BIGINT;
    DECLARE v_estado_vb    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_nuevo VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etiqueta     VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_horas        DECIMAL(10,2);
    DECLARE v_sla          INT;
    DECLARE v_fecha_sol    DATETIME;
    DECLARE v_faltan       INT DEFAULT 0;
    DECLARE v_motivo_label VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_areas_label  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_areas_total  INT DEFAULT 0;
    DECLARE v_areas_ok     INT DEFAULT 0;
    DECLARE v_id_corr      BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_accion     = LOWER(TRIM(IFNULL(p_accion, '')));
    SET p_comentario = NULLIF(TRIM(p_comentario), '');

    IF p_accion NOT IN ('aprobar', 'corregir', 'rechazar') THEN
        SELECT 1 AS IdTipoMensaje, 'Acción no válida. Use aprobar, corregir o rechazar.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_accion IN ('corregir', 'rechazar') AND CHAR_LENGTH(IFNULL(p_comentario, '')) < 10 THEN
        SELECT 1 AS IdTipoMensaje,
               IF(p_accion = 'corregir', 'Indique qué debe corregir el comercial (mínimo 10 caracteres).',
                                         'Indique el motivo del rechazo (mínimo 10 caracteres).') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── HU-15: requisitos de cada decisión ──────────────────────────────
    SET p_validaciones = IF(TRIM(IFNULL(p_validaciones, '')) = '', '[]', p_validaciones);
    SET p_areas        = IF(TRIM(IFNULL(p_areas, '')) = '', '[]', p_areas);

    IF JSON_VALID(p_validaciones) = 0 OR JSON_VALID(p_areas) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Las validaciones y las áreas deben enviarse como lista.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_accion = 'aprobar' THEN
        SELECT COUNT(*), GROUP_CONCAT(String1 ORDER BY Num1 SEPARATOR ' ')
          INTO v_faltan, v_areas_label
        FROM tabla_maestra
        WHERE Descripcion = 'VALIDACION_APROBACION_VB' AND eliminado_en IS NULL AND IFNULL(Num2, 1) = 1
          AND JSON_CONTAINS(p_validaciones, JSON_QUOTE(String2)) = 0;

        IF v_faltan > 0 THEN
            SELECT 1 AS IdTipoMensaje, CONCAT('Confirme las validaciones requeridas: ', v_areas_label) AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_areas_label = NULL;
    END IF;

    IF p_accion = 'rechazar' THEN
        SELECT String1 INTO v_motivo_label
        FROM tabla_maestra
        WHERE IdMaestro = 10 AND IdEmpresa = 1 AND Num1 = p_id_motivo_rechazo AND eliminado_en IS NULL
        LIMIT 1;

        IF v_motivo_label IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo del rechazo.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF p_accion = 'corregir' THEN
        SELECT COUNT(*), COUNT(tm.String2),
               GROUP_CONCAT(tm.String1 ORDER BY tm.Num1 SEPARATOR ', ')
          INTO v_areas_total, v_areas_ok, v_areas_label
        FROM JSON_TABLE(p_areas, '$[*]' COLUMNS (codigo VARCHAR(40) PATH '$')) a
        LEFT JOIN tabla_maestra tm ON tm.Descripcion = 'AREA_CORRECCION_PROPUESTA'
                                  AND tm.String2 = a.codigo AND tm.eliminado_en IS NULL;

        IF v_areas_total = 0 OR v_areas_ok < v_areas_total THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione al menos un área válida a corregir.' AS Mensaje;
            LEAVE proc;
        END IF;

        IF p_fecha_limite IS NULL OR p_fecha_limite <= NOW() THEN
            SELECT 1 AS IdTipoMensaje, 'Indique una fecha y hora límite de corrección posterior a la actual.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SELECT p.estado, p.numero, p.version, p.id_requerimiento, COALESCE(p.id_responsable, p.id_creador)
      INTO v_estado_p, v_numero, v_version, v_id_rq, v_autor
    FROM propuesta_comercial p
    WHERE p.id_propuesta = p_id_propuesta AND p.eliminado_en IS NULL;

    IF v_estado_p IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_vb, sla_horas, fecha_solicitud INTO v_id_vb, v_sla, v_fecha_sol
    FROM visto_bueno
    WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente' AND eliminado_en IS NULL
    ORDER BY id_vb DESC LIMIT 1;

    IF v_id_vb IS NULL OR v_estado_p <> 'pendiente_vb' THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no tiene un visto bueno pendiente.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── ¿Quién puede resolver? ──────────────────────────────────────────
    SELECT id_supervisor INTO v_jefe FROM usuario WHERE id_usuario = v_autor;
    SELECT us.id_suplente INTO v_suplente
    FROM usuario_suplente us
    JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
    WHERE us.id_titular = v_jefe AND us.SoftDelete = 0 AND us.activo = 1
      AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
    ORDER BY us.fecha_inicio DESC LIMIT 1;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_resolver') = 0
       OR NOT (p_id_usuario = v_jefe OR p_id_usuario = v_suplente
               OR FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 1) THEN
        SELECT 1 AS IdTipoMensaje,
               'Solo el jefe directo del comercial (o su suplente vigente) puede resolver este visto bueno.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario = v_autor AND FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No puede dar visto bueno a una propuesta propia.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado_vb    = CASE p_accion WHEN 'aprobar' THEN 'aprobado' WHEN 'corregir' THEN 'devuelto' ELSE 'rechazado' END;
    SET v_estado_nuevo = CASE p_accion WHEN 'aprobar' THEN 'aprobado' WHEN 'corregir' THEN 'borrador' ELSE 'rechazado' END;
    SET v_etiqueta     = CASE p_accion WHEN 'aprobar' THEN 'aprobada' WHEN 'corregir' THEN 'devuelta para corrección' ELSE 'rechazada' END;
    SET v_horas        = FN_HorasHabiles(v_fecha_sol, NOW());
    SELECT CONCAT(nombre, ' ', apellido) INTO v_usu_nombre FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    UPDATE visto_bueno
       SET estado = v_estado_vb, fecha_respuesta = NOW(), resuelto_por = p_id_usuario,
           comentario_respuesta = p_comentario, modificado_por = p_id_usuario,
           id_motivo_rechazo = IF(p_accion = 'rechazar', p_id_motivo_rechazo, NULL),
           validaciones_confirmadas = IF(p_accion = 'aprobar', CAST(p_validaciones AS JSON), NULL)
     WHERE id_vb = v_id_vb;

    IF p_accion = 'corregir' THEN
        UPDATE propuesta_correccion
           SET estado = 'cancelada'
         WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente';

        INSERT INTO propuesta_correccion (id_propuesta, id_vb, areas, observaciones, id_responsable,
                                          fecha_limite, estado, solicitado_por, creado_en)
        VALUES (p_id_propuesta, v_id_vb, CAST(p_areas AS JSON), p_comentario, v_autor,
                p_fecha_limite, 'pendiente', p_id_usuario, NOW());
        SET v_id_corr = LAST_INSERT_ID();
    END IF;

    UPDATE propuesta_comercial
       SET estado = v_estado_nuevo, modificado_en = NOW(), modificado_por = p_id_usuario
     WHERE id_propuesta = p_id_propuesta;

    -- Canal 5 = Notificación en la plataforma
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_autor, 5,
            CONCAT('Propuesta ', v_etiqueta, ': ', v_numero, ' v', v_version),
            CONCAT(v_usu_nombre, ' ',
                   CASE p_accion WHEN 'aprobar'  THEN 'aprobó la propuesta. Ya puede enviarla al cliente.'
                                 WHEN 'corregir' THEN CONCAT('solicitó correcciones en ', v_areas_label,
                                                             ' (límite ', DATE_FORMAT(p_fecha_limite, '%d/%m/%Y %H:%i'), '): ')
                                 ELSE CONCAT('rechazó la propuesta (', v_motivo_label, '): ') END,
                   IFNULL(IF(p_accion = 'aprobar', NULL, p_comentario), '')),
            'propuesta', p_id_propuesta, NOW(), p_id_usuario);

    IF v_id_rq IS NOT NULL THEN
        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta', CONCAT('Visto bueno: ', v_etiqueta),
                CASE p_accion WHEN 'aprobar' THEN 'verified' WHEN 'corregir' THEN 'undo' ELSE 'block' END,
                CONCAT('Propuesta ', v_numero, ' v', v_version, ' ', v_etiqueta, '.'),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', p_id_propuesta, CONCAT('vb_', p_accion), 'pendiente_vb', v_estado_nuevo,
            CONCAT('Propuesta ', v_etiqueta, ' en visto bueno por ', v_usu_nombre,
                   IF(p_id_usuario = v_suplente, ' (suplente del jefe directo)', ''), '.'),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_vb', v_id_vb, 'es_suplente', p_id_usuario = v_suplente,
                        'horas_habiles', v_horas, 'sla_horas', v_sla, 'dentro_sla', v_horas <= v_sla,
                        'comentario', p_comentario,
                        'validaciones', IF(p_accion = 'aprobar', CAST(p_validaciones AS JSON), NULL),
                        'id_motivo_rechazo', IF(p_accion = 'rechazar', p_id_motivo_rechazo, NULL),
                        'motivo_rechazo', v_motivo_label,
                        'id_correccion', v_id_corr,
                        'areas', IF(p_accion = 'corregir', CAST(p_areas AS JSON), NULL),
                        'fecha_limite', p_fecha_limite));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Propuesta ', v_etiqueta, '.') AS Mensaje;
    SELECT p_id_propuesta AS id_propuesta, v_estado_nuevo AS estado, v_estado_vb AS estado_vb,
           v_id_corr AS id_correccion, IF(p_accion = 'corregir', p_fecha_limite, NULL) AS fecha_limite;
END$$

DELIMITER ;
