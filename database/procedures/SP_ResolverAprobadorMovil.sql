-- ============================================================
-- SP_ResolverAprobadorMovil  (App Mobile — apoyo, NO es un endpoint)
-- Qué aprobaciones ve un usuario, con la regla Área + Rol de SP_ResolverJefaturaMovil (2026-11-18):
--   p_general   = 1 → ve las de TODAS las áreas (cualquier rol en Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial…; o Administrador).
--   p_area_jefe     → 'servicio_tecnico' | 'metrologia' si es Supervisor de esa área: solo las de su área.
--   Ambos vacíos    → no ve aprobaciones (Usuario / Visor de Servicio Técnico o Metrología, o sin área).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverAprobadorMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResolverAprobadorMovil(
    IN  p_id_usuario BIGINT,
    OUT p_area_jefe  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_general    TINYINT
)
BEGIN
    DECLARE v_area     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_gen  TINYINT DEFAULT 0;

    SET p_area_jefe = NULL;
    SET p_general   = 0;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);

    IF v_area IS NOT NULL THEN
        IF v_area IN ('servicio_tecnico', 'metrologia') AND IFNULL(@tw_jf_alcance_total, 0) = 0 THEN
            SET p_area_jefe = v_area;      -- Supervisor de ST / Metrología: solo su área
        ELSE
            SET p_general = 1;             -- otras áreas (cualquier rol) o Administrador de ST / Metrología
        END IF;
    END IF;

    -- Un Administrador sin área sigue viendo todo (como antes)
    IF EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
                 AND u.rol_sistema IN ('administrador', 'admin')) THEN
        SET p_general   = 1;
        SET p_area_jefe = NULL;
    END IF;
END$$

DELIMITER ;
