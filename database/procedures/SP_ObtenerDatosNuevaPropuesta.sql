-- HU-07 — Datos heredados del requerimiento para iniciar una propuesta
--   + propuesta existente (última versión) para el aviso "Crear nueva versión"
DROP PROCEDURE IF EXISTS SP_ObtenerDatosNuevaPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDatosNuevaPropuesta(
    IN p_id_requerimiento BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM requerimiento WHERE id_requerimiento = p_id_requerimiento AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Requerimiento no encontrado.' AS Mensaje;
    ELSE
        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Datos heredados del RQ
        SELECT
            r.id_requerimiento,
            r.numero                    AS numero_requerimiento,
            r.estado                    AS estado_requerimiento,
            r.id_cliente,
            c.razon_social,
            c.ruc,
            r.id_sede,
            sc.nombre                   AS nombre_sede,
            r.id_contacto,
            co.nombres                  AS nombre_contacto,
            co.cargo                    AS cargo_contacto,
            r.id_area,
            tm_area.String1             AS area_label,
            r.id_prioridad,
            tm_prio.String1             AS prioridad_label,
            r.descripcion
        FROM requerimiento r
        JOIN cliente c                ON c.id_cliente   = r.id_cliente
        LEFT JOIN sede_cliente sc     ON sc.id_sede     = r.id_sede
        LEFT JOIN contacto_cliente co ON co.id_contacto = r.id_contacto
        LEFT JOIN tabla_maestra tm_area ON tm_area.IdMaestro = 64 AND tm_area.IdEmpresa = 1 AND tm_area.Num1 = r.id_area
        LEFT JOIN tabla_maestra tm_prio ON tm_prio.IdMaestro = 65 AND tm_prio.IdEmpresa = 1 AND tm_prio.Num1 = r.id_prioridad
        WHERE r.id_requerimiento = p_id_requerimiento;

        -- 3. Propuesta existente (última versión vinculada al RQ), si la hay.
        -- Las anuladas se ignoran porque son terminales por acción interna:
        -- el usuario ya no debe poder "retomarlas" ni generarles nueva versión.
        -- Las rechazadas/vencidas sí cuentan porque el ciclo con el cliente terminó
        -- pero aún se puede generar una nueva versión y reintentar la venta.
        SELECT
            p.id_propuesta,
            p.numero,
            p.version,
            p.estado
        FROM propuesta_comercial p
        WHERE p.id_requerimiento = p_id_requerimiento
          AND p.eliminado_en IS NULL
          AND p.estado <> 'anulado'
        ORDER BY p.version DESC, p.id_propuesta DESC
        LIMIT 1;
    END IF;
END$$

DELIMITER ;
