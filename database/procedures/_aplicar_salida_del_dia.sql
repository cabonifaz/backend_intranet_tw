-- Aplicar en la base (solo procedimientos, sin datos). NO subir al repositorio.

-- ============================================================
-- SP_ObtenerSalidaHabilitadaMovil  (App Mobile HU-04 — apoyo, no es un endpoint)
-- Regla única: la salida (validar el checklist, pedir autorización e iniciar el traslado) solo se
-- habilita desde el DÍA programado de la OS. Antes, el técnico puede ver el detalle pero no validar la salida.
--   p_habilitada: 1 = hoy (o antes) es la fecha de ejecución, o la OS no tiene fecha; 0 = aún no es el día.
--   p_mensaje   : NULL si está habilitada; si no, "Aún no es el día del servicio. Podrás validar la salida el dd/mm/aaaa."
-- "Hoy" es la fecha de Lima (UTC-5, sin horario de verano), calculada desde UTC para no depender de la zona del servidor.
-- Lo usan SP_ObtenerChecklistSalidaMovil (lo informa a la app) y los SP que modifican (Marcar, Solicitar, IniciarTraslado).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerSalidaHabilitadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSalidaHabilitadaMovil(
    IN  p_id_os      BIGINT,
    OUT p_habilitada TINYINT,
    OUT p_mensaje    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_fecha DATE DEFAULT NULL;
    DECLARE v_hoy   DATE;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    SELECT DATE(os.fecha_ejecucion) INTO v_fecha
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;

    IF v_fecha IS NOT NULL AND v_fecha > v_hoy THEN
        SET p_habilitada = 0;
        SET p_mensaje    = CONCAT('Aún no es el día del servicio. Podrás validar la salida el ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), '.');
    ELSE
        SET p_habilitada = 1;
        SET p_mensaje    = NULL;
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerChecklistSalidaMovil  (App Mobile HU-04 — Checklist de pre-salida)
-- Datos con los que el back arma el checklist (las reglas viven en C#: ReglasChecklistSalida).
-- Solo lectura. Mismo control de acceso que el detalle (OS del técnico que inició sesión).
-- Resultados:
--   1. Encabezado
--   2. Una fila: datos de la tarjeta + estado de cada ítem + autorización vigente
--      + área que autoriza la salida (según la RQ) y su(s) encargado(s)
--      + salida_habilitada / salida_mensaje: la salida se valida solo desde el día programado
--        (regla en SP_ObtenerSalidaHabilitadaMovil; la consulta sigue disponible antes de ese día).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerChecklistSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerChecklistSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_salida_ok  TINYINT DEFAULT 1;
    DECLARE v_salida_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    IF NOT EXISTS (SELECT 1 FROM orden_servicio os
                   WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL
                     AND (os.id_tecnico_principal = p_id_usuario
                          OR EXISTS (SELECT 1 FROM os_personal op
                                     WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))) THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           TRIM(CONCAT(IFNULL(tp.nombre, ''), ' ', IFNULL(tp.apellido, '')))  AS tecnico,
           os.estado                                                        AS estado_os,
           os.id_tipo_servicio,
           os.confirmacion_cliente                                          AS cliente_confirmado,
           COALESCE(
               (SELECT op.estado_ssoma FROM os_personal op
                WHERE  op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
               (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                            WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                            WHEN COUNT(*) > 0 THEN 'habilitado' END
                FROM   os_personal op WHERE op.id_os = os.id_os AND op.eliminado_en IS NULL),
               'pendiente')                                                 AS estado_ssoma,
           (ed.id_orden_compra IS NOT NULL)                                 AS tiene_oc,
           (SELECT COUNT(*) FROM item_presalida ip
            WHERE  ip.id_os = os.id_os AND ip.id_tipo_item = 1 AND ip.eliminado_en IS NULL)                     AS repuestos_total,
           (SELECT COUNT(*) FROM item_presalida ip
            WHERE  ip.id_os = os.id_os AND ip.id_tipo_item = 1 AND ip.confirmado = 0 AND ip.eliminado_en IS NULL) AS repuestos_pendientes,
           (SELECT COUNT(*) FROM alerta_predictiva ap
            WHERE  ap.id_os = os.id_os AND ap.resuelta = 0 AND ap.eliminado_en IS NULL)                         AS alertas_pendientes,
           -- Confirmaciones del técnico
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'expediente'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_expediente,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'epp'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_epp,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'materiales'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_materiales,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'herramientas'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_herramientas,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'pesas_patron'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_pesas_patron,
           -- Autorización vigente (la última de la OS)
           au.estado                                                        AS aut_estado,
           au.comentario                                                    AS aut_comentario,
           au.solicitado_en                                                 AS aut_solicitado_en,
           au.resuelto_en                                                   AS aut_resuelto_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS aut_jefe,
           -- Área que autoriza (la de la solicitud vigente o, si no hay, la de la RQ)
           COALESCE(au.area_destino, asr.area_usuario)                      AS area_autoriza_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1
              AND  t.String2 = COALESCE(au.area_destino, asr.area_usuario) LIMIT 1)          AS area_autoriza,
           (SELECT c.String1 FROM tabla_maestra c
            WHERE  c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 LIKE 'jefe\_%'
              AND  c.String3 = COALESCE(au.area_destino, asr.area_usuario) LIMIT 1)          AS cargo_encargado,
           (SELECT GROUP_CONCAT(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) ORDER BY u.nombre SEPARATOR ', ')
            FROM   usuario u
            JOIN   tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND c.String2 LIKE 'jefe\_%'
              AND  c.String3 = COALESCE(au.area_destino, asr.area_usuario))                 AS encargado_area,
           -- La salida solo se valida desde el día programado
           v_salida_ok                                                      AS salida_habilitada,
           v_salida_msg                                                     AS salida_mensaje
    FROM   orden_servicio os
    LEFT JOIN cliente            cl ON cl.id_cliente    = os.id_cliente
    LEFT JOIN usuario            tp ON tp.id_usuario    = os.id_tecnico_principal
    LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
    LEFT JOIN autorizacion_salida_os au
           ON au.id_autorizacion = (SELECT MAX(a2.id_autorizacion) FROM autorizacion_salida_os a2
                                    WHERE a2.id_os = os.id_os AND a2.eliminado_en IS NULL)
    LEFT JOIN usuario            jf ON jf.id_usuario    = au.id_jefe
    LEFT JOIN requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq  = rq.id_area
    WHERE  os.id_os = p_id_os;
END$$

DELIMITER ;

-- ============================================================
-- SP_MarcarChecklistSalidaMovil  (App Mobile HU-04)
-- El técnico confirma (o desmarca) un ítem manual del checklist de pre-salida.
--   p_codigo: expediente | epp | materiales | herramientas | pesas_patron  (lista blanca)
-- Solo mientras la OS siga programada/reprogramada y desde el día programado (SP_ObtenerSalidaHabilitadaMovil).
-- Deja registro en auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_MarcarChecklistSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_MarcarChecklistSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigo     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_confirmado TINYINT
)
proc: BEGIN
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id       BIGINT;
    DECLARE v_anterior TINYINT DEFAULT 0;
    DECLARE v_nombre   VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_ok  TINYINT DEFAULT 1;
    DECLARE v_salida_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_nombre = CASE p_codigo
                       WHEN 'expediente'   THEN 'Expediente revisado'
                       WHEN 'epp'          THEN 'EPP revisado'
                       WHEN 'materiales'   THEN 'Materiales e insumos'
                       WHEN 'herramientas' THEN 'Herramientas listas'
                       WHEN 'pesas_patron' THEN 'Pesas patrón asignadas'
                   END;

    IF v_nombre IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ítem del checklist no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT os.estado INTO v_estado
    FROM   orden_servicio os
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
        SELECT 1 AS IdTipoMensaje, 'El traslado ya se inició: el checklist ya no se puede cambiar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- La salida se valida solo desde el día programado
    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);
    IF v_salida_ok = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_salida_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT c.id_checklist, c.confirmado INTO v_id, v_anterior
    FROM   checklist_presalida_os c
    WHERE  c.id_os = p_id_os AND c.codigo = p_codigo AND c.eliminado_en IS NULL
    ORDER BY c.id_checklist DESC LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO checklist_presalida_os (id_os, codigo, confirmado, confirmado_por, confirmado_en, creado_por)
        VALUES (p_id_os, p_codigo, IF(p_confirmado = 1, 1, 0),
                IF(p_confirmado = 1, p_id_usuario, NULL), IF(p_confirmado = 1, NOW(), NULL), p_id_usuario);
    ELSE
        UPDATE checklist_presalida_os
        SET    confirmado     = IF(p_confirmado = 1, 1, 0),
               confirmado_por = IF(p_confirmado = 1, p_id_usuario, NULL),
               confirmado_en  = IF(p_confirmado = 1, NOW(), NULL),
               modificado_por = p_id_usuario
        WHERE  id_checklist = v_id;
    END IF;

    IF IFNULL(v_anterior, 0) <> IF(p_confirmado = 1, 1, 0) THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('orden_servicio', p_id_os, 'checklist_salida',
                IF(IFNULL(v_anterior, 0) = 1, 'conforme', 'pendiente'),
                IF(p_confirmado = 1, 'conforme', 'pendiente'),
                CONCAT(v_nombre, IF(p_confirmado = 1, ': confirmado por el técnico.', ': desmarcado por el técnico.')),
                p_id_usuario, NOW());
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, IF(p_confirmado = 1, ' confirmado.', ' desmarcado.')) AS Mensaje;
END$$

