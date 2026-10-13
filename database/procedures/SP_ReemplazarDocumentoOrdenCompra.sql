-- HU-25 Reemplazar el PDF de la orden de compra con un motivo (nueva versión del documento).
-- Acción oc_documento_reemplazar, OC del área del usuario y no anulada.
-- Motivo obligatorio (5 a 300 caracteres). No se acepta un archivo idéntico (mismo hash) a la versión actual.
-- La versión anterior se conserva en documento_adjunto y queda en la auditoría (reemplazar_pdf_oc).
-- p_solo_validar = 1 valida sin guardar (antes de escribir el PDF en disco).
-- Resultados: 1 mensaje, 2 nueva versión.
DROP PROCEDURE IF EXISTS SP_ReemplazarDocumentoOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ReemplazarDocumentoOrdenCompra(
    IN p_id_usuario   BIGINT,
    IN p_id_oc        BIGINT,
    IN p_motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_pdf     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf   VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf   BIGINT,
    IN p_hash_pdf     CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar TINYINT
)
proc: BEGIN
    DECLARE v_existe  INT DEFAULT 0;
    DECLARE v_estado  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hash    CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero  VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version INT DEFAULT 0;
    DECLARE v_id_doc  BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'oc_documento_reemplazar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reemplazar el documento de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(numero_oc) INTO v_existe, v_estado, v_numero FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada: no se puede reemplazar su documento.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique el motivo del reemplazo (mínimo 5 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT hash_pdf INTO v_hash FROM orden_compra WHERE id_oc = p_id_oc;
    IF p_hash_pdf IS NOT NULL AND v_hash IS NOT NULL AND p_hash_pdf = v_hash THEN
        SELECT 1 AS IdTipoMensaje, 'El archivo es idéntico a la versión actual del documento.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Adjunte el nuevo PDF de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_AgregarVersionDocumentoOc(p_id_oc, p_id_usuario, p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf, v_motivo);

    SELECT MAX(id_documento), MAX(version) INTO v_id_doc, v_version
    FROM documento_adjunto
    WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc AND eliminado_en IS NULL;

    UPDATE orden_compra SET
        url_archivo_pdf    = p_ruta_pdf,
        nombre_archivo_pdf = p_nombre_pdf,
        tamano_pdf_bytes   = p_tamano_pdf,
        hash_pdf           = p_hash_pdf,
        modificado_por     = p_id_usuario
    WHERE id_oc = p_id_oc;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'reemplazar_pdf_oc', v_estado, v_estado,
            CONCAT('PDF reemplazado por la versión ', v_version, '. Motivo: ', v_motivo), p_id_usuario, NOW(),
            JSON_OBJECT('id_documento', v_id_doc, 'version', v_version, 'nombre', p_nombre_pdf,
                        'tamano_bytes', p_tamano_pdf, 'hash', p_hash_pdf));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Documento actualizado a la versión ', v_version, '.') AS Mensaje;
    SELECT v_id_doc AS id_documento, v_version AS version, p_nombre_pdf AS nombre_archivo,
           p_tamano_pdf AS tamano_bytes, v_motivo AS motivo,
           CONCAT('/api/crm/ordenes-compra/', p_id_oc, '/documentos/', v_id_doc) AS url;
END$$

DELIMITER ;
