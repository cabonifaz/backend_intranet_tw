-- ============================================================
-- SP_ObtenerAlcanceCrm
-- Alcance de visibilidad de los listados del CRM para el usuario autenticado (pedido 14).
--   p_ver_todo    = 1 → gerencia / TI o quien tiene 'propuesta_seguimiento_todas' (administrar): ve todo.
--   p_solo_propio = 1 → rol 'usuario': solo lo que tiene como responsable actual + suplencias vigentes.
--   Supervisor / administrador / visor del área: todo lo de su área.
--   p_ids         → lista (FIND_IN_SET) de los usuarios cuyos registros puede ver.
--   p_area        → área del usuario (las bandejas de operaciones solo filtran al área comercial).
-- Se usa con: (v_ver_todo = 1 OR FIND_IN_SET(dueño, v_ids) > 0 OR (dueño IS NULL AND v_solo_propio = 0))
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAlcanceCrm;

DELIMITER //

CREATE PROCEDURE SP_ObtenerAlcanceCrm(
    IN  p_id_usuario  BIGINT,
    OUT p_ver_todo    TINYINT,
    OUT p_solo_propio TINYINT,
    OUT p_ids         TEXT,
    OUT p_area        VARCHAR(40)
)
BEGIN
    DECLARE v_area VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rol  VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET SESSION group_concat_max_len = 1000000;

    SELECT area, rol_sistema INTO v_area, v_rol
    FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo'
    LIMIT 1;

    SET p_area        = v_area;
    SET p_ver_todo    = IF(v_area IN ('gerencia', 'ti')
                           OR IFNULL(FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas'), 0) = 1, 1, 0);
    SET p_solo_propio = IF(p_ver_todo = 0 AND (v_rol IS NULL OR v_rol = 'usuario'), 1, 0);

    SELECT IFNULL(GROUP_CONCAT(DISTINCT u.id_usuario), '') INTO p_ids
    FROM usuario u
    WHERE u.id_usuario = p_id_usuario
       OR (p_solo_propio = 0 AND v_area IS NOT NULL AND u.area = v_area)
       OR EXISTS (SELECT 1 FROM usuario_suplente us
                  WHERE us.id_titular  = u.id_usuario
                    AND us.id_suplente = p_id_usuario
                    AND us.activo = 1 AND us.SoftDelete = 0
                    AND us.fecha_inicio <= CURDATE()
                    AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE()));
END //

DELIMITER ;
