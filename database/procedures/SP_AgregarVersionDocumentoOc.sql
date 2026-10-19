-- HU-25 (interno) Agrega una versión del PDF de la OC en documento_adjunto.
-- Lo llaman SP_EditarOrdenCompra y SP_ReemplazarDocumentoOrdenCompra DENTRO de su transacción y
-- ANTES de actualizar orden_compra: si la OC aún no tiene versiones (registrada antes de la HU-25),
-- primero guarda como v1 el PDF vigente de orden_compra, así no se pierde.
-- No devuelve resultados. Solo inserta (el historial de versiones es inmutable).
DROP PROCEDURE IF EXISTS SP_AgregarVersionDocumentoOc;

DELIMITER $$

CREATE PROCEDURE SP_AgregarVersionDocumentoOc(
    IN p_id_oc      BIGINT,
    IN p_id_usuario BIGINT,
    IN p_ruta       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre     VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano     BIGINT,
    IN p_hash       CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_version INT DEFAULT 0;

    SELECT IFNULL(MAX(version), 0) INTO v_version
    FROM documento_adjunto
    WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc AND eliminado_en IS NULL;

    IF v_version = 0 THEN
        INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                                       version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
        SELECT 'orden_compra', oc.id_oc, 1,
               LEFT(COALESCE(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')), 200),
               oc.url_archivo_pdf, 1, 1,
               JSON_OBJECT('motivo', 'Versión inicial', 'tamano_bytes', oc.tamano_pdf_bytes, 'hash', oc.hash_pdf),
               IFNULL(oc.creado_por, p_id_usuario), oc.fecha_registro, oc.creado_por
        FROM orden_compra oc
        WHERE oc.id_oc = p_id_oc AND oc.url_archivo_pdf IS NOT NULL;

        SET v_version = ROW_COUNT();
    END IF;

    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                                   version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
    VALUES ('orden_compra', p_id_oc, 1, LEFT(IFNULL(p_nombre, 'orden-compra.pdf'), 200), p_ruta,
            v_version + 1, 1,
            JSON_OBJECT('motivo', p_motivo, 'tamano_bytes', p_tamano, 'hash', p_hash),
            p_id_usuario, NOW(), p_id_usuario);
END$$

DELIMITER ;
