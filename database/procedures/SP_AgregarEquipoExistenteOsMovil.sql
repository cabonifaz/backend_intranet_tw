-- ============================================================
-- SP_AgregarEquipoExistenteOsMovil  (App Mobile HU-22 — agregar a la OS un equipo YA REGISTRADO escaneando su QR / código · escritura)
-- El técnico escanea el QR de un equipo que existe en el maestro del cliente pero NO está en la lista de la OS: se agrega como objetivo de esta OS.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_EvaluarCampoMovil).
--   - El equipo se busca por COD TW, código del cliente o N/S (sin distinguir mayúsculas), por una URL que traiga su COD TW / código (5 o más caracteres)
--     o por la etiqueta QR de TW ya vinculada al equipo (equipo_qr). Debe ser del MISMO cliente de la OS (también se acepta el de otro registro de cliente con el mismo RUC, o un equipo sin cliente asignado).
--     Si es de OTRO cliente el mensaje dice de cuál es y, si está en una OS vigente, en cuál; solo en ese caso no se puede agregar.
--   - No se agregan equipos inactivos ni en evaluación (bloqueados) ni en borrador (pendientes de validar). Si ya está en la lista de la OS, se avisa.
--   - Queda con el mismo tipo de intervención que los demás objetivos de la OS, al final de la lista, "por iniciar". Auditoría en auditoria_evento.
--     ingresado_en_campo = 1: así lo muestra la lista de objetivos aunque no esté en la programación (SP_ArmarObjetivosMovil). La app solo lo marca como BORRADOR
--     si su COD TW es provisional (NEW-…).
--   - Si el código no corresponde a ningún equipo del cliente, la app ofrece registrarlo como equipo nuevo (NEW, con foto de la placa).
--   - p_solo_verificar = 1: hace TODAS las validaciones y devuelve los datos del equipo SIN agregarlo (id_os_equipo = 0): la app los muestra y pide confirmar;
--     solo con la confirmación vuelve a llamar con p_solo_verificar = 0 y recién entonces el equipo se registra en la OS.
--   - REEMPLAZO (no se crea un objetivo nuevo): el equipo escaneado ocupa el lugar del equipo de un objetivo SIN INICIAR (estado pendiente, visible y sin ingreso registrado):
--     el objetivo indicado (p_id_os_equipo_objetivo, el de la pantalla Selección de equipo) o, sin indicar, el primero de la lista. Así un servicio de 1 objetivo sigue teniendo 1
--     aunque se use otro equipo para hacer el trabajo. El objetivo conserva su id (concepto, ingreso y tiempos) y queda como «agregado desde campo». El equipo reemplazado sale de la OS
--     (sigue en el maestro de equipos) y queda en la auditoría. Si ningún objetivo se puede reemplazar (todos iniciados) se agrega como objetivo nuevo, como antes.
--     Un equipo que está en OTRA orden también se puede agregar: solo se evita repetirlo en la misma OS.
-- Resultados: 1 mensaje; 2 (id_os_equipo, id_equipo, codigo_tw, marca, modelo, num_serie, codigo_cliente, ubicacion, reemplaza_id_os_equipo, reemplaza_codigo_tw, reemplaza_nombre).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AgregarEquipoExistenteOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_AgregarEquipoExistenteOsMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_verificar TINYINT,
    IN p_id_os_equipo_objetivo BIGINT
)
proc: BEGIN
    DECLARE v_codigo      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave       VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_id_cli_eq   BIGINT DEFAULT NULL;
    DECLARE v_codigo_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_activo      TINYINT DEFAULT 1;
    DECLARE v_estado_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oper        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_interv INT DEFAULT NULL;
    DECLARE v_orden       INT DEFAULT 1;
    DECLARE v_id_oe       BIGINT DEFAULT NULL;
    DECLARE v_marca       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_modelo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_serie       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_cli     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ubic        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ruc         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_otro_id     BIGINT DEFAULT NULL;
    DECLARE v_otro_cod    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_otro_cli    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_otra_os     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_obj      BIGINT DEFAULT NULL;
    DECLARE v_cod_obj     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_obj     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_prog     BIGINT DEFAULT NULL;
    DECLARE v_n_prog      INT DEFAULT 0;
    DECLARE v_dup         BIGINT DEFAULT NULL;
    DECLARE v_id_dest     BIGINT DEFAULT NULL;

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
    SET v_codigo = UPPER(TRIM(IFNULL(p_codigo, '')));
    IF CHAR_LENGTH(v_codigo) = 0 OR CHAR_LENGTH(v_codigo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El código escaneado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_cliente INTO v_estado_os, v_numero_os, v_id_cliente
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarCampoMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje;
        LEAVE proc;
    END IF;

    -- RUC del cliente de la OS: un mismo cliente puede tener más de un registro y sus equipos también valen
    SELECT NULLIF(TRIM(c.ruc), '') INTO v_ruc FROM cliente c WHERE c.id_cliente = v_id_cliente;

    -- Etiqueta QR de TW (enlace corto): se reconoce si ya está vinculada a un equipo
    CALL SP_NormalizarQrMovil(p_codigo, v_clave);

    -- Primero entre los equipos del cliente de la OS (la coincidencia exacta gana sobre la que solo contiene el código)
    SELECT ec.id_equipo, ec.codigo_tw, ec.id_cliente, IF(ec.es_activo = 0 OR ec.estado = 'inactivo' OR ec.estado_operativo = 'evaluacion', 0, 1), ec.estado
    INTO   v_id_equipo, v_codigo_tw, v_id_cli_eq, v_activo, v_estado_eq
    FROM   equipo_cliente ec
    WHERE  ec.SoftDelete = 0
      AND  (ec.id_cliente = v_id_cliente OR ec.id_cliente IS NULL
            OR (v_ruc IS NOT NULL AND ec.id_cliente IN (SELECT c2.id_cliente FROM cliente c2 WHERE NULLIF(TRIM(c2.ruc), '') = v_ruc)))
      AND  (UPPER(ec.codigo_tw) = v_codigo OR UPPER(ec.codigo_cliente) = v_codigo OR UPPER(ec.num_serie) = v_codigo
            OR (CHAR_LENGTH(IFNULL(ec.codigo_tw, '')) >= 5 AND LOCATE(UPPER(ec.codigo_tw), v_codigo) > 0)
            OR (CHAR_LENGTH(IFNULL(ec.codigo_cliente, '')) >= 5 AND LOCATE(UPPER(ec.codigo_cliente), v_codigo) > 0)
            OR (v_clave IS NOT NULL AND ec.id_equipo IN (SELECT q.id_equipo FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL)))
    ORDER BY (UPPER(ec.codigo_tw) = v_codigo OR UPPER(ec.codigo_cliente) = v_codigo OR UPPER(ec.num_serie) = v_codigo) DESC, ec.id_equipo
    LIMIT 1;

    IF v_id_equipo IS NULL THEN
        -- ¿Existe, pero es de otro cliente? Se dice de cuál es (y en qué OS vigente está) para que el técnico sepa por qué no se puede agregar
        SELECT ec.id_equipo, ec.codigo_tw, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)
        INTO   v_otro_id, v_otro_cod, v_otro_cli
        FROM   equipo_cliente ec
        LEFT JOIN cliente c ON c.id_cliente = ec.id_cliente
        WHERE  ec.SoftDelete = 0
          AND  (UPPER(ec.codigo_tw) = v_codigo OR UPPER(ec.codigo_cliente) = v_codigo OR UPPER(ec.num_serie) = v_codigo
                OR (v_clave IS NOT NULL AND ec.id_equipo IN (SELECT q.id_equipo FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL)))
        ORDER BY ec.id_equipo
        LIMIT 1;
        IF v_otro_id IS NOT NULL THEN
            SELECT os.numero INTO v_otra_os
            FROM   os_equipo oe
            JOIN   orden_servicio os ON os.id_os = oe.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada')
            WHERE  oe.id_equipo = v_otro_id AND oe.eliminado_en IS NULL AND oe.id_os <> p_id_os
            ORDER BY os.id_os DESC
            LIMIT 1;
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   CONCAT(IFNULL(v_otro_cod, 'Ese equipo'), ' pertenece a ', IFNULL(v_otro_cli, 'otro cliente'),
                          IF(v_otra_os IS NULL, '', CONCAT(' y está asignado a la ', v_otra_os)),
                          ': no se puede agregar a esta OS porque es de otro cliente.') AS Mensaje;
        ELSE
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El código no corresponde a ningún equipo registrado de este cliente. Regístralo como equipo nuevo (NEW).' AS Mensaje;
        END IF;
        LEAVE proc;
    END IF;

    IF v_activo = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' está inactivo o en evaluación: no se puede agregar a la OS.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado_eq = 'borrador' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' está pendiente de validar en la intranet: aún no se puede agregar a otra OS.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Datos del equipo para mostrar en la confirmación de la app
    SELECT ec.marca, ec.modelo, ec.num_serie, ec.codigo_cliente, ec.ubicacion_especifica
    INTO   v_marca, v_modelo, v_serie, v_cod_cli, v_ubic
    FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_equipo;

    -- Objetivo cuyo equipo ocupará el escaneado: el indicado por la app o, sin indicar, el primero sin iniciar (mismas reglas de visibilidad que SP_ArmarObjetivosMovil)
    SELECT pr.id_programacion INTO v_id_prog
    FROM   programacion pr
    WHERE  pr.id_os = p_id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC LIMIT 1;
    SELECT COUNT(*) INTO v_n_prog FROM programacion_equipo pe WHERE pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;

    SELECT oe.id, ec2.codigo_tw, LEFT(TRIM(CONCAT(IFNULL(ec2.marca, ''), ' ', IFNULL(ec2.modelo, ''))), 200)
    INTO   v_id_obj, v_cod_obj, v_nom_obj
    FROM   os_equipo oe
    JOIN   equipo_cliente ec2 ON ec2.id_equipo = oe.id_equipo
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
      AND  IFNULL(oe.estado_ejecucion, 'pendiente') = 'pendiente'
      AND  oe.id_equipo <> v_id_equipo
      AND  (IFNULL(p_id_os_equipo_objetivo, 0) = 0 OR oe.id = p_id_os_equipo_objetivo)
      AND  (v_n_prog = 0 OR oe.ingresado_en_campo = 1
            OR EXISTS (SELECT 1 FROM programacion_equipo pe WHERE pe.id_programacion = v_id_prog AND pe.id_equipo = oe.id_equipo AND pe.eliminado_en IS NULL))
      AND  NOT EXISTS (SELECT 1 FROM os_equipo_ingreso i WHERE i.id_os_equipo = oe.id)
    ORDER BY IFNULL(oe.orden, oe.id), oe.id
    LIMIT 1;
    IF IFNULL(p_id_os_equipo_objetivo, 0) > 0 AND v_id_obj IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese objetivo ya se inició o ya tiene su ingreso registrado: no se puede cambiar su equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Solo verificar: el equipo es válido para esta OS pero NO se agrega hasta que el técnico confirme
    IF IFNULL(p_solo_verificar, 0) = 1 THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' encontrado: confirma para agregarlo a la OS.') AS Mensaje;
        SELECT 0 AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_marca AS marca, v_modelo AS modelo, v_serie AS num_serie,
               v_cod_cli AS codigo_cliente, v_ubic AS ubicacion, v_id_obj AS reemplaza_id_os_equipo, v_cod_obj AS reemplaza_codigo_tw, v_nom_obj AS reemplaza_nombre;
        LEAVE proc;
    END IF;

    -- Reemplazo: el equipo escaneado ocupa el lugar del equipo pendiente del objetivo (no se crea un objetivo nuevo)
    IF v_id_obj IS NOT NULL THEN
        SELECT oe.id INTO v_dup FROM os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL AND oe.id <> v_id_obj LIMIT 1;
        IF v_dup IS NOT NULL THEN
            -- el equipo ya tenía una fila (oculta) en esta OS: se deja visible y el objetivo reemplazado sale de la OS
            UPDATE os_equipo SET ingresado_en_campo = 1 WHERE id = v_dup;
            UPDATE os_equipo SET eliminado_en = NOW() WHERE id = v_id_obj;
            SET v_id_dest = v_dup;
        ELSE
            UPDATE os_equipo SET id_equipo = v_id_equipo, ingresado_en_campo = 1 WHERE id = v_id_obj;
            SET v_id_dest = v_id_obj;
        END IF;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', v_id_dest, 'reemplazar_equipo_objetivo', v_cod_obj, v_codigo_tw,
                LEFT(CONCAT('Equipo ', v_codigo_tw, ' ocupó el lugar de ', v_cod_obj, ' en el objetivo de ', v_numero_os, ' (escaneado en campo)'), 300),
                p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', v_id_dest, 'codigo_tw_nuevo', v_codigo_tw, 'codigo_tw_anterior', v_cod_obj));
        COMMIT;
        SELECT 2 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' ocupó el lugar de ', v_cod_obj, ' en el objetivo de la OS.') AS Mensaje;
        SELECT v_id_dest AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_marca AS marca, v_modelo AS modelo, v_serie AS num_serie,
               v_cod_cli AS codigo_cliente, v_ubic AS ubicacion, v_id_obj AS reemplaza_id_os_equipo, v_cod_obj AS reemplaza_codigo_tw, v_nom_obj AS reemplaza_nombre;
        LEAVE proc;
    END IF;

    -- Si el equipo ya tiene fila en la OS pero la lista de objetivos no lo mostraba (SP_ArmarObjetivosMovil solo muestra los de la programación o los
    -- registrados en campo), se deja visible. Si el técnico llegó aquí es porque la búsqueda en la lista no lo encontró.
    SELECT oe.id INTO v_id_oe FROM os_equipo oe WHERE oe.id_os = p_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL LIMIT 1;
    IF v_id_oe IS NOT NULL THEN
        UPDATE os_equipo SET ingresado_en_campo = 1 WHERE id = v_id_oe;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', v_id_oe, 'agregar_equipo_existente', NULL, 'por iniciar',
                LEFT(CONCAT('Equipo ', v_codigo_tw, ' agregado desde campo (QR) a ', v_numero_os), 300),
                p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_equipo', v_id_equipo, 'codigo_tw', v_codigo_tw, 'ya_estaba_en_la_os', TRUE));
        COMMIT;
        SELECT 2 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' agregado a la lista de la OS.') AS Mensaje;
        SELECT v_id_oe AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_marca AS marca, v_modelo AS modelo, v_serie AS num_serie,
               v_cod_cli AS codigo_cliente, v_ubic AS ubicacion, NULL AS reemplaza_id_os_equipo, NULL AS reemplaza_codigo_tw, NULL AS reemplaza_nombre;
        LEAVE proc;
    END IF;

    SELECT oe.id_tipo_intervencion INTO v_tipo_interv
    FROM   os_equipo oe
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_tipo_intervencion IS NOT NULL
    ORDER BY oe.id LIMIT 1;
    SELECT IFNULL(MAX(IFNULL(oe.orden, oe.id)), 0) + 1 INTO v_orden
    FROM   os_equipo oe WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL;

    INSERT INTO os_equipo (id_os, id_equipo, id_tipo_intervencion, orden, ingresado_en_campo, estado_ejecucion, creado_por)
    VALUES (p_id_os, v_id_equipo, v_tipo_interv, v_orden, 1, 'pendiente', p_id_usuario);
    SET v_id_oe = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', v_id_oe, 'agregar_equipo_existente', NULL, 'por iniciar',
            LEFT(CONCAT('Equipo ', v_codigo_tw, ' agregado desde campo (QR) a ', v_numero_os), 300),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_equipo', v_id_equipo, 'codigo_tw', v_codigo_tw));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' agregado a la lista de la OS.') AS Mensaje;
    SELECT v_id_oe AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_marca AS marca, v_modelo AS modelo, v_serie AS num_serie,
           v_cod_cli AS codigo_cliente, v_ubic AS ubicacion, NULL AS reemplaza_id_os_equipo, NULL AS reemplaza_codigo_tw, NULL AS reemplaza_nombre;
END$$

DELIMITER ;
