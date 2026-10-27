-- HU-40 (Sprint 4) Catálogo de motivos de la OS/OM: p_tipo = edicion (MOTIVO_EDICION_OS) | anulacion (MOTIVO_ANULACION_OS).
-- Resultados: 1 mensaje, 2 motivos (id = Num1, nombre, codigo).
DROP PROCEDURE IF EXISTS SP_ObtenerMotivosOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMotivosOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'os_bandeja') = 0 AND FN_PermisoAccion(p_id_usuario, 'os_bandeja_operaciones') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para ver las órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_tipo, '') NOT IN ('edicion', 'anulacion') THEN
        SELECT 1 AS IdTipoMensaje, 'Tipo de motivo no válido (edicion | anulacion).' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra
    WHERE Descripcion = IF(p_tipo = 'edicion', 'MOTIVO_EDICION_OS', 'MOTIVO_ANULACION_OS') AND eliminado_en IS NULL
    ORDER BY Num1;
END$$

DELIMITER ;
