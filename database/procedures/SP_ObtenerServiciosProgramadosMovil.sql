-- ============================================================
-- SP_ObtenerServiciosProgramadosMovil  (App Mobile HU-03 — Agenda de servicios)
-- Lista de servicios (OS) del técnico que inició sesión, para la app de campo.
--   p_filtro   : 'todos' | 'hoy' | 'pendientes' | 'en_ejecucion'   (vacío = todos)
--   p_busqueda : texto libre sobre N° de OS, RQ, OM o cliente     (vacío = sin filtro)
-- Mismo universo que el menú (HU-02): OS vigentes desde hoy (o en curso) donde el
-- técnico es principal o integra el personal (os_personal).
-- Estado general de la tarjeta:
--   BLOQUEADO : OS bloqueada, expediente con bloqueo sin resolver o SSOMA bloqueado.
--   LISTO     : cliente confirmado y SSOMA habilitado.
--   PENDIENTE : cualquier otro caso.
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

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

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
          AND  (os.fecha_ejecucion >= CURDATE() OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
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
               os.estado                                                   AS estado_os,
               s.nombre                                                    AS sede,
               TRIM(CONCAT(IFNULL(tp.nombre, ''), ' ', IFNULL(tp.apellido, ''))) AS responsable,
               (SELECT COUNT(*) FROM os_equipo oe
                WHERE  oe.id_os = os.id_os AND oe.eliminado_en IS NULL)     AS objetivos_total,
               (SELECT COUNT(DISTINCT oe.id_equipo) FROM os_equipo oe
                JOIN   informe_tecnico it
                       ON it.id_os = os.id_os AND it.id_equipo = oe.id_equipo AND it.eliminado_en IS NULL
                      AND it.estado IN ('pendiente_revision', 'en_revision', 'aprobado')
                WHERE  oe.id_os = os.id_os AND oe.eliminado_en IS NULL)     AS objetivos_completados,
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
                   WHEN d.cliente_confirmado = 1 AND d.estado_ssoma = 'habilitado'
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
           alertas_predictivas, estado_general, motivo_bloqueo
    FROM   con_estado
    WHERE  (v_filtro IN ('', 'todos')
            OR (v_filtro = 'hoy'          AND fecha_ejecucion = CURDATE())
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
