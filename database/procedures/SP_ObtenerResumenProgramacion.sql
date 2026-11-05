-- HU-35 (Sprint 5) Bandeja de Programación Operativa — tab "Vista Principal" (dashboard global, solo lectura).
-- Acceso: prog_bandeja (módulo operaciones). No lleva filtros: es el panorama global de la semana.
--   p_fecha_semana: cualquier fecha de la semana a mostrar (lunes a domingo); vacío = la semana de hoy.
--   p_busqueda: opcional; acota solo el calendario (N° OS/OM, cliente, RUC o técnico). Tarjetas, carga y alertas siguen globales.
-- Reglas (ver cabecera de SP_ArmarBaseProgramacion para los sub-estados y la plantilla de técnicos):
--   Carga, calendario, conflictos y disponibilidad cuentan al técnico principal y al personal de apoyo de cada orden.
--   Carga diaria por técnico (horas de sus servicios del día = hora fin estimada - hora inicio):
--     libre = 0 · baja < 6 · óptimo 6 a 8 · alta > 8 a 10 · sobrecarga > 10 h o servicios solapados.
--   Utilización semanal = horas de la semana / capacidad (HORAS_JORNADA x DIAS_LABORABLES_SEMANA, por defecto 8 x 6 = 48 h):
--     sobrecarga > 100 % · alta >= 90 % · óptimo >= 60 % · baja > 0 % · libre.
--   Los servicios finalizados de la semana mostrada también cuentan en la carga y el calendario (días ya trabajados).
--   Servicios hoy = programados para hoy que no se cancelaron (incluye los que están en curso y los ya finalizados).
--   Técnico disponible = de la plantilla y sin ningún servicio pendiente hoy (como principal ni como apoyo).
--   Alerta SSOMA: última versión de un documento aprobado, cargado o vencido que vence dentro de DIAS_ALERTA_SSOMA días
--   (o ya venció) en una OS/OM activa.
--   Los parámetros salen de PARAMETRO_PROGRAMACION (migración 85); sin ellos se usan los valores por defecto.
-- Resultados: 1 mensaje, 2 tarjetas (con la semana y la capacidad), 3 calendario (una fila por servicio y persona asignada),
--   4 carga por técnico y día, 5 carga por técnico en la semana, 6 alertas (conflictos, reprogramaciones y SSOMA).
DROP PROCEDURE IF EXISTS SP_ObtenerResumenProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenProgramacion(
    IN p_id_usuario   BIGINT,
    IN p_fecha_semana DATE,
    IN p_busqueda     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_param       DECIMAL(18,6);
    DECLARE v_jornada     DECIMAL(5,1) DEFAULT 8;
    DECLARE v_capacidad   DECIMAL(5,1) DEFAULT 48;
    DECLARE v_dias_ssoma  INT          DEFAULT 7;
    DECLARE v_fecha       DATE;
    DECLARE v_inicio      DATE;
    DECLARE v_fin         DATE;
    DECLARE v_inicio_hoy  DATE;
    DECLARE v_plantilla   INT          DEFAULT 0;
    DECLARE v_disponibles INT          DEFAULT 0;
    DECLARE v_finalizados INT          DEFAULT 0;
    DECLARE v_busqueda    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la programación operativa.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('HORAS_JORNADA', 8, v_param);
    SET v_jornada    = IF(v_param BETWEEN 1 AND 24, v_param, 8);
    CALL SP_LeerParametroProgramacion('DIAS_LABORABLES_SEMANA', 6, v_param);
    SET v_capacidad  = v_jornada * IF(v_param BETWEEN 1 AND 7, ROUND(v_param), 6);
    CALL SP_LeerParametroProgramacion('DIAS_ALERTA_SSOMA', 7, v_param);
    SET v_dias_ssoma = IF(v_param BETWEEN 0 AND 90, ROUND(v_param), 7);

    SET v_fecha      = IFNULL(p_fecha_semana, CURDATE());
    SET v_inicio     = DATE_SUB(v_fecha, INTERVAL WEEKDAY(v_fecha) DAY);
    SET v_fin        = DATE_ADD(v_inicio, INTERVAL 6 DAY);
    SET v_inicio_hoy = DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY);
    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));

    CALL SP_ArmarBaseProgramacion(v_inicio, v_fin);

    SELECT COUNT(*) INTO v_plantilla FROM tmp_prog_tecnicos;

    SELECT COUNT(*) INTO v_disponibles
    FROM tmp_prog_tecnicos t
    WHERE NOT EXISTS (SELECT 1 FROM tmp_prog_asig s
                      WHERE s.id_usuario = t.id_usuario AND s.fecha_ejecucion = CURDATE()
                        AND s.estado <> 'finalizada');

    -- Finalizados hoy (la base solo los trae si hoy cae en la semana mostrada)
    SELECT COUNT(*) INTO v_finalizados
    FROM orden_servicio os
    WHERE os.eliminado_en IS NULL AND os.estado = 'finalizada' AND os.fecha_ejecucion = CURDATE();

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Tarjetas
    SELECT
        v_inicio                                                                         AS inicio_semana,
        v_fin                                                                            AS fin_semana,
        v_capacidad                                                                      AS capacidad_semanal_horas,
        v_jornada                                                                        AS capacidad_diaria_horas,
        IFNULL(SUM(b.fecha_ejecucion = CURDATE() AND b.estado NOT IN ('emitida', 'finalizada')), 0)
          + v_finalizados                                                                AS servicios_hoy,
        IFNULL(SUM(b.fecha_ejecucion = CURDATE()
                   AND b.estado IN ('en_ruta', 'en_ejecucion', 'pausada')), 0)           AS en_ejecucion_hoy,
        v_finalizados                                                                    AS finalizados_hoy,
        IFNULL(SUM(b.sub_estado = 'pendiente_programar'), 0)                             AS pendientes_programar,
        IFNULL(SUM(b.sub_estado = 'pendiente_conf_cliente'), 0)                          AS pendientes_conf_cliente,
        IFNULL(SUM(b.sub_estado = 'pendiente_reprogramacion'), 0)                        AS pendientes_reprogramacion,
        IFNULL(SUM(b.sub_estado = 'pendiente_ssoma'), 0)                                 AS pendientes_ssoma,
        IFNULL(SUM(b.sub_estado IN ('pendiente_programar', 'pendiente_conf_cliente',
                                    'pendiente_reprogramacion', 'pendiente_ssoma')), 0)  AS total_pendientes,
        IFNULL(SUM(b.sub_estado = 'programado'), 0)                                      AS programados,
        IFNULL(SUM(b.sub_estado = 'programado'
                   AND b.fecha_ejecucion BETWEEN v_inicio_hoy AND DATE_ADD(v_inicio_hoy, INTERVAL 6 DAY)), 0) AS programados_semana,
        IFNULL(SUM(b.en_conflicto = 1), 0)                                               AS con_conflicto,
        v_disponibles                                                                    AS tecnicos_disponibles,
        v_plantilla                                                                      AS plantilla_tecnicos
    FROM tmp_prog_base b;

    -- 3. Calendario: una fila por servicio de la semana y persona asignada (principal o apoyo)
    SELECT b.id_os, b.tipo, b.numero, b.estado, b.sub_estado,
           b.id_programacion,
           s.id_usuario                        AS id_tecnico,
           s.nombre                            AS tecnico,
           s.rol,
           b.tecnico                           AS tecnico_principal,
           b.fecha_ejecucion,
           TIME_FORMAT(b.hora_inicio, '%H:%i') AS hora_inicio,
           TIME_FORMAT(b.hora_fin, '%H:%i')    AS hora_fin,
           b.horas,
           b.razon_social                      AS cliente,
           b.sede,
           b.tipo_servicio,
           b.en_conflicto,
           b.confirmacion_cliente
    FROM tmp_prog_asig s
    JOIN tmp_prog_base b ON b.id_os = s.id_os
    WHERE b.fecha_ejecucion BETWEEN v_inicio AND v_fin
      AND (v_busqueda = ''
           OR b.numero       LIKE CONCAT('%', v_busqueda, '%')
           OR b.razon_social LIKE CONCAT('%', v_busqueda, '%')
           OR b.ruc          LIKE CONCAT('%', v_busqueda, '%')
           OR s.nombre       LIKE CONCAT('%', v_busqueda, '%')
           OR b.tecnico      LIKE CONCAT('%', v_busqueda, '%'))
    ORDER BY b.fecha_ejecucion, b.hora_inicio, b.id_os, (s.rol = 'apoyo'), s.nombre;

    -- 4. Carga por técnico y día (los 7 días de la semana, también los libres)
    SELECT x.id_usuario, x.nombre, x.cargo, x.tipo_recurso, x.sede_operativa_nombre,
           x.fecha, x.horas, x.conflicto, x.servicios,
           CASE WHEN x.conflicto = 1 OR x.horas > 10 THEN 'sobrecarga'
                WHEN x.horas > 8                     THEN 'alta'
                WHEN x.horas >= 6                    THEN 'optimo'
                WHEN x.horas > 0                     THEN 'baja'
                ELSE 'libre'
           END AS nivel
    FROM (
        SELECT t.id_usuario, t.nombre, t.cargo, t.tipo_recurso, t.sede_operativa_nombre,
               DATE_ADD(v_inicio, INTERVAL d.n DAY)  AS fecha,
               IFNULL(ROUND(SUM(s.horas), 2), 0)     AS horas,
               IF(MAX(cu.id_usuario) IS NULL, 0, 1)  AS conflicto,
               COUNT(s.id_os)                        AS servicios
        FROM tmp_prog_tecnicos t
        CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6) d
        LEFT JOIN tmp_prog_asig s ON s.id_usuario = t.id_usuario
                                 AND s.fecha_ejecucion = DATE_ADD(v_inicio, INTERVAL d.n DAY)
        LEFT JOIN tmp_prog_conf_ud cu ON cu.id_usuario = t.id_usuario
                                     AND cu.fecha_ejecucion = DATE_ADD(v_inicio, INTERVAL d.n DAY)
        GROUP BY t.id_usuario, t.nombre, t.cargo, t.tipo_recurso, t.sede_operativa_nombre, d.n
    ) x
    ORDER BY x.nombre, x.id_usuario, x.fecha;

    -- 5. Carga por técnico en la semana
    SELECT y.id_usuario, y.total_horas, y.utilizacion_pct,
           CASE WHEN y.utilizacion_pct > 100 THEN 'sobrecarga'
                WHEN y.utilizacion_pct >= 90 THEN 'alta'
                WHEN y.utilizacion_pct >= 60 THEN 'optimo'
                WHEN y.utilizacion_pct > 0   THEN 'baja'
                ELSE 'libre'
           END AS nivel
    FROM (
        SELECT t.id_usuario,
               IFNULL(ROUND(SUM(s.horas), 2), 0)                              AS total_horas,
               ROUND(IFNULL(SUM(s.horas), 0) / v_capacidad * 100)             AS utilizacion_pct
        FROM tmp_prog_tecnicos t
        LEFT JOIN tmp_prog_asig s ON s.id_usuario = t.id_usuario
                                 AND s.fecha_ejecucion BETWEEN v_inicio AND v_fin
        GROUP BY t.id_usuario
    ) y;

    -- 6. Alertas: conflictos de horario, reprogramaciones pendientes y SSOMA por vencer
    SELECT z.tipo, z.severidad, z.titulo, z.detalle, z.id_usuario, z.id_os, z.id_os_2, z.fecha, z.cantidad
    FROM (
        SELECT 'conflicto'  AS tipo,
               'critica'    AS severidad,
               a.nombre     AS titulo,
               CONCAT('Solapamiento ', DATE_FORMAT(a.fecha_ejecucion, '%d/%m'), ' ',
                      TIME_FORMAT(GREATEST(a.hora_inicio, b.hora_inicio), '%H:%i'), '-',
                      TIME_FORMAT(LEAST(a.hora_fin, b.hora_fin), '%H:%i'),
                      ' (', a.numero, ' y ', b.numero, ')') AS detalle,
               a.id_usuario AS id_usuario,
               a.id_os      AS id_os,
               b.id_os      AS id_os_2,
               a.fecha_ejecucion AS fecha,
               2            AS cantidad
        FROM tmp_prog_a a
        JOIN tmp_prog_b b ON b.id_usuario = a.id_usuario
                         AND b.fecha_ejecucion = a.fecha_ejecucion
                         AND a.id_os < b.id_os
                         AND a.hora_inicio < b.hora_fin
                         AND b.hora_inicio < a.hora_fin
        UNION ALL
        SELECT 'reprogramacion',
               'advertencia',
               os.numero,
               CONCAT('Solicitud de reprogramación pendiente: ', IFNULL(DATE_FORMAT(rp.fecha_actual, '%d/%m'), '-'),
                      ' a ', DATE_FORMAT(rp.fecha_propuesta, '%d/%m'),
                      ' (', IFNULL(NULLIF(TRIM(CONCAT(IFNULL(us.nombre, ''), ' ', IFNULL(us.apellido, ''))), ''), 'sin solicitante'), ')'),
               rp.id_solicitante,
               os.id_os,
               NULL,
               rp.fecha_propuesta,
               1
        FROM os_reprogramacion rp
        JOIN orden_servicio os ON os.id_os = rp.id_os AND os.eliminado_en IS NULL
        LEFT JOIN usuario us   ON us.id_usuario = rp.id_solicitante
        WHERE rp.estado = 'pendiente' AND rp.eliminado_en IS NULL
        UNION ALL
        SELECT 'ssoma',
               'advertencia',
               MAX(NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '')),
               CONCAT('Habilitación SSOMA ', IF(d.fecha_vencimiento < CURDATE(), 'vencida', 'por vencer'),
                      ' (', IFNULL(MAX(rq.String1), 'documento'), ' ', DATE_FORMAT(d.fecha_vencimiento, '%d/%m'), ') con ',
                      COUNT(DISTINCT d.id_os),
                      IF(COUNT(DISTINCT d.id_os) = 1, ' programación activa', ' programaciones activas')),
               d.id_usuario,
               MIN(d.id_os),
               NULL,
               d.fecha_vencimiento,
               COUNT(DISTINCT d.id_os)
        FROM ssoma_documento d
        JOIN orden_servicio os ON os.id_os = d.id_os AND os.eliminado_en IS NULL
                              AND os.estado IN ('emitida', 'programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
        LEFT JOIN usuario u        ON u.id_usuario = d.id_usuario
        LEFT JOIN tabla_maestra rq ON rq.IdMaestro = 36 AND rq.IdEmpresa = 1 AND rq.Num1 = d.id_requisito
        WHERE d.eliminado_en IS NULL
          AND d.fecha_vencimiento IS NOT NULL
          AND d.fecha_vencimiento <= DATE_ADD(CURDATE(), INTERVAL v_dias_ssoma DAY)
          AND d.estado IN ('aprobado', 'cargado', 'vencido')
          AND NOT EXISTS (SELECT 1 FROM ssoma_documento sn
                          WHERE sn.id_os = d.id_os AND sn.id_usuario = d.id_usuario
                            AND sn.id_requisito = d.id_requisito AND sn.eliminado_en IS NULL
                            AND (sn.version > d.version
                                 OR (sn.version = d.version AND sn.id_ssoma_doc > d.id_ssoma_doc)))
        GROUP BY d.id_usuario, d.id_requisito, d.fecha_vencimiento
    ) z
    ORDER BY FIELD(z.tipo, 'conflicto', 'reprogramacion', 'ssoma'), z.fecha, z.id_os
    LIMIT 50;

    CALL SP_LimpiarBaseProgramacion();
END$$

DELIMITER ;
