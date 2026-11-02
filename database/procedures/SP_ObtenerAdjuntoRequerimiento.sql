-- Observaciones 31/10 (RQ) — Ruta de un adjunto del requerimiento para verlo o descargarlo. Acción rq_ver.
-- Resultados: 1 mensaje, 2 ruta, nombre_archivo, tipo_contenido.
DROP PROCEDURE IF EXISTS SP_ObtenerAdjuntoRequerimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAdjuntoRequerimiento(
    IN p_id_usuario   BIGINT,
    IN p_id_documento BIGINT
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'rq_ver') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver requerimientos.' AS Mensaje; LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM documento_adjunto WHERE id_documento = p_id_documento AND entidad_tipo = 'requerimiento'
                     AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El adjunto no existe.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT url_archivo AS ruta, nombre_archivo, JSON_UNQUOTE(JSON_EXTRACT(metadatos, '$.tipo_contenido')) AS tipo_contenido
    FROM documento_adjunto WHERE id_documento = p_id_documento;
END$$

DELIMITER ;
