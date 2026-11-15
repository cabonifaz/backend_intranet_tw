-- ============================================================
-- SP_ObtenerServiciosProgramadosMovil  (App Mobile HU-03 — Agenda de servicios)
-- Lista de servicios (OS) del técnico que inició sesión, para la app de campo.
--   p_filtro   : 'todos' | 'hoy' | 'pendientes' | 'en_ejecucion'   (vacío = todos)
--   p_busqueda : texto libre sobre N° de OS, RQ, OM o cliente     (vacío = sin filtro)
-- Mismo universo que el menú (HU-02): OS vigentes desde hoy (o en curso) donde el
-- técnico es principal o integra el personal (os_personal).
-- Estado general de la tarjeta:
--   BLOQUEADO : OS bloqueada, expediente con bloqueo sin resolver o SSOMA bloqueado.
--   LISTO     : llegó el día programado (hoy o antes: servicio en curso o atrasado).
--   PENDIENTE : programado para una fecha posterior a hoy.
--   (Cliente confirmado y SSOMA se muestran aparte en la tarjeta; no cambian LISTO/PENDIENTE.)
-- "Hoy" = fecha de Lima (UTC-5), calculada desde UTC; es la misma regla de SP_ObtenerSalidaHabilitadaMovil.
-- La regla de BLOQUEADO está también en SP_ObtenerBloqueoServicioMovil (la usa el detalle): si se cambia, cambiar las dos.
-- Datos de la programación operativa (intranet, HU-36/38): horario inicio–fin, tipo de servicio, cantidad de técnicos y
--   objetivos = equipos que se confirmaron en la programación vigente (sin selección, todos los equipos de la OS).
-- alerta_predictiva: texto de la alerta sin resolver de mayor prioridad (máx. 120 caracteres); alertas_predictivas, la cantidad.
--   No se listan los servicios ya CERRADOS (constancia firmada y cerrada: os_constancia.cerrada_en), aunque la OS siga programada/en curso en el sistema.
-- Solo lectura. Usa CTE (sin tablas temporales).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerServiciosProgramadosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerServiciosProgramadosMovil(
    IN p_id_usuario BIGINT,
    IN p_filtro     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_filtro   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hoy      DATE;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy      = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    SET v_filtro   = LOWER(TRIM(IFNULL(p_filtro, '')));
    SET v_busqueda = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');

    IF v_filtro NOT IN ('', 'todos', 'hoy', 'pendientes', 'en_ejecucion') THEN
        SELECT 1 AS IdTipoMensaje, 'Filtro no válido. Use todos, hoy, pendientes o en_ejecucion.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    WITH os_tecnico AS (
        SELECT os.*
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
          AND  NOT EXISTS (SELECT 1 FROM os_constancia k WHERE k.id_os = os.id_os AND k.cerrada_en IS NOT NULL)
          AND  (os.fecha_ejecucion >= v_hoy OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ),
    -- Objetivos: equipos de la OS confirmados en la programación vigente; sin selección (o sin programación), todos.
    objetivos AS (
        SELECT oe.id_os, oe.id_equipo
        FROM   os_equipo oe
        JOIN   os_tecnico o ON o.id_os = oe.id_os
        WHERE  oe.eliminado_en IS NULL
          AND  (NOT EXISTS (SELECT 1 FROM programacion_equipo pe
                            JOIN   programacion pr ON pr.id_programacion = pe.id_programacion
                            WHERE  pr.id_os = oe.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
                              AND  pe.eliminado_en IS NULL)
                OR EXISTS (SELECT 1 FROM programacion_equipo pe
                           JOIN   programacion pr ON pr.id_programacion = pe.id_programacion
                           WHERE  pr.id_os = oe.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
                             AND  pe.eliminado_en IS NULL AND pe.id_equipo = oe.id_equipo))
    ),
    detalle AS (
        SELECT os.id_os,
               os.numero                                                   AS numero_os,
               rq.numero                                                   AS numero_rq,
               (SELECT om.numero FROM orden_metrologia om
                WHERE  om.id_os = os.id_os AND om.eliminado_en IS NULL
                ORDER BY om.id_om LIMIT 1)                                 AS numero_om,
               COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)    AS cliente,
               os.fecha_ejecucion,
               TIME_FORMAT(os.hora_inicio, '%H:%i')                        AS hora_inicio,
               TIME_FORMAT(os.hora_fin_estimada, '%H:%i')                  AS hora_fin,
               os.estado                                                   AS estado_os,
               s.nombre                                                    AS sede,
               (SELECT t.String1 FROM tabla_maestra t
                WHERE  t.Descripcion = 'TIPO_SERVICIO' AND t.IdEmpresa = 1 AND t.Num1 = os.id_tipo_servicio
                ORDER BY t.IdMaestro DESC LIMIT 1)                         AS tipo_servicio,
               TRIM(CONCAT(IFNULL(tp.nombre, ''), ' ', IFNULL(tp.apellido, ''))) AS responsable,
               (SELECT COUNT(*) FROM os_personal op
                WHERE  op.id_os = os.id_os AND op.eliminado_en IS NULL)
               + IF(os.id_tecnico_principal IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM os_personal op
                                    WHERE  op.id_os = os.id_os AND op.id_usuario = os.id_tecnico_principal
                                      AND  op.eliminado_en IS NULL), 1, 0) AS n_tecnicos,
               (SELECT COUNT(*) FROM objetivos ob WHERE ob.id_os = os.id_os) AS objetivos_total,
               (SELECT COUNT(DISTINCT ob.id_equipo) FROM objetivos ob
                JOIN   informe_tecnico it
                       ON it.id_os = os.id_os AND it.id_equipo = ob.id_equipo AND it.eliminado_en IS NULL
                      AND it.estado IN ('pendiente_revision', 'en_revision', 'aprobado')
                WHERE  ob.id_os = os.id_os)                                 AS objetivos_completados,
               os.confirmacion_cliente                                     AS cliente_confirmado,
               -- SSOMA: el del técnico en esta OS; si no figura en os_personal, el peor del equipo
               COALESCE(
                   (SELECT op.estado_ssoma FROM os_personal op
                    WHERE  op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
                   (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                                WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                                WHEN COUNT(*) > 0 THEN 'habilitado' END
                    FROM   os_personal op WHERE op.id_os = os.id_os AND op.eliminado_en IS NULL),
                   'pendiente')                                            AS estado_ssoma,
               (SELECT COUNT(*) FROM alerta_predictiva ap
                WHERE  ap.id_os = os.id_os AND ap.resuelta = 0 AND ap.eliminado_en IS NULL) AS alertas_predictivas,
               (SELECT LEFT(ap.descripcion, 120) FROM alerta_predictiva ap
                WHERE  ap.id_os = os.id_os AND ap.resuelta = 0 AND ap.eliminado_en IS NULL
                ORDER BY ap.id_prioridad DESC, ap.fecha_generacion DESC LIMIT 1) AS alerta_predictiva,
               (SELECT eb.descripcion FROM expediente_bloqueador eb
                WHERE  eb.id_expediente = os.id_expediente AND eb.resuelto = 0
                  AND  eb.clase = 'bloqueo' AND eb.eliminado_en IS NULL
                ORDER BY eb.id_bloqueador LIMIT 1)                         AS bloqueo_expediente
        FROM   os_tecnico os
        LEFT JOIN cliente            c  ON c.id_cliente      = os.id_cliente
        LEFT JOIN sede_cliente       s  ON s.id_sede         = os.id_sede
        LEFT JOIN usuario            tp ON tp.id_usuario     = os.id_tecnico_principal
        LEFT JOIN expediente_digital ed ON ed.id_expediente  = os.id_expediente
        LEFT JOIN requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    ),
    con_estado AS (
        SELECT d.*,
               CASE
                   WHEN d.estado_os = 'bloqueada' OR d.bloqueo_expediente IS NOT NULL OR d.estado_ssoma = 'bloqueado'
                       THEN 'BLOQUEADO'
                   WHEN d.fecha_ejecucion <= v_hoy
                       THEN 'LISTO'
                   ELSE 'PENDIENTE'
               END AS estado_general,
               CASE
                   WHEN d.bloqueo_expediente IS NOT NULL THEN d.bloqueo_expediente
                   WHEN d.estado_ssoma = 'bloqueado'     THEN 'SSOMA bloqueado'
                   WHEN d.estado_os = 'bloqueada'        THEN 'Servicio bloqueado'
               END AS motivo_bloqueo
        FROM   detalle d
    )
    SELECT id_os, numero_os, numero_rq, numero_om, cliente, fecha_ejecucion, hora_inicio, estado_os,
           sede, responsable, objetivos_total, objetivos_completados, cliente_confirmado, estado_ssoma,
           alertas_predictivas, estado_general, motivo_bloqueo, hora_fin, tipo_servicio, n_tecnicos, alerta_predictiva
    FROM   con_estado
    WHERE  (v_filtro IN ('', 'todos')
            OR (v_filtro = 'hoy'          AND fecha_ejecucion = v_hoy)
            OR (v_filtro = 'pendientes'   AND estado_general = 'PENDIENTE')
            OR (v_filtro = 'en_ejecucion' AND estado_os IN ('en_ruta', 'en_ejecucion', 'pausada')))
      AND  (v_busqueda IS NULL
            OR numero_os LIKE CONCAT('%', v_busqueda, '%')
            OR numero_rq LIKE CONCAT('%', v_busqueda, '%')
            OR numero_om LIKE CONCAT('%', v_busqueda, '%')
            OR cliente   LIKE CONCAT('%', v_busqueda, '%'))
    ORDER BY (estado_os IN ('en_ruta', 'en_ejecucion', 'pausada')) DESC, fecha_ejecucion, hora_inicio;
