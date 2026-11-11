-- ============================================================
-- SP_GuardarConstanciaMovil  (App Mobile HU-17 — firma del cliente, formato físico y "Generar constancia")
-- Una fila por OS (os_constancia). El estado de los informes lo arma SP_ArmarFirmasOsMovil (una sola vez). Se necesita al menos un informe completo.
--   p_accion = firma   : firma del cliente por dispositivo (p_trazos ≤ 30 000 caracteres + p_hash SHA-256) y p_nombre (quien firmó, 3 a 150).
--              fisico  : foto del formato en papel (p_ruta_foto, guardada por el caso de uso) y p_nombre (quien firmó). Es OPCIONAL: se suma a la firma del cliente.
--              generar : "Generar constancia": exige la firma del cliente; deja la constancia generada (una sola vez).
--   Con el servicio ya cerrado no se cambia nada. Orden de bloqueos: orden_servicio → constancia. Auditoría: auditoria_evento (entidad os_constancia).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) generada, listo (todos los informes completos y los responsables resueltos),
--   cierre_listo (listo + firmada + generada y sin cerrar: el caso de uso genera el PDF y registra el cierre), ruta_foto_anterior.
-- Requiere la migración 105 y la de la HU-15.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarConstanciaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_trazos     MEDIUMTEXT   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_hash       VARCHAR(64)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_foto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_lock   BIGINT DEFAULT NULL;
    DECLARE v_firmada DATETIME DEFAULT NULL; DECLARE v_gen DATETIME DEFAULT NULL; DECLARE v_cierre DATETIME DEFAULT NULL;
    DECLARE v_foto_ant VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora  DATETIME DEFAULT UTC_TIMESTAMP();
    DECLARE v_texto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cierre_listo TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_accion = LOWER(TRIM(IFNULL(p_accion, '')));
    SET p_nombre = NULLIF(TRIM(IFNULL(p_nombre, '')), '');
    IF p_accion NOT IN ('firma', 'fisico', 'generar') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción de la constancia no es válida.' AS Mensaje; LEAVE proc;
    ELSEIF p_accion = 'firma' AND (p_trazos IS NULL OR CHAR_LENGTH(p_trazos) < 20 OR CHAR_LENGTH(p_trazos) > 30000 OR NOT JSON_VALID(p_trazos)
                                   OR IFNULL(p_hash, '') NOT REGEXP '^[0-9a-f]{64}$' OR p_nombre IS NULL OR CHAR_LENGTH(p_nombre) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'El cliente debe firmar e indicar su nombre.' AS Mensaje; LEAVE proc;
    ELSEIF p_accion = 'fisico' AND (NULLIF(TRIM(IFNULL(p_ruta_foto, '')), '') IS NULL OR p_nombre IS NULL OR CHAR_LENGTH(p_nombre) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto del formato físico e indica el nombre de quien firmó.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os FOR UPDATE;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    IF v_comp = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Aún no hay informes técnicos generados en este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT IGNORE INTO os_constancia (id_os, creado_por) VALUES (p_id_os, p_id_usuario);
    SELECT k.firmado_en, k.generada_en, k.cerrada_en, k.ruta_foto INTO v_firmada, v_gen, v_cierre, v_foto_ant FROM os_constancia k WHERE k.id_os = p_id_os FOR UPDATE;
    IF v_cierre IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya está cerrado: la constancia no se puede cambiar.' AS Mensaje; LEAVE proc;
    END IF;

    IF p_accion = 'firma' THEN
        UPDATE os_constancia SET modo = 'dispositivo', firmante_nombre = p_nombre, trazos = p_trazos, hash_firma = p_hash, firmado_en = v_ahora, firmado_por = p_id_usuario,
               modificado_por = p_id_usuario WHERE id_os = p_id_os;
        SET v_firmada = v_ahora, v_texto = CONCAT('Firma del cliente (', p_nombre, ') por dispositivo.');
    ELSEIF p_accion = 'fisico' THEN
        UPDATE os_constancia SET ruta_foto = p_ruta_foto, firmante_nombre = p_nombre, firmado_en = IFNULL(firmado_en, v_ahora), firmado_por = IFNULL(firmado_por, p_id_usuario),
               modo = IF(trazos IS NULL, 'fisico', modo), modificado_por = p_id_usuario WHERE id_os = p_id_os;
        SET v_firmada = IFNULL(v_firmada, v_ahora), v_texto = CONCAT('Formato físico de la constancia firmado por ', p_nombre, '.');
    ELSE
        IF v_firmada IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Primero el cliente debe firmar la constancia.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_gen IS NULL THEN
            UPDATE os_constancia SET generada_en = v_ahora, generada_por = p_id_usuario, modificado_por = p_id_usuario WHERE id_os = p_id_os;
            SET v_gen = v_ahora;
        END IF;
        SET v_texto = 'Constancia de servicio generada.';
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_constancia', p_id_os, CONCAT('constancia_', p_accion), NULL, p_accion, LEFT(CONCAT(v_texto, ' ', v_num), 900), p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'hash', p_hash, 'firmante', p_nombre));

    SET v_cierre_listo = IF(v_listo = 1 AND v_firmada IS NOT NULL AND v_gen IS NOT NULL, 1, 0);
    COMMIT;

    SELECT 2 AS IdTipoMensaje, v_texto AS Mensaje;
    SELECT IF(v_gen IS NULL, 0, 1) AS generada, v_listo AS listo, v_cierre_listo AS cierre_listo, IF(p_accion = 'fisico', v_foto_ant, NULL) AS ruta_foto_anterior;
END$$

DELIMITER ;
