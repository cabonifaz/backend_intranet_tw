-- ============================================================
-- SP_RegistrarEquipoNuevoMovil  (App Mobile HU-07 — "Equipo nuevo (NEW)" · escritura)
-- El técnico registra en campo un equipo que no está en la lista de la O/S ("Registrar y seleccionar").
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_EvaluarCampoMovil).
--   - Obligatorios: N/S, código del cliente, marca (del catálogo MARCA_SUMINISTRO), modelo, tipo de equipo (suministro activo de clase
--     equipo / instrumento / pesa), ubicación y la foto de la placa (solo cámara; la valida y guarda el back antes de llamar a este SP).
--   - El cliente y la sede salen de la OS. La clasificación sale de la clase del suministro.
--   - Si el equipo YA existe en el maestro del cliente (mismo N/S + marca + modelo) NO se duplica: se agrega a esta O/S como objetivo
--     (ya_existia = 1, la foto no se usa). Si ya está en la lista de esta O/S: no se agrega otra vez (responde cuál es), salvo que lo haya
--     registrado el mismo técnico en esta O/S (reintento de la app): responde éxito con el ya registrado (ya_registrado = 1).
--   - Equipo creado: equipo_cliente en estado 'borrador' (pendiente de aprobación de la intranet) con COD TW PROVISIONAL "NEW-000123";
--     la intranet asigna el COD TW definitivo (EQ-TW-AAAA-NNNN) al aprobar el registro. Queda marcado registrado_en_campo, con la O/S y la
--     foto de la placa. El objetivo (os_equipo) queda con ingresado_en_campo = 1 y el mismo tipo de intervención que los demás de la O/S.
--   - Avisa por notificación a los supervisores/administradores del área del técnico y a su jefe (jefe_<área>); si no hay, a los administradores.
--   - Deja el registro en auditoria_evento (equipo_cliente y os_equipo).
-- Resultados: 1 mensaje; 2 (id_os_equipo, id_equipo, codigo_tw, ya_existia, ya_registrado, foto_guardada, notificados).
--   foto_guardada = 1 solo si el equipo se creó con esa foto (si no, el back borra el archivo).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarEquipoNuevoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarEquipoNuevoMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_os          BIGINT,
    IN p_num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_suministro  BIGINT,
    IN p_ubicacion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_foto_placa     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_serie       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca_cat   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ubicacion   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_sede     BIGINT;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_codigo_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oe       BIGINT DEFAULT NULL;
    DECLARE v_oe_campo    TINYINT DEFAULT 0;
    DECLARE v_oe_orden    INT DEFAULT NULL;
    DECLARE v_oe_usuario  BIGINT DEFAULT NULL;
    DECLARE v_ya_existia  TINYINT DEFAULT 0;
    DECLARE v_ya_reg      TINYINT DEFAULT 0;
    DECLARE v_foto_ok     TINYINT DEFAULT 0;
    DECLARE v_tipo_interv INT DEFAULT NULL;
    DECLARE v_orden       INT DEFAULT 1;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_login       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_serie      = TRIM(IFNULL(p_num_serie, ''));
    SET v_codigo_cli = TRIM(IFNULL(p_codigo_cliente, ''));
    SET v_marca      = TRIM(IFNULL(p_marca, ''));
    SET v_modelo     = TRIM(IFNULL(p_modelo, ''));
    SET v_ubicacion  = TRIM(IFNULL(p_ubicacion, ''));

    IF v_serie = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el N/S del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_codigo_cli = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el código del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_marca = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona la marca.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_modelo = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el modelo.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_id_suministro, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ubicacion = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la ubicación del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_num_serie, '')) > 80 OR CHAR_LENGTH(IFNULL(p_codigo_cliente, '')) > 80
       OR CHAR_LENGTH(IFNULL(p_modelo, '')) > 80 OR CHAR_LENGTH(IFNULL(p_ubicacion, '')) > 200 THEN
        SELECT 1 AS IdTipoMensaje, 'Algún dato supera el largo permitido (N/S, código y modelo: 80; ubicación: 200).' AS Mensaje; LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_foto_placa, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto de la placa del equipo (solo cámara).' AS Mensaje; LEAVE proc;
    END IF;

    -- La marca debe ser una del catálogo (se guarda con el nombre del catálogo)
    SELECT t.String1 INTO v_marca_cat
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'MARCA_SUMINISTRO' AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.String1 = v_marca
    LIMIT 1;
    IF v_marca_cat IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La marca no está en el catálogo: elige una de la lista.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_marca = v_marca_cat;

    -- El tipo de equipo es un suministro activo de clase equipo / instrumento / pesa
    SELECT su.clase INTO v_clase
    FROM   suministros su
    WHERE  su.id_suministro = p_id_suministro AND su.eliminado_en IS NULL AND su.estado = 'activo' AND su.clase IN ('equipo', 'instrumento', 'pesa');
    IF v_clase IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de equipo elegido no existe o no está activo.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    -- La OS debe ser del técnico del token (se bloquea la fila: dos envíos seguidos no se pisan)
    SELECT os.estado, os.numero, os.id_cliente, os.id_sede INTO v_estado_os, v_numero_os, v_id_cliente, v_id_sede
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop (HU-06): una sola vez, en SP_EvaluarCampoMovil
    CALL SP_EvaluarCampoMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje; LEAVE proc;
    END IF;

    SELECT u.correo, u.area, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_login, v_area, v_nombre_tec
    FROM   usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;

    -- ¿El equipo ya existe en el maestro del cliente? (misma regla que SP_GuardarEquipoCliente: serie + marca + modelo)
    SELECT ec.id_equipo, ec.codigo_tw INTO v_id_equipo, v_codigo_tw
    FROM   equipo_cliente ec
    WHERE  ec.id_cliente = v_id_cliente AND ec.SoftDelete = 0
      AND  ec.num_serie = v_serie AND ec.marca = v_marca AND ec.modelo = v_modelo
    ORDER BY ec.id_equipo LIMIT 1;

    IF v_id_equipo IS NOT NULL THEN
        SET v_ya_existia = 1;
        SELECT oe.id, oe.ingresado_en_campo, oe.orden, oe.creado_por INTO v_id_oe, v_oe_campo, v_oe_orden, v_oe_usuario
        FROM   os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL
        LIMIT 1;

        IF v_id_oe IS NOT NULL THEN
            IF v_oe_campo = 1 AND v_oe_usuario = p_id_usuario THEN
                -- Reintento de la app: ya lo registró este técnico en esta O/S
                SET v_ya_reg = 1;
            ELSE
                ROLLBACK;
                SELECT 1 AS IdTipoMensaje,
                       CONCAT('Este equipo ya está en la lista de la O/S (', v_codigo_tw, '): búscalo y selecciónalo.') AS Mensaje;
                LEAVE proc;
            END IF;
        END IF;
    END IF;

    IF v_ya_reg = 0 THEN
        -- Mismo tipo de intervención que los demás objetivos de la O/S (la intranet lo puede cambiar); el orden va al final
        SELECT oe.id_tipo_intervencion INTO v_tipo_interv
        FROM   os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_tipo_intervencion IS NOT NULL
        ORDER BY oe.id LIMIT 1;
        SELECT IFNULL(MAX(IFNULL(oe.orden, oe.id)), 0) + 1 INTO v_orden
        FROM   os_equipo oe WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL;

        IF v_id_equipo IS NULL THEN
            -- COD TW provisional (único): la intranet asigna el definitivo al aprobar el registro
            INSERT INTO equipo_cliente (
                codigo_tw, num_serie, id_cliente, id_sede, codigo_cliente, clasificacion, marca, modelo, ubicacion_especifica,
                es_pre_revisado, bloqueado_para_servicios, id_suministro, estado_operativo, es_activo, estado,
                usuario_registro, SoftDelete, UsuCre, FchCre, registrado_en_campo, id_os_registro, foto_placa_url)
            VALUES (
                CONCAT('NEW-', UUID_SHORT()), v_serie, v_id_cliente, v_id_sede, v_codigo_cli, v_clase, v_marca, v_modelo, v_ubicacion,
                0, 0, p_id_suministro, NULL, 1, 'borrador',
                v_login, 0, v_login, NOW(), 1, p_id_os, TRIM(p_foto_placa));
            SET v_id_equipo = LAST_INSERT_ID();
            SET v_codigo_tw = CONCAT('NEW-', LPAD(v_id_equipo, 6, '0'));
            UPDATE equipo_cliente SET codigo_tw = v_codigo_tw WHERE id_equipo = v_id_equipo;
            SET v_foto_ok = 1;
        END IF;

        INSERT INTO os_equipo (id_os, id_equipo, id_tipo_intervencion, orden, ingresado_en_campo, estado_ejecucion, creado_por)
        VALUES (p_id_os, v_id_equipo, v_tipo_interv, v_orden, 1, 'pendiente', p_id_usuario);
        SET v_id_oe = LAST_INSERT_ID();

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', v_id_oe, 'registrar_equipo_campo', NULL, 'por iniciar',
                LEFT(CONCAT(IF(v_ya_existia = 1, 'Equipo ya registrado agregado desde campo a ', 'Equipo nuevo registrado desde campo en '), v_numero_os,
                            ': N/S ', v_serie, ' · ', v_marca, ' ', v_modelo, ' · ', v_ubicacion), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'id_equipo', v_id_equipo, 'codigo_tw', v_codigo_tw, 'ya_existia', v_ya_existia = 1));

        IF v_ya_existia = 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('equipo_cliente', v_id_equipo, 'registrar_equipo_campo', NULL, 'borrador',
                    LEFT(CONCAT('Registrado desde la app móvil en ', v_numero_os, ' por ', v_nombre_tec, ': pendiente de aprobación (COD TW provisional ', v_codigo_tw, ').'), 900),
                    p_id_usuario, NOW(),
                    JSON_OBJECT('id_os', p_id_os, 'num_serie', v_serie, 'marca', v_marca, 'modelo', v_modelo, 'id_suministro', p_id_suministro));

            -- Aviso para aprobar el registro: supervisores/administradores del área del técnico y su jefe; si no hay, administradores
            SET v_texto = LEFT(CONCAT(v_nombre_tec, ' registró un equipo nuevo en la O/S ', v_numero_os, ' (N/S ', v_serie, ' · ', v_marca, ' ', v_modelo,
                                      '). Falta aprobar el registro y asignar su COD TW.'), 500);
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Equipo nuevo por aprobar', v_texto, 'equipo_cliente', v_id_equipo, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
              AND  IFNULL(v_area, '') <> ''
              AND  ((u.area = v_area AND u.rol_sistema IN ('supervisor', 'administrador'))
                    OR u.cargo = CONCAT('jefe_', v_area));
            SET v_notif = ROW_COUNT();
            IF v_notif = 0 THEN
                INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
                SELECT u.id_usuario, 5, 'Equipo nuevo por aprobar', v_texto, 'equipo_cliente', v_id_equipo, NOW(), p_id_usuario
                FROM   usuario u
                WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
                  AND  u.rol_sistema IN ('administrador', 'admin');
                SET v_notif = ROW_COUNT();
            END IF;
        END IF;
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE WHEN v_ya_reg = 1 THEN 'Ya registraste este equipo.'
                WHEN v_ya_existia = 1 THEN 'El equipo ya estaba registrado en el sistema: se agregó a esta O/S.'
                ELSE 'Equipo registrado. El COD TW lo asigna la intranet al aprobar el registro.' END AS Mensaje;
    SELECT v_id_oe AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_ya_existia AS ya_existia, v_ya_reg AS ya_registrado,
           v_foto_ok AS foto_guardada, v_notif AS notificados;
END$$

DELIMITER ;