END$$

DELIMITER ;
-- ============================================================
-- SP_ObtenerResumenMenuMovil  (App Mobile HU-02 — Menú principal)
-- Indicadores del menú de la app para el técnico que inició sesión:
--   1) servicios_asignados : OS vigentes (hoy en adelante) donde es técnico
--                            principal o integra el personal (os_personal).
--   2) servicios_hoy       : de esas, las programadas para hoy (Ruta del Día).
--   3) Próximo servicio    : la OS en curso o la siguiente por fecha y hora
--                            (banner "Próximo Hit"). 0 filas si no hay.
--   4) Viáticos y Gastos   : saldo por rendir (viáticos activos), cantidad de viáticos activos y gastos en revisión
--                            (monto y cantidad). Las reglas están en SP_ObtenerViaticosUsuarioMovil (se leen en el
--                            mismo resultado de indicadores: viaticos_saldo, viaticos_activos, gastos_revision_monto, gastos_revision_n).
-- Fechas en hora de Lima (CURDATE / NOW, migración 63).
-- Solo lectura; no modifica datos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerResumenMenuMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenMenuMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_vi_saldo   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_vi_activos INT DEFAULT 0;
    DECLARE v_vi_final   INT DEFAULT 0;
    DECLARE v_gs_monto   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_gs_n       INT DEFAULT 0;
    DECLARE v_gs_obs     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El indicador de viáticos no debe tumbar el menú: si falla, esos números quedan en 0 y el resto del menú se muestra.
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET v_vi_saldo = 0, v_vi_activos = 0, v_gs_monto = 0, v_gs_n = 0;
        END;
        CALL SP_ObtenerViaticosUsuarioMovil(p_id_usuario, v_vi_saldo, v_vi_activos, v_vi_final, v_gs_monto, v_gs_n, v_gs_obs);
    END;
    DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- Indicadores
    WITH os_tecnico AS (
        SELECT os.fecha_ejecucion
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
          AND  NOT EXISTS (SELECT 1 FROM os_constancia k WHERE k.id_os = os.id_os AND k.cerrada_en IS NOT NULL)
          AND  (os.fecha_ejecucion >= CURDATE() OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    )
    SELECT COUNT(*)                                       AS servicios_asignados,
           COALESCE(SUM(fecha_ejecucion = CURDATE()), 0)  AS servicios_hoy,
           v_vi_saldo                                     AS viaticos_saldo,
           v_vi_activos                                   AS viaticos_activos,
           v_gs_monto                                     AS gastos_revision_monto,
           v_gs_n                                         AS gastos_revision_n
    FROM   os_tecnico;

    -- Próximo servicio (en curso primero; luego el más cercano por fecha y hora)
    SELECT os.id_os,
           os.numero,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente,
           s.nombre                                                 AS sede,
           s.distrito                                               AS distrito,
           ts.String1                                               AS tipo_servicio,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                     AS hora_inicio,
           os.estado
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente s  ON s.id_sede    = os.id_sede
    LEFT JOIN tabla_maestra ts
           ON ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
          AND ts.IdMaestro = (SELECT MAX(x.IdMaestro) FROM tabla_maestra x
                              WHERE x.Descripcion = 'TIPO_SERVICIO' AND x.IdEmpresa = 1)
    WHERE  os.eliminado_en IS NULL
      AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
      AND  NOT EXISTS (SELECT 1 FROM os_constancia k WHERE k.id_os = os.id_os AND k.cerrada_en IS NOT NULL)
      AND  (os.fecha_ejecucion >= CURDATE() OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ORDER BY (os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')) DESC,
             os.fecha_ejecucion, os.hora_inicio
    LIMIT 1;
END$$

DELIMITER ;
