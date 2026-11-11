-- ============================================================
-- SP_ObtenerLlegadasForzadas  (App Mobile HU-06 / HU-31 — bandeja de Aprobaciones del encargado · lectura)
-- Solicitudes de llegada forzada que puede ver el usuario (misma regla de áreas que las autorizaciones de salida):
--   encargado de área (Jefe de Servicio Técnico / Jefe de Metrología o supervisor de Metrología): las de SU área y las sin área en la RQ;
--   Jefe/Coordinador de Operaciones, supervisor de Operaciones y administradores: todas.
--   p_id_os = 0/NULL → las PENDIENTES (la bandeja). p_id_os > 0 → la más reciente de esa OS, en cualquier estado (el detalle).
-- Resultado: 1 mensaje · 2 filas (id_solicitud, id_os, numero_os, cliente, sede, fecha_ejecucion, hora_inicio, tecnico, estado, motivo, intentos,
--   latitud, longitud, precision_metros, distancia_m, lat_planta, lon_planta, radio_m, area_destino, area, solicitado_en, jefe, resuelto_en, comentario, usada_en).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerLlegadasForzadas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerLlegadasForzadas(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;
    DECLARE v_radio     DECIMAL(18,6);

    SELECT 1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_existe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_existe = 0 OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los encargados de Servicio Técnico y Metrología pueden ver las llegadas forzadas.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT s.id_solicitud,
           s.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           COALESCE(NULLIF(sc.nombre, ''), sc2.nombre)                      AS sede,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           NULLIF(TRIM(CONCAT(IFNULL(tc.nombre, ''), ' ', IFNULL(tc.apellido, ''))), '') AS tecnico,
           s.estado,
           s.motivo,
           s.intentos,
           s.latitud,
           s.longitud,
           s.precision_metros,
           s.distancia_metros                                               AS distancia_m,
           COALESCE(sc.latitud, sc2.latitud, os.latitud_llegada)            AS lat_planta,
           COALESCE(sc.longitud, sc2.longitud, os.longitud_llegada)         AS lon_planta,
           ROUND(v_radio)                                                   AS radio_m,
           s.area_destino,
           ar.String1                                                       AS area,
           s.solicitado_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS jefe,
           s.resuelto_en,
           s.comentario,
           s.usada_en
    FROM   llegada_forzada_os s
    JOIN   orden_servicio os ON os.id_os = s.id_os AND os.eliminado_en IS NULL
    LEFT JOIN cliente        cl  ON cl.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente   sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN requerimiento  rq  ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente   sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    LEFT JOIN usuario        tc  ON tc.id_usuario = s.id_tecnico
    LEFT JOIN usuario        jf  ON jf.id_usuario = s.id_jefe
    LEFT JOIN tabla_maestra  ar  ON ar.IdMaestro = 79 AND ar.IdEmpresa = 1 AND ar.String2 = s.area_destino
    WHERE  s.eliminado_en IS NULL
      AND  (v_general = 1 OR s.area_destino IS NULL OR s.area_destino = v_area_jefe)
      AND  ((IFNULL(p_id_os, 0) = 0 AND s.estado = 'pendiente')
            OR (IFNULL(p_id_os, 0) > 0 AND s.id_os = p_id_os
                AND s.id_solicitud = (SELECT MAX(x.id_solicitud) FROM llegada_forzada_os x WHERE x.id_os = p_id_os AND x.eliminado_en IS NULL)))
    ORDER BY s.solicitado_en DESC, s.id_solicitud DESC
    LIMIT 200;
END$$

DELIMITER ;
