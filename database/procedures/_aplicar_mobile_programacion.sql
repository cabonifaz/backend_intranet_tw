-- App móvil: Servicios Programados refleja Programación Operativa (HU-03/HU-04). Ejecutar completo, en este orden.
-- No crea tablas ni datos: solo reemplaza 3 procedimientos (el 1.º es nuevo).

-- ============================================================
-- SP_ObtenerBloqueoServicioMovil  (App Mobile HU-03 / HU-04 — regla de bloqueo del servicio)
-- Ayuda interna: NO devuelve resultados. Dice si un servicio está BLOQUEADO para el técnico y por qué.
--   p_motivo (OUT): NULL si el servicio NO está bloqueado; si lo está, el motivo que se muestra en la tarjeta:
--     1. descripción del primer bloqueo sin resolver del expediente (clase 'bloqueo');
--     2. 'SSOMA bloqueado'  : el SSOMA del técnico en esta OS (o, si no figura en el personal, el peor del equipo);
--     3. 'Servicio bloqueado': la OS está en estado 'bloqueada'.
-- Es la misma regla de estado_general = 'BLOQUEADO' de SP_ObtenerServiciosProgramadosMovil (agenda). El detalle la usa para
-- no entregar datos de un servicio bloqueado hasta que se levante el motivo (HU-03, criterio 4).
-- Solo lee datos. Sin funciones almacenadas (exigen SUPER) ni tablas temporales.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerBloqueoServicioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBloqueoServicioMovil(
    IN  p_id_os      BIGINT,
    IN  p_id_usuario BIGINT,
    OUT p_motivo     VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ssoma     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloqueo   VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_motivo = NULL;

    SELECT os.estado INTO v_estado_os FROM orden_servicio os WHERE os.id_os = p_id_os;

    SET v_ssoma = COALESCE(
        (SELECT op.estado_ssoma FROM os_personal op
         WHERE  op.id_os = p_id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
        (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                     WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                     WHEN COUNT(*) > 0 THEN 'habilitado' END
         FROM   os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL),
        'pendiente');

    SET v_bloqueo = (SELECT eb.descripcion
                     FROM   orden_servicio os
                     JOIN   expediente_bloqueador eb ON eb.id_expediente = os.id_expediente
                     WHERE  os.id_os = p_id_os AND eb.resuelto = 0 AND eb.clase = 'bloqueo' AND eb.eliminado_en IS NULL
                     ORDER BY eb.id_bloqueador LIMIT 1);

    SET p_motivo = CASE
                       WHEN v_bloqueo IS NOT NULL      THEN v_bloqueo
                       WHEN v_ssoma = 'bloqueado'      THEN 'SSOMA bloqueado'
                       WHEN v_estado_os = 'bloqueada'  THEN 'Servicio bloqueado'
                   END;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerDetalleServicioMovil  (App Mobile HU-04 — Detalle del servicio)
-- Detalle de una OS para el técnico que inició sesión. Solo lectura.
-- Seguridad: si la OS no existe o el técnico no es principal ni integra el personal,
-- responde el MISMO mensaje (no se revela si la OS existe: evita IDOR / enumeración).
-- HU-03: un servicio BLOQUEADO no entrega su detalle hasta que se levante el motivo (misma regla que la agenda, en
--   SP_ObtenerBloqueoServicioMovil). Responde IdTipoMensaje 1 con el motivo.
-- Lo que registra la intranet en "Programación Operativa" (modal Detalle de la Programación, HU-36/37/38) se refleja aquí:
--   horario (inicio–fin y duración), código y observaciones de la programación, equipo de trabajo con su SSOMA de hoy,
--   equipos confirmados para la programación, conceptos del servicio, respuestas del cliente y la línea de tiempo.
--   No se muestran los viáticos (montos de otros técnicos) ni las acciones de gestión (reprogramar, cancelar, registrar respuesta).
--   El motivo SSOMA solo se muestra para el propio técnico; de sus compañeros solo se ve el estado.
-- Resultados (el orden de los 7 primeros no cambia; los nuevos van al final):
--   1. Encabezado (IdTipoMensaje, Mensaje)
--   2. Detalle: destino, contacto, documentos (RQ / OS / OM), horario, estado y chips
--   3. Alertas predictivas sin resolver
--   4. Riesgos identificados (os_riesgo + catálogo RIESGO_OPERATIVO)
--   5. Repuestos a llevar (item_presalida tipo REPUESTO)
--   6. Historial: cambios del equipo (equipo_historial) y del servicio y su programación (auditoria_evento),
--      cada uno con su valor anterior y actual
--   7. Documentación (adjuntos de la OS y del expediente visibles para todos)
--   8. Programación vigente de la OS (0 o 1 fila): código, estado y observaciones
--   9. Equipo de trabajo (principal primero) con cargo, rol y SSOMA actual
--  10. Equipos del servicio (los confirmados en la programación; si no hay programación, los de la OS)
--  11. Conceptos del servicio
--  12. Respuestas del cliente registradas (la más reciente primero)
-- SSOMA actual: SP_EvaluarSsomaProgramacion (la misma regla del buscador y de Programar, con la fecha del servicio).
-- Sin funciones almacenadas (exigen SUPER). Las tablas temporales se borran al terminar.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleServicioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleServicioMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_id_expediente BIGINT;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_id_sede       BIGINT;
    DECLARE v_id_contacto   BIGINT;
    DECLARE v_id_prog       BIGINT       DEFAULT NULL;
    DECLARE v_estado_os     VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha         DATE;
    DECLARE v_aplica        TINYINT      DEFAULT 0;
    DECLARE v_n_eq_prog     INT          DEFAULT 0;
    DECLARE v_bloqueo       VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        DROP TEMPORARY TABLE IF EXISTS tmp_mov_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.id_expediente, os.id_cliente, os.id_sede, os.estado, os.fecha_ejecucion
    INTO   v_id_expediente, v_id_cliente, v_id_sede, v_estado_os, v_fecha
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os
      AND  os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_id_cliente IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- HU-03: el detalle de un servicio bloqueado no se entrega hasta que se levante el motivo.
    CALL SP_ObtenerBloqueoServicioMovil(p_id_os, p_id_usuario, v_bloqueo);
    IF v_bloqueo IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Servicio bloqueado: ', v_bloqueo, '. El detalle se habilita cuando se levante el motivo.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Contacto: principal de la sede, si no el principal del cliente, si no cualquiera activo de la sede.
    SELECT c.id_contacto INTO v_id_contacto
    FROM   contacto_cliente c
    LEFT JOIN contacto_sede cs ON cs.id_contacto = c.id_contacto AND cs.id_sede = v_id_sede
    WHERE  c.id_cliente = v_id_cliente AND c.SoftDelete = 0 AND IFNULL(c.estado, 'Activo') = 'Activo'
    ORDER BY (cs.es_principal_sede = 1) DESC,
             (cs.id_sede IS NOT NULL OR c.id_sede = v_id_sede) DESC,
             (c.es_contacto_principal = 1) DESC,
             c.id_contacto
    LIMIT 1;

    -- Programación vigente de la OS (una sola activa a la vez; la regla la valida SP_CrearProgramacion).
    SELECT pr.id_programacion INTO v_id_prog
    FROM   programacion pr
    WHERE  pr.id_os = p_id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC
    LIMIT 1;

    SELECT COUNT(*) INTO v_n_eq_prog
    FROM   programacion_equipo pe
    WHERE  pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;

    -- El SSOMA solo aplica mientras la orden sigue programada y su fecha es de hoy en adelante (como en la intranet).
    SET v_aplica = IF(v_estado_os IN ('programada', 'reprogramada') AND v_fecha IS NOT NULL AND v_fecha >= CURDATE(), 1, 0);

    -- ── Equipo de trabajo y su situación SSOMA de hoy ─────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_mov_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_mov_tec (id_usuario BIGINT NOT NULL, rol VARCHAR(10) NOT NULL, PRIMARY KEY (id_usuario));
    IF v_id_prog IS NOT NULL THEN
        INSERT IGNORE INTO tmp_mov_tec (id_usuario, rol)
        SELECT pt.id_usuario, pt.rol FROM programacion_tecnico pt
        WHERE  pt.id_programacion = v_id_prog AND pt.eliminado_en IS NULL;
    ELSE
        -- OS anterior a la programación operativa: el equipo sale de la propia OS.
        INSERT IGNORE INTO tmp_mov_tec (id_usuario, rol)
        SELECT os.id_tecnico_principal, 'principal' FROM orden_servicio os
        WHERE  os.id_os = p_id_os AND os.id_tecnico_principal IS NOT NULL;
        INSERT IGNORE INTO tmp_mov_tec (id_usuario, rol)
        SELECT op.id_usuario, 'apoyo' FROM os_personal op
        WHERE  op.id_os = p_id_os AND op.eliminado_en IS NULL;
    END IF;

    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_mov_tec;
    CALL SP_EvaluarSsomaProgramacion(p_id_os, v_fecha);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Detalle
    SELECT os.id_os,
           os.numero                                                        AS numero_os,
           rq.numero                                                        AS numero_rq,
           (SELECT om.numero FROM orden_metrologia om
            WHERE  om.id_os = os.id_os AND om.eliminado_en IS NULL
            ORDER BY om.id_om LIMIT 1)                                      AS numero_om,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.id_tipo_servicio,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.Descripcion = 'TIPO_SERVICIO' AND t.IdEmpresa = 1 AND t.Num1 = os.id_tipo_servicio
            ORDER BY t.IdMaestro DESC LIMIT 1)                              AS tipo_servicio,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           TIME_FORMAT(os.hora_fin_estimada, '%H:%i')                       AS hora_fin,
           IF(os.hora_inicio IS NOT NULL AND os.hora_fin_estimada > os.hora_inicio,
              ROUND(TIME_TO_SEC(TIMEDIFF(os.hora_fin_estimada, os.hora_inicio)) / 3600, 2), NULL) AS duracion_horas,
           os.estado                                                        AS estado_os,
           s.nombre                                                         AS sede,
           NULLIF(CONCAT_WS(', ', NULLIF(s.direccion_exacta, ''), NULLIF(s.distrito, ''), NULLIF(s.provincia, '')), '') AS direccion,
           ct.nombres                                                       AS contacto_nombre,
           ct.cargo                                                         AS contacto_cargo,
           COALESCE(NULLIF(ct.telefono_movil, ''), NULLIF(ct.telefono_anexo, '')) AS contacto_telefono,
           TRIM(CONCAT(IFNULL(tp.nombre, ''), ' ', IFNULL(tp.apellido, ''))) AS responsable,
           os.confirmacion_cliente                                          AS cliente_confirmado,
           COALESCE(
               (SELECT op.estado_ssoma FROM os_personal op
                WHERE  op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
               (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                            WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                            WHEN COUNT(*) > 0 THEN 'habilitado' END
                FROM   os_personal op WHERE op.id_os = os.id_os AND op.eliminado_en IS NULL),
               'pendiente')                                                 AS estado_ssoma,
           -- Objetivos = equipos de la OS que se confirmaron en la programación (si no hay selección, todos los de la OS)
           (SELECT COUNT(*) FROM os_equipo oe
            WHERE  oe.id_os = os.id_os AND oe.eliminado_en IS NULL
              AND  (v_n_eq_prog = 0
                    OR EXISTS (SELECT 1 FROM programacion_equipo pe
                               WHERE pe.id_programacion = v_id_prog AND pe.id_equipo = oe.id_equipo
                                 AND pe.eliminado_en IS NULL)))             AS objetivos_total,
           os.notas_operativas
    FROM   orden_servicio os
    LEFT JOIN cliente            cl ON cl.id_cliente       = os.id_cliente
    LEFT JOIN sede_cliente       s  ON s.id_sede           = os.id_sede
    LEFT JOIN usuario            tp ON tp.id_usuario       = os.id_tecnico_principal
    LEFT JOIN expediente_digital ed ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN contacto_cliente   ct ON ct.id_contacto      = v_id_contacto
    WHERE  os.id_os = p_id_os;

    -- 3. Alertas predictivas sin resolver
    SELECT ap.id_alerta,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.Descripcion = 'TIPO_ALERTA_PREDICTIVA' AND t.IdEmpresa = 1 AND t.Num1 = ap.id_tipo_alerta
            ORDER BY t.IdMaestro DESC LIMIT 1)                   AS tipo,
           ap.descripcion,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.Descripcion = 'PRIORIDAD' AND t.IdEmpresa = 1 AND t.Num1 = ap.id_prioridad
            ORDER BY t.IdMaestro DESC LIMIT 1)                   AS prioridad,
           NULLIF(CONCAT_WS(' · ', e.codigo_tw, NULLIF(e.modelo, '')), '') AS equipo,
           ap.fecha_generacion
    FROM   alerta_predictiva ap
    LEFT JOIN equipo e ON e.id_equipo = ap.id_equipo
    WHERE  ap.id_os = p_id_os AND ap.resuelta = 0 AND ap.eliminado_en IS NULL
    ORDER BY ap.id_prioridad DESC, ap.fecha_generacion DESC;

    -- 4. Riesgos identificados
    SELECT r.id_riesgo,
           t.String1                                            AS nombre,
           t.String2                                            AS codigo,
           t.String3                                            AS icono,
           r.observacion
    FROM   os_riesgo r
    LEFT JOIN tabla_maestra t ON t.Descripcion = 'RIESGO_OPERATIVO' AND t.IdEmpresa = 1 AND t.Num1 = r.id_riesgo
                             AND t.eliminado_en IS NULL
    WHERE  r.id_os = p_id_os AND r.eliminado_en IS NULL
    ORDER BY r.id;

    -- 5. Repuestos a llevar (asignado = confirmado por programación / almacén)
    SELECT ip.id_item,
           ip.descripcion,
           ip.confirmado                                         AS asignado
    FROM   item_presalida ip
    WHERE  ip.id_os = p_id_os AND ip.id_tipo_item = 1 AND ip.eliminado_en IS NULL
    ORDER BY ip.confirmado, ip.id_item;

    -- 6. Historial: modificación anterior y actual (equipo, servicio y programación; mismos títulos que la intranet)
    SELECT h.fecha, h.origen, h.titulo, h.referencia, h.valor_anterior, h.valor_nuevo, h.detalle, h.usuario
    FROM (
        SELECT eh.registrado_en                                              AS fecha,
               'equipo'                                                      AS origen,
               eh.campo_modificado                                           AS titulo,
               NULLIF(CONCAT_WS(' · ', e.codigo_tw, NULLIF(e.modelo, '')), '') AS referencia,
               eh.valor_anterior,
               eh.valor_nuevo,
               eh.motivo                                                     AS detalle,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS usuario
        FROM   equipo_historial eh
        JOIN   os_equipo oe ON oe.id_equipo = eh.id_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
        LEFT JOIN equipo  e ON e.id_equipo  = eh.id_equipo
        LEFT JOIN usuario u ON u.id_usuario = eh.registrado_por
        UNION ALL
        SELECT a.registrado_en,
               'servicio',
               CASE a.accion
                   WHEN 'checklist_salida'               THEN 'Checklist de salida'
                   WHEN 'solicitar_autorizacion_salida'  THEN 'Solicitud de autorización'
                   WHEN 'visto_bueno_salida'             THEN 'Visto bueno de salida del encargado del área'
                   WHEN 'iniciar_traslado'               THEN 'Inicio de traslado'
                   WHEN 'programar_os'                   THEN 'Programación creada'
                   WHEN 'anular_os'                      THEN 'Orden anulada: programación cancelada'
                   ELSE REPLACE(a.accion, '_', ' ')
               END,
               NULL,
               a.estado_anterior,
               a.estado_nuevo,
               a.descripcion,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
        FROM   auditoria_evento a
        LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
        WHERE  a.entidad_tipo = 'orden_servicio' AND a.id_entidad = p_id_os
          -- cancelar_programacion se registra también sobre la programación (rama de abajo): no se duplica.
          -- derivar_ssoma trae los documentos SSOMA de todos los técnicos: no es para la app.
          AND  a.accion NOT IN ('cancelar_programacion', 'derivar_ssoma')
        UNION ALL
        SELECT a.registrado_en,
               'servicio',
               CASE a.accion
                   WHEN 'respuesta_cliente'                  THEN 'Respuesta del cliente'
                   WHEN 'cancelar_programacion'              THEN 'Programación cancelada'
                   WHEN 'solicitar_reprogramacion'           THEN 'Reprogramación solicitada'
                   WHEN 'reprogramacion_directa'             THEN 'Reprogramación (edición directa del Jefe)'
                   WHEN 'aprobar_reprogramacion'             THEN 'Reprogramación aprobada'
                   WHEN 'rechazar_reprogramacion'            THEN 'Reprogramación rechazada'
                   WHEN 'retirar_solicitud_reprogramacion'   THEN 'Solicitud de reprogramación retirada'
                   ELSE REPLACE(a.accion, '_', ' ')
               END,
               NULL,
               a.estado_anterior,
               a.estado_nuevo,
               a.descripcion,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
        FROM   auditoria_evento a
        LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
        WHERE  a.entidad_tipo = 'programacion'
          -- Solo los eventos de la línea de tiempo de la intranet; asignar_viaticos y cerrar_rendicion llevan montos de otros técnicos.
          AND  a.accion IN ('respuesta_cliente', 'cancelar_programacion', 'solicitar_reprogramacion', 'reprogramacion_directa',
                            'aprobar_reprogramacion', 'rechazar_reprogramacion', 'retirar_solicitud_reprogramacion')
          AND  a.id_entidad IN (SELECT pg.id_programacion FROM programacion pg
                                WHERE pg.id_os = p_id_os AND pg.eliminado_en IS NULL)
    ) h
    ORDER BY h.fecha DESC
    LIMIT 20;

    -- 7. Documentación (visibilidad 1 = interno y 5 = cliente: las ven todos)
    SELECT d.id_documento,
           d.nombre_archivo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 96 AND t.IdEmpresa = 1 AND t.Num1 = d.id_tipo_documento LIMIT 1) AS tipo,
           d.version,
           d.fecha_carga
    FROM   documento_adjunto d
    WHERE  d.eliminado_en IS NULL
      AND  ((d.entidad_tipo = 'orden_servicio' AND d.id_entidad = p_id_os)
            OR (d.entidad_tipo = 'expediente' AND d.id_entidad = v_id_expediente AND d.id_visibilidad IN (1, 5)))
    ORDER BY d.fecha_carga DESC
    LIMIT 30;

    -- 8. Programación vigente (0 filas si la OS es anterior a la programación operativa)
    SELECT pr.codigo,
           pr.estado,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada'             THEN 'Programado'
                          WHEN 'cancelada'              THEN 'Cancelada' END AS estado_label,
           pr.observaciones
    FROM   programacion pr
    WHERE  pr.id_programacion = v_id_prog;

    -- 9. Equipo de trabajo (principal primero). El motivo SSOMA solo se muestra para el propio técnico.
    SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido))                                           AS nombre,
           COALESCE(cg.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')) AS cargo,
           t.rol,
           IF(t.id_usuario = p_id_usuario, 1, 0)                                             AS es_usuario,
           r.estado                                                                          AS ssoma_actual,
           IF(v_aplica = 1 AND t.id_usuario = p_id_usuario, NULLIF(r.motivo_bloqueo, ''), NULL) AS ssoma_motivo
    FROM   tmp_mov_tec t
    JOIN   usuario u            ON u.id_usuario = t.id_usuario
    LEFT JOIN tabla_maestra cg  ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tmp_ssoma_res r   ON r.id_usuario = t.id_usuario
    ORDER BY t.rol = 'apoyo', u.nombre, u.apellido;

    -- 10. Equipos del servicio (confirmados en la programación; sin selección, todos los de la OS)
    SELECT ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie
    FROM   os_equipo oe
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
      AND  (v_n_eq_prog = 0
            OR EXISTS (SELECT 1 FROM programacion_equipo pe
                       WHERE pe.id_programacion = v_id_prog AND pe.id_equipo = oe.id_equipo AND pe.eliminado_en IS NULL))
    ORDER BY ec.codigo_tw, ec.id_equipo;

    -- 11. Conceptos del servicio
    SELECT oc.id AS id_concepto, oc.codigo, oc.descripcion, oc.alcance
    FROM   os_concepto oc
    WHERE  oc.id_os = p_id_os AND oc.eliminado_en IS NULL
    ORDER BY IFNULL(oc.orden, oc.id);

    -- 12. Respuestas del cliente registradas (la más reciente primero)
    SELECT pc.id, pc.canal,
           CASE pc.canal WHEN 'correo' THEN 'Correo' WHEN 'whatsapp' THEN 'WhatsApp'
                         WHEN 'llamada' THEN 'Llamada' ELSE 'Presencial' END            AS canal_label,
           pc.resultado,
           CASE pc.resultado WHEN 'acepto' THEN 'Aceptó la programación'
                             WHEN 'pidio_reprogramar' THEN 'Pidió reprogramar' ELSE 'Canceló' END AS resultado_label,
           pc.comentario, pc.fecha_registro, TRIM(CONCAT(ur.nombre, ' ', ur.apellido)) AS registrado_por
    FROM   programacion_confirmacion pc
    LEFT JOIN usuario ur ON ur.id_usuario = pc.id_registrado_por
    WHERE  pc.id_programacion = v_id_prog AND pc.eliminado_en IS NULL
    ORDER BY pc.id DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_mov_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;

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
-- La regla de BLOQUEADO está también en SP_ObtenerBloqueoServicioMovil (la usa el detalle): si se cambia, cambiar las dos.
-- Datos de la programación operativa (intranet, HU-36/38): horario inicio–fin, tipo de servicio, cantidad de técnicos y
--   objetivos = equipos que se confirmaron en la programación vigente (sin selección, todos los equipos de la OS).
-- alerta_predictiva: texto de la alerta sin resolver de mayor prioridad (máx. 120 caracteres); alertas_predictivas, la cantidad.
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
           alertas_predictivas, estado_general, motivo_bloqueo, hora_fin, tipo_servicio, n_tecnicos, alerta_predictiva
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
