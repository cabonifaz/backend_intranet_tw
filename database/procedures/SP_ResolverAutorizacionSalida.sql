-- ============================================================
-- SP_ResolverAutorizacionSalida  (Intranet · App Mobile HU-04)
-- El encargado del área da (o niega) el visto bueno de salida de una OS desde la intranet.
--   - Área de la OS: la de la solicitud (area_destino) o, si no hay solicitud, la de la RQ
--     (requerimiento.id_area → area_servicio_rq).
--   - Pueden resolver: el encargado de ESA área (cargo jefe_* del área: Jefe de Servicio Técnico
--     o Jefe de Metrología; si la RQ no tiene área, cualquiera de los dos), el Jefe/Coordinador
--     de Operaciones (supervisión general) o un administrador. El encargado de la otra área NO.
--   - Si hay una solicitud pendiente del técnico, la resuelve; si no, registra el visto bueno igual.
--   - Solo mientras la OS siga programada/reprogramada.
--   - Notifica al técnico principal y al personal de la OS. Deja registro en auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverAutorizacionSalida;

DELIMITER $$

CREATE PROCEDURE SP_ResolverAutorizacionSalida(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal  BIGINT;
    DECLARE v_id_aut     BIGINT;
    DECLARE v_aut_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_area_sol   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- Quién es: encargado de un área (v_area_jefe) o supervisión general (v_general)
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin'))
    INTO   v_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede dar el visto bueno de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = IF(p_aprobar = 1, 'aprobada', 'rechazada');

    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_tecnico_principal, asr.area_usuario
    INTO   v_estado, v_numero, v_principal, v_area
    FROM   orden_servicio os
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La OS ya no está programada (', REPLACE(v_estado, '_', ' '), '): no requiere visto bueno.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.id_autorizacion, a.estado, IF(a.estado = 'pendiente', a.area_destino, NULL)
    INTO   v_id_aut, v_aut_estado, v_area_sol
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    -- La solicitud pendiente manda: es el área a la que se notificó
    IF v_aut_estado = 'pendiente' AND v_area_sol IS NOT NULL THEN
        SET v_area = v_area_sol;
    END IF;

    -- El encargado de la otra área no puede resolver (sí la supervisión general)
    IF v_general = 0 AND v_area IS NOT NULL AND v_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo autoriza el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'pendiente' THEN
        UPDATE autorizacion_salida_os
        SET    estado = v_nuevo, id_jefe = p_id_jefe, resuelto_en = NOW(),
               comentario = NULLIF(TRIM(p_comentario), ''), modificado_por = p_id_jefe
        WHERE  id_autorizacion = v_id_aut;
    ELSE
        INSERT INTO autorizacion_salida_os (id_os, id_tecnico, estado, area_destino, id_jefe, resuelto_en, comentario, creado_por)
        VALUES (p_id_os, v_principal, v_nuevo, v_area, p_id_jefe, NOW(), NULLIF(TRIM(p_comentario), ''), p_id_jefe);
        SET v_id_aut = LAST_INSERT_ID();
    END IF;

    -- Aviso al técnico principal y al personal de la OS
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           CONCAT(IF(p_aprobar = 1, 'Visto bueno de salida: ', 'Salida no autorizada: '), v_numero),
           CONCAT(v_jefe, IF(p_aprobar = 1, ' aprobó tu salida', ' no autorizó tu salida'), ' para la ', v_numero, '.',
                  IF(NULLIF(TRIM(p_comentario), '') IS NULL, '', CONCAT(' Comentario: ', TRIM(p_comentario)))),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM (
        SELECT v_principal AS id_usuario FROM DUAL WHERE v_principal IS NOT NULL
        UNION
        SELECT op.id_usuario FROM os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ) d;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'visto_bueno_salida', IFNULL(v_aut_estado, 'sin_solicitud'), v_nuevo,
            CONCAT(v_jefe, IF(p_aprobar = 1, ' dio el visto bueno de salida.', ' no autorizó la salida.'),
                   IF(NULLIF(TRIM(p_comentario), '') IS NULL, '', CONCAT(' ', TRIM(p_comentario)))),
            p_id_jefe, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area', v_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_aprobar = 1, 'Visto bueno de salida registrado.', 'Salida no autorizada.') AS Mensaje;
END$$

DELIMITER ;
