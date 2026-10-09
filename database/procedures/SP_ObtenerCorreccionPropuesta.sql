-- HU-15 — Última solicitud de corrección de una propuesta (para mostrarla en el editor).
--   Resultados: 1 header · 2 corrección (vacío si nunca tuvo) · 3 áreas marcadas
DROP PROCEDURE IF EXISTS SP_ObtenerCorreccionPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCorreccionPropuesta(
    IN p_id_propuesta BIGINT
)
proc: BEGIN
    DECLARE v_id_corr BIGINT;

    IF NOT EXISTS (SELECT 1 FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_correccion INTO v_id_corr
    FROM propuesta_correccion
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL
    ORDER BY id_correccion DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT pc.id_correccion, pc.estado, pc.observaciones, pc.fecha_limite,
           (pc.estado = 'pendiente' AND pc.fecha_limite < NOW()) AS vencida,
           pc.creado_en                            AS solicitado_en,
           CONCAT(us.nombre, ' ', us.apellido)     AS solicitado_por,
           pc.id_responsable,
           CONCAT(ur.nombre, ' ', ur.apellido)     AS nombre_responsable,
           pc.atendida_en
    FROM propuesta_correccion pc
    LEFT JOIN usuario us ON us.id_usuario = pc.solicitado_por
    LEFT JOIN usuario ur ON ur.id_usuario = pc.id_responsable
    WHERE pc.id_correccion = v_id_corr;

    SELECT a.codigo, IFNULL(tm.String1, a.codigo) AS etiqueta
    FROM propuesta_correccion pc
    JOIN JSON_TABLE(pc.areas, '$[*]' COLUMNS (codigo VARCHAR(40) PATH '$')) a
    LEFT JOIN tabla_maestra tm ON tm.Descripcion = 'AREA_CORRECCION_PROPUESTA' AND tm.String2 = a.codigo
                              AND tm.eliminado_en IS NULL
    WHERE pc.id_correccion = v_id_corr
    ORDER BY tm.Num1;
END$$

DELIMITER ;
