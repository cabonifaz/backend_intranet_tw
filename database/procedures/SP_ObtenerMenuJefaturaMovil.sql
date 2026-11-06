-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día del ÁREA del Jefe de Metrología que inició sesión.
--   El menú depende del ROL y el ÁREA: el supervisor (rol_sistema = 'supervisor') del área Metrología es el Jefe de Metrología.
--   El Jefe de Servicio Técnico usa el menú de campo (no tiene menú de Jefatura). Quien no es jefe de una de las áreas con
--   Jefatura recibe un mensaje y la app le muestra el menú de campo. Para sumar otra área con Jefatura: agregar su condición
--   aquí (y en utilidades/perfil.ts y modulosJefatura de la app).
--   Toda la información se filtra por el área del jefe según la RQ de cada servicio:
--     orden_servicio → expediente_digital → requerimiento.id_area → area_servicio_rq.area_usuario.
-- Resultados:
--   1. Mensaje
--   2. Una fila: area_codigo, area_nombre, sede, y los contadores de HOY (fecha de Lima, UTC-5):
--        programados      : servicios del área programados para hoy (en cualquier estado activo)
--        en_ruta          : de esos, en ruta
--        en_ejecucion     : de esos, en ejecución o pausados (ya están en planta)
--        con_demora       : de esos, con una demora registrada hoy
--        aprobaciones_pendientes : solicitudes de salida esperando su decisión. Misma regla que
--                           SP_ObtenerAutorizacionesSalida para el encargado del área (las de su área y las que la RQ no ubica en un área).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerMenuJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMenuJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hoy  DATE;

    -- Jefe de Metrología = SUPERVISOR del área Metrología (no depende de cómo se escriba el cargo, que es texto libre).
    SELECT IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL),
           s.String1
    INTO   v_area, v_sede
    FROM   usuario u
    LEFT JOIN tabla_maestra s ON s.IdMaestro = 69 AND s.IdEmpresa = 1 AND s.String2 = u.sede_operativa
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    WITH os_area AS (
        SELECT os.id_os, os.estado
        FROM   orden_servicio os
        LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
        LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
        WHERE  os.eliminado_en IS NULL
          AND  asr.area_usuario = v_area
          AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND  os.fecha_ejecucion = v_hoy
    )
    SELECT v_area                                                           AS area_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1) AS area_nombre,
           v_sede                                                           AS sede,
           COUNT(*)                                                         AS programados,
           IFNULL(SUM(estado = 'en_ruta'), 0)                               AS en_ruta,
           IFNULL(SUM(estado IN ('en_ejecucion', 'pausada')), 0)            AS en_ejecucion,
           (SELECT COUNT(DISTINCT d.id_os)
            FROM   demora_registro d
            WHERE  d.eliminado_en IS NULL AND DATE(d.fecha_registro) = v_hoy
              AND  d.id_os IN (SELECT o.id_os FROM os_area o))              AS con_demora,
           (SELECT COUNT(*)
            FROM   autorizacion_salida_os a
            WHERE  a.eliminado_en IS NULL AND a.estado = 'pendiente'
              AND  (a.area_destino IS NULL OR a.area_destino = v_area))     AS aprobaciones_pendientes
    FROM   os_area;
END$$

DELIMITER ;
