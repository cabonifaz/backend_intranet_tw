-- HU-87 — Ficha del procedimiento (incluye trazabilidad)
DROP PROCEDURE IF EXISTS SP_ObtenerProcedimientoPorId;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProcedimientoPorId(
    IN p_id_procedimiento BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM procedimiento_metrologico WHERE id_procedimiento = p_id_procedimiento AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Procedimiento no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
        p.id_procedimiento,
        p.codigo,
        p.anio,
        p.version,
        p.es_formato_digital_iso,
        p.norma_base,
        p.autor_norma,
        p.descripcion,
        CASE p.estado
            WHEN 'activo'   THEN 'Activo'
            WHEN 'inactivo' THEN 'Inactivo'
            WHEN 'borrador' THEN 'Borrador'
            ELSE p.estado
        END                    AS estado,
        p.FchCre               AS fecha_registro,
        IF(p.estado = 'activo', 1, 0)                    AS es_activo,
        p.url_pdf_aprobado,
        COALESCE(CONCAT(u.nombre, ' ', u.apellido), p.UsuCre) AS usuario_registro,
        p.pc_registro,
        COALESCE(p.FchMod, p.FchCre)                     AS fecha_modificacion,
        p.total_ediciones
    FROM procedimiento_metrologico p
    LEFT JOIN usuario u ON u.id_usuario = p.id_usuario_registro
    WHERE p.id_procedimiento = p_id_procedimiento;
    END IF;
END$$

DELIMITER ;
