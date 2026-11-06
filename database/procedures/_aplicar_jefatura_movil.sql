-- Aplicar en la base (solo procedimientos, sin datos). NO subir al repositorio.

-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día del ÁREA del Jefe de Metrología que inició sesión.
--   El menú depende del ROL y el ÁREA: el supervisor (rol_sistema = 'supervisor') del área Metrología es el Jefe de Metrología.
--   El Jefe de Servicio Técnico usa el menú de campo (no tiene menú de Jefatura). Quien no es jefe de una de las áreas con
--   Jefatura recibe un mensaje y la app le muestra el menú de campo. Para sumar otra área con Jefatura: agregar su condición
--   aquí (y en utilidades/perfil.ts y modulosJefatura de la app).
--   Toda la información se filtra por el área del jefe según la RQ de cada servicio:
--     orden_servicio → expediente_digital → requerimiento.id_area → area_servicio_rq.area_usuario.
-- Resultados:
--   1. Mensaje
--   2. Una fila: area_codigo, area_nombre, sede, y los contadores de HOY (fecha de Lima, UTC-5):
--        programados      : servicios del área programados para hoy (en cualquier estado activo)
--        en_ruta          : de esos, en ruta
--        en_ejecucion     : de esos, en ejecución o pausados (ya están en planta)
--        con_demora       : de esos, con una demora registrada hoy
--        aprobaciones_pendientes : solicitudes de salida esperando su decisión. Misma regla que
--                           SP_ObtenerAutorizacionesSalida para el encargado del área (las de su área y las que la RQ no ubica en un área).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerMenuJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMenuJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hoy  DATE;

    -- Jefe de Metrología = SUPERVISOR del área Metrología (no depende de cómo se escriba el cargo, que es texto libre).
    SELECT IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL),
           s.String1
    INTO   v_area, v_sede
    FROM   usuario u
    LEFT JOIN tabla_maestra s ON s.IdMaestro = 69 AND s.IdEmpresa = 1 AND s.String2 = u.sede_operativa
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    WITH os_area AS (
        SELECT os.id_os, os.estado
        FROM   orden_servicio os
        LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
        LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
        WHERE  os.eliminado_en IS NULL
          AND  asr.area_usuario = v_area
          AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND  os.fecha_ejecucion = v_hoy
    )
    SELECT v_area                                                           AS area_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1) AS area_nombre,
           v_sede                                                           AS sede,
           COUNT(*)                                                         AS programados,
           IFNULL(SUM(estado = 'en_ruta'), 0)                               AS en_ruta,
           IFNULL(SUM(estado IN ('en_ejecucion', 'pausada')), 0)            AS en_ejecucion,
           (SELECT COUNT(DISTINCT d.id_os)
            FROM   demora_registro d
            WHERE  d.eliminado_en IS NULL AND DATE(d.fecha_registro) = v_hoy
              AND  d.id_os IN (SELECT o.id_os FROM os_area o))              AS con_demora,
           (SELECT COUNT(*)
            FROM   autorizacion_salida_os a
            WHERE  a.eliminado_en IS NULL AND a.estado = 'pendiente'
              AND  (a.area_destino IS NULL OR a.area_destino = v_area))     AS aprobaciones_pendientes
    FROM   os_area;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerAutorizacionesSalida  (Intranet · App Mobile HU-04)
-- Bandeja de solicitudes de visto bueno de salida de los técnicos.
--   p_estado: pendiente | aprobada | rechazada | (vacío = todas)
--   Encargado de área (Jefe de Servicio Técnico / Jefe de Metrología, o el supervisor del área Metrología): solo las de SU área
--   (y las que no tienen área en la RQ). Jefe/Coordinador de Operaciones y administradores: todas.
-- id_tecnico (última columna): quién la pidió; la app móvil del Jefe lo usa para mostrar el checklist de ese técnico.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAutorizacionesSalida;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAutorizacionesSalida(
    IN p_id_usuario BIGINT,
    IN p_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;

    SELECT 1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin'))
    INTO   v_existe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_existe = 0 OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los encargados de Servicio Técnico y Metrología pueden ver las autorizaciones de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = LOWER(TRIM(IFNULL(p_estado, '')));
    IF v_estado NOT IN ('', 'pendiente', 'aprobada', 'rechazada') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use pendiente, aprobada o rechazada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT a.id_autorizacion,
           a.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           os.estado                                                        AS estado_os,
           NULLIF(TRIM(CONCAT(IFNULL(tc.nombre, ''), ' ', IFNULL(tc.apellido, ''))), '') AS tecnico,
           a.motivo,
           a.pendientes,
           a.estado,
           a.area_destino,
           ar.String1                                                       AS area,
           a.solicitado_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS jefe,
           a.resuelto_en,
           a.comentario,
           a.id_tecnico
    FROM   autorizacion_salida_os a
    JOIN   orden_servicio os ON os.id_os = a.id_os AND os.eliminado_en IS NULL
    LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    LEFT JOIN usuario tc ON tc.id_usuario = a.id_tecnico
    LEFT JOIN usuario jf ON jf.id_usuario = a.id_jefe
    LEFT JOIN tabla_maestra ar ON ar.IdMaestro = 79 AND ar.IdEmpresa = 1 AND ar.String2 = a.area_destino
    WHERE  a.eliminado_en IS NULL
      AND  (v_estado = '' OR a.estado = v_estado)
      AND  (v_general = 1 OR a.area_destino IS NULL OR a.area_destino = v_area_jefe)
    ORDER BY (a.estado = 'pendiente') DESC, IFNULL(a.solicitado_en, a.creado_en) DESC
    LIMIT 200;
END$$

DELIMITER ;

-- ============================================================
-- SP_ResolverAutorizacionSalida  (Intranet · App Mobile HU-04)
-- El encargado del área da (o niega) el visto bueno de salida de una OS desde la intranet.
--   - Área de la OS: la de la solicitud (area_destino) o, si no hay solicitud, la de la RQ
--     (requerimiento.id_area → area_servicio_rq).
--   - Pueden resolver: el encargado de ESA área (cargo jefe_* del área: Jefe de Servicio Técnico
--     o Jefe de Metrología; y también el SUPERVISOR del área Metrología, que es su jefe en la app móvil;
--     si la RQ no tiene área, cualquiera de los dos), el Jefe/Coordinador
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
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
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

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================

-- 0) Usuarios de Metrología: su rol y área (el Jefe de Metrología es el que tiene rol_sistema = 'supervisor')
SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre, u.cargo, u.area, u.rol_sistema, u.nombre_usuario, u.canal_acceso, u.estado
FROM   usuario u
WHERE  u.eliminado_en IS NULL AND u.area = 'metrologia'
ORDER BY u.id_usuario;

-- 1) Menú de Jefatura del supervisor de Metrología (1.ª pestaña = mensaje; 2.ª = área, sede y contadores de hoy)
SET @jefe_met = (SELECT MIN(id_usuario) FROM usuario WHERE rol_sistema = 'supervisor' AND area = 'metrologia' AND eliminado_en IS NULL AND estado = 'activo');
CALL SP_ObtenerMenuJefaturaMovil(@jefe_met);

-- 2) Solicitudes de salida pendientes que ve ese jefe (última columna nueva: id_tecnico)
CALL SP_ObtenerAutorizacionesSalida(@jefe_met, 'pendiente');

-- 3) Un técnico no tiene menú de Jefatura: debe responder "Tu cargo no tiene el menú de Jefatura."
CALL SP_ObtenerMenuJefaturaMovil(16);
