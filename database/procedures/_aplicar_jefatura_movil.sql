-- Aplicar en la base (solo procedimientos, sin datos). NO subir al repositorio.

-- HU-83 — Crear (p_id_usuario = 0) o editar un usuario
--   p_password_hash: NULL = no cambia la contraseña (solo en edición)
--   p_area:           código de AREA_USUARIO (79)
--   p_sede_operativa: código de SEDE_OPERATIVA_TW (69); si no se envía, 'lima_central'
--   p_anexo / p_troncal / p_fecha_nacimiento: contacto interno (reunión 02-oct)
--   p_rol_sistema: nivel (administrador | supervisor | usuario | visor)
--   p_id_supervisor: se ignora; el supervisor se calcula solo (SP_RecalcularSupervisores)
--   p_nombre_usuario: usuario de la app móvil (App Mobile HU-01). La ficha lo gestiona para TODAS las áreas (Servicio Técnico
--                     lo sugiere y los demás lo dejan en blanco si no usarán la app). El menú de la app sale del cargo (HU-28).
--                       - con valor ........ lo asigna (único entre vigentes) y habilita el canal: intranet -> todos.
--                       - vacío en edición . si el usuario tenía usuario de app, quita el acceso
--                                            (todos -> intranet) y cierra la sesión de la app.
--                       - vacío en otro caso no toca nombre_usuario ni canal_acceso.
--   Requiere la migración 75 (columna usuario.nombre_usuario).
DROP PROCEDURE IF EXISTS SP_GuardarUsuario;

DELIMITER $$