DELIMITER ;

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
--   - Solo desde el día programado de la OS (SP_ObtenerSalidaHabilitadaMovil).
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
    DECLARE v_salida_ok   TINYINT DEFAULT 1;
    DECLARE v_salida_msg  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

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

    -- La salida (y su autorización) solo se gestiona desde el día programado
    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);
    IF v_salida_ok = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_salida_msg AS Mensaje;
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

-- ============================================================
-- SP_IniciarTrasladoMovil  (App Mobile HU-04)
-- El técnico inicia el traslado hacia el cliente: la OS pasa a 'en_ruta', se registra el
-- evento de campo "Salida desde base" y queda en auditoria_evento.
-- El back valida antes el checklist (ReglasChecklistSalida). Aquí se vuelve a validar lo
-- que podría cambiar en el medio: estado de la OS, que sea el día programado (SP_ObtenerSalidaHabilitadaMovil)
-- y, si se usa, el visto bueno vigente.
--   p_con_visto_bueno = 1 → sale con pendientes gracias al visto bueno del jefe.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_IniciarTrasladoMovil;

DELIMITER $$

CREATE PROCEDURE SP_IniciarTrasladoMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_os           BIGINT,
    IN p_con_visto_bueno TINYINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       INT;
    DECLARE v_salida_ok  TINYINT DEFAULT 1;
    DECLARE v_salida_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    START TRANSACTION;

    SELECT os.estado INTO v_estado
    FROM   orden_servicio os
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
        SELECT 1 AS IdTipoMensaje, CONCAT('No se puede iniciar el traslado: el servicio está ', REPLACE(v_estado, '_', ' '), '.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- El traslado solo se inicia desde el día programado
    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);
    IF v_salida_ok = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_salida_msg AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_con_visto_bueno = 1 THEN
        SELECT a.estado INTO v_aut_estado
        FROM   autorizacion_salida_os a
        WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
        ORDER BY a.id_autorizacion DESC LIMIT 1;

        IF IFNULL(v_aut_estado, '') <> 'aprobada' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El visto bueno del encargado del área ya no está vigente.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SELECT t.Num1 INTO v_tipo
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.String2 = 'SALIDA_BASE'
    ORDER BY t.IdMaestro DESC LIMIT 1;

    UPDATE orden_servicio
    SET    estado = 'en_ruta', modificado_por = p_id_usuario
    WHERE  id_os = p_id_os;

    INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
    VALUES (p_id_os, p_id_usuario, IFNULL(v_tipo, 1), UTC_TIMESTAMP(), 1,
            IF(p_con_visto_bueno = 1, 'Inicio de traslado con visto bueno del encargado del área.', 'Inicio de traslado con checklist completo.'),
            p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
    VALUES ('orden_servicio', p_id_os, 'iniciar_traslado', v_estado, 'en_ruta',
            IF(p_con_visto_bueno = 1, 'Inicio de traslado con pendientes, autorizado por el encargado del área.',
                                      'Inicio de traslado con el checklist de salida completo.'),
            p_id_usuario, NOW());

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Traslado iniciado. ¡Buen viaje!' AS Mensaje;
END$$

DELIMITER ;

-- Verificación (solo lectura): los 5 deben aparecer con la fecha/hora de hoy
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado
FROM   INFORMATION_SCHEMA.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE()
  AND  ROUTINE_NAME IN ('SP_ObtenerSalidaHabilitadaMovil','SP_ObtenerChecklistSalidaMovil','SP_MarcarChecklistSalidaMovil',
                        'SP_SolicitarAutorizacionSalidaMovil','SP_IniciarTrasladoMovil')
ORDER BY ROUTINE_NAME;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos). OS-000003 = id_os 6, técnico Pedro Salazar = id_usuario 16.
-- Mientras hoy sea anterior al 09/11/2026 se espera:
-- ============================================================

-- 1) Regla: habilitada = 0 y mensaje "Aún no es el día del servicio. Podrás validar la salida el 09/11/2026."
CALL SP_ObtenerSalidaHabilitadaMovil(6, @habilitada, @mensaje);
SELECT @habilitada AS habilitada, @mensaje AS mensaje;

-- 2) Checklist: en la 2.ª pestaña, al final de la fila, salida_habilitada = 0 y el mismo salida_mensaje
CALL SP_ObtenerChecklistSalidaMovil(16, 6);

-- 3) Detalle: SIGUE devolviendo todo (servicio, alertas, riesgos, repuestos, historial, documentos, programación, equipo, equipos, conceptos, respuestas)
CALL SP_ObtenerDetalleServicioMovil(16, 6);
