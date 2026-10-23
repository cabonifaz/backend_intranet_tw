-- ============================================================
-- SP_SolicitarAutorizacionSalidaMovil  (App Mobile HU-04)
-- El técnico pide el visto bueno para salir con pendientes al ENCARGADO DEL ÁREA del servicio.
--   - El área sale de la RQ de la OS: orden_servicio → expediente_digital → requerimiento.id_area
--     (catálogo AREA_REQUERIMIENTO 64) → area_servicio_rq → servicio_tecnico | metrologia.
--   - Encargado = usuario activo cuyo cargo es el "jefe_*" de esa área en CARGO_USUARIO (80):
--     Jefe de Servicio Técnico o Jefe de Metrología.
--   - Si la RQ no tiene área (o no está mapeada) se notifica a ambos encargados.
--   - Respaldo si el área no tiene encargado activo: supervisores/administradores del área;
--     si tampoco, Jefe/Coordinador de Operaciones; si tampoco, administradores.
--   - Una sola solicitud pendiente por OS (evita duplicados y spam de notificaciones).
--   - Deja registro en autorizacion_salida_os (con area_destino) y auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarAutorizacionSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarAutorizacionSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_motivo     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pendientes VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_aut      BIGINT;
    DECLARE v_destinos    INT DEFAULT 0;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    START TRANSACTION;

    SELECT os.estado, os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_estado, v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente        = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente     = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento  = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq       = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está programado: no hace falta autorización de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.estado INTO v_aut_estado
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    IF v_aut_estado = 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya enviaste una solicitud: espera la respuesta del encargado del área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'aprobada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya tienes el visto bueno: puedes iniciar el traslado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico
    FROM usuario WHERE id_usuario = p_id_usuario;

    SET v_area_nombre = (SELECT t.String1 FROM tabla_maestra t
                         WHERE t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1);

    INSERT INTO autorizacion_salida_os (id_os, id_tecnico, motivo, pendientes, estado, area_destino, solicitado_en, creado_por)
    VALUES (p_id_os, p_id_usuario, NULLIF(TRIM(p_motivo), ''), NULLIF(TRIM(p_pendientes), ''), 'pendiente', v_area, NOW(), p_id_usuario);
    SET v_id_aut = LAST_INSERT_ID();

    -- Destinatarios (en una tabla temporal para notificar y responder con los nombres)
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;
    CREATE TEMPORARY TABLE tmp_aut_destino (
        id_usuario BIGINT PRIMARY KEY,
        nombre     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- 1) Encargado(s) del área: cargo jefe_* del área (si la RQ no tiene área: de ambas áreas)
    INSERT IGNORE INTO tmp_aut_destino
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
    FROM   usuario u
    JOIN   tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
      AND  c.String2 LIKE 'jefe\_%'
      AND  ((v_area IS NOT NULL AND c.String3 = v_area)
            OR (v_area IS NULL AND c.String3 IN ('servicio_tecnico', 'metrologia')));

    -- 2) Respaldo: supervisores / administradores del área
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.rol_sistema IN ('supervisor', 'administrador')
          AND  ((v_area IS NOT NULL AND u.area = v_area)
                OR (v_area IS NULL AND u.area IN ('servicio_tecnico', 'metrologia')));
    END IF;

    -- 3) Respaldo: Jefe / Coordinador de Operaciones
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.cargo IN ('jefe_operaciones', 'coordinador_operaciones');
    END IF;

    -- 4) Respaldo final: administradores
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('administrador', 'admin');
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           CONCAT('Autorización de salida', IF(v_area_nombre IS NULL, '', CONCAT(' · ', v_area_nombre)), ': ', v_numero),
           CONCAT(v_tecnico, ' solicita tu visto bueno para salir a ', IFNULL(v_cliente, 'el cliente'), ' (', v_numero, ').',
                  IF(v_area_nombre IS NULL, ' La RQ no indica el área del servicio.', CONCAT(' Área del servicio según la RQ: ', v_area_nombre, '.')),
                  IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.')),
                  IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))),
           'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM   tmp_aut_destino d;
    SET v_destinos = ROW_COUNT();

    SELECT GROUP_CONCAT(CONCAT(d.nombre, IFNULL(CONCAT(' (', d.cargo, ')'), '')) ORDER BY d.nombre SEPARATOR ', ')
    INTO   v_notificados
    FROM   tmp_aut_destino d;
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_autorizacion_salida', IFNULL(v_aut_estado, 'sin_solicitud'), 'pendiente',
            CONCAT('El técnico solicita visto bueno para salir.',
                   IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.'))),
            p_id_usuario, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area_destino', v_area, 'notificados', v_destinos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_destinos > 0,
              CONCAT('Solicitud enviada a ', v_notificados, '.'),
              'Solicitud registrada, pero no hay un encargado activo para notificar: avisa a tu jefe.') AS Mensaje;
END$$

DELIMITER ;