CREATE PROCEDURE SP_GuardarUsuario(
    IN p_id_usuario                     BIGINT,
    IN p_nombre                         VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_apellido                       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_documento                 VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_numero_documento               VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_correo                         VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_telefono                       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_anexo                          VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_troncal                        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_nacimiento               DATE,
    IN p_cargo                          VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_area                           VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_usuario                 VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rol_sistema                   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_sede_operativa                 VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_supervisor                  BIGINT,
    IN p_habilitado_firma_inacal        TINYINT,
    IN p_numero_registro_inacal         VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_expiracion_certificacion DATE,
    IN p_requiere_induccion_sctr        TINYINT,
    IN p_password_hash                  VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_forzar_cambio_contrasena       TINYINT,
    IN p_enviar_credenciales_correo     TINYINT,
    IN p_autenticacion_2fa              TINYINT,
    IN p_guardar_como_borrador          TINYINT,
    IN p_id_usuario_ejecutor            BIGINT
)
proc: BEGIN
    DECLARE v_id              BIGINT;
    DECLARE v_nombre_usuario  VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_anterior   VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_canal_anterior  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario_anterior VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_asignar_app     TINYINT DEFAULT 0;
    DECLARE v_quitar_app      TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones ─────────────────────────────────────────────────────
    IF EXISTS (
        SELECT 1 FROM usuario
        WHERE correo = p_correo
          AND eliminado_en IS NULL
          AND (p_id_usuario = 0 OR id_usuario <> p_id_usuario)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El correo ya está registrado para otro usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = 68 AND IdEmpresa = 1 AND String2 = p_rol_sistema
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El rol seleccionado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_troncal, '') <> '' AND NOT EXISTS (
        SELECT 1 FROM tabla_maestra WHERE IdMaestro = 84 AND IdEmpresa = 1 AND String2 = p_troncal
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'La troncal seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_area IS NOT NULL AND p_area <> '' AND NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = 79 AND IdEmpresa = 1 AND String2 = p_area
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El área seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_sede_operativa IS NOT NULL AND p_sede_operativa <> '' AND NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = 69 AND IdEmpresa = 1 AND String2 = p_sede_operativa
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'La sede operativa seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_supervisor IS NOT NULL AND p_id_usuario <> 0 AND p_id_supervisor = p_id_usuario THEN
        SELECT 1 AS IdTipoMensaje, 'Un usuario no puede ser su propio supervisor.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario = 0 AND (p_password_hash IS NULL OR p_password_hash = '') THEN
        SELECT 1 AS IdTipoMensaje, 'La contraseña temporal es obligatoria para un usuario nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario <> 0 AND NOT EXISTS (
        SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Acceso a la app móvil (App Mobile HU-01) ─────────────────────────
    SET v_nombre_usuario = NULLIF(LOWER(TRIM(IFNULL(p_nombre_usuario, ''))), '');

    IF p_id_usuario <> 0 THEN
        SELECT area, canal_acceso, nombre_usuario
        INTO   v_area_anterior, v_canal_anterior, v_usuario_anterior
        FROM   usuario
        WHERE  id_usuario = p_id_usuario AND eliminado_en IS NULL;
    END IF;

    IF v_nombre_usuario IS NOT NULL THEN
        IF v_canal_anterior = 'extranet' THEN
            SELECT 1 AS IdTipoMensaje, 'Los usuarios del portal del cliente no pueden usar la app de campo.' AS Mensaje;
            LEAVE proc;
        END IF;

        IF EXISTS (
            SELECT 1 FROM usuario
            WHERE nombre_usuario = v_nombre_usuario
              AND eliminado_en IS NULL
              AND (p_id_usuario = 0 OR id_usuario <> p_id_usuario)
        ) THEN
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('El usuario "', v_nombre_usuario, '" ya está asignado a otra persona.') AS Mensaje;
            LEAVE proc;
        END IF;

        SET v_asignar_app = 1;
    ELSEIF p_id_usuario <> 0 AND v_usuario_anterior IS NOT NULL THEN
        SET v_quitar_app = 1;
    END IF;

    START TRANSACTION;

    IF p_id_usuario = 0 THEN
        INSERT INTO usuario (
            nombre, apellido, tipo_documento, numero_documento, correo,
            telefono, anexo, troncal, fecha_nacimiento, cargo, area, nombre_usuario, rol_sistema, sede_operativa,
            id_supervisor, habilitado_firma_inacal, numero_registro_inacal,
            fecha_expiracion_certificacion, requiere_induccion_sctr,
            password_hash, forzar_cambio_contrasena, enviar_credenciales_correo,
            autenticacion_2fa, canal_acceso, estado, creado_en, creado_por
        ) VALUES (
            p_nombre, p_apellido, p_tipo_documento, p_numero_documento, p_correo,
            p_telefono, NULLIF(p_anexo, ''), NULLIF(p_troncal, ''), p_fecha_nacimiento, p_cargo, NULLIF(p_area, ''), v_nombre_usuario, p_rol_sistema,
            COALESCE(NULLIF(p_sede_operativa, ''), 'lima_central'),
            p_id_supervisor, IFNULL(p_habilitado_firma_inacal, 0), p_numero_registro_inacal,
            p_fecha_expiracion_certificacion, IFNULL(p_requiere_induccion_sctr, 0),
            p_password_hash, IFNULL(p_forzar_cambio_contrasena, 0), IFNULL(p_enviar_credenciales_correo, 1),
            IFNULL(p_autenticacion_2fa, 0), IF(v_asignar_app = 1, 'todos', 'intranet'),
            IF(p_guardar_como_borrador = 1, 'borrador', 'activo'),
            NOW(), p_id_usuario_ejecutor
        );
        SET v_id = LAST_INSERT_ID();
    ELSE
        UPDATE usuario SET
            nombre                         = p_nombre,
            apellido                       = p_apellido,
            tipo_documento                 = p_tipo_documento,
            numero_documento               = p_numero_documento,
            correo                         = p_correo,
            telefono                       = p_telefono,
            anexo                          = NULLIF(p_anexo, ''),
            troncal                        = NULLIF(p_troncal, ''),
            fecha_nacimiento               = p_fecha_nacimiento,
            cargo                          = p_cargo,
            area                           = NULLIF(p_area, ''),
            nombre_usuario                 = CASE
                                                 WHEN v_asignar_app = 1 THEN v_nombre_usuario
                                                 WHEN v_quitar_app  = 1 THEN NULL
                                                 ELSE nombre_usuario
                                             END,
            canal_acceso                   = CASE
                                                 WHEN v_asignar_app = 1 THEN IF(canal_acceso = 'intranet', 'todos', canal_acceso)
                                                 WHEN v_quitar_app  = 1 THEN IF(canal_acceso = 'todos', 'intranet', canal_acceso)
                                                 ELSE canal_acceso
                                             END,
            rol_sistema                    = p_rol_sistema,
            sede_operativa                 = COALESCE(NULLIF(p_sede_operativa, ''), sede_operativa, 'lima_central'),
            id_supervisor                  = p_id_supervisor,
            habilitado_firma_inacal        = IFNULL(p_habilitado_firma_inacal, 0),
            numero_registro_inacal         = p_numero_registro_inacal,
            fecha_expiracion_certificacion = p_fecha_expiracion_certificacion,
            requiere_induccion_sctr        = IFNULL(p_requiere_induccion_sctr, 0),
            password_hash                  = COALESCE(NULLIF(p_password_hash, ''), password_hash),
            forzar_cambio_contrasena       = IFNULL(p_forzar_cambio_contrasena, 0),
            enviar_credenciales_correo     = IFNULL(p_enviar_credenciales_correo, 1),
            autenticacion_2fa              = IFNULL(p_autenticacion_2fa, 0),
            estado = CASE
                         WHEN p_guardar_como_borrador = 1 THEN 'borrador'
                         WHEN estado = 'borrador'         THEN 'activo'
                         ELSE estado
                     END,
            modificado_en                  = NOW(),
            modificado_por                 = p_id_usuario_ejecutor
        WHERE id_usuario = p_id_usuario;
        SET v_id = p_id_usuario;

        -- Sin usuario de app no hay sesión de app (igual que SP_AsignarAccesoMovil al deshabilitar).
        IF v_quitar_app = 1 THEN
            UPDATE sesion_usuario
            SET    activo            = 0,
                   fecha_revocacion  = NOW(),
                   motivo_revocacion = 'ACCESO_DESHABILITADO',
                   modificado_en     = NOW(),
                   modificado_por    = p_id_usuario_ejecutor
            WHERE  id_usuario      = p_id_usuario
              AND  id_canal_acceso = 2
              AND  activo          = 1;
        END IF;
    END IF;

    COMMIT;

    -- NOTA: SP_RecalcularSupervisores fue eliminado en el refactor de VB (bandeja compartida
    -- por área + rol). La columna usuario.id_supervisor ya no se usa para VB — todos los
    -- supervisores/administradores del área del comercial son el equipo aprobador.

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_usuario = 0, 'Usuario registrado correctamente.', 'Usuario actualizado correctamente.') AS Mensaje;
    SELECT v_id AS id_usuario;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerAutorizacionesSalida  (Intranet · App Mobile HU-04)
