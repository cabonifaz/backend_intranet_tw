-- HU-32: alertas y apoyo en campo. Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- ============================================================
-- Migración 118 — Alertas y apoyo en campo desde la app móvil (App Mobile HU-32)
--   incidencia_operativa (la misma que lee la bandeja de Seguimiento Operativo): + evidencia_url (foto de la incidencia, solo cámara)
--   y escalada_en (cuándo el jefe la escaló). No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'evidencia_url'),
    'ALTER TABLE incidencia_operativa ADD COLUMN evidencia_url VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'escalada_en'),
    'ALTER TABLE incidencia_operativa ADD COLUMN escalada_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ============================================================
-- SP_RegistrarLlamadaEnsayoMovil  (App Mobile HU-10 — "Llamar" al encargado ante un error crítico · escritura)
-- El técnico llama al encargado del área (según la RQ) para comunicarle el error en la calibración. Se REGISTRA la llamada en el ensayo (hora y error
-- reportado) en auditoria_evento, y se devuelve a quién llamar. La llamada en sí la hace el teléfono; aquí solo queda constancia.
--   - Mismo acceso que los ensayos (SP_ContextoEnsayoMovil). p_detalle = el error reportado (hasta 300 caracteres).
-- Resultados: 1 mensaje; 2 (nombre, cargo, telefono, area). Sin encargado con teléfono responde la regla de negocio.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarLlamadaEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarLlamadaEnsayoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_detalle      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF CHAR_LENGTH(IFNULL(p_detalle, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El detalle puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    IF v_nom_enc IS NULL OR v_tel_enc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay un encargado del área con teléfono registrado. Comunícate con Operaciones.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'llamar_encargado_ensayo', NULL, NULL,
            LEFT(CONCAT('Llamada al encargado ', v_nom_enc, ' (', IFNULL(v_area, ''), ') por error en el ensayo de ', v_nombre, ' en ', v_num_os,
                        IF(NULLIF(TRIM(IFNULL(p_detalle, '')), '') IS NULL, '', CONCAT(': ', TRIM(p_detalle)))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_encargado', v_id_enc, 'telefono', v_tel_enc));

    -- HU-32: el aviso «Ensayo con error crítico» le llega al encargado del área (abre «Alerta de campo» con la tabla del ensayo y las decisiones)
    IF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT v_id_enc, 5, 'Ensayo con error crítico',
               LEFT(CONCAT(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), ' pide apoyo en ', v_num_os, ': ', v_nombre,
                           IF(NULLIF(TRIM(IFNULL(p_detalle, '')), '') IS NULL, '', CONCAT(' (', TRIM(p_detalle), ')'))), 500),
               'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u WHERE u.id_usuario = p_id_usuario;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Llamada registrada en el ensayo.' AS Mensaje;
    SELECT v_nom_enc AS nombre, v_car_enc AS cargo, v_tel_enc AS telefono, v_area AS area;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerAlertaCampoMovil  (App Mobile HU-32 — "Alerta de campo": pedido de apoyo del técnico ante un error crítico en un ensayo · lectura)
-- El jefe abre desde Notificaciones el aviso "Ensayo con error crítico" (HU-10) y ve: quién pidió apoyo y hace cuánto, la OS, el equipo y la tabla del ensayo
-- (carga L, indicación I, error E y EMP, con las lecturas críticas marcadas) para decidir.
--   - El aviso debe ser del jefe del token y ser un "Ensayo con error crítico" de una OS. La OS debe estar en el alcance del jefe (SP_ResolverJefaturaMovil +
--     SP_ArmarAlcanceJefaturaMovil: los servicios de su área; aquí cualquier fecha).
--   - El equipo es el último con una lectura crítica en esa OS (informe_ensayo.critico = 1).
-- Resultados: 1 mensaje · 2 alerta (1 fila) · 3 pesaje · 4 excentricidad.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAlertaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAlertaCampoMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT
)
proc: BEGIN
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen    TINYINT;
    DECLARE v_titulo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuerpo     VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha      DATETIME;
    DECLARE v_tec        BIGINT;
    DECLARE v_id_os      BIGINT;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_informe    BIGINT DEFAULT NULL;
    DECLARE v_id_eq      BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT n.titulo, n.cuerpo, n.fecha_creacion, n.creado_por, n.id_entidad INTO v_titulo, v_cuerpo, v_fecha, v_tec, v_id_os
    FROM   notificacion n
    WHERE  n.id_notificacion = p_id_notificacion AND n.id_usuario_destino = p_id_usuario AND n.entidad_tipo = 'orden_servicio'
      AND  n.titulo LIKE 'Ensayo con error cr%'
    LIMIT 1;
    IF v_titulo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La alerta no existe o no es tuya.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarAlcanceJefaturaMovil(v_area, v_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = v_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio de esta alerta no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El equipo con la lectura crítica más reciente de la OS
    SELECT it.id_informe, it.id_equipo INTO v_informe, v_id_eq
    FROM   informe_tecnico it
    JOIN   informe_ensayo ie ON ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL
    WHERE  it.id_os = v_id_os AND it.eliminado_en IS NULL
    ORDER BY ie.id_ensayo DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT n.id_notificacion, n.titulo, n.cuerpo,
           CONVERT_TZ(n.fecha_creacion, '+00:00', '-05:00') AS creada_en,
           GREATEST(0, TIMESTAMPDIFF(MINUTE, n.fecha_creacion, UTC_TIMESTAMP())) AS hace_min,
           os.id_os, os.numero AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente, sc.nombre AS sede,
           u.id_usuario AS id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS tecnico, NULLIF(TRIM(u.telefono), '') AS telefono,
           v_id_eq AS id_equipo,
           (SELECT oe.id FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.id_equipo = v_id_eq AND oe.eliminado_en IS NULL LIMIT 1) AS id_os_equipo,
           (SELECT CONCAT_WS(' · ', NULLIF(ec.codigo_cliente, ''), NULLIF(ec.codigo_tw, '')) FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq) AS equipo_codigo,
           (SELECT CONCAT_WS(' ', NULLIF(ec.marca, ''), NULLIF(ec.modelo, '')) FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq) AS equipo_descripcion,
           (SELECT NULLIF(ec.ubicacion_especifica, '') FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq) AS equipo_ubicacion
    FROM   notificacion n
    JOIN   orden_servicio os ON os.id_os = n.id_entidad
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede = os.id_sede
    LEFT JOIN usuario u ON u.id_usuario = n.creado_por
    WHERE  n.id_notificacion = p_id_notificacion;

    SELECT ie.orden, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'pesaje' AND ie.eliminado_en IS NULL
    ORDER BY ie.orden, ie.id_ensayo;

    SELECT ie.grupo, ie.orden AS posicion, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'excentricidad' AND ie.eliminado_en IS NULL
    ORDER BY ie.grupo, ie.orden, ie.id_ensayo;
END$$

DELIMITER ;

-- ============================================================
-- SP_AccionAlertaCampoMovil  (App Mobile HU-32 — decisiones del jefe ante un pedido de apoyo · escritura)
-- p_accion:
--   llamar  : deja constancia de la llamada al técnico (auditoria_evento) y devuelve su teléfono (la llamada la hace el teléfono).
--   repetir : "Pedir repetir ensayo": avisa al técnico (notificación) para que repita el ensayo del equipo.
--   ajuste  : "Indicar ajuste y nueva calibración": avisa al técnico para que ajuste el equipo y calibre de nuevo.
--   p_mensaje (opcional, hasta 300 caracteres): indicación del jefe que se agrega al aviso.
-- Mismo acceso que SP_ObtenerAlertaCampoMovil (aviso propio de "Ensayo con error crítico" y OS del alcance del jefe).
-- Resultados: 1 mensaje · 2 técnico (nombre, telefono).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AccionAlertaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_AccionAlertaCampoMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT,
    IN p_accion          VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_mensaje         VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_accion    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_msg       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_titulo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tec       BIGINT;
    DECLARE v_id_os     BIGINT;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_tec   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_tec   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_accion = LOWER(TRIM(IFNULL(p_accion, '')));
    IF v_accion NOT IN ('llamar', 'repetir', 'ajuste') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_msg = NULLIF(TRIM(IFNULL(p_mensaje, '')), '');
    IF CHAR_LENGTH(IFNULL(v_msg, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'La indicación puede tener hasta 300 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT n.titulo, n.creado_por, n.id_entidad INTO v_titulo, v_tec, v_id_os
    FROM   notificacion n
    WHERE  n.id_notificacion = p_id_notificacion AND n.id_usuario_destino = p_id_usuario AND n.entidad_tipo = 'orden_servicio'
      AND  n.titulo LIKE 'Ensayo con error cr%'
    LIMIT 1;
    IF v_titulo IS NULL OR v_tec IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La alerta no existe o no es tuya.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarAlcanceJefaturaMovil(v_area, v_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = v_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio de esta alerta no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.numero INTO v_num_os FROM orden_servicio os WHERE os.id_os = v_id_os;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULLIF(TRIM(u.telefono), '') INTO v_nom_tec, v_tel_tec
    FROM   usuario u WHERE u.id_usuario = v_tec;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    IF v_accion = 'llamar' THEN
        IF v_tel_tec IS NULL THEN
            SELECT 1 AS IdTipoMensaje, CONCAT(v_nom_tec, ' no tiene un teléfono registrado.') AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    START TRANSACTION;

    IF v_accion IN ('repetir', 'ajuste') THEN
        SET v_texto = LEFT(CONCAT(v_nom_jefe, IF(v_accion = 'repetir', ' te pide repetir el ensayo', ' indica ajustar el equipo y volver a calibrar'),
                                  ' (', v_num_os, ').', IF(v_msg IS NULL, '', CONCAT(' ', v_msg))), 500);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_tec, 5, IF(v_accion = 'repetir', 'Repite el ensayo', 'Ajuste y nueva calibración'), v_texto, 'orden_servicio', v_id_os, NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', v_id_os, CONCAT('alerta_campo_', v_accion), NULL, NULL,
            LEFT(CONCAT(v_nom_jefe, CASE v_accion WHEN 'llamar' THEN ' llamó a ' WHEN 'repetir' THEN ' pidió repetir el ensayo a ' ELSE ' indicó ajuste y nueva calibración a ' END,
                        v_nom_tec, ' en ', v_num_os, IF(v_msg IS NULL, '', CONCAT(': ', v_msg))), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_notificacion', p_id_notificacion, 'id_tecnico', v_tec));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE v_accion WHEN 'llamar' THEN 'Llamada registrada.'
                         WHEN 'repetir' THEN CONCAT('Se avisó a ', v_nom_tec, ' que repita el ensayo.')
                         ELSE CONCAT('Se avisó a ', v_nom_tec, ' que ajuste el equipo y calibre de nuevo.') END AS Mensaje;
    SELECT v_nom_tec AS nombre, v_tel_tec AS telefono;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarIncidenciaCampoMovil  (App Mobile HU-32 — "Registrar incidencia" y "Escalar" · escritura)
-- El jefe registra una incidencia de un servicio de su área (imprevisto en ruta o en planta): tipo, severidad, impacto, descripción y foto (solo cámara).
--   - Se guarda en incidencia_operativa, la misma tabla que lee la bandeja de Seguimiento Operativo: una incidencia con impacto "detiene" o de nivel crítico
--     deja el servicio "con incidente" y genera la alerta crítica. Queda a nombre del técnico de la OS (id_usuario) y del jefe (creado_por).
--   - Tipo: catálogo TIPO_INCIDENCIA_OPERATIVA (1 a 6). Severidad: NIVEL_ALERTA (1 Bajo · 2 Medio · 3 Alto · 4 Crítico). Impacto: retrasa | detiene.
--   - p_escalar = 1: la incidencia queda "escalada" (escalada_en) y se avisa a los administradores y al Jefe de Operaciones.
--   - La OS debe estar en el alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil). p_evidencia = ruta de la foto ya guardada por el back.
-- Resultados: 1 mensaje; 2 (id_incidencia, estado, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarIncidenciaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarIncidenciaCampoMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_id_tipo     INT,
    IN p_id_nivel    INT,
    IN p_impacto     VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion VARCHAR(1100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_evidencia   VARCHAR(500)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_escalar     TINYINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_impacto   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desc      VARCHAR(1100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec       BIGINT DEFAULT NULL;
    DECLARE v_tipo_txt  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nivel_txt VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id        BIGINT;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_impacto = LOWER(TRIM(IFNULL(p_impacto, '')));
    SET v_desc    = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT t.String1 INTO v_tipo_txt FROM tabla_maestra t
    WHERE  t.Descripcion = 'TIPO_INCIDENCIA_OPERATIVA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_tipo AND t.eliminado_en IS NULL LIMIT 1;
    IF v_tipo_txt IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de incidencia.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT t.String1 INTO v_nivel_txt FROM tabla_maestra t
    WHERE  t.Descripcion = 'NIVEL_ALERTA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_nivel AND t.eliminado_en IS NULL LIMIT 1;
    IF v_nivel_txt IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona la severidad.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_impacto NOT IN ('retrasa', 'detiene') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el impacto en el servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_desc IS NULL OR CHAR_LENGTH(v_desc) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe la descripción de la incidencia (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_desc) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 1000 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.numero, os.id_tecnico_principal INTO v_num_os, v_tec FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    SET v_estado = IF(IFNULL(p_escalar, 0) = 1, 'escalada', 'abierta');

    START TRANSACTION;

    INSERT INTO incidencia_operativa (id_os, id_usuario, id_tipo, descripcion, id_nivel_alerta, estado, impacto, fecha_registro, creado_por, evidencia_url, escalada_en)
    VALUES (p_id_os, IFNULL(v_tec, p_id_usuario), p_id_tipo, v_desc, p_id_nivel, v_estado, v_impacto, NOW(), p_id_usuario,
            NULLIF(TRIM(IFNULL(p_evidencia, '')), ''), IF(v_estado = 'escalada', NOW(), NULL));
    SET v_id = LAST_INSERT_ID();

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    IF v_estado = 'escalada' THEN
        SET v_texto = LEFT(CONCAT(v_nom_jefe, ' escaló una incidencia en ', v_num_os, ': ', v_tipo_txt, ' · severidad ', v_nivel_txt, ' · ',
                                  IF(v_impacto = 'detiene', 'detiene el servicio', 'retrasa el servicio'), '. ', v_desc), 500);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, CONCAT('Incidencia escalada: ', LEFT(v_tipo_txt, 60)), v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND  (u.rol_sistema IN ('administrador', 'admin') OR u.cargo = 'jefe_operaciones');
        SET v_notif = ROW_COUNT();
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, IF(v_estado = 'escalada', 'incidencia_escalada', 'incidencia_registrada'), NULL, v_estado,
            LEFT(CONCAT(v_nom_jefe, ' registró una incidencia en ', v_num_os, ': ', v_tipo_txt, ' · ', v_nivel_txt, ' · ', v_impacto, ' · ', v_desc), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_incidencia', v_id, 'id_tipo', p_id_tipo, 'id_nivel', p_id_nivel, 'impacto', v_impacto));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_estado = 'escalada', 'Incidencia registrada y escalada.', 'Incidencia registrada.') AS Mensaje;
    SELECT v_id AS id_incidencia, v_estado AS estado, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerTecnicosReasignacionMovil  (App Mobile HU-32 — "Reasignar técnico en ruta": candidatos · lectura)
-- Técnicos a los que el jefe puede pasar un servicio de su área: de la MISMA especialidad (el área del técnico actual), cercanos a la planta y con SSOMA conforme.
--   - Candidato = usuario activo de servicio técnico o metrología, sin jefaturas ni asistentes, distinto del técnico actual.
--   - Distancia: última posición GPS de hoy (ubicacion_tecnico) a la planta (sede de la OS), en línea recta; llega_min = distancia a 30 km/h (referencial).
--     Sin posición o sin sede ubicada, distancia y llegada salen NULL.
--   - Carga: servicios de hoy del técnico (principal o personal) frente a SERVICIOS_MAX_DIA (parámetro de programación, 4 por defecto), en %.
--   - SSOMA: SP_EvaluarSsomaProgramacion contra los requisitos del cliente / zona de la OS (conforme · por_vencer habilitan; incompleto · pendiente · bloqueado no).
--   - disponible = SSOMA conforme o por vencer, con cupo en su día y no es el técnico actual. motivo_no = por qué no está habilitado.
--   - Orden: habilitados primero, por cercanía.
-- La OS debe estar en el alcance del jefe. Resultados: 1 mensaje · 2 OS y técnico actual (1 fila) · 3 candidatos.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTecnicosReasignacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTecnicosReasignacionMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_hoy       DATE;
    DECLARE v_param     DECIMAL(18,6);
    DECLARE v_max_dia   INT DEFAULT 4;
    DECLARE v_tec       BIGINT DEFAULT NULL;
    DECLARE v_area_tec  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_lat       DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lon       DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_fecha_os  DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_rea_cand;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    CALL SP_LeerParametroProgramacion('SERVICIOS_MAX_DIA', 4, v_param);
    SET v_max_dia = GREATEST(1, IFNULL(v_param, 4));

    SELECT os.id_tecnico_principal, os.fecha_ejecucion, COALESCE(sc.latitud, s.latitud), COALESCE(sc.longitud, s.longitud)
    INTO   v_tec, v_fecha_os, v_lat, v_lon
    FROM   orden_servicio os
    LEFT JOIN sede_cliente sc ON sc.id_sede = os.id_sede
    LEFT JOIN sede s ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    WHERE  os.id_os = p_id_os;
    SELECT u.area INTO v_area_tec FROM usuario u WHERE u.id_usuario = v_tec;

    DROP TEMPORARY TABLE IF EXISTS tmp_rea_cand;
    CREATE TEMPORARY TABLE tmp_rea_cand (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_rea_cand (id_usuario)
    SELECT u.id_usuario
    FROM   usuario u
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area IN ('servicio_tecnico', 'metrologia')
      AND  (v_area_tec IS NULL OR u.area = v_area_tec)
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
      AND  u.id_usuario <> IFNULL(v_tec, 0);

    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_rea_cand;
    CALL SP_EvaluarSsomaProgramacion(p_id_os, IFNULL(v_fecha_os, v_hoy));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os, os.numero AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente, v_tec AS id_tecnico_actual,
           (SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) FROM usuario u WHERE u.id_usuario = v_tec) AS tecnico_actual,
           v_lat AS planta_latitud, v_lon AS planta_longitud
    FROM   orden_servicio os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os;

    SELECT x.id_usuario, x.nombre, x.iniciales, x.latitud, x.longitud, x.distancia_km,
           IF(x.distancia_km IS NULL, NULL, CEIL(x.distancia_km / 30 * 60)) AS llega_min,
           x.servicios_hoy, LEAST(100, ROUND(x.servicios_hoy * 100 / v_max_dia)) AS carga_pct, x.ssoma,
           IF(x.ssoma IN ('conforme', 'por_vencer') AND x.servicios_hoy < v_max_dia, 1, 0) AS disponible,
           CASE WHEN x.ssoma = 'bloqueado'  THEN 'SSOMA bloqueado'
                WHEN x.ssoma = 'pendiente'  THEN 'Falta documento SSOMA'
                WHEN x.ssoma = 'incompleto' THEN 'SSOMA incompleto'
                WHEN x.servicios_hoy >= v_max_dia THEN 'Sin cupo hoy'
                ELSE NULL END AS motivo_no
    FROM (
        SELECT t.id_usuario,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS nombre,
               UPPER(CONCAT(LEFT(IFNULL(u.nombre, '?'), 1), LEFT(IFNULL(u.apellido, ''), 1))) AS iniciales,
               p.latitud, p.longitud,
               IF(p.latitud IS NULL OR v_lat IS NULL OR v_lon IS NULL, NULL,
                  ROUND(6371 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat - p.latitud) / 2), 2)
                        + COS(RADIANS(p.latitud)) * COS(RADIANS(v_lat)) * POW(SIN(RADIANS(v_lon - p.longitud) / 2), 2))), 1)) AS distancia_km,
               (SELECT COUNT(*) FROM orden_servicio o2
                WHERE o2.eliminado_en IS NULL AND o2.fecha_ejecucion = IFNULL(v_fecha_os, v_hoy)
                  AND o2.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
                  AND (o2.id_tecnico_principal = t.id_usuario
                       OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = o2.id_os AND op.id_usuario = t.id_usuario AND op.eliminado_en IS NULL))) AS servicios_hoy,
               IFNULL(s.estado, 'conforme') AS ssoma
        FROM   tmp_rea_cand t
        JOIN   usuario u ON u.id_usuario = t.id_usuario
        LEFT JOIN ubicacion_tecnico p ON p.id_ubicacion = (SELECT MAX(y.id_ubicacion) FROM ubicacion_tecnico y
                                                            WHERE y.id_usuario = t.id_usuario AND y.timestamp_utc >= UTC_TIMESTAMP() - INTERVAL 1 DAY)
        LEFT JOIN tmp_ssoma_res s ON s.id_usuario = t.id_usuario
    ) x
    ORDER BY IF(x.ssoma IN ('conforme', 'por_vencer') AND x.servicios_hoy < v_max_dia, 0, 1), IFNULL(x.distancia_km, 9999), x.nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_rea_cand;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;

-- ============================================================
-- SP_ReasignarTecnicoMovil  (App Mobile HU-32 — "Reasignar a <técnico>" · escritura)
-- El jefe pasa el servicio a otro técnico cercano, de la misma especialidad y con SSOMA conforme.
--   - La OS debe estar en el alcance del jefe y no estar finalizada ni anulada. El nuevo técnico debe ser candidato habilitado
--     (SP_ObtenerTecnicosReasignacionMovil: misma especialidad, SSOMA conforme o por vencer, con cupo en el día).
--   - Cambia el técnico principal de la OS (orden_servicio) y de su programación confirmada (programacion), que es de donde lee la bandeja de Seguimiento.
--     El técnico anterior, si integraba el personal (os_personal), se quita; el nuevo queda como principal.
--   - Avisa por notificación al técnico anterior ("Servicio reasignado") y al nuevo ("Nuevo servicio: reasignado…", abre el servicio). Deja auditoría.
--   - OJO: no copia la salida / llegada ya registradas del técnico anterior: el nuevo técnico registra las suyas. Aviso al cliente: no hay canal en el sistema todavía.
-- Resultados: 1 mensaje; 2 (id_os, id_tecnico, tecnico, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ReasignarTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ReasignarTecnicoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_tecnico BIGINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec_ant   BIGINT DEFAULT NULL;
    DECLARE v_habil     TINYINT DEFAULT 0;
    DECLARE v_nom_nuevo VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_ant   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_tecnico, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el técnico al que se reasigna el servicio.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.numero, os.estado, os.id_tecnico_principal INTO v_num_os, v_estado, v_tec_ant FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_estado IN ('finalizada', 'anulada', 'borrador', 'emitida') THEN
        SELECT 1 AS IdTipoMensaje, 'Este servicio ya no se puede reasignar.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_tec_ant = p_id_tecnico THEN
        SELECT 1 AS IdTipoMensaje, 'Ese técnico ya está asignado al servicio.' AS Mensaje; LEAVE proc;
    END IF;

    -- El nuevo técnico debe ser de la misma especialidad y tener la SSOMA habilitada (misma regla que la lista de candidatos)
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_nuevo
    FROM   usuario u
    WHERE  u.id_usuario = p_id_tecnico AND u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area IN ('servicio_tecnico', 'metrologia')
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
      AND  (v_tec_ant IS NULL OR u.area = (SELECT x.area FROM usuario x WHERE x.id_usuario = v_tec_ant));
    IF v_nom_nuevo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ese técnico no es de la misma especialidad o no está activo.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) VALUES (p_id_tecnico);
    CALL SP_EvaluarSsomaProgramacion(p_id_os, NULL);
    SELECT IF(IFNULL(s.estado, 'conforme') IN ('conforme', 'por_vencer'), 1, 0) INTO v_habil FROM tmp_ssoma_res s WHERE s.id_usuario = p_id_tecnico;
    SET v_habil = IFNULL(v_habil, 1);
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
    IF v_habil = 0 THEN
        SELECT 1 AS IdTipoMensaje, CONCAT(v_nom_nuevo, ' no tiene la SSOMA conforme para este servicio.') AS Mensaje; LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_ant FROM usuario u WHERE u.id_usuario = v_tec_ant;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    START TRANSACTION;

    UPDATE orden_servicio SET id_tecnico_principal = p_id_tecnico WHERE id_os = p_id_os;
    UPDATE programacion SET id_tecnico_principal = p_id_tecnico WHERE id_os = p_id_os AND estado = 'confirmada' AND eliminado_en IS NULL;
    IF v_tec_ant IS NOT NULL THEN
        UPDATE os_personal SET eliminado_en = NOW() WHERE id_os = p_id_os AND id_usuario = v_tec_ant AND eliminado_en IS NULL;
    END IF;

    IF v_tec_ant IS NOT NULL AND v_tec_ant <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_tec_ant, 5, 'Servicio reasignado', LEFT(CONCAT(v_nom_jefe, ' reasignó ', v_num_os, ' a ', v_nom_nuevo, '. Ya no es tu servicio.'), 500), 'orden_servicio', p_id_os, NOW(), p_id_usuario);
        SET v_notif = v_notif + 1;
    END IF;
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_tecnico, 5, CONCAT('Nuevo servicio: ', v_num_os), LEFT(CONCAT(v_nom_jefe, ' te reasignó el servicio ', v_num_os, IF(v_nom_ant IS NULL, '', CONCAT(' (antes de ', v_nom_ant, ')')), '. Revísalo y sal a planta.'), 500),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);
    SET v_notif = v_notif + 1;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'reasignar_tecnico', v_nom_ant, v_nom_nuevo,
            LEFT(CONCAT(v_nom_jefe, ' reasignó ', v_num_os, ' de ', IFNULL(v_nom_ant, 'sin técnico'), ' a ', v_nom_nuevo), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_tecnico_anterior', v_tec_ant, 'id_tecnico_nuevo', p_id_tecnico));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_num_os, ' reasignado a ', v_nom_nuevo, '.') AS Mensaje;
    SELECT p_id_os AS id_os, p_id_tecnico AS id_tecnico, v_nom_nuevo AS tecnico, v_notif AS notificados;
END$$

DELIMITER ;
