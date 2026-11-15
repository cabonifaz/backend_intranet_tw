-- HU-52 (Sprint 5) El encargado aprueba o rechaza un ensayo guardado con error crítico (HU-10: "Guardar de todas formas", migraciones 100 y 107).
--   Pueden resolver: el encargado del área de la RQ de la OS (Jefe de Servicio Técnico / Jefe de Metrología o el supervisor de Metrología), la supervisión
--   general (Jefe o Coordinador de Operaciones, supervisor de Operaciones) y los administradores. El de la otra área NO.
--   El informe debe ser de ESA OS (p_id_os NULL/0 = la del informe, desde la app), tener el error crítico registrado y estar sin revisar.
--   Comentario hasta 500 caracteres, obligatorio al rechazar (la intranet lo exige siempre en su caso de uso).
--   Rechazar no borra las lecturas: queda registrada la decisión y se avisa al técnico para que repita o corrija el ensayo.
--   Notifica al técnico y deja el registro en auditoria_evento. Requiere la migración 113.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
DROP PROCEDURE IF EXISTS SP_ResolverEnsayoConError;

DELIMITER $$

CREATE PROCEDURE SP_ResolverEnsayoConError(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_informe BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT;
    DECLARE v_revision   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    BIGINT;
    DECLARE v_equipo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aprobar    TINYINT DEFAULT 0;
    DECLARE v_nuevo      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND IFNULL(v_general, 0) = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede resolver el ensayo con error.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SET v_aprobar = IF(IFNULL(p_aprobar, 0) = 1, 1, 0);
    SET v_nuevo   = IF(v_aprobar = 1, 'aprobada', 'rechazada');
    IF (v_aprobar = 0 AND v_com IS NULL) OR CHAR_LENGTH(IFNULL(v_com, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, IF(v_com IS NULL, 'Indica el motivo del rechazo.', 'El comentario admite hasta 500 caracteres.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Desde la app llega solo el id del informe: la OS se toma del informe
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT MAX(id_os) INTO p_id_os FROM informe_tecnico WHERE id_informe = p_id_informe AND eliminado_en IS NULL;
    END IF;

    START TRANSACTION;

    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente       = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_numero IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT it.id_informe, it.error_critico_revision, it.error_critico_motivo, it.id_tecnico, ec.codigo_tw
    INTO   v_id, v_revision, v_motivo, v_tecnico, v_equipo
    FROM   informe_tecnico it
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    WHERE  it.id_informe = p_id_informe AND it.id_os = p_id_os AND it.eliminado_en IS NULL
    FOR UPDATE;

    IF v_id IS NULL OR v_motivo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El ensayo con error no existe en este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_revision IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este ensayo ya fue revisado (quizá por otra persona).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(v_general, 0) = 0 AND v_area IS NOT NULL AND v_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo revisa el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE informe_tecnico
    SET    error_critico_revision = v_nuevo, error_critico_revisado_por = p_id_jefe, error_critico_revisado_en = NOW(),
           error_critico_comentario = v_com, modificado_por = p_id_jefe
    WHERE  id_informe = v_id;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT v_tecnico, 5,
           IF(v_aprobar = 1, 'Ensayo con error aprobado', 'Ensayo con error rechazado'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), IF(v_equipo IS NULL, '', CONCAT(' · ', v_equipo)),
                       ' · ', v_jefe, IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(v_aprobar = 1, CONCAT(' aprobó el ensayo guardado con error crítico.', IF(v_com IS NULL, '', CONCAT(' Comentario: ', v_com))),
                                         CONCAT(' rechazó el ensayo guardado con error crítico: repítelo o corrige las lecturas. Motivo: ', v_com))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM   DUAL
    WHERE  v_tecnico IS NOT NULL AND v_tecnico <> p_id_jefe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'resolver_ensayo_error', 'pendiente', v_nuevo,
            LEFT(CONCAT(v_jefe, IF(v_aprobar = 1, ' aprobó', ' rechazó'), ' el ensayo con error crítico',
                        IF(v_equipo IS NULL, '', CONCAT(' del equipo ', v_equipo)), '.', IF(v_com IS NULL, '', CONCAT(' ', v_com))), 900),
            p_id_jefe, NOW(), JSON_OBJECT('id_informe', v_id, 'area', v_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_aprobar = 1, 'Ensayo con error aprobado.', 'Ensayo con error rechazado: se avisó al técnico.') AS Mensaje;
END$$

DELIMITER ;
