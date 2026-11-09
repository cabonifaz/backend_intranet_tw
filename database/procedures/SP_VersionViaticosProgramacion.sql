-- HU-45 (Sprint 5) Huella de la asignación de viáticos de una programación (control de concurrencia optimista).
-- Cambia cuando alguien agrega, edita o quita una línea, o cuando Contabilidad registra un depósito. Quien guarda envía la huella que vio
-- al abrir el modal: si ya no coincide, se rechaza el guardado para no pisar el trabajo de otra persona. Solo lectura.
--   p_vigente = 1: también cuenta las líneas históricas de la OS que aún no tienen programación asociada.
DROP PROCEDURE IF EXISTS SP_VersionViaticosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_VersionViaticosProgramacion(
    IN  p_id_programacion BIGINT,
    IN  p_id_os           BIGINT,
    IN  p_vigente         TINYINT,
    OUT p_version         VARCHAR(80)
)
BEGIN
    SELECT CONCAT(COUNT(*), '-', IFNULL(SUM(g.monto), 0), '-', IFNULL(BIT_XOR(CRC32(CONCAT_WS(':', g.id_gasto, g.id_usuario, g.id_concepto, g.monto, g.estado, IFNULL(g.fecha_deposito, '')))), 0))
      INTO p_version
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = p_id_os AND p_vigente = 1));
END$$

DELIMITER ;
