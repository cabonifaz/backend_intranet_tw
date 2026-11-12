-- ============================================================
-- SP_ResolverLlegadaForzada  (App Mobile HU-06 / HU-31 — el encargado aprueba o rechaza la llegada forzada · escritura)
--   - Pueden resolver las mismas personas que ven la solicitud (SP_ObtenerLlegadasForzadas): el encargado del ÁREA de la solicitud, la supervisión
--     general (Jefe/Coordinador de Operaciones, supervisor de Operaciones) y los administradores. El de la otra área NO.
--   - Solo una solicitud PENDIENTE de la OS; el comentario es obligatorio (condición al aprobar, motivo al rechazar; 3 a 500 caracteres).
--   - Aprobar deja a la OS lista para que el técnico registre su llegada UNA vez (SP_EvaluarLlegadaMovil → 'autorizada'); rechazar le pide volver a
--     acercarse (puede intentarlo otra vez tras 5 capturas más).
--   - Notifica al técnico principal y al personal de la OS («Llegada forzada aprobada/rechazada») y deja el registro en auditoria_evento.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverLlegadaForzada;

DELIMITER $$

CREATE PROCEDURE SP_ResolverLlegadaForzada(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_principal  BIGINT;
    DECLARE v_id_sol     BIGINT;
    DECLARE v_sol_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sol_area   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
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

    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede resolver la llegada forzada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(p_comentario), '') IS NULL OR CHAR_LENGTH(TRIM(p_comentario)) < 3 THEN
        SELECT 1 AS IdTipoMensaje, IF(p_aprobar = 1, 'Indica la condición con la que autorizas la llegada.', 'Indica el motivo por el que no autorizas la llegada.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = IF(p_aprobar = 1, 'aprobada', 'rechazada');

    START TRANSACTION;

    SELECT os.numero, os.estado, os.id_tecnico_principal, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)
    INTO   v_numero, v_estado_os, v_principal, v_cliente
    FROM   orden_servicio os
    LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_numero IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT s.id_solicitud, s.estado, s.area_destino INTO v_id_sol, v_sol_estado, v_sol_area
    FROM   llegada_forzada_os s
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL
    ORDER BY s.id_solicitud DESC LIMIT 1;

    IF v_id_sol IS NULL OR v_sol_estado <> 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay una solicitud de llegada forzada pendiente para este servicio (quizá ya la resolvió otra persona).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_general = 0 AND v_sol_area IS NOT NULL AND v_sol_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo autoriza el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_aprobar = 1 AND v_estado_os <> 'en_ruta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está en ruta: no hace falta autorizar la llegada.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE llegada_forzada_os
    SET    estado = v_nuevo, id_jefe = p_id_jefe, resuelto_en = NOW(), comentario = TRIM(p_comentario), modificado_por = p_id_jefe
    WHERE  id_solicitud = v_id_sol;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           IF(p_aprobar = 1, 'Llegada forzada aprobada', 'Llegada forzada rechazada'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), ' · ', v_jefe,
                       IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(p_aprobar = 1, ' autorizó tu llegada: ya puedes registrarla.', ' no autorizó tu llegada: acércate a la planta.'),
                       IF(p_aprobar = 1, ' Condición: ', ' Motivo: '), TRIM(p_comentario)), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM (
        SELECT v_principal AS id_usuario FROM DUAL WHERE v_principal IS NOT NULL
        UNION
        SELECT op.id_usuario FROM os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ) d;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'resolver_llegada_forzada', 'pendiente', v_nuevo,
            LEFT(CONCAT(v_jefe, IF(p_aprobar = 1, ' autorizó la llegada forzada.', ' no autorizó la llegada forzada.'), ' ', TRIM(p_comentario)), 900),
            p_id_jefe, NOW(), JSON_OBJECT('id_solicitud', v_id_sol, 'area', v_sol_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_aprobar = 1, 'Llegada autorizada: el técnico ya puede registrarla.', 'Llegada no autorizada.') AS Mensaje;
END$$

DELIMITER ;
