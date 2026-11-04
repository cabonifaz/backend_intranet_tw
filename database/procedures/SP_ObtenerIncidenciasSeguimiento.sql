-- HU-51 (Sprint 5) Pestaña 4 "Incidencias del Día": demoras e incidencias de hoy en orden cronológico, de todos los técnicos, con sus tarjetas resumen.
-- Origen: Técnico (lo registró el propio técnico desde la app) o Asistente (registro del Asistente de Seguimiento, HU-53). Impacto: Retrasa o Detiene.
-- Filtros: Técnico, Cliente, Zona/Sede, buscador, Tipo (código del catálogo) e Impacto. Las demoras sin impacto registrado cuentan como "Retrasa".
-- Resultados: 1 mensaje, 2 tarjetas, 3 filas.
DROP PROCEDURE IF EXISTS SP_ObtenerIncidenciasSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIncidenciasSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_impacto    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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
    IF (p_id_tecnico IS NOT NULL AND p_id_tecnico <= 0) OR (p_id_cliente IS NOT NULL AND p_id_cliente <= 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El técnico o el cliente del filtro no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_zona, '')) > 100 OR CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 OR CHAR_LENGTH(IFNULL(p_tipo, '')) > 40 THEN
        SELECT 1 AS IdTipoMensaje, 'La zona, la búsqueda o el tipo superan el largo permitido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_impacto, '') IS NOT NULL AND p_impacto NOT IN ('retrasa', 'detiene') THEN
        SELECT 1 AS IdTipoMensaje, 'El impacto no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_FiltrarSeguimientoOperativo(NULL, p_id_cliente, NULL, NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    DELETE i FROM tmp_sg_inc i
    WHERE (p_id_tecnico IS NOT NULL AND i.id_usuario <> p_id_tecnico)
       OR (NULLIF(p_tipo, '') IS NOT NULL AND i.tipo_codigo <> p_tipo)
       OR (NULLIF(p_impacto, '') IS NOT NULL AND i.impacto <> p_impacto)
       OR i.id_os NOT IN (SELECT f.id_os FROM tmp_sg_f f);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT IFNULL(SUM(impacto = 'retrasa'), 0) AS Retrasan, IFNULL(SUM(impacto = 'detiene'), 0) AS Detienen,
           IFNULL(SUM(origen = 'tecnico'), 0) AS RegistradasTecnico, IFNULL(SUM(origen = 'asistente'), 0) AS RegistradasAsistente,
           COUNT(*) AS Total
    FROM tmp_sg_inc;
    SELECT i.clave AS Clave, DATE_FORMAT(i.fecha, '%H:%i') AS Hora, i.id_usuario AS IdUsuario, i.tecnico AS Tecnico, i.iniciales AS Iniciales,
           i.id_os AS IdOs, i.numero AS Numero, i.cliente AS Cliente, i.tipo_codigo AS TipoCodigo, i.tipo AS Tipo, i.descripcion AS Descripcion,
           i.duracion_min AS DuracionMin, i.impacto AS Impacto, i.origen AS Origen
    FROM tmp_sg_inc i
    ORDER BY i.fecha, i.clave
    LIMIT 500;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
