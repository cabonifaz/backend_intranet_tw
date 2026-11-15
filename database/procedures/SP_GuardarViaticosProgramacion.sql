-- HU-45 (Sprint 5) "Guardar asignación" de la pestaña Asignación de Viáticos. Solo el Jefe (prog_aprobar_reprogramacion) y con la programación
-- CONFIRMADA (Programado), su rendición abierta y el servicio todavía sin salir a campo (OS no en_ruta/en_ejecucion/pausada/finalizada). Modelo B: el Jefe asigna un monto por técnico y concepto como ADELANTO.
--   p_version: la huella que devolvió SP_ObtenerViaticosProgramacion. Si otra persona (o Contabilidad al depositar) cambió la asignación
--     mientras se editaba, se rechaza y hay que recargar (control de concurrencia optimista).
--   p_lineas (JSON): la asignación COMPLETA que debe quedar: [{"idGasto":n|null,"idTecnico":n,"idConcepto":n|null,"nuevoConcepto":"texto"|null,"monto":0.00}]
--     · idGasto null = línea nueva · idGasto = línea existente (se actualiza si cambió) · línea existente que no viene = se quita.
--     · Un concepto es del catálogo (idConcepto) O nuevo (nuevoConcepto: se crea una vez; si ya existe con el mismo nombre se reutiliza).
--     · Solo técnicos de esta programación; un concepto por técnico; monto > 0 y hasta VIATICOS_MONTO_MAXIMO (5 000 por defecto).
--     · Las líneas DEPOSITADAS (estado 'aprobado', las marca Contabilidad) son inmutables: deben venir tal cual y no se pueden quitar.
-- Al guardar con cambios (o con líneas nunca avisadas) se NOTIFICA a Contabilidad (área contabilidad) con la lista consolidada de lo pendiente
--   de depósito. Este módulo NUNCA marca "Depositado". Auditoría en el historial de la programación.
-- Concurrencia: OS → programación → catálogo (mismo orden que el resto). Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_GuardarViaticosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_GuardarViaticosProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT,
    IN p_version         VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_lineas          JSON
)
proc: BEGIN
    DECLARE v_id_os      BIGINT DEFAULT NULL;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente BIGINT DEFAULT NULL;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version    VARCHAR(80);
    DECLARE v_cap        DECIMAL(18,6) DEFAULT 5000;
    DECLARE v_error      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n          INT DEFAULT 0;
    DECLARE v_i          INT DEFAULT 1;
    DECLARE v_nombre     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_conc    INT DEFAULT NULL;
    DECLARE v_next       INT DEFAULT 0;
    DECLARE v_nuevos     INT DEFAULT 0;
    DECLARE v_custom     INT DEFAULT 0;
    DECLARE v_creadas    INT DEFAULT 0;
    DECLARE v_modif      INT DEFAULT 0;
    DECLARE v_retiradas  INT DEFAULT 0;
    DECLARE v_retirados  TEXT;
    DECLARE v_sin_avisar INT DEFAULT 0;
    DECLARE v_lista      TEXT;
    DECLARE v_total      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_depos      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_pend       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_contab     INT DEFAULT 0;
    DECLARE v_mensaje    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    SET SESSION group_concat_max_len = 32768;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede asignar viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_version, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la versión de la asignación: vuelve a abrir la gestión de viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_lineas IS NULL OR NOT JSON_VALID(p_lineas) OR JSON_TYPE(p_lineas) <> 'ARRAY' THEN
        SELECT 1 AS IdTipoMensaje, 'La asignación debe enviarse como una lista de líneas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF JSON_LENGTH(p_lineas) > 60 THEN
        SELECT 1 AS IdTipoMensaje, 'Una programación admite hasta 60 líneas de viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LeerParametroProgramacion('VIATICOS_MONTO_MAXIMO', 5000, v_cap);

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT numero, tipo, id_cliente, estado INTO v_numero, v_tipo, v_id_cliente, v_estado_os
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;
    SELECT codigo, estado INTO v_codigo, v_estado FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;

    IF v_codigo IS NULL THEN
        SET v_error = 'La programación no existe.';
    ELSEIF v_estado_os IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada') THEN
        -- La app pasa la OS a en_ruta al iniciar el traslado (SP_IniciarTrasladoMovil)
        SET v_error = 'La asignación ya no se puede editar: el servicio salió a campo.';
    ELSEIF v_estado = 'cancelada' THEN
        SET v_error = CONCAT('La programación ', v_codigo, ' está cancelada: ya no admite viáticos.');
    ELSEIF v_estado <> 'confirmada' THEN
        SET v_error = CONCAT('La programación ', v_codigo, ' aún no está confirmada por el cliente: los viáticos se asignan cuando está Programado.');
    ELSEIF EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL) THEN
        SET v_error = 'La rendición ya fue cerrada: los viáticos quedan solo de lectura.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_VersionViaticosProgramacion(p_id_programacion, v_id_os, 1, v_version);
    IF v_version <> TRIM(p_version) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La asignación cambió mientras la editabas (por ejemplo, Contabilidad registró un depósito). Recarga e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Entrada ───────────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
    CREATE TEMPORARY TABLE tmp_vi_in (
        n        INT NOT NULL, id_gasto BIGINT NULL, id_usuario BIGINT NULL, id_concepto INT NULL,
        nuevo    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, monto DECIMAL(12,2) NULL, cf INT NULL,
        PRIMARY KEY (n)
    );
    INSERT INTO tmp_vi_in (n, id_gasto, id_usuario, id_concepto, nuevo, monto)
    SELECT j.n, j.id_gasto, j.id_usuario, j.id_concepto, NULLIF(TRIM(j.nuevo), ''), j.monto
    FROM JSON_TABLE(p_lineas, '$[*]' COLUMNS (
            n FOR ORDINALITY,
            id_gasto    BIGINT         PATH '$.idGasto'       NULL ON EMPTY NULL ON ERROR,
            id_usuario  BIGINT         PATH '$.idTecnico'     NULL ON EMPTY NULL ON ERROR,
            id_concepto INT            PATH '$.idConcepto'    NULL ON EMPTY NULL ON ERROR,
            nuevo       VARCHAR(100)   PATH '$.nuevoConcepto' NULL ON EMPTY NULL ON ERROR,
            monto       DECIMAL(12,2)  PATH '$.monto'         NULL ON EMPTY NULL ON ERROR)) j;
    SELECT COUNT(*) INTO v_n FROM tmp_vi_in;

    -- Formas
    IF v_n <> JSON_LENGTH(p_lineas) THEN
        SET v_error = 'La asignación tiene líneas con un formato no válido.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE monto IS NULL OR monto <= 0 OR monto > v_cap) THEN
        SET v_error = CONCAT('Cada monto debe ser mayor a 0 y de hasta S/ ', FORMAT(v_cap, 2), '.');
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE id_usuario IS NULL OR id_usuario <= 0) THEN
        SET v_error = 'Cada línea debe indicar el técnico.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE (id_concepto IS NULL AND nuevo IS NULL) OR (id_concepto IS NOT NULL AND nuevo IS NOT NULL)) THEN
        SET v_error = 'Cada línea debe tener un concepto: elige uno del catálogo o crea uno nuevo (no ambos).';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE nuevo IS NOT NULL AND (CHAR_LENGTH(nuevo) NOT BETWEEN 2 AND 60 OR nuevo REGEXP '[[:cntrl:]]')) THEN
        SET v_error = 'El nombre del concepto nuevo debe tener entre 2 y 60 caracteres, sin caracteres de control.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE id_gasto IS NOT NULL AND id_gasto <= 0) THEN
        SET v_error = 'Hay una línea con un identificador no válido.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE id_gasto IS NOT NULL GROUP BY id_gasto HAVING COUNT(*) > 1) THEN
        SET v_error = 'Una línea viene repetida en la asignación.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_concepto IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM tabla_maestra c WHERE c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = t.id_concepto AND c.eliminado_en IS NULL)) THEN
        SET v_error = 'Hay un concepto que no existe en el catálogo.';
    ELSEIF (SELECT COUNT(DISTINCT id_usuario) FROM tmp_vi_in) > 10 THEN
        SET v_error = 'Una programación admite viáticos para hasta 10 técnicos.';
    END IF;

    -- Líneas existentes
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM gasto_viatico g WHERE g.id_gasto = t.id_gasto AND g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
                          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os)))) THEN
        SET v_error = 'Una de las líneas ya no existe: recarga la gestión de viáticos.';
    END IF;

    -- Líneas depositadas: inmutables (deben venir iguales) y no se pueden quitar
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM gasto_viatico g
        WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado IN ('aprobado', 'rendido')
          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
          AND NOT EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto = g.id_gasto)) THEN
        SET v_error = 'Los viáticos ya depositados no se pueden quitar: inclúyelos tal como están.';
    END IF;
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM tmp_vi_in t JOIN gasto_viatico g ON g.id_gasto = t.id_gasto
        WHERE g.estado IN ('aprobado', 'rendido') AND (g.monto <> t.monto OR g.id_usuario <> t.id_usuario OR (t.id_concepto IS NOT NULL AND g.id_concepto <> t.id_concepto) OR t.nuevo IS NOT NULL)) THEN
        SET v_error = 'Los viáticos ya depositados no se pueden modificar.';
    END IF;

    -- Técnicos: solo el personal de la programación (una línea nueva o modificada no puede ir a otra persona)
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM tmp_vi_in t
        LEFT JOIN gasto_viatico g ON g.id_gasto = t.id_gasto
        WHERE NOT EXISTS (SELECT 1 FROM programacion_tecnico pt WHERE pt.id_programacion = p_id_programacion AND pt.id_usuario = t.id_usuario AND pt.eliminado_en IS NULL)
          AND (g.id_gasto IS NULL OR g.id_usuario <> t.id_usuario OR g.monto <> t.monto OR t.nuevo IS NOT NULL OR (t.id_concepto IS NOT NULL AND g.id_concepto <> t.id_concepto))) THEN
        SET v_error = 'Los viáticos solo se asignan al personal de esta programación.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Conceptos nuevos: se reutiliza el existente con el mismo nombre; si no existe, se crea en el catálogo ─────────
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
    CREATE TEMPORARY TABLE tmp_vi_nc (i INT NOT NULL AUTO_INCREMENT, nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (i));
    INSERT INTO tmp_vi_nc (nombre) SELECT DISTINCT nuevo FROM tmp_vi_in WHERE nuevo IS NOT NULL;
    SELECT COUNT(*) INTO v_nuevos FROM tmp_vi_nc;
    SET v_i = 1;
    WHILE v_i <= v_nuevos DO
        SELECT nombre INTO v_nombre FROM tmp_vi_nc WHERE i = v_i;
        SET v_id_conc = NULL;
        SELECT Num1 INTO v_id_conc FROM tabla_maestra
        WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String1 = v_nombre ORDER BY Num1 LIMIT 1;
        IF v_id_conc IS NULL THEN
            SELECT COUNT(*) INTO v_custom FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 LIKE 'PERS\_%';
            IF v_custom >= 50 THEN
                SET v_error = 'Se alcanzó el máximo de conceptos personalizados (50): usa uno existente.';
            ELSE
                SELECT IFNULL(MAX(Num1), 0) + 1 INTO v_next FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 FOR UPDATE;
                INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3, creado_por)
                VALUES (1, 25, 'CONCEPTO_GASTO', v_next, v_nombre, 'viatico', CONCAT('PERS_', v_next), p_id_usuario);
                SET v_id_conc = v_next;
            END IF;
        END IF;
        IF v_error IS NOT NULL THEN
            SET v_i = v_nuevos + 1;
        ELSE
            UPDATE tmp_vi_in SET cf = v_id_conc WHERE nuevo = v_nombre;
            SET v_i = v_i + 1;
        END IF;
    END WHILE;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;
    UPDATE tmp_vi_in SET cf = id_concepto WHERE id_concepto IS NOT NULL;

    IF EXISTS (SELECT 1 FROM tmp_vi_in GROUP BY id_usuario, cf HAVING COUNT(*) > 1) THEN
        SET v_error = 'Un técnico no puede tener dos líneas con el mismo concepto: edita el monto de la existente.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in GROUP BY id_usuario HAVING COUNT(*) > 12) THEN
        SET v_error = 'Un técnico admite hasta 12 conceptos de viáticos.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Cambios ───────────────────────────────────────────────────────────────────────────
    -- Quitadas (solo pendientes de depósito): se guarda qué se retiró si ya se le había avisado a Contabilidad
    SELECT GROUP_CONCAT(CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' · ', IFNULL(c.String1, 'Concepto'), ' S/ ', FORMAT(g.monto, 2)) ORDER BY g.id_gasto SEPARATOR '; ')
      INTO v_retirados
    FROM gasto_viatico g
    JOIN usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = g.id_concepto
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NOT NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
      AND NOT EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto = g.id_gasto);

    UPDATE gasto_viatico g
    SET g.eliminado_en = NOW(), g.eliminado_por = p_id_usuario
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido')
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
      AND NOT EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto = g.id_gasto);
    SET v_retiradas = ROW_COUNT();

    UPDATE gasto_viatico g
    JOIN tmp_vi_in t ON t.id_gasto = g.id_gasto
    SET g.id_usuario = t.id_usuario, g.id_concepto = t.cf, g.monto = t.monto, g.notificado_en = NULL, g.modificado_por = p_id_usuario
    WHERE g.estado NOT IN ('aprobado', 'rendido') AND (g.monto <> t.monto OR g.id_concepto <> t.cf OR g.id_usuario <> t.id_usuario);
    SET v_modif = ROW_COUNT();

    UPDATE gasto_viatico g
    JOIN tmp_vi_in t ON t.id_gasto = g.id_gasto
    SET g.id_programacion = p_id_programacion
    WHERE g.id_programacion IS NULL;

    INSERT INTO gasto_viatico (id_os, id_programacion, id_usuario, id_concepto, id_moneda, monto, tipo, estado, fecha_solicitud, creado_por)
    SELECT v_id_os, p_id_programacion, t.id_usuario, t.cf, 1, t.monto, 'viatico_asignado', 'pendiente', CURDATE(), p_id_usuario
    FROM tmp_vi_in t WHERE t.id_gasto IS NULL;
    SET v_creadas = ROW_COUNT();

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;

    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0),
           IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), 0, g.monto)), 0), IFNULL(SUM(g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NULL), 0)
      INTO v_total, v_depos, v_pend, v_sin_avisar
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os));

    IF v_creadas + v_modif + v_retiradas = 0 AND v_sin_avisar = 0 THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'No hay cambios en la asignación de viáticos.' AS Mensaje;
        SELECT p_id_programacion AS id_programacion, 0 AS creadas, 0 AS modificadas, 0 AS retiradas, v_total AS total_asignado, v_depos AS total_depositado,
               v_pend AS total_pendiente, 0 AS notificados_contabilidad, 1 AS sin_cambios, v_nuevos AS conceptos_nuevos, v_version AS version;
        LEAVE proc;
    END IF;

    -- ── Notificación a Contabilidad: lista consolidada de lo pendiente de depósito ─────────────────
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;
    SELECT GROUP_CONCAT(CONCAT(x.tecnico, ': ', x.conceptos) ORDER BY x.orden, x.tecnico SEPARATOR ' · ') INTO v_lista
    FROM (SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico, MIN(g.id_gasto) AS orden,
                 GROUP_CONCAT(CONCAT(IFNULL(c.String1, 'Concepto'), ' S/ ', FORMAT(g.monto, 2)) ORDER BY g.id_gasto SEPARATOR ', ') AS conceptos
          FROM gasto_viatico g
          JOIN usuario u ON u.id_usuario = g.id_usuario
          LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = g.id_concepto
          WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido')
            AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
          GROUP BY g.id_usuario) x;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, LEFT(CONCAT('Viáticos por depositar: ', v_numero), 150),
           LEFT(CONCAT('Programación ', v_codigo, ' · ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), '. ',
                       IF(v_pend > 0, CONCAT('Pendiente de depósito: S/ ', FORMAT(v_pend, 2), ' (', IFNULL(v_lista, ''), ').'), 'No quedan viáticos pendientes de depósito.'),
                       IF(v_retirados IS NULL, '', CONCAT(' Se retiró lo anunciado antes: ', v_retirados, '.'))), 3000),
           'programacion', p_id_programacion, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'contabilidad' AND u.id_usuario <> p_id_usuario;
    SET v_contab = ROW_COUNT();

    UPDATE gasto_viatico g SET g.notificado_en = NOW()
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os));

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'asignar_viaticos', v_estado, v_estado,
            LEFT(CONCAT('Viáticos asignados en ', v_codigo, ': total S/ ', FORMAT(v_total, 2), ', pendiente de depósito S/ ', FORMAT(v_pend, 2),
                        ' (', v_creadas, ' nuevas, ', v_modif, ' modificadas, ', v_retiradas, ' retiradas).'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('creadas', v_creadas, 'modificadas', v_modif, 'retiradas', v_retiradas, 'totalAsignado', v_total,
                        'totalDepositado', v_depos, 'totalPendiente', v_pend, 'conceptosNuevos', v_nuevos, 'notificadosContabilidad', v_contab));

    COMMIT;

    CALL SP_VersionViaticosProgramacion(p_id_programacion, v_id_os, 1, v_version);
    SET v_mensaje = CONCAT('Asignación de viáticos guardada.',
                           IF(v_contab > 0, CONCAT(' Se notificó a Contabilidad: S/ ', FORMAT(v_pend, 2), ' pendientes de depósito.'),
                              ' No hay usuarios de Contabilidad configurados para recibir el aviso.'));
    SELECT 2 AS IdTipoMensaje, v_mensaje AS Mensaje;
    SELECT p_id_programacion AS id_programacion, v_creadas AS creadas, v_modif AS modificadas, v_retiradas AS retiradas, v_total AS total_asignado,
           v_depos AS total_depositado, v_pend AS total_pendiente, v_contab AS notificados_contabilidad, 0 AS sin_cambios, v_nuevos AS conceptos_nuevos,
           v_version AS version;
END$$

DELIMITER ;
