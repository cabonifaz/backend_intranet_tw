-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día para quien tiene el menú de Jefatura en la app: los usuarios con rol SUPERVISOR o ADMINISTRADOR de CUALQUIER
-- área excepto Servicio Técnico (cuyo personal usa el menú de campo). El rol y el área son catálogos; el cargo es texto libre
-- y no se usa. Quien no cumple recibe un mensaje y la app le muestra el menú de campo (técnicos, metrólogos y usuarios comunes).
--   - Metrología: se filtra por el área de la RQ de cada servicio (orden_servicio → expediente_digital → requerimiento.id_area →
--     area_servicio_rq.area_usuario = 'metrologia').
--   - Otras áreas (Operaciones, TI, Gerencia, Comercial…): no tienen área en la RQ, así que ven el resumen de TODOS los servicios.
-- Resultados:
--   1. Mensaje
--   2. Una fila: area_codigo (el área del usuario), area_nombre, sede, y los contadores de HOY (fecha de Lima, UTC-5):
--        programados      : servicios programados para hoy (en cualquier estado activo)
--        en_ruta          : de esos, en ruta
--        en_ejecucion     : de esos, en ejecución o pausados (ya están en planta)
--        con_demora       : de esos, con una demora registrada hoy
--        aprobaciones_pendientes : solicitudes de salida que ESTE usuario puede resolver. Misma regla que
--                           SP_ObtenerAutorizacionesSalida: supervisor de Metrología → las de su área y las que la RQ no ubica en
--                           un área; supervisión general (Jefe/Coordinador de Operaciones, supervisor de Operaciones, administrador)
--                           → todas; el resto → 0.
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
    DECLARE v_aut_area    VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;

    SELECT IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') NOT IN ('', 'servicio_tecnico'), u.area, NULL),
           s.String1,
           IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_area, v_sede, v_aut_area, v_aut_general
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
        WHERE  os.eliminado_en IS NULL
          AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND  os.fecha_ejecucion = v_hoy
          AND  (v_area <> 'metrologia'
                OR EXISTS (SELECT 1
                           FROM   expediente_digital ed
                           JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                           JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                           WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = 'metrologia'))
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
              AND  (v_aut_general = 1
                    OR (v_aut_area IS NOT NULL AND (a.area_destino IS NULL OR a.area_destino = v_aut_area)))) AS aprobaciones_pendientes
    FROM   os_area;
END$$

DELIMITER ;