-- Bandeja de solicitudes de visto bueno de salida de los técnicos.
--   p_estado: pendiente | aprobada | rechazada | (vacío = todas)
--   Encargado de área (Jefe de Servicio Técnico / Jefe de Metrología): solo las de SU área
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
           IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
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
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día del ÁREA del Jefe de Metrología que inició sesión.
--   El menú depende del cargo (CARGO_USUARIO: cargo "jefe_*" cuya área es metrologia). El Jefe de Servicio Técnico usa el menú de
--   campo (no tiene menú de Jefatura). Quien no es jefe de una de las áreas con Jefatura recibe un mensaje y la app le muestra el
--   menú de campo. Para sumar otra área con Jefatura: agregarla a la lista del IN (y a modulosJefatura en la app).
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

    SELECT IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('metrologia'), c.String3, NULL),
           s.String1
    INTO   v_area, v_sede
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
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
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================

-- 0) Usuarios por área: su cargo tal como está guardado, si ya tienen usuario de la app y si el sistema reconoce al Jefe de Metrología.
--    reconocido_como_jefe_metrologia = el cargo coincide con el código del catálogo (jefe_metrologia). Si el Jefe de Metrología sale en
--    NULL, su cargo se escribió como texto libre y no tendrá el menú de Jefatura.
SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre, u.cargo, u.area, u.nombre_usuario, u.canal_acceso, u.estado,
       IF(c.String2 = 'jefe_metrologia', 'si', NULL) AS reconocido_como_jefe_metrologia
FROM   usuario u
LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
WHERE  u.eliminado_en IS NULL AND u.area IN ('metrologia', 'servicio_tecnico')
ORDER BY u.area, u.id_usuario;

-- 1) Menú de Jefatura del Jefe de Metrología (1.ª pestaña = mensaje; 2.ª = área, sede y contadores de hoy)
SET @jefe_met = (SELECT MIN(id_usuario) FROM usuario WHERE cargo = 'jefe_metrologia' AND eliminado_en IS NULL AND estado = 'activo');
CALL SP_ObtenerMenuJefaturaMovil(@jefe_met);

-- 2) Solicitudes de salida pendientes que ve ese jefe (la última columna nueva es id_tecnico)
CALL SP_ObtenerAutorizacionesSalida(@jefe_met, 'pendiente');

-- 3) El Jefe de Servicio Técnico y los técnicos NO tienen menú de Jefatura: debe responder "Tu cargo no tiene el menú de Jefatura."
CALL SP_ObtenerMenuJefaturaMovil(16);
