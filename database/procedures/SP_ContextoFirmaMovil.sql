-- ============================================================
-- SP_ContextoFirmaMovil  (App Mobile HU-17 — apoyo, NO es un endpoint)
-- Valida, UNA sola vez, que el técnico pueda firmar los informes y la constancia de una OS: el servicio es suyo (técnico principal o personal de apoyo) y no está anulado.
--   p_mensaje trae el texto para el técnico cuando algo lo impide (lo demás queda NULL). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoFirmaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoFirmaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_id_os      BIGINT,
    OUT p_mensaje    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET p_mensaje = NULL, p_numero_os = NULL;
    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SET p_mensaje = 'Servicio no encontrado.';
    ELSE
        SELECT os.estado, os.numero INTO v_estado, p_numero_os
        FROM   orden_servicio os
        WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
        IF v_estado IS NULL THEN
            SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
        ELSEIF v_estado = 'anulada' THEN
            SET p_mensaje = 'El servicio está anulado.';
        END IF;
    END IF;
END$$

DELIMITER ;
