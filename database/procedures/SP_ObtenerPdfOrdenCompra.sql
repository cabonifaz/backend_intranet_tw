-- HU-22 Ruta del PDF de una orden de compra para verlo o descargarlo.
-- Lo puede ver quien tenga acceso a la bandeja de OC (oc_bandeja) o a los expedientes (expediente_bandeja):
-- Comercial, Operaciones, Contabilidad (Administración) y Gerencia según la matriz de permisos.
-- HU-25: registra cada acceso en descarga_documento.
-- Resultados: 1 mensaje, 2 ruta y nombre del archivo.
DROP PROCEDURE IF EXISTS SP_ObtenerPdfOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPdfOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
    ELSEIF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 AND FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver documentos de órdenes de compra.' AS Mensaje;
    ELSEIF NOT EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe.' AS Mensaje;
    ELSEIF NOT EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND url_archivo_pdf IS NOT NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no tiene PDF adjunto.' AS Mensaje;
    ELSE
        -- HU-25: cada acceso al PDF queda registrado (trazabilidad ISO 9001)
        INSERT INTO descarga_documento (id_usuario, entidad_tipo, id_entidad, url_archivo, canal, registrado_en)
        SELECT p_id_usuario, 'orden_compra', p_id_oc, url_archivo_pdf, 'intranet', NOW()
        FROM orden_compra WHERE id_oc = p_id_oc;

        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT url_archivo_pdf AS ruta,
               COALESCE(nombre_archivo_pdf, CONCAT('OC-', numero_oc, '.pdf')) AS nombre_archivo
        FROM orden_compra WHERE id_oc = p_id_oc;
    END IF;
END$$

DELIMITER ;
