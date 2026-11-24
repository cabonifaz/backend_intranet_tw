-- ============================================================
-- SP_ContextoInformeComplementario  (Revisión Técnica — Informe Complementario, 23/11/2026 · apoyo, no es un endpoint)
-- Valida el permiso pedido, que el complementario exista (fila de informe_tecnico con id_informe_padre) y que su informe original esté
-- en el alcance del usuario (SP_ArmarBaseInformes: informes de los técnicos de su área; gerencia / TI ven todo).
--   p_msg        NULL = todo bien; si no, el mensaje para el usuario.
--   p_estado     estado del complementario: borrador (generado, sin guardar) · complementario (guardado).
--   p_editable   1 mientras el informe original no esté revisado (el complementario se cierra junto con el original).
-- No abre transacción ni deja tablas temporales.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_ContextoInformeComplementario(
    IN  p_id_usuario        BIGINT,
    IN  p_id_complementario BIGINT,
    IN  p_permiso           VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_msg               VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_padre          BIGINT,
    OUT p_estado            VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_estado_padre      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_editable          TINYINT
)
BEGIN
    DECLARE v_n INT DEFAULT 0;

    SET p_msg = NULL, p_id_padre = NULL, p_estado = NULL, p_estado_padre = NULL, p_editable = 0;

    IF FN_PermisoAccion(p_id_usuario, p_permiso) = 0 THEN
        SET p_msg = IF(p_permiso = 'rt_editar', 'No tienes permiso para editar informes complementarios.',
                                                'No tienes permiso para ver la revisión de informes técnicos.');
    ELSE
        SELECT c.id_informe_padre, c.estado INTO p_id_padre, p_estado
        FROM informe_tecnico c
        WHERE c.id_informe = p_id_complementario AND c.id_informe_padre IS NOT NULL AND c.eliminado_en IS NULL;

        IF p_id_padre IS NULL THEN
            SET p_msg = 'El informe complementario no existe.';
        ELSE
            CALL SP_ArmarBaseInformes(p_id_usuario, p_id_padre);
            SELECT COUNT(*), MAX(estado) INTO v_n, p_estado_padre FROM tmp_rt_base;
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            IF v_n = 0 THEN
                SET p_msg = 'El informe complementario no existe o no está en tu alcance.';
            ELSE
                SET p_editable = IF(p_estado_padre IN ('revisado', 'aprobado'), 0, 1);
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;
