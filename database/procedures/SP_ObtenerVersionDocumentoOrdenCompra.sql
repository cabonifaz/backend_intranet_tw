-- HU-25 Ruta de una versión del PDF de la OC para previsualizarla o descargarla.
-- Mismo permiso que el PDF vigente: oc_bandeja o expediente_bandeja.
-- Cada acceso queda registrado en descarga_documento (trazabilidad ISO 9001).
-- Resultados: 1 mensaje, 2 ruta, nombre y versión.
DROP PROCEDURE IF EXISTS SP_ObtenerVersionDocumentoOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerVersionDocumentoOrdenCompra(
    IN p_id_usuario   BIGINT,
    IN p_id_oc        BIGINT,
    IN p_id_documento BIGINT
)
proc: BEGIN
    DECLARE v_ruta    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version INT;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 AND FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver documentos de órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT d.url_archivo, d.nombre_archivo, d.version INTO v_ruta, v_nombre, v_version
    FROM documento_adjunto d
    JOIN orden_compra oc ON oc.id_oc = d.id_entidad AND oc.eliminado_en IS NULL
    WHERE d.id_documento = p_id_documento AND d.entidad_tipo = 'orden_compra'
      AND d.id_entidad = p_id_oc AND d.eliminado_en IS NULL;

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La versión del documento no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    INSERT INTO descarga_documento (id_usuario, entidad_tipo, id_entidad, url_archivo, canal, registrado_en)
    VALUES (p_id_usuario, 'orden_compra', p_id_oc, v_ruta, 'intranet', NOW());

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta, v_nombre AS nombre_archivo, v_version AS version;
END$$

DELIMITER ;
