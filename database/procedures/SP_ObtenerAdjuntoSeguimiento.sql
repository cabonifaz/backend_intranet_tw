-- HU-19 Ruta de un adjunto de seguimiento para descargarlo.
-- Solo usuarios del área del responsable de la propuesta (o todas con propuesta_seguimiento_todas).
-- Resultados: 1 mensaje, 2 ruta, nombre_archivo, tipo_contenido.
DROP PROCEDURE IF EXISTS SP_ObtenerAdjuntoSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAdjuntoSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_adjunto BIGINT
)
BEGIN
    DECLARE v_area_usuario VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_resp    VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe       INT DEFAULT 0;

    SELECT COUNT(*), MAX(u.area) INTO v_existe, v_area_resp
    FROM seguimiento_adjunto a
    JOIN seguimiento_comercial s ON s.id_seguimiento = a.id_seguimiento
    JOIN propuesta_comercial p   ON p.id_propuesta   = s.id_propuesta
    JOIN usuario u               ON u.id_usuario     = COALESCE(p.id_responsable, p.id_creador)
    WHERE a.id_adjunto = p_id_adjunto AND a.eliminado_en IS NULL;

    SELECT area INTO v_area_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El adjunto no existe.' AS Mensaje;
    ELSEIF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas') = 0
           AND IFNULL(v_area_usuario, '') <> IFNULL(v_area_resp, '-') THEN
        SELECT 1 AS IdTipoMensaje, 'El adjunto no pertenece a tu área.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT ruta, nombre_archivo, tipo_contenido
        FROM seguimiento_adjunto WHERE id_adjunto = p_id_adjunto;
    END IF;
END$$

DELIMITER ;
