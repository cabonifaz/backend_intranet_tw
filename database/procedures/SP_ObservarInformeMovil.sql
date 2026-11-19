-- ============================================================
-- SP_ObservarInformeMovil  (App Mobile HU-33 — "Observar informe": pedir la corrección al técnico)
-- El Jefe de Área observa un informe sin revisar: indica el motivo, las secciones afectadas, qué debe corregir y el plazo. El técnico recibe la solicitud (notificación + push) y el
-- informe queda 'observado' (pestaña "En corrección").
-- Acceso: rt_revisar + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil → SP_ArmarBaseInformes).
-- Validaciones (catálogo fijo: SP_ArmarCatalogoRevisionInformeMovil):
--   p_motivo ......... evidencia_insuficiente | datos_incorrectos | ensayos_inconsistentes | firma_faltante | otro
--   p_secciones ...... códigos separados por coma, al menos una y sin repetir: registro_fotografico | cabecera | ensayos | firmas
--   p_instruccion .... "Qué debe corregir": de 10 a 1000 caracteres
--   p_plazo_horas .... 4 | 24 | 48 | 72 (desde ahora, hora de Lima)
--   El informe no puede estar revisado ni tener ya una corrección pendiente (informe bloqueado con FOR UPDATE: dos jefes a la vez, gana el primero).
-- Efectos (una transacción): informe_correccion pendiente · informe_tecnico.estado = 'observado' · evento 'observado' en el historial (auditoria_evento, categoría revisión, origen móvil)
--   · notificación al técnico "Informe observado: N°" (prioridad alta; el push sale solo).
-- Resultados: 1 mensaje · 2 (id_correccion, plazo_en ISO sin zona, notificados). Requiere la migración 121.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObservarInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObservarInformeMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_informe  BIGINT,
    IN p_motivo      VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_secciones   VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_instruccion VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_plazo_horas INT
)
proc: BEGIN
    DECLARE v_tiene      TINYINT DEFAULT 0;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_en_tx      TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_tecnico BIGINT DEFAULT NULL;
    DECLARE v_numero_inf VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_equipo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_nom VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_instr      VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_secc       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_secc_nom   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_resto      VARCHAR(260) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tok        VARCHAR(260) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_plazo_txt  VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_err        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_plazo      DATETIME;
    DECLARE v_id_corr    BIGINT DEFAULT NULL;
    DECLARE v_pend       INT DEFAULT 0;
    DECLARE v_notif      INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        IF v_en_tx = 1 THEN ROLLBACK; END IF;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_revisar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para observar informes.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Validación de la entrada contra el catálogo fijo ──────────────────────────────────────
    CALL SP_ArmarCatalogoRevisionInformeMovil();
    DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;
    CREATE TEMPORARY TABLE tmp_sec_obs (codigo VARCHAR(30) NOT NULL) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    SET v_motivo = LOWER(TRIM(IFNULL(p_motivo, '')));
    SET v_instr  = TRIM(IFNULL(p_instruccion, ''));
    SET v_secc   = LOWER(REPLACE(TRIM(IFNULL(p_secciones, '')), ' ', ''));

    IF NOT EXISTS (SELECT 1 FROM tmp_cat_rev c WHERE c.tipo = 'motivo' AND c.codigo = v_motivo) THEN
        SET v_err = 'Elige el motivo de la observación.';
    ELSEIF v_secc = '' OR CHAR_LENGTH(v_secc) > 200 THEN
        SET v_err = 'Elige al menos una sección afectada.';
    ELSEIF CHAR_LENGTH(v_instr) < 10 OR CHAR_LENGTH(v_instr) > 1000 THEN
        SET v_err = 'Indica qué debe corregir el técnico (de 10 a 1000 caracteres).';
    ELSEIF NOT EXISTS (SELECT 1 FROM tmp_cat_rev c WHERE c.tipo = 'plazo' AND c.horas = IFNULL(p_plazo_horas, 0)) THEN
        SET v_err = 'Elige un plazo válido (4, 24, 48 o 72 horas).';
    END IF;

    IF v_err IS NULL THEN
        SET v_resto = CONCAT(v_secc, ',');
        WHILE v_err IS NULL AND CHAR_LENGTH(v_resto) > 0 DO
            SET v_tok   = SUBSTRING_INDEX(v_resto, ',', 1);
            SET v_resto = SUBSTRING(v_resto, CHAR_LENGTH(v_tok) + 2);
            IF NOT EXISTS (SELECT 1 FROM tmp_cat_rev c WHERE c.tipo = 'seccion' AND c.codigo = v_tok) THEN
                SET v_err = 'Alguna de las secciones indicadas no es válida.';
            ELSEIF EXISTS (SELECT 1 FROM tmp_sec_obs s WHERE s.codigo = v_tok) THEN
                SET v_err = 'Hay secciones repetidas.';
            ELSE
                INSERT INTO tmp_sec_obs (codigo) VALUES (v_tok);
            END IF;
        END WHILE;
    END IF;

    IF v_err IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;
        SELECT 1 AS IdTipoMensaje, v_err AS Mensaje;
        LEAVE proc;
    END IF;

    -- Textos canónicos (en el orden del catálogo) para guardar y para el aviso al técnico
    SELECT GROUP_CONCAT(c.codigo ORDER BY c.orden SEPARATOR ','), GROUP_CONCAT(c.nombre ORDER BY c.orden SEPARATOR ', ')
      INTO v_secc, v_secc_nom
    FROM tmp_cat_rev c WHERE c.tipo = 'seccion' AND c.codigo IN (SELECT s.codigo FROM tmp_sec_obs s);
    SELECT c.nombre INTO v_motivo_nom FROM tmp_cat_rev c WHERE c.tipo = 'motivo' AND c.codigo = v_motivo LIMIT 1;
    SELECT c.nombre INTO v_plazo_txt  FROM tmp_cat_rev c WHERE c.tipo = 'plazo' AND c.horas = p_plazo_horas LIMIT 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
    DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;

    -- ── Alcance del jefe ─────────────────────────────────────────────────────────────────────
    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    SELECT COUNT(*), MAX(estado), MAX(id_tecnico), MAX(numero_informe), MAX(numero_os), MAX(equipo)
      INTO v_existe, v_estado, v_id_tecnico, v_numero_inf, v_numero_os, v_equipo
    FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado IN ('revisado', 'aprobado') THEN
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: no se puede observar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Transacción ──────────────────────────────────────────────────────────────────────────
    START TRANSACTION;
    SET v_en_tx = 1;

    SELECT estado INTO v_estado FROM informe_tecnico WHERE id_informe = p_id_informe AND eliminado_en IS NULL FOR UPDATE;
    IF v_estado IN ('revisado', 'aprobado') THEN
        ROLLBACK;
        SET v_en_tx = 0;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: no se puede observar.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_pend FROM informe_correccion WHERE id_informe = p_id_informe AND estado = 'pendiente' AND eliminado_en IS NULL;
    IF v_pend > 0 THEN
        ROLLBACK;
        SET v_en_tx = 0;
        SELECT 1 AS IdTipoMensaje, 'El informe ya tiene una corrección pendiente: espera a que el técnico la atienda.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_plazo = NOW() + INTERVAL p_plazo_horas HOUR;

    INSERT INTO informe_correccion (id_informe, id_jefe, motivo, secciones, instruccion, plazo_en, estado, creado_por)
    VALUES (p_id_informe, p_id_usuario, v_motivo, v_secc, v_instr, v_plazo, 'pendiente', p_id_usuario);
    SET v_id_corr = LAST_INSERT_ID();

    UPDATE informe_tecnico SET estado = 'observado', modificado_por = p_id_usuario WHERE id_informe = p_id_informe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', p_id_informe, 'observado', v_estado, 'observado',
            LEFT(CONCAT('Observó el informe (', v_motivo_nom, ') desde la app'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('categoria', 'revision', 'origen', 'movil', 'detalle', CONCAT('Secciones: ', v_secc_nom, ' · Plazo: ', v_plazo_txt), 'nota', v_instr,
                        'idCorreccion', v_id_corr));

    IF v_id_tecnico IS NOT NULL AND v_id_tecnico <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por, prioridad_origen)
        VALUES (v_id_tecnico, 5,
                LEFT(CONCAT('Informe observado: ', IFNULL(v_numero_inf, IFNULL(v_numero_os, ''))), 150),
                LEFT(CONCAT('Tu informe de ', IFNULL(v_equipo, 'el equipo'), IF(v_numero_os IS NULL, '', CONCAT(' (', v_numero_os, ')')), ' fue observado. Motivo: ', v_motivo_nom,
                            '. Secciones: ', v_secc_nom, '. Qué corregir: ', v_instr, '. Plazo: ', DATE_FORMAT(v_plazo, '%d/%m/%Y %H:%i'), ' (', v_plazo_txt, ').'), 3000),
                'informe_tecnico', p_id_informe, NOW(), p_id_usuario, 'alta');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;
    SET v_en_tx = 0;

    SELECT 2 AS IdTipoMensaje, 'Informe observado. El técnico recibió la solicitud de corrección.' AS Mensaje;
    SELECT v_id_corr AS id_correccion, DATE_FORMAT(v_plazo, '%Y-%m-%dT%H:%i:%s') AS plazo_en, v_notif AS notificados;
END$$

DELIMITER ;
