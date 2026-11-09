-- HU-51 (Sprint 5) Pestaña 2 "Servicios en Campo": una fila por OS/OM de hoy con propuesta de origen, cliente, técnico, estado, última ubicación y avance (equipos).
-- Filtro de rango: en_curso (en ruta, en planta, en ejecución, con demora o incidente), finalizados, sin_iniciar. Paginado (tamaño 1 a 50).
-- Resultados: 1 mensaje, 2 totales (con filtros) y paginación, 3 filas.
DROP PROCEDURE IF EXISTS SP_ObtenerServiciosSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerServiciosSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rango      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_tamano     INT
)
proc: BEGIN
    DECLARE v_estados VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT ',sin_salir,en_ruta,en_planta,en_ejecucion,con_demora,con_incidente,finalizado,';
    DECLARE v_off INT;
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
    IF NULLIF(p_estado, '') IS NOT NULL AND LOCATE(CONCAT(',', p_estado, ','), v_estados) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El estado del servicio no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_zona, '')) > 100 OR CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La zona o la búsqueda superan los 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_rango, '') IS NOT NULL AND p_rango NOT IN ('en_curso', 'finalizados', 'sin_iniciar') THEN
        SELECT 1 AS IdTipoMensaje, 'El rango de estado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_pagina, 0) < 1 OR IFNULL(p_tamano, 0) < 1 OR p_tamano > 50 THEN
        SELECT 1 AS IdTipoMensaje, 'La paginación no es válida (página desde 1, tamaño de 1 a 50).' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_off = (p_pagina - 1) * p_tamano;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_FiltrarSeguimientoOperativo(p_id_tecnico, p_id_cliente, NULLIF(p_estado, ''), NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    -- Filtro de rango sobre los servicios ya filtrados
    DELETE f FROM tmp_sg_f f JOIN tmp_sg_os o ON o.id_os = f.id_os
    WHERE (p_rango = 'en_curso' AND o.estado_seg IN ('sin_salir', 'finalizado'))
       OR (p_rango = 'finalizados' AND o.estado_seg <> 'finalizado')
       OR (p_rango = 'sin_iniciar' AND o.estado_seg <> 'sin_salir');

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT COUNT(*) AS Total, p_pagina AS Pagina, p_tamano AS Tamano, CEIL(COUNT(*) / p_tamano) AS TotalPaginas, DATE_FORMAT(MAX(c.ahora), '%H:%i') AS Actualizado
    FROM tmp_sg_f f JOIN tmp_sg_cfg c;

    SELECT o.id_os AS IdOs, o.numero AS Numero, o.tipo AS Tipo, o.propuesta AS Propuesta, o.razon_social AS Cliente, o.ruc AS Ruc,
           o.id_tecnico AS IdTecnico, o.tecnico AS Tecnico, UPPER(CONCAT(LEFT(o.nombre_pila, 1), LEFT(IFNULL(SUBSTRING_INDEX(o.tecnico, ' ', -1), ''), 1))) AS Iniciales,
           o.estado_seg AS Estado, o.zona AS Zona, DATE_FORMAT(o.hora_inicio, '%H:%i') AS HoraInicio,
           COALESCE(NULLIF(p.direccion, ''), IF(p.lat IS NULL, NULL, CONCAT(FORMAT(p.lat, 5), ', ', FORMAT(p.lon, 5)))) AS UltimaUbicacion,
           IF(p.ts_utc IS NULL, NULL, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc)) AS MinutosUbicacion,
           o.n_equipos AS Equipos, o.n_ejecutados AS Ejecutados,
           IF(o.n_equipos = 0, 0, ROUND(o.n_ejecutados * 100 / o.n_equipos)) AS AvancePct
    FROM tmp_sg_f f
    JOIN tmp_sg_os o ON o.id_os = f.id_os
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = o.id_tecnico
    JOIN tmp_sg_cfg c
    ORDER BY o.prio, o.hora_inicio, o.id_os
    LIMIT v_off, p_tamano;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
