-- Expediente Digital (interno): notificación en la intranet a los jefes (supervisor y administrador) de un área y,
-- opcionalmente, a un usuario puntual (responsable). No notifica a quien ejecuta la acción.
-- p_notificados devuelve cuántas notificaciones se crearon.
DROP PROCEDURE IF EXISTS SP_NotificarAreaExpediente;

DELIMITER $$

CREATE PROCEDURE SP_NotificarAreaExpediente(
    IN  p_id_expediente BIGINT,
    IN  p_area          VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_id_usuario    BIGINT,
    IN  p_titulo        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_cuerpo        TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_id_ejecutor   BIGINT,
    OUT p_notificados   INT
)
BEGIN
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, LEFT(p_titulo, 150), p_cuerpo, 'expediente', p_id_expediente, NOW(), p_id_ejecutor
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> IFNULL(p_id_ejecutor, 0)
      AND ((p_area IS NOT NULL AND u.area = p_area AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = IFNULL(p_id_usuario, 0));
    SET p_notificados = ROW_COUNT();
END$$

DELIMITER ;
