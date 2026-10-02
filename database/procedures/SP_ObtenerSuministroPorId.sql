-- HU-86 — Ficha del suministro (incluye trazabilidad)
DROP PROCEDURE IF EXISTS SP_ObtenerSuministroPorId;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSuministroPorId(
    IN p_id_suministro BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM suministros WHERE id_suministro = p_id_suministro AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Suministro no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
        ci.id_suministro                               AS id_suministro,
        ci.codigo,
        ci.clase,
        COALESCE(t_cla.String1, ci.clase)                 AS clase_label,
        ci.tipo,
        COALESCE(t_tip.String1, ci.tipo)                  AS tipo_label,
        ci.subtipo,
        COALESCE(t_sub.String1, ci.subtipo)               AS subtipo_label,
        ci.descripcion,
        ci.marca,
        ci.modelo,
        ci.cta_contable,
        ci.procedencia,
        COALESCE(t_pro.String1, ci.procedencia)           AS procedencia_label,
        CASE ci.estado
            WHEN 'activo'   THEN 'Activo'
            WHEN 'inactivo' THEN 'Inactivo'
            WHEN 'borrador' THEN 'Borrador'
            ELSE ci.estado
        END                                               AS estado,
        IF(ci.estado = 'activo', 1, 0)                    AS es_activo_en_catalogo,
        ci.usar_en_propuestas,
        ci.descripcion                                    AS descripcion_auto,
        ci.descripcion_manual,
        ci.alcance,
        ci.unidad_medida                                  AS unidad,
        ci.casillero,
        ci.codigo_unspsc,
        ci.precio_referencia                              AS precio_min_referencia,
        ci.precio_nivel_estandar,
        ci.precio_nivel_volumen,
        ci.precio_nivel_corporativo,
        ci.aplica_comercial,
        ci.aplica_servicio,
        ci.aplica_metrologia,
        ci.id_primer_procedimiento,
        ci.id_segundo_procedimiento,
        COALESCE(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario_registro,
        ci.creado_en                                      AS fecha_registro,
        COALESCE(ci.modificado_en, ci.creado_en)          AS fecha_modificacion,
        ci.total_ediciones,
        UPPER(LEFT(SHA2(CONCAT(ci.id_suministro, '|', ci.codigo, '|',
              COALESCE(ci.modificado_en, ci.creado_en), '|', ci.total_ediciones), 256), 16)) AS firma_digital,
        ci.url_foto,
        ci.url_manual_pdf
    FROM suministros ci
    LEFT JOIN tabla_maestra t_cla ON t_cla.IdMaestro = 71 AND t_cla.IdEmpresa = 1 AND t_cla.String2 = ci.clase
    LEFT JOIN tabla_maestra t_tip ON t_tip.IdMaestro = 72 AND t_tip.IdEmpresa = 1 AND t_tip.String2 = ci.tipo
    LEFT JOIN tabla_maestra t_sub ON t_sub.IdMaestro = 73 AND t_sub.IdEmpresa = 1 AND t_sub.String2 = ci.subtipo
    LEFT JOIN tabla_maestra t_pro ON t_pro.IdMaestro = 74 AND t_pro.IdEmpresa = 1 AND t_pro.String2 = ci.procedencia
    LEFT JOIN usuario u ON u.id_usuario = ci.creado_por
    WHERE ci.id_suministro = p_id_suministro;
    END IF;
END$$

DELIMITER ;
