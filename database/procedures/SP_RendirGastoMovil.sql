-- ============================================================
-- SP_RendirGastoMovil  (App Mobile HU-27 — rendir un gasto o corregir uno observado · escritura)
-- Una sola ruta para los dos orígenes del dinero (los dos van a gasto_viatico tipo 'gasto_solicitado', los revisa el Jefe de Operaciones y entran al
-- cierre de la rendición):
--   origen 'viatico'   sale del adelanto: trae p_reparto [{ "idViaticoLinea": n, "monto": 0.00 }] (líneas viatico_asignado del MISMO técnico y de ESA OS,
--                      sin repetirse, y la suma exacta = p_monto). El concepto del gasto es el de la línea con más monto. Si una línea se pasa de lo que le
--                      queda NO se rechaza: se guarda y se devuelve una advertencia (lo aprobado de más se le paga al técnico al cerrar la rendición).
--   origen 'reembolso' lo pagó el técnico: trae p_id_concepto (CONCEPTO_GASTO) y, si es "Otro" (String3 = 'OTRO'), p_concepto_texto (2 a 100 caracteres).
--   p_id_gasto = 0: gasto nuevo. p_id_cliente_app (GUID de la app): si ya existe un gasto del técnico con ese GUID, se devuelve ese (reintento de la
--     sincronización) sin crear otro: duplicado = 1 (la API borra las fotos que acaba de guardar).
--   p_id_gasto > 0: corregir un gasto OBSERVADO del técnico (vuelve a 'pendiente'). p_fotos_conservar = [orden…] de las fotos que se quedan; las demás se
--     retiran. Las nuevas se agregan al final.
--   p_fotos_nuevas: ["ruta", …] ya guardadas por la API (JPEG validados por contenido, máx. 5 MB, nombre generado por el servidor). Total ≤ 5 fotos.
--   Sin ninguna foto, p_motivo_sin_foto es obligatorio (3 a 300 caracteres).
--   p_monto_ia / p_coincide_ia: lo que leyó la IA en la primera foto nueva (NULL = sin lectura). Al corregir sin fotos nuevas se conserva la lectura anterior.
-- Reglas: monto > 0 y hasta GASTO_MONTO_MAXIMO (5 000 por defecto); fecha del gasto no futura; el técnico está en la programación activa de la OS, que debe
--   estar confirmada y con la rendición abierta. Notifica a quienes revisan gastos (prog_aprobar_reprogramacion) y deja auditoría. Requiere la migración 114.
-- Resultados: 1 mensaje · 2 gasto (id_gasto, codigo, estado, duplicado) · 3 advertencias (0 o más filas).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RendirGastoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RendirGastoMovil(
    IN p_id_usuario       BIGINT,
    IN p_id_gasto         BIGINT,
    IN p_id_cliente_app   VARCHAR(36)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_origen           VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os            BIGINT,
    IN p_id_concepto      INT,
    IN p_concepto_texto   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_monto            DECIMAL(12,2),
    IN p_fecha_gasto      DATE,
    IN p_descripcion      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_reparto          JSON,
    IN p_motivo_sin_foto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fotos_nuevas     JSON,
    IN p_fotos_conservar  JSON,
    IN p_monto_ia         DECIMAL(12,2),
    IN p_coincide_ia      TINYINT
)
proc: BEGIN
    DECLARE v_hoy        DATE;
    DECLARE v_cap        DECIMAL(18,6) DEFAULT 5000;
    DECLARE v_origen     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os      BIGINT;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal  BIGINT;
    DECLARE v_prog       BIGINT;
    DECLARE v_codigo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_pg  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_g_id       BIGINT;
    DECLARE v_g_estado   VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_g_usuario  BIGINT;
    DECLARE v_id_conc    INT;
    DECLARE v_conc_cod   VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_conc_nom   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desc       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_rep      INT DEFAULT 0;
    DECLARE v_suma       DECIMAL(14,2) DEFAULT 0;
    DECLARE v_n_nuevas   INT DEFAULT 0;
    DECLARE v_n_cons     INT DEFAULT 0;
    DECLARE v_n_cons_ok  INT DEFAULT 0;
    DECLARE v_max_orden  INT DEFAULT 0;
    DECLARE v_error      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_es_nuevo   TINYINT DEFAULT 1;
    DECLARE v_url1       VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando este gasto en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    SET v_hoy      = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    SET v_origen   = LOWER(TRIM(IFNULL(p_origen, '')));
    SET v_es_nuevo = IF(IFNULL(p_id_gasto, 0) > 0, 0, 1);
    SET v_desc     = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');
    SET v_motivo   = NULLIF(TRIM(IFNULL(p_motivo_sin_foto, '')), '');
    SET v_texto    = NULLIF(TRIM(IFNULL(p_concepto_texto, '')), '');
    CALL SP_LeerParametroProgramacion('GASTO_MONTO_MAXIMO', 5000, v_cap);

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Reintento de la sincronización: el mismo GUID devuelve el gasto ya creado ─────────────
    IF v_es_nuevo = 1 AND NULLIF(TRIM(IFNULL(p_id_cliente_app, '')), '') IS NOT NULL THEN
        SELECT MAX(id_gasto) INTO v_g_id
        FROM gasto_viatico
        WHERE id_usuario = p_id_usuario AND id_cliente_app = TRIM(p_id_cliente_app) AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
        IF v_g_id IS NOT NULL THEN
            SELECT 2 AS IdTipoMensaje, 'El gasto ya estaba registrado.' AS Mensaje;
            SELECT id_gasto, CONCAT('GS-', LPAD(id_gasto, 6, '0')) AS codigo, estado, 1 AS duplicado FROM gasto_viatico WHERE id_gasto = v_g_id;
            SELECT CAST(NULL AS CHAR(300)) AS advertencia FROM DUAL WHERE 1 = 0;
            LEAVE proc;
        END IF;
    END IF;

    -- ── Formas ────────────────────────────────────────────────────────────────────────────
    IF v_origen NOT IN ('viatico', 'reembolso') THEN
        SET v_error = 'El origen del gasto debe ser viatico o reembolso.';
    ELSEIF p_monto IS NULL OR p_monto <= 0 OR p_monto > v_cap THEN
        SET v_error = CONCAT('El monto debe ser mayor a 0 y de hasta S/ ', FORMAT(v_cap, 2), '.');
    ELSEIF p_fecha_gasto IS NULL OR p_fecha_gasto > v_hoy OR p_fecha_gasto < v_hoy - INTERVAL 90 DAY THEN
        SET v_error = 'Indica la fecha del gasto (no futura y de los últimos 90 días).';
    ELSEIF v_desc IS NOT NULL AND v_desc REGEXP '[[:cntrl:]]' THEN
        SET v_error = 'La descripción tiene caracteres no permitidos.';
    ELSEIF p_reparto IS NOT NULL AND (NOT JSON_VALID(p_reparto) OR JSON_TYPE(p_reparto) <> 'ARRAY') THEN
        SET v_error = 'El reparto debe enviarse como una lista.';
    ELSEIF p_fotos_nuevas IS NOT NULL AND (NOT JSON_VALID(p_fotos_nuevas) OR JSON_TYPE(p_fotos_nuevas) <> 'ARRAY') THEN
        SET v_error = 'Las fotos no tienen un formato válido.';
    ELSEIF p_fotos_conservar IS NOT NULL AND (NOT JSON_VALID(p_fotos_conservar) OR JSON_TYPE(p_fotos_conservar) <> 'ARRAY') THEN
        SET v_error = 'Las fotos a conservar deben enviarse como una lista.';
    END IF;
    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Gasto a corregir (solo uno observado del propio técnico) ───────────────────────────
    IF v_es_nuevo = 0 THEN
        SELECT id_gasto, estado, id_usuario, id_os INTO v_g_id, v_g_estado, v_g_usuario, v_id_os
        FROM gasto_viatico WHERE id_gasto = p_id_gasto AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
        IF v_g_id IS NULL OR v_g_usuario <> p_id_usuario THEN
            SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_g_estado <> 'observado' THEN
            SELECT 1 AS IdTipoMensaje, 'Solo se puede corregir un gasto observado por el Jefe de Operaciones.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF IFNULL(p_id_os, 0) > 0 AND p_id_os <> v_id_os THEN
            SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a ese servicio.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SET v_id_os = p_id_os;
    END IF;
    IF IFNULL(v_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el servicio del gasto.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Entradas a tablas temporales ──────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
    CREATE TEMPORARY TABLE tmp_rg_rep (n INT NOT NULL, id_linea BIGINT NULL, monto DECIMAL(14,2) NULL, PRIMARY KEY (n));
    CREATE TEMPORARY TABLE tmp_rg_fn (n INT NOT NULL, ruta VARCHAR(500) NULL, PRIMARY KEY (n));
    CREATE TEMPORARY TABLE tmp_rg_fc (orden INT NOT NULL, PRIMARY KEY (orden));
    CREATE TEMPORARY TABLE tmp_rg_adv (n INT NOT NULL AUTO_INCREMENT, advertencia VARCHAR(300) NOT NULL, PRIMARY KEY (n))
        DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    IF v_origen = 'viatico' AND p_reparto IS NOT NULL THEN
        INSERT INTO tmp_rg_rep (n, id_linea, monto)
        SELECT j.n, j.id_linea, j.monto
        FROM JSON_TABLE(p_reparto, '$[*]' COLUMNS (
                n FOR ORDINALITY,
                id_linea BIGINT        PATH '$.idViaticoLinea' NULL ON EMPTY NULL ON ERROR,
                monto    DECIMAL(14,2) PATH '$.monto'          NULL ON EMPTY NULL ON ERROR)) j;
    END IF;
    IF p_fotos_nuevas IS NOT NULL THEN
        INSERT INTO tmp_rg_fn (n, ruta)
        SELECT j.n, NULLIF(TRIM(j.ruta), '')
        FROM JSON_TABLE(p_fotos_nuevas, '$[*]' COLUMNS (n FOR ORDINALITY, ruta VARCHAR(500) PATH '$' NULL ON EMPTY NULL ON ERROR)) j;
    END IF;
    IF v_es_nuevo = 0 AND p_fotos_conservar IS NOT NULL THEN
        INSERT IGNORE INTO tmp_rg_fc (orden)
        SELECT j.orden FROM JSON_TABLE(p_fotos_conservar, '$[*]' COLUMNS (orden INT PATH '$' NULL ON EMPTY NULL ON ERROR)) j
        WHERE j.orden IS NOT NULL;
    END IF;
    SELECT COUNT(*) INTO v_n_rep FROM tmp_rg_rep;
    SELECT IFNULL(SUM(monto), 0) INTO v_suma FROM tmp_rg_rep;
    SELECT COUNT(*) INTO v_n_nuevas FROM tmp_rg_fn;
    SELECT COUNT(*) INTO v_n_cons FROM tmp_rg_fc;
    IF v_es_nuevo = 0 THEN
        SELECT COUNT(*) INTO v_n_cons_ok FROM gasto_viatico_foto f
        WHERE f.id_gasto = v_g_id AND f.eliminado_en IS NULL AND f.orden IN (SELECT orden FROM tmp_rg_fc);
    END IF;

    -- ── Fotos y motivo ────────────────────────────────────────────────────────────────────
    IF EXISTS (SELECT 1 FROM tmp_rg_fn WHERE ruta IS NULL OR ruta LIKE '%..%') THEN
        SET v_error = 'Una de las fotos no es válida.';
    ELSEIF v_n_cons_ok <> v_n_cons THEN
        SET v_error = 'Una de las fotos a conservar no existe en el gasto.';
    ELSEIF v_n_nuevas + v_n_cons > 5 THEN
        SET v_error = 'Un gasto admite hasta 5 fotos.';
    ELSEIF v_n_nuevas + v_n_cons = 0 AND (v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3) THEN
        SET v_error = 'Sin foto del comprobante, indica el motivo (mínimo 3 caracteres).';
    ELSEIF v_motivo IS NOT NULL AND v_motivo REGEXP '[[:cntrl:]]' THEN
        SET v_error = 'El motivo tiene caracteres no permitidos.';
    END IF;

    -- ── Según el origen ───────────────────────────────────────────────────────────────────
    IF v_error IS NULL AND v_origen = 'reembolso' THEN
        SELECT MAX(Num1), MAX(String3), MAX(String1) INTO v_id_conc, v_conc_cod, v_conc_nom
        FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND Num1 = p_id_concepto AND eliminado_en IS NULL;
        IF v_id_conc IS NULL THEN
            SET v_error = 'Elige un concepto del catálogo.';
        ELSEIF v_conc_cod = 'OTRO' AND (v_texto IS NULL OR CHAR_LENGTH(v_texto) < 2 OR v_texto REGEXP '[[:cntrl:]]') THEN
            SET v_error = 'Escribe el concepto del gasto (2 a 100 caracteres).';
        ELSEIF v_n_rep > 0 THEN
            SET v_error = 'Un reembolso no lleva reparto entre viáticos.';
        END IF;
        IF IFNULL(v_conc_cod, '') <> 'OTRO' THEN SET v_texto = NULL; END IF;
    ELSEIF v_error IS NULL THEN
        SET v_texto = NULL;
        IF v_n_rep = 0 THEN
            SET v_error = 'Indica de qué viáticos sale el gasto.';
        ELSEIF v_n_rep > 12 THEN
            SET v_error = 'El reparto admite hasta 12 líneas.';
        ELSEIF EXISTS (SELECT 1 FROM tmp_rg_rep WHERE id_linea IS NULL OR id_linea <= 0 OR monto IS NULL OR monto <= 0) THEN
            SET v_error = 'Cada línea del reparto debe tener el viático y un monto mayor a 0.';
        ELSEIF EXISTS (SELECT 1 FROM tmp_rg_rep GROUP BY id_linea HAVING COUNT(*) > 1) THEN
            SET v_error = 'Un viático aparece dos veces en el reparto.';
        ELSEIF v_suma <> p_monto THEN
            SET v_error = CONCAT('La suma del reparto (S/ ', FORMAT(v_suma, 2), ') debe ser igual al monto del gasto (S/ ', FORMAT(p_monto, 2), ').');
        END IF;
    END IF;
    IF v_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- ── OS, programación y técnico ────────────────────────────────────────────────────────
    SELECT numero, estado, id_tecnico_principal INTO v_numero, v_estado_os, v_principal
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;
    SELECT MAX(id_programacion) INTO v_prog FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    IF v_prog IS NOT NULL THEN
        SELECT codigo, estado INTO v_codigo, v_estado_pg FROM programacion WHERE id_programacion = v_prog FOR UPDATE;
    END IF;

    IF v_numero IS NULL OR v_estado_os = 'anulada' THEN
        SET v_error = 'El servicio no existe o fue anulado.';
    ELSEIF v_prog IS NULL OR v_estado_pg <> 'confirmada' THEN
        SET v_error = 'El servicio no tiene una programación confirmada: aún no admite gastos.';
    ELSEIF EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL) THEN
        SET v_error = 'La rendición de este servicio ya se cerró: no admite más gastos.';
    ELSEIF NOT (IFNULL(v_principal, 0) = p_id_usuario
                OR EXISTS (SELECT 1 FROM programacion_tecnico pt WHERE pt.id_programacion = v_prog AND pt.id_usuario = p_id_usuario AND pt.eliminado_en IS NULL)
                OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = v_id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL)) THEN
        SET v_error = 'No estás asignado a este servicio.';
    END IF;

    -- Reparto: líneas del adelanto del MISMO técnico y de ESTA OS
    IF v_error IS NULL AND v_origen = 'viatico' AND EXISTS (
        SELECT 1 FROM tmp_rg_rep t
        WHERE NOT EXISTS (SELECT 1 FROM gasto_viatico l
                          WHERE l.id_gasto = t.id_linea AND l.tipo = 'viatico_asignado' AND l.eliminado_en IS NULL AND l.id_usuario = p_id_usuario
                            AND (l.id_programacion = v_prog OR (l.id_programacion IS NULL AND l.id_os = v_id_os)))) THEN
        SET v_error = 'Una línea del reparto no es un viático tuyo de este servicio.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_origen = 'viatico' THEN
        -- Concepto del gasto: el de la línea con más monto
        SELECT l.id_concepto INTO v_id_conc
        FROM tmp_rg_rep t JOIN gasto_viatico l ON l.id_gasto = t.id_linea
        ORDER BY t.monto DESC, t.id_linea LIMIT 1;
        SELECT MAX(String1) INTO v_conc_nom FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND Num1 = v_id_conc;

        -- Advertencias: la línea se pasa de lo que le queda (otros gastos no rechazados ya repartidos en ella + los antiguos sin reparto del mismo concepto)
        INSERT INTO tmp_rg_adv (advertencia)
        SELECT LEFT(CONCAT(IFNULL(c.String1, 'Viático'), ': el reparto (S/ ', FORMAT(t.monto, 2), ') supera lo que queda (S/ ',
                           FORMAT(GREATEST(l.monto - IFNULL(r.usado, 0) - IFNULL(a.usado, 0), 0), 2),
                           '). Lo aprobado de más se paga al cerrar la rendición.'), 300)
        FROM tmp_rg_rep t
        JOIN gasto_viatico l ON l.id_gasto = t.id_linea
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = l.id_concepto
        LEFT JOIN (SELECT rp.id_viatico_linea, SUM(rp.monto) AS usado
                   FROM gasto_viatico_reparto rp
                   JOIN gasto_viatico g ON g.id_gasto = rp.id_gasto AND g.eliminado_en IS NULL AND g.estado <> 'rechazado'
                   WHERE rp.eliminado_en IS NULL AND rp.id_gasto <> IFNULL(v_g_id, 0)
                   GROUP BY rp.id_viatico_linea) r ON r.id_viatico_linea = t.id_linea
        LEFT JOIN (SELECT g.id_usuario, g.id_concepto, SUM(g.monto) AS usado
                   FROM gasto_viatico g
                   WHERE g.tipo = 'gasto_solicitado' AND g.origen IS NULL AND g.estado <> 'rechazado' AND g.eliminado_en IS NULL
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
                   GROUP BY g.id_usuario, g.id_concepto) a ON a.id_usuario = l.id_usuario AND a.id_concepto = l.id_concepto
        WHERE t.monto > l.monto - IFNULL(r.usado, 0) - IFNULL(a.usado, 0)
        ORDER BY t.n;
    END IF;

    SET v_motivo = IF(v_n_nuevas + v_n_cons > 0, NULL, v_motivo);

    -- ── Guardar ───────────────────────────────────────────────────────────────────────────
    IF v_es_nuevo = 1 THEN
        INSERT INTO gasto_viatico (id_os, id_programacion, id_usuario, id_concepto, id_moneda, monto, descripcion, tipo, estado,
                                   fecha_solicitud, fecha_gasto, origen, id_cliente_app, concepto_texto, motivo_sin_foto, monto_ia, coincide_ia, creado_por)
        VALUES (v_id_os, v_prog, p_id_usuario, v_id_conc, 1, p_monto, v_desc, 'gasto_solicitado', 'pendiente',
                v_hoy, p_fecha_gasto, v_origen, NULLIF(TRIM(IFNULL(p_id_cliente_app, '')), ''), v_texto, v_motivo,
                p_monto_ia, IF(p_coincide_ia IS NULL, NULL, IF(p_coincide_ia = 1, 1, 0)), p_id_usuario);
        SET v_g_id = LAST_INSERT_ID();
    ELSE
        UPDATE gasto_viatico
        SET id_programacion = IFNULL(id_programacion, v_prog), id_concepto = v_id_conc, monto = p_monto, descripcion = v_desc,
            estado = 'pendiente', fecha_gasto = p_fecha_gasto, origen = v_origen, concepto_texto = v_texto, motivo_sin_foto = v_motivo,
            monto_ia    = IF(v_n_nuevas > 0, p_monto_ia, monto_ia),
            coincide_ia = IF(v_n_nuevas > 0, IF(p_coincide_ia IS NULL, NULL, IF(p_coincide_ia = 1, 1, 0)), coincide_ia),
            modificado_por = p_id_usuario
        WHERE id_gasto = v_g_id;

        UPDATE gasto_viatico_reparto SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_gasto = v_g_id AND eliminado_en IS NULL;
        UPDATE gasto_viatico_foto SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_gasto = v_g_id AND eliminado_en IS NULL AND orden NOT IN (SELECT orden FROM tmp_rg_fc);
    END IF;

    INSERT INTO gasto_viatico_reparto (id_gasto, id_viatico_linea, monto, creado_por)
    SELECT v_g_id, t.id_linea, t.monto, p_id_usuario FROM tmp_rg_rep t WHERE v_origen = 'viatico' ORDER BY t.n;

    SELECT IFNULL(MAX(orden), 0) INTO v_max_orden FROM gasto_viatico_foto WHERE id_gasto = v_g_id AND eliminado_en IS NULL;
    INSERT INTO gasto_viatico_foto (id_gasto, url, orden, creado_por)
    SELECT v_g_id, f.ruta, v_max_orden + f.n, p_id_usuario FROM tmp_rg_fn f ORDER BY f.n;

    -- Compatibilidad: url_comprobante = la primera foto (la intranet de HU-45 y los SPs anteriores la leen)
    SELECT url INTO v_url1 FROM gasto_viatico_foto WHERE id_gasto = v_g_id AND eliminado_en IS NULL ORDER BY orden LIMIT 1;
    UPDATE gasto_viatico SET url_comprobante = v_url1 WHERE id_gasto = v_g_id;

    -- Aviso a quienes revisan gastos (Jefe de Operaciones)
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, LEFT(CONCAT(IF(v_es_nuevo = 1, 'Gasto por revisar: ', 'Gasto corregido: '), v_numero), 150),
           LEFT(CONCAT(v_codigo, ' · ', v_numero, ' · ', IFNULL(v_texto, IFNULL(v_conc_nom, 'Gasto')), ' S/ ', FORMAT(p_monto, 2),
                       IF(v_origen = 'reembolso', ' (reembolso)', ''), IF(v_n_nuevas + v_n_cons = 0, ' · sin foto', ''), '.'), 3000),
           'programacion', v_prog, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND FN_PermisoAccion(u.id_usuario, 'prog_aprobar_reprogramacion') = 1;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('programacion', v_prog, IF(v_es_nuevo = 1, 'rendir_gasto', 'corregir_gasto'), IF(v_es_nuevo = 1, NULL, 'observado'), 'pendiente',
            LEFT(CONCAT('Gasto ', CONCAT('GS-', LPAD(v_g_id, 6, '0')), IF(v_es_nuevo = 1, ' rendido', ' corregido'), ' desde la app: ',
                        IFNULL(v_texto, IFNULL(v_conc_nom, 'Gasto')), ' S/ ', FORMAT(p_monto, 2), ' (', v_origen, ').'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('idGasto', v_g_id, 'origen', v_origen, 'monto', p_monto, 'fotos', v_n_nuevas + v_n_cons, 'reparto', v_n_rep,
                        'montoIa', p_monto_ia, 'advertencias', (SELECT COUNT(*) FROM tmp_rg_adv)));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_es_nuevo = 1, 'Gasto registrado: queda pendiente de la revisión del Jefe de Operaciones.',
                              'Gasto corregido: vuelve a la revisión del Jefe de Operaciones.') AS Mensaje;
    SELECT v_g_id AS id_gasto, CONCAT('GS-', LPAD(v_g_id, 6, '0')) AS codigo, 'pendiente' AS estado, 0 AS duplicado;
    SELECT advertencia FROM tmp_rg_adv ORDER BY n;

    DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
END$$

DELIMITER ;
