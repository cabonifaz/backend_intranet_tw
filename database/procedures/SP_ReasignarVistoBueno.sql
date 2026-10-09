-- HU-16 — Reasignar el aprobador del visto bueno pendiente.
--   Puede reasignar quien está a cargo del VB (FN_PuedeResolverVistoBueno) y tiene
--   la acción propuesta_vb_reasignar.
--   El nuevo aprobador debe cumplir las reglas de SP_ObtenerCandidatosReasignacionVb
--   (activo, puede resolver VB, rol que supervisa y no inferior al del comercial,
--   distinto del comercial y del aprobador actual).
--   Motivo obligatorio (MOTIVO_REASIGNACION_VB), comentario opcional.
--   El VB actual pasa a 'reasignado' y se crea uno nuevo 'pendiente'. Con
--   p_reiniciar_sla = 1 el plazo se cuenta desde ahora, si no se conserva la
--   fecha de solicitud original. Notifica al nuevo aprobador y al comercial.
DROP PROCEDURE IF EXISTS SP_ReasignarVistoBueno;

DELIMITER $$

CREATE PROCEDURE SP_ReasignarVistoBueno(
    IN p_id_propuesta       BIGINT,
    IN p_id_nuevo_aprobador BIGINT,
    IN p_id_motivo          INT,
    IN p_comentario         TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_reiniciar_sla      TINYINT,
    IN p_id_usuario         BIGINT
)
proc: BEGIN
    DECLARE v_id_vb        BIGINT;
    DECLARE v_id_vb_nuevo  BIGINT;
    DECLARE v_estado_p     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version      INT;
    DECLARE v_id_rq        BIGINT;
    DECLARE v_autor        BIGINT;
    DECLARE v_aprob_ant    BIGINT;
    DECLARE v_sla          INT;
    DECLARE v_fecha_sol    DATETIME;
    DECLARE v_fecha_nueva  DATETIME;
    DECLARE v_comentario_s TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nivel_aut    INT;
    DECLARE v_valido       TINYINT DEFAULT 0;
    DECLARE v_motivo_label VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo_nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ant_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_horas        DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_comentario    = NULLIF(TRIM(p_comentario), '');
    SET p_reiniciar_sla = IFNULL(p_reiniciar_sla, 0);

    SELECT p.estado, p.numero, p.version, p.id_requerimiento, COALESCE(p.id_responsable, p.id_creador)
      INTO v_estado_p, v_numero, v_version, v_id_rq, v_autor
    FROM propuesta_comercial p
    WHERE p.id_propuesta = p_id_propuesta AND p.eliminado_en IS NULL;

    IF v_estado_p IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_vb, sla_horas, fecha_solicitud, comentario
      INTO v_id_vb, v_sla, v_fecha_sol, v_comentario_s
    FROM visto_bueno
    WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente' AND eliminado_en IS NULL
    ORDER BY id_vb DESC LIMIT 1;

    IF v_id_vb IS NULL OR v_estado_p <> 'pendiente_vb' THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no tiene un visto bueno pendiente.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_reasignar') = 0
       OR FN_PuedeResolverVistoBueno(v_id_vb, p_id_usuario) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el aprobador asignado puede reasignar este visto bueno.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_motivo_label
    FROM tabla_maestra
    WHERE Descripcion = 'MOTIVO_REASIGNACION_VB' AND Num1 = p_id_motivo AND eliminado_en IS NULL
    LIMIT 1;

    IF v_motivo_label IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo de la reasignación.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Nuevo aprobador válido ──────────────────────────────────────────
    SET v_aprob_ant = FN_AprobadorVistoBueno(v_id_vb);

    SELECT IFNULL(t.Num1, 99) INTO v_nivel_aut
    FROM usuario u
    LEFT JOIN tabla_maestra t ON t.IdMaestro = 68 AND t.IdEmpresa = 1 AND t.String2 = u.rol_sistema
    WHERE u.id_usuario = v_autor;

    SELECT 1, CONCAT(u.nombre, ' ', u.apellido) INTO v_valido, v_nuevo_nombre
    FROM usuario u
    JOIN tabla_maestra t ON t.IdMaestro = 68 AND t.IdEmpresa = 1 AND t.String2 = u.rol_sistema AND t.Num3 = 1
    WHERE u.id_usuario = p_id_nuevo_aprobador
      AND u.eliminado_en IS NULL AND u.estado = 'activo'
      AND u.id_usuario <> v_autor
      AND u.id_usuario <> IFNULL(v_aprob_ant, 0)
      AND IFNULL(t.Num1, 99) <= IFNULL(v_nivel_aut, 99)
      AND FN_PermisoAccion(u.id_usuario, 'propuesta_vb_resolver') = 1;

    IF v_valido = 0 THEN
        SELECT 1 AS IdTipoMensaje,
               'El nuevo aprobador no es válido: debe ser un jefe activo con permiso de visto bueno, de rol igual o superior al del comercial y distinto del aprobador actual.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usu_nombre FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT CONCAT(nombre, ' ', apellido) INTO v_ant_nombre FROM usuario WHERE id_usuario = v_aprob_ant;
    SET v_horas       = FN_HorasHabiles(v_fecha_sol, NOW());
    SET v_fecha_nueva = IF(p_reiniciar_sla = 1, NOW(), v_fecha_sol);

    START TRANSACTION;

    UPDATE visto_bueno
       SET estado = 'reasignado', fecha_respuesta = NOW(), resuelto_por = p_id_usuario,
           comentario_respuesta = p_comentario, id_motivo_reasignacion = p_id_motivo,
           modificado_por = p_id_usuario
     WHERE id_vb = v_id_vb;

    INSERT INTO visto_bueno (id_propuesta, id_aprobador, id_vb_origen, estado, comentario, sla_horas,
                             fecha_solicitud, creado_en, creado_por)
    VALUES (p_id_propuesta, p_id_nuevo_aprobador, v_id_vb, 'pendiente', v_comentario_s, v_sla,
            v_fecha_nueva, NOW(), p_id_usuario);
    SET v_id_vb_nuevo = LAST_INSERT_ID();

    -- Canal 5 = Notificación en la plataforma
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_nuevo_aprobador, 5,
            CONCAT('Visto bueno reasignado: ', v_numero, ' v', v_version),
            CONCAT(v_usu_nombre, ' le reasignó el visto bueno de la propuesta ', v_numero, ' v', v_version,
                   ' (', v_motivo_label, ').',
                   IF(p_reiniciar_sla = 1, ' El plazo se reinició.', ' El plazo continúa desde la solicitud original.'),
                   IFNULL(CONCAT(' ', p_comentario), '')),
            'propuesta', p_id_propuesta, NOW(), p_id_usuario);

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_autor, 5,
            CONCAT('Cambio de aprobador: ', v_numero, ' v', v_version),
            CONCAT('El visto bueno de su propuesta ', v_numero, ' v', v_version, ' ahora lo revisa ', v_nuevo_nombre, '.'),
            'propuesta', p_id_propuesta, NOW(), p_id_usuario);

    IF v_id_rq IS NOT NULL THEN
        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta', 'Visto bueno reasignado', 'swap_horiz',
                CONCAT('VB de ', v_numero, ' v', v_version, ' reasignado de ', IFNULL(v_ant_nombre, '-'),
                       ' a ', v_nuevo_nombre, ' (', v_motivo_label, ').'),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', p_id_propuesta, 'vb_reasignar', 'pendiente_vb', 'pendiente_vb',
            CONCAT('Visto bueno reasignado de ', IFNULL(v_ant_nombre, '-'), ' a ', v_nuevo_nombre, ' (', v_motivo_label, ').'),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_vb_anterior',     v_id_vb,
                        'id_vb_nuevo',        v_id_vb_nuevo,
                        'id_aprobador_ant',   v_aprob_ant,
                        'id_aprobador_nuevo', p_id_nuevo_aprobador,
                        'id_motivo',          p_id_motivo,
                        'motivo',             v_motivo_label,
                        'comentario',         p_comentario,
                        'reiniciar_sla',      p_reiniciar_sla = 1,
                        'horas_habiles_transcurridas', v_horas,
                        'sla_horas',          v_sla));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Visto bueno reasignado a ', v_nuevo_nombre, '.') AS Mensaje;

    SELECT p_id_propuesta                                  AS id_propuesta,
           v_id_vb_nuevo                                   AS id_visto_bueno,
           p_id_nuevo_aprobador                            AS id_aprobador,
           v_nuevo_nombre                                  AS nombre_aprobador,
           v_fecha_nueva                                   AS fecha_solicitud,
           FN_SumarHorasHabiles(v_fecha_nueva, v_sla)      AS vence_en,
           p_reiniciar_sla                                 AS sla_reiniciado;
END$$

DELIMITER ;
