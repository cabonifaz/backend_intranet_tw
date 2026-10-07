-- Estado operativo automático del equipo (#4300, notas de TW del 07-oct). Solo 3 estados:
--   oficina_tw  En oficina .... se generó un control de ingreso (CIE) para el equipo
--   evaluacion  En evaluación . el equipo tiene una evaluación pendiente
--   ejecucion   En ejecución .. el equipo tiene una orden de servicio o de mantenimiento (OS / OM)
--   NULL        Sin movimiento (al salir con guía de salida o cerrar la orden)
-- Lo llaman los módulos de CIE, evaluación y OS/OM (no el formulario de la ficha).
-- No devuelve resultados para poder llamarse desde otros SPs.
DROP PROCEDURE IF EXISTS SP_ActualizarEstadoOperativoEquipo;

DELIMITER $$

CREATE PROCEDURE SP_ActualizarEstadoOperativoEquipo(
    IN p_id_equipo BIGINT,
    IN p_estado    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_origen    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF p_estado IS NULL OR p_estado = '' OR EXISTS (
        SELECT 1 FROM tabla_maestra WHERE IdMaestro = 83 AND IdEmpresa = 1 AND String2 = p_estado
    ) THEN
        UPDATE equipo_cliente
        SET estado_operativo = NULLIF(p_estado, ''),
            UsuMod           = LEFT(CONCAT('auto: ', IFNULL(p_origen, '')), 100),
            FchMod           = NOW()
        WHERE id_equipo = p_id_equipo AND SoftDelete = 0;
    END IF;
END$$

DELIMITER ;
