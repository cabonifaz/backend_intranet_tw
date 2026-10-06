-- Estado operativo automático del equipo (reunión 02-oct).
-- Lo llamarán los módulos que mueven el equipo, no el formulario de la ficha:
--   Control de Ingreso (CIE) .......... oficina_tw
--   Evaluación ........................ evaluacion
--   Orden de servicio / metrología .... ejecucion
--   Guía de salida / cierre ........... operativo_planta
-- No devuelve resultados para poder llamarse desde otros SPs.
DROP PROCEDURE IF EXISTS SP_ActualizarEstadoOperativoEquipo;

DELIMITER $$

CREATE PROCEDURE SP_ActualizarEstadoOperativoEquipo(
    IN p_id_equipo BIGINT,
    IN p_estado    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_origen    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF EXISTS (SELECT 1 FROM tabla_maestra
               WHERE IdMaestro = 83 AND IdEmpresa = 1 AND String2 = p_estado) THEN
        UPDATE equipo_cliente
        SET estado_operativo = p_estado,
            UsuMod           = LEFT(CONCAT('auto: ', IFNULL(p_origen, '')), 100),
            FchMod           = NOW()
        WHERE id_equipo = p_id_equipo AND SoftDelete = 0;
    END IF;
END$$

DELIMITER ;
