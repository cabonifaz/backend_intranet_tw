-- HU-35 (Sprint 5) Base común de la Programación Operativa. Ayuda interna: NO devuelve resultados. Solo lee datos.
-- La llaman SP_ObtenerResumenProgramacion, SP_ObtenerPendientesProgramacion y SP_ObtenerProgramadosProgramacion,
-- que al terminar ejecutan SP_LimpiarBaseProgramacion.
--   p_desde / p_hasta: ventana en la que también se incluyen los servicios FINALIZADOS (la semana del resumen), para que
--                      la carga y el calendario de días ya trabajados no queden en cero. NULL = sin finalizados (listas).
-- Tablas temporales de la sesión (MySQL no permite usar dos veces la misma temporal en una consulta, de ahí las copias):
--   tmp_prog_tecnicos : plantilla de técnicos: usuario activo de servicio técnico o metrología, sin jefaturas ni
--                       asistentes (un técnico sin cargo también cuenta). tipo_recurso: metrologo o tecnico.
--   tmp_prog_base     : una fila por OS/OM activa (de emitida a bloqueada, más las finalizadas de la ventana) con su
--                       sub-estado de programación, el técnico principal y los nombres del personal de apoyo
--   tmp_prog_asig     : una fila por OS/OM programada y persona asignada (principal o apoyo de os_personal): la carga,
--                       el calendario, la disponibilidad y los conflictos cuentan también al personal de apoyo
--   tmp_prog_a / _b   : copias de las asignaciones con horario, de hoy en adelante (para detectar solapamientos)
--   tmp_prog_conf_os  : OS/OM con algún asignado cuyo horario se cruza con otra suya el mismo día
--   tmp_prog_conf_ud  : técnico y día con horarios cruzados (para la matriz de carga)
-- sub_estado (excluyentes, en este orden de prioridad):
--   pendiente_reprogramacion  programada, sin confirmación del cliente y con una solicitud de reprogramación pendiente
--                             (os_reprogramacion). Si ya está confirmada, la solicitud no la saca de Programados.
--   pendiente_ssoma           programada y una validación SSOMA la bloquea: personal con SSOMA pendiente o bloqueado,
--                             última versión de un documento observada o vencida, documento que vence antes del día del
--                             servicio, o bloqueo SSOMA abierto en el expediente (ssoma_motivo dice cuál)
--   pendiente_programar       OS/OM emitida que todavía no tiene programación
--   pendiente_conf_cliente    programada internamente, falta la confirmación del cliente
--   programado                programada y confirmada por el cliente (lista para ejecutar)
--   en_curso                  en ruta, en ejecución, pausada o bloqueada
--   finalizado                finalizada (solo dentro de la ventana p_desde / p_hasta)
-- Requiere la migración 85.
DROP PROCEDURE IF EXISTS SP_ArmarBaseProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ArmarBaseProgramacion(
    IN p_desde DATE,
    IN p_hasta DATE
)
BEGIN
    CALL SP_LimpiarBaseProgramacion();

    -- Plantilla de técnicos
    CREATE TEMPORARY TABLE tmp_prog_tecnicos AS
    SELECT u.id_usuario,
           TRIM(CONCAT(u.nombre, ' ', u.apellido))                                   AS nombre,
           COALESCE(c.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')) AS cargo,
           u.area,
           IF(u.area = 'metrologia' OR IFNULL(u.cargo, '') LIKE 'metrologo%', 'metrologo', 'tecnico') AS tipo_recurso,
           u.sede_operativa,
           so.String1                                                                AS sede_operativa_nombre
    FROM usuario u
    LEFT JOIN tabla_maestra c  ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    LEFT JOIN tabla_maestra so ON so.IdMaestro = 69 AND so.IdEmpresa = 1 AND so.String2 = u.sede_operativa
    WHERE u.eliminado_en IS NULL
      AND u.estado = 'activo'
      AND u.area IN ('servicio_tecnico', 'metrologia')
      AND (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'));

    -- OS/OM activas con sus datos de programación
    CREATE TEMPORARY TABLE tmp_prog_raw AS
    SELECT os.id_os,
           os.tipo,
           os.numero,
           os.estado,
           os.id_expediente,
           os.id_cliente,
           c.razon_social,
           c.ruc,
           os.id_sede,
           sc.nombre                                                                    AS sede,
           NULLIF(TRIM(sc.region), '')                                                  AS zona,
           COALESCE(os.id_propuesta, e.id_propuesta)                                    AS id_propuesta,
           p.numero                                                                     AS numero_propuesta,
           p.version                                                                    AS version_propuesta,
           r.numero                                                                     AS numero_requerimiento,
           r.id_area                                                                    AS id_area,
           ar.String1                                                                   AS area,
           os.id_tipo_servicio,
           ts.String1                                                                   AS tipo_servicio,
           os.id_tecnico_principal                                                      AS id_tecnico,
           NULLIF(TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))), '') AS tecnico,
           (SELECT GROUP_CONCAT(DISTINCT TRIM(CONCAT(ua.nombre, ' ', ua.apellido)) ORDER BY ua.nombre SEPARATOR ', ')
            FROM os_personal pa
            JOIN usuario ua ON ua.id_usuario = pa.id_usuario
            WHERE pa.id_os = os.id_os AND pa.eliminado_en IS NULL
              AND pa.id_usuario <> IFNULL(os.id_tecnico_principal, 0))                  AS tecnicos_apoyo,
           (SELECT COUNT(DISTINCT pa2.id_usuario) FROM os_personal pa2
            WHERE pa2.id_os = os.id_os AND pa2.eliminado_en IS NULL
              AND pa2.id_usuario <> IFNULL(os.id_tecnico_principal, 0))
             + IF(os.id_tecnico_principal IS NULL, 0, 1)                                AS n_tecnicos,
           os.fecha_ejecucion,
           os.hora_inicio,
           os.hora_fin_estimada                                                         AS hora_fin,
           CASE WHEN os.hora_inicio IS NOT NULL AND os.hora_fin_estimada IS NOT NULL
                     AND os.hora_fin_estimada > os.hora_inicio
                THEN ROUND(TIME_TO_SEC(TIMEDIFF(os.hora_fin_estimada, os.hora_inicio)) / 3600, 2)
           END                                                                          AS horas,
           os.fecha_programada_desde,
           os.fecha_programada_hasta,
           os.confirmacion_cliente,
           os.fecha_confirmacion_cliente,
           COALESCE(os.fecha_emision, os.creado_en)                                     AS fecha_emision,
           (SELECT MAX(pr.id_programacion) FROM programacion pr
            WHERE pr.id_os = os.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL)  AS id_programacion,
           (SELECT MAX(pr.codigo) FROM programacion pr
            WHERE pr.id_os = os.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL)  AS codigo_programacion,
           (SELECT MAX(rp.id_reprogramacion) FROM os_reprogramacion rp
            WHERE rp.id_os = os.id_os AND rp.estado = 'pendiente' AND rp.eliminado_en IS NULL) AS id_reprogramacion_pendiente,
           -- Motivo SSOMA (solo para órdenes programadas; NULL = nada bloquea)
           IF(os.estado NOT IN ('programada', 'reprogramada'), NULL,
              COALESCE(
                  (SELECT CONCAT('SSOMA ', pe.estado_ssoma, ': ', TRIM(CONCAT(up.nombre, ' ', up.apellido)))
                   FROM os_personal pe
                   JOIN usuario up ON up.id_usuario = pe.id_usuario
                   WHERE pe.id_os = os.id_os AND pe.eliminado_en IS NULL
                     AND pe.estado_ssoma IN ('pendiente', 'bloqueado')
                   ORDER BY (pe.estado_ssoma = 'bloqueado') DESC, pe.id
                   LIMIT 1),
                  (SELECT CONCAT(IFNULL(td.String1, 'Documento SSOMA'), ' ',
                                 CASE WHEN sd.estado = 'observado' THEN 'observado'
                                      WHEN sd.estado = 'vencido'   THEN 'vencido'
                                      ELSE CONCAT('vence el ', DATE_FORMAT(sd.fecha_vencimiento, '%d/%m/%Y'), ', antes del servicio')
                                 END,
                                 ': ', TRIM(CONCAT(ud.nombre, ' ', ud.apellido)))
                   FROM ssoma_documento sd
                   JOIN usuario ud            ON ud.id_usuario = sd.id_usuario
                   LEFT JOIN tabla_maestra td ON td.IdMaestro = 36 AND td.IdEmpresa = 1 AND td.Num1 = sd.id_requisito
                   WHERE sd.id_os = os.id_os AND sd.eliminado_en IS NULL
                     -- solo la última versión de cada documento (una renovación reemplaza a la vencida)
                     AND NOT EXISTS (SELECT 1 FROM ssoma_documento sn
                                     WHERE sn.id_os = sd.id_os AND sn.id_usuario = sd.id_usuario
                                       AND sn.id_requisito = sd.id_requisito AND sn.eliminado_en IS NULL
                                       AND (sn.version > sd.version
                                            OR (sn.version = sd.version AND sn.id_ssoma_doc > sd.id_ssoma_doc)))
                     AND (sd.estado IN ('observado', 'vencido')
                          OR (sd.estado IN ('aprobado', 'cargado') AND sd.fecha_vencimiento IS NOT NULL
                              AND os.fecha_ejecucion IS NOT NULL AND sd.fecha_vencimiento < os.fecha_ejecucion))
                   ORDER BY sd.id_ssoma_doc
                   LIMIT 1),
                  (SELECT CONCAT('Bloqueo SSOMA en el expediente: ', eb.descripcion)
                   FROM expediente_bloqueador eb
                   WHERE eb.id_expediente = os.id_expediente AND eb.tipo = 'ssoma'
                     AND eb.clase = 'bloqueo' AND eb.resuelto = 0 AND eb.eliminado_en IS NULL
                   ORDER BY eb.id_bloqueador
                   LIMIT 1)))                                                           AS ssoma_motivo,
           (SELECT IFNULL(SUM(gv.monto), 0) FROM gasto_viatico gv
            WHERE gv.id_os = os.id_os AND gv.tipo = 'viatico_asignado'
              AND gv.estado <> 'rechazado' AND gv.eliminado_en IS NULL)                  AS viatico_monto,
           (SELECT COUNT(*) FROM gasto_viatico gv2
            WHERE gv2.id_os = os.id_os AND gv2.tipo = 'viatico_asignado'
              AND gv2.estado IN ('pendiente', 'observado') AND gv2.eliminado_en IS NULL)  AS viatico_pendientes,
           (SELECT IFNULL(SUM(gv4.monto), 0) FROM gasto_viatico gv4
            WHERE gv4.id_os = os.id_os AND gv4.tipo = 'viatico_asignado'
              AND gv4.estado IN ('pendiente', 'observado') AND gv4.eliminado_en IS NULL)  AS viatico_pendiente_monto,
           (SELECT mo.String2 FROM gasto_viatico gv3
            JOIN tabla_maestra mo ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = gv3.id_moneda
            WHERE gv3.id_os = os.id_os AND gv3.tipo = 'viatico_asignado'
              AND gv3.estado <> 'rechazado' AND gv3.eliminado_en IS NULL
            ORDER BY gv3.id_gasto
            LIMIT 1)                                                                    AS viatico_moneda
    FROM orden_servicio os
    LEFT JOIN cliente c            ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc      ON sc.id_sede = os.id_sede
    LEFT JOIN expediente_digital e ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento r      ON r.id_requerimiento = COALESCE(os.id_requerimiento, p.id_requerimiento, e.id_requerimiento)
    LEFT JOIN tabla_maestra ar     ON ar.IdMaestro = 64 AND ar.IdEmpresa = 1 AND ar.Num1 = r.id_area
    LEFT JOIN tabla_maestra ts     ON ts.IdMaestro = 3  AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario ut           ON ut.id_usuario = os.id_tecnico_principal
    WHERE os.eliminado_en IS NULL
      AND (os.estado IN ('emitida', 'programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
           OR (os.estado = 'finalizada' AND p_desde IS NOT NULL AND p_hasta IS NOT NULL
               AND os.fecha_ejecucion BETWEEN p_desde AND p_hasta));

    CREATE TEMPORARY TABLE tmp_prog_base AS
    SELECT t.*,
           CASE
               -- Una solicitud del Asistente sobre una programación ya confirmada por el cliente NO la saca de Programados
               -- (el detalle muestra "Solicitud pendiente"); solo cuenta mientras falta la confirmación del cliente.
               WHEN t.id_reprogramacion_pendiente IS NOT NULL
                    AND t.estado IN ('programada', 'reprogramada')
                    AND t.confirmacion_cliente = 0                               THEN 'pendiente_reprogramacion'
               WHEN t.ssoma_motivo IS NOT NULL                                   THEN 'pendiente_ssoma'
               WHEN t.estado = 'emitida'                                         THEN 'pendiente_programar'
               WHEN t.estado IN ('programada', 'reprogramada')
                    AND t.confirmacion_cliente = 0                               THEN 'pendiente_conf_cliente'
               WHEN t.estado IN ('programada', 'reprogramada')                   THEN 'programado'
               WHEN t.estado = 'finalizada'                                      THEN 'finalizado'
               ELSE 'en_curso'
           END                                                                   AS sub_estado,
           0                                                                     AS en_conflicto
    FROM tmp_prog_raw t;

    DROP TEMPORARY TABLE IF EXISTS tmp_prog_raw;

    -- Asignaciones de las órdenes ya programadas (las emitidas todavía no ocupan a nadie):
    -- técnico principal + personal de apoyo
    CREATE TEMPORARY TABLE tmp_prog_asig (
        id_os           BIGINT       NOT NULL,
        id_usuario      BIGINT       NOT NULL,
        rol             VARCHAR(10)  NOT NULL,
        nombre          VARCHAR(250) NULL,
        fecha_ejecucion DATE         NULL,
        hora_inicio     TIME         NULL,
        hora_fin        TIME         NULL,
        horas           DECIMAL(8,2) NULL,
        estado          VARCHAR(20)  NOT NULL,
        PRIMARY KEY (id_os, id_usuario),
        KEY (id_usuario, fecha_ejecucion)
    );

    INSERT IGNORE INTO tmp_prog_asig (id_os, id_usuario, rol, nombre, fecha_ejecucion, hora_inicio, hora_fin, horas, estado)
    SELECT b.id_os, b.id_tecnico, 'principal', b.tecnico, b.fecha_ejecucion, b.hora_inicio, b.hora_fin, b.horas, b.estado
    FROM tmp_prog_base b
    WHERE b.id_tecnico IS NOT NULL
      AND b.estado <> 'emitida';

    INSERT IGNORE INTO tmp_prog_asig (id_os, id_usuario, rol, nombre, fecha_ejecucion, hora_inicio, hora_fin, horas, estado)
    SELECT b.id_os, pe.id_usuario, 'apoyo', TRIM(CONCAT(u.nombre, ' ', u.apellido)),
           b.fecha_ejecucion, b.hora_inicio, b.hora_fin, b.horas, b.estado
    FROM tmp_prog_base b
    JOIN os_personal pe ON pe.id_os = b.id_os AND pe.eliminado_en IS NULL
    JOIN usuario u      ON u.id_usuario = pe.id_usuario
    WHERE b.estado <> 'emitida';

    -- Asignaciones con horario completo, de hoy en adelante y no finalizadas: base para detectar solapamientos
    CREATE TEMPORARY TABLE tmp_prog_a AS
    SELECT s.id_os, b.numero, s.id_usuario, s.nombre, s.fecha_ejecucion, s.hora_inicio, s.hora_fin
    FROM tmp_prog_asig s
    JOIN tmp_prog_base b ON b.id_os = s.id_os
    WHERE s.fecha_ejecucion IS NOT NULL
      AND s.hora_inicio IS NOT NULL
      AND s.hora_fin IS NOT NULL
      AND s.hora_fin > s.hora_inicio
      AND s.fecha_ejecucion >= CURDATE()
      AND s.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');

    CREATE TEMPORARY TABLE tmp_prog_b AS
    SELECT * FROM tmp_prog_a;

    -- Misma persona, mismo día y horarios que se cruzan
    CREATE TEMPORARY TABLE tmp_prog_conf_os AS
    SELECT DISTINCT a.id_os
    FROM tmp_prog_a a
    JOIN tmp_prog_b b ON b.id_usuario = a.id_usuario
                     AND b.fecha_ejecucion = a.fecha_ejecucion
                     AND b.id_os <> a.id_os
                     AND a.hora_inicio < b.hora_fin
                     AND b.hora_inicio < a.hora_fin;

    CREATE TEMPORARY TABLE tmp_prog_conf_ud AS
    SELECT DISTINCT a.id_usuario, a.fecha_ejecucion
    FROM tmp_prog_a a
    JOIN tmp_prog_b b ON b.id_usuario = a.id_usuario
                     AND b.fecha_ejecucion = a.fecha_ejecucion
                     AND b.id_os <> a.id_os
                     AND a.hora_inicio < b.hora_fin
                     AND b.hora_inicio < a.hora_fin;

    UPDATE tmp_prog_base b
    JOIN tmp_prog_conf_os c ON c.id_os = b.id_os
    SET b.en_conflicto = 1;
END$$

DELIMITER ;
