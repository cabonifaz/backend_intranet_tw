-- ============================================================
-- SP_GuardarFirmaResponsableMovil  (App Mobile HU-17 — "Confirmar firma" / "Cliente ausente" / "Formato físico" / "Editar firma")
-- Registra la firma de UN responsable para TODOS sus informes completos de la OS (una sola firma por responsable y OS; "Editar firma" la reemplaza y la anterior
-- queda en auditoria_evento). El estado (responsables, informes completos, plazo) lo arma SP_ArmarFirmasOsMovil, una sola vez.
--   p_modo = dispositivo : p_trazos (JSON de trazos normalizados, ≤ 30 000 caracteres) y p_hash (SHA-256 en hexadecimal). La regla "firmas iguales entre responsables
--                          distintos" la aplica el caso de uso .NET (ComparadorFirmas) ANTES de llamar a este SP.
--            fisico      : p_ruta_foto (foto del formato en papel, guardada por el caso de uso) y p_nombre (quien firmó, 3 a 150 caracteres).
--            ausente     : "Cliente ausente": deja constancia de la aceptación tácita (quién, cuándo y p_motivo de 5 a 300 caracteres); la firma sigue PENDIENTE y el
--                          plazo de aceptación tácita corre. No se puede usar si el responsable ya firmó.
--   Orden de bloqueos: orden_servicio → firma del responsable. Auditoría: auditoria_evento (entidad os_firma_responsable).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) firma, responsables, resueltos, firmados (informes), listo, cierre_listo
--   (todo resuelto + constancia firmada y generada y el servicio aún sin cerrar: el caso de uso genera el PDF y registra el cierre), ruta_foto_anterior.
-- Requiere la migración 105 y la de la HU-15.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarFirmaResponsableMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarFirmaResponsableMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(32)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modo       VARCHAR(12)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_trazos     MEDIUMTEXT    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_hash       VARCHAR(64)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre     VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_foto  VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo     VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_lock   BIGINT DEFAULT NULL;
    DECLARE v_nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cargo  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tel    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_firmado TINYINT DEFAULT 0;
    DECLARE v_ninf   INT DEFAULT 0;
    DECLARE v_modo_ant  VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hash_ant  CHAR(64) DEFAULT NULL;
    DECLARE v_foto_ant  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_firma_ant DATETIME DEFAULT NULL;
    DECLARE v_ahora  DATETIME DEFAULT UTC_TIMESTAMP();
    DECLARE v_c_firma DATETIME DEFAULT NULL; DECLARE v_c_gen DATETIME DEFAULT NULL; DECLARE v_c_cierre DATETIME DEFAULT NULL;
    DECLARE v_cierre TINYINT DEFAULT 0;
    DECLARE v_texto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_modo = LOWER(TRIM(IFNULL(p_modo, '')));
    SET p_nombre = NULLIF(TRIM(IFNULL(p_nombre, '')), '');
    SET p_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF IFNULL(p_clave, '') NOT REGEXP '^[0-9a-f]{32}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El responsable no es válido.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo NOT IN ('dispositivo', 'fisico', 'ausente') THEN
        SELECT 1 AS IdTipoMensaje, 'La forma de firma no es válida.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'dispositivo' AND (p_trazos IS NULL OR CHAR_LENGTH(p_trazos) < 20 OR CHAR_LENGTH(p_trazos) > 30000 OR NOT JSON_VALID(p_trazos)
                                      OR IFNULL(p_hash, '') NOT REGEXP '^[0-9a-f]{64}$') THEN
        SELECT 1 AS IdTipoMensaje, 'Dibuja la firma del responsable.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'fisico' AND (NULLIF(TRIM(IFNULL(p_ruta_foto, '')), '') IS NULL OR p_nombre IS NULL OR CHAR_LENGTH(p_nombre) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto del formato físico e indica el nombre de quien firmó.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'ausente' AND (p_motivo IS NULL OR CHAR_LENGTH(p_motivo) < 5) THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo por el que el responsable está ausente (mínimo 5 caracteres).' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os FOR UPDATE;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    SELECT r.nombre, r.cargo, r.telefono, r.firmado, r.n_informes INTO v_nombre, v_cargo, v_tel, v_firmado, v_ninf FROM tmp_fm_resp r WHERE r.clave = p_clave;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    IF v_nombre IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese responsable no tiene informes generados en este servicio.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'ausente' AND v_firmado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_nombre, ' ya firmó sus informes.') AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM os_constancia c WHERE c.id_os = p_id_os AND c.cerrada_en IS NOT NULL) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya está cerrado: no se pueden cambiar las firmas.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.modo, f.hash_firma, f.ruta_foto, f.firmado_en INTO v_modo_ant, v_hash_ant, v_foto_ant, v_firma_ant
    FROM   os_firma_responsable f WHERE f.id_os = p_id_os AND f.clave = p_clave FOR UPDATE;

    INSERT INTO os_firma_responsable (id_os, clave, nombre, cargo, telefono, modo, trazos, hash_firma, nombre_firmante, ruta_foto, motivo, firmado_en, firmado_por, creado_por)
    VALUES (p_id_os, p_clave, v_nombre, v_cargo, v_tel, p_modo, IF(p_modo = 'dispositivo', p_trazos, NULL), IF(p_modo = 'dispositivo', p_hash, NULL),
            IF(p_modo = 'fisico', p_nombre, NULL), IF(p_modo = 'fisico', p_ruta_foto, NULL), IF(p_modo = 'ausente', p_motivo, NULL), v_ahora, p_id_usuario, p_id_usuario)
    ON DUPLICATE KEY UPDATE modo = VALUES(modo), trazos = VALUES(trazos), hash_firma = VALUES(hash_firma), nombre_firmante = VALUES(nombre_firmante),
                            ruta_foto = VALUES(ruta_foto), motivo = VALUES(motivo), firmado_en = VALUES(firmado_en), firmado_por = VALUES(firmado_por),
                            modificado_por = p_id_usuario, version = version + 1;

    SET v_texto = CASE p_modo WHEN 'dispositivo' THEN CONCAT('Firma por dispositivo de ', v_nombre, IF(v_modo_ant IS NULL, '.', ' (reemplaza la firma anterior).'))
                              WHEN 'fisico'      THEN CONCAT('Formato físico firmado por ', p_nombre, ' (responsable ', v_nombre, ').')
                              ELSE CONCAT('Cliente ausente: ', v_nombre, ' · aceptación tácita. Motivo: ', p_motivo) END;
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_firma_responsable', p_id_os, IF(v_modo_ant IS NULL, 'firmar_informes', 'editar_firma'), v_modo_ant, p_modo, LEFT(CONCAT(v_texto, ' ', v_num), 900), p_id_usuario, NOW(),
            JSON_OBJECT('clave', p_clave, 'responsable', v_nombre, 'modo', p_modo, 'hash_nuevo', p_hash, 'hash_anterior', v_hash_ant, 'firmado_anterior_en', v_firma_ant));

    -- Estado después de firmar (una sola regla: SP_ArmarFirmasOsMovil)
    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    SELECT c.firmado_en, c.generada_en, c.cerrada_en INTO v_c_firma, v_c_gen, v_c_cierre FROM os_constancia c WHERE c.id_os = p_id_os;
    SET v_cierre = IF(v_listo = 1 AND v_c_firma IS NOT NULL AND v_c_gen IS NOT NULL AND v_c_cierre IS NULL, 1, 0);
    COMMIT;

    SELECT 2 AS IdTipoMensaje, CASE p_modo WHEN 'ausente' THEN CONCAT('Cliente ausente registrado para ', v_nombre, ': la firma sigue pendiente.')
                                           ELSE CONCAT('Firma de ', v_nombre, ' registrada para ', v_ninf, IF(v_ninf = 1, ' informe.', ' informes.')) END AS Mensaje;
    SELECT IF(p_modo = 'ausente', 'ausente', 'firmado') AS firma, v_resp AS responsables, v_ok AS resueltos, v_firm AS firmados, v_listo AS listo, v_cierre AS cierre_listo,
           v_foto_ant AS ruta_foto_anterior;
END$$

DELIMITER ;
