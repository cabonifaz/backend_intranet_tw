-- HU-25 Modal "Documento de Orden de Compra": documento actual e historial de versiones.
-- Acción oc_bandeja y OC del área del usuario.
-- Si una OC antigua aún no tiene versiones, se muestra su PDF vigente como v1.
-- Resultados: 1 mensaje, 2 OC (y si el usuario puede reemplazar), 3 versiones (la actual primero).
DROP PROCEDURE IF EXISTS SP_ObtenerDocumentosOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDocumentosOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_estado VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_max    INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd) INTO v_existe, v_estado FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT IFNULL(MAX(version), 0) INTO v_max
    FROM documento_adjunto
    WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc AND eliminado_en IS NULL;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OC
    SELECT oc.id_oc, oc.numero_oc, oc.estado,
           (FN_PermisoAccion(p_id_usuario, 'oc_documento_reemplazar') = 1 AND oc.estado <> 'anulada') AS puede_reemplazar,
           GREATEST(v_max, IF(oc.url_archivo_pdf IS NULL, 0, 1)) AS total_versiones
    FROM orden_compra oc WHERE oc.id_oc = p_id_oc;

    -- 3. Versiones
    SELECT d.id_documento, d.version, d.nombre_archivo,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED)  AS tamano_bytes,
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.motivo')), 'null')                        AS motivo,
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.hash')), 'null')                          AS hash,
           d.fecha_carga, d.subido_por AS id_subido_por, CONCAT(u.nombre, ' ', u.apellido) AS subido_por,
           (d.version = v_max)                                                        AS es_actual,
           CONCAT('/api/crm/ordenes-compra/', p_id_oc, '/documentos/', d.id_documento) AS url
    FROM documento_adjunto d
    LEFT JOIN usuario u ON u.id_usuario = d.subido_por
    WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = p_id_oc AND d.eliminado_en IS NULL
    UNION ALL
    SELECT NULL, 1, COALESCE(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')),
           oc.tamano_pdf_bytes, 'Versión inicial', oc.hash_pdf,
           oc.fecha_registro, oc.creado_por, CONCAT(u.nombre, ' ', u.apellido),
           1, CONCAT('/api/crm/ordenes-compra/', oc.id_oc, '/pdf')
    FROM orden_compra oc
    LEFT JOIN usuario u ON u.id_usuario = oc.creado_por
    WHERE oc.id_oc = p_id_oc AND oc.url_archivo_pdf IS NOT NULL AND v_max = 0
    ORDER BY version DESC;
END$$

DELIMITER ;
