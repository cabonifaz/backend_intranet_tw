-- HU-30 Exportación del expediente completo (estructura y documentos en un ZIP).
-- Acción expediente_bandeja. Devuelve los documentos descargables que el usuario puede ver, con su carpeta
-- (categoría) y la ruta interna o el id de la propuesta (su PDF se genera). Registra la exportación en la auditoría.
-- Resultados: 1 mensaje · 2 archivos
DROP PROCEDURE IF EXISTS SP_ObtenerArchivosExportacionExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivosExportacionExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarDocumentosExpediente(p_id_usuario, p_id_expediente);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en)
    VALUES ('expediente', p_id_expediente, 'exportar_expediente', 'Expediente completo exportado (estructura y documentos).',
            p_id_usuario, NOW());

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT d.clave, d.categoria, IFNULL(c.String1, d.categoria) AS carpeta, d.nombre_archivo, d.version, d.estado,
           d.ruta, d.id_propuesta
    FROM tmp_exp_doc d
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 101 AND c.IdEmpresa = 1 AND c.String2 = d.categoria
    WHERE d.ruta IS NOT NULL OR d.id_propuesta IS NOT NULL
    ORDER BY d.categoria, d.fecha;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;
END$$

DELIMITER ;
