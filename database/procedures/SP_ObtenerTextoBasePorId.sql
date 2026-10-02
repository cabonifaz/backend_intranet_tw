-- HU-85 — Ficha del texto base
DROP PROCEDURE IF EXISTS SP_ObtenerTextoBasePorId;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTextoBasePorId(
    IN p_id_texto_base BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM texto_base WHERE id_texto_base = p_id_texto_base AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Texto base no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            tb.id_texto_base,
            tb.codigo_corto,
            tb.tipo_categoria,
            COALESCE(tm.String1, tb.tipo_categoria)        AS tipo_categoria_label,
            tb.nombre,
            tb.texto_clausula,
            CASE tb.estado
                WHEN 'activo'   THEN 'Activo'
                WHEN 'inactivo' THEN 'Inactivo'
                WHEN 'borrador' THEN 'Borrador'
                ELSE tb.estado
            END                                             AS estado,
            tb.es_predeterminado,
            tb.es_negrita_por_defecto,
            tb.FchCre                                       AS fecha_creacion,
            COALESCE(CONCAT(u.nombre, ' ', u.apellido), tb.UsuCre) AS usuario_creador,
            tb.seccion_dossier,
            tb.orden_aparicion,
            tb.nivel_sangria,
            tb.aplica_calibracion_lab,
            tb.aplica_calibracion_planta,
            tb.aplica_mantenimiento,
            tb.aplica_venta_suministros,
            tb.visible_gestores_comerciales,
            tb.visible_tecnicos_metrologos,
            tb.visible_supervisores,
            tb.version,
            0                                               AS propuestas_asociadas
        FROM texto_base tb
        LEFT JOIN tabla_maestra tm
               ON tm.IdMaestro = 70 AND tm.IdEmpresa = 1 AND tm.String2 = tb.tipo_categoria
        LEFT JOIN usuario u ON u.id_usuario = tb.id_usuario_creador
        WHERE tb.id_texto_base = p_id_texto_base;
    END IF;
END$$

DELIMITER ;
