-- HU-51 (Sprint 5) Opciones de los filtros globales de la bandeja: técnicos, clientes y zonas con servicios hoy, estados y catálogo de tipos de incidencia.
-- Resultados: 1 mensaje, 2 técnicos, 3 clientes, 4 zonas, 5 tipos de incidencia.
DROP PROCEDURE IF EXISTS SP_ObtenerFiltrosSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFiltrosSeguimiento(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_estados VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT ',sin_salir,en_ruta,en_planta,en_ejecucion,con_demora,con_incidente,finalizado,';
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la bandeja de seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT t.id_usuario AS Id, t.nombre AS Nombre FROM tmp_sg_tec t ORDER BY t.nombre;
    SELECT DISTINCT o.id_cliente AS Id, o.razon_social AS Nombre FROM tmp_sg_os o ORDER BY o.razon_social;
    SELECT DISTINCT o.zona AS Nombre FROM tmp_sg_os o WHERE o.zona IS NOT NULL ORDER BY o.zona;
    SELECT m.String2 AS Codigo, m.String1 AS Nombre FROM tabla_maestra m
    WHERE m.IdEmpresa = 1 AND m.Descripcion IN ('TIPO_INCIDENCIA_OPERATIVA', 'MOTIVO_DEMORA_RUTA') AND m.eliminado_en IS NULL
    GROUP BY m.String2, m.String1 ORDER BY m.String1;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
