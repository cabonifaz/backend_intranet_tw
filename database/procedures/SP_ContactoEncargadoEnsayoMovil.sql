-- ============================================================
-- SP_ContactoEncargadoEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Encargado del área responsable de la OS según la RQ (area_servicio_rq: metrologia | servicio_tecnico), UNA sola vez. Lo usan "Llamar al encargado",
-- el aviso de "Guardar de todas formas" y la cabecera de Ensayos.
--   Prioridad: el usuario activo con cargo jefe_<área>; si no hay, un supervisor / administrador del área; si no hay, nadie (todo NULL).
--   p_area = área de la RQ; p_nombre, p_cargo, p_telefono, p_id_usuario = del encargado. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContactoEncargadoEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContactoEncargadoEnsayoMovil(
    IN  p_id_os     BIGINT,
    OUT p_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_usuario BIGINT,
    OUT p_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cargo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_telefono  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    SET p_area = NULL, p_id_usuario = NULL, p_nombre = NULL, p_cargo = NULL, p_telefono = NULL;

    SELECT asr.area_usuario INTO p_area
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    JOIN   area_servicio_rq  asr ON asr.id_area_rq = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;

    IF p_area IS NOT NULL THEN
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
               COALESCE(c.String1, u.cargo, IF(p_area = 'metrologia', 'Jefe de Metrología', 'Jefe de Servicio Técnico')),
               NULLIF(TRIM(u.telefono), '')
        INTO   p_id_usuario, p_nombre, p_cargo, p_telefono
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  (u.cargo = CONCAT('jefe_', p_area) OR (u.area = p_area AND u.rol_sistema IN ('supervisor', 'administrador')))
        ORDER BY (u.cargo = CONCAT('jefe_', p_area)) DESC, (NULLIF(TRIM(u.telefono), '') IS NOT NULL) DESC, u.id_usuario
        LIMIT 1;
    END IF;
END$$

DELIMITER ;
