-- HU-37 (Sprint 5) Detalle de la Programación (se abre desde cualquier tab de la bandeja). Solo lectura.
-- Acceso: prog_bandeja (módulo operaciones). Las acciones (registrar respuesta, reprogramar, cancelar, viáticos) vienen como
-- banderas calculadas con el usuario del token.
-- HU-38: cancelar lo permite cualquier rol con prog_gestionar (no pide aprobación); trae la solicitud de reprogramación pendiente
--   (id_solicitud_pendiente) y puede_resolver_solicitud (jefe); el historial incluye reprogramaciones, aprobaciones y la cancelación.
-- Resultados: 1 mensaje, 2 programación (datos, enlaces cruzados, próximo paso y acciones), 3 técnicos, 4 equipos reservados,
--   5 conceptos del servicio, 6 checklist de validación (4 ítems, siempre visibles), 7 alertas SSOMA sobrevenidas,
--   8 historial (timeline), 9 respuestas del cliente registradas.
-- Checklist: técnico asignado · equipos reservados · SSOMA habilitado · cronograma válido (mismo criterio que HU-36 al programar,
--   evaluado hoy: cambió algo después de programar si un documento venció, otro servicio se cruzó o la fecha ya pasó).
-- Alerta SSOMA sobrevenida: solo mientras la programación está vigente (no cancelada, orden programada o reprogramada) y su fecha
--   es de hoy en adelante. Usa SP_EvaluarSsomaProgramacion (la misma regla del buscador y de Programar) con la fecha del servicio:
--   un documento vencido, observado o que vence antes del servicio es crítico (bloquea la ejecución hasta reasignar o reprogramar);
--   uno que vence pronto es advertencia.
-- Historial: eventos de la programación y de su orden (programar, respuestas del cliente, anulación) más las solicitudes de
--   reprogramación y su resolución (os_reprogramacion), con los motivos.
-- Sin funciones almacenadas (exigen SUPER). Las tablas temporales se borran al terminar.
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT
)
proc: BEGIN
    DECLARE v_id_os        BIGINT       DEFAULT NULL;
    DECLARE v_estado       VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os    VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha        DATE;
    DECLARE v_ini          TIME;
    DECLARE v_fin          TIME;
    DECLARE v_creado       DATETIME;
    DECLARE v_activa       TINYINT      DEFAULT 0;
    DECLARE v_aplica       TINYINT      DEFAULT 0;
    DECLARE v_gestiona     TINYINT      DEFAULT 0;
    DECLARE v_aprueba      TINYINT      DEFAULT 0;
    DECLARE v_pendiente    BIGINT       DEFAULT NULL;
    DECLARE v_n_tec        INT          DEFAULT 0;
    DECLARE v_principal    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_eq_prog    INT          DEFAULT 0;
    DECLARE v_n_eq_os      INT          DEFAULT 0;
    DECLARE v_n_bloq       INT          DEFAULT 0;
    DECLARE v_motivo       VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_cruces     INT          DEFAULT 0;
    DECLARE v_cruces       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_crono_ok     TINYINT      DEFAULT 1;
    DECLARE v_crono_txt    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultimo       VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_proximo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        DROP TEMPORARY TABLE IF EXISTS tmp_det_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_det_cruce;
        DROP TEMPORARY TABLE IF EXISTS tmp_det_check;
        DROP TEMPORARY TABLE IF EXISTS tmp_det_alerta;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la programación operativa.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, creado_en
      INTO v_id_os, v_estado, v_fecha, v_ini, v_fin, v_creado
    FROM programacion
    WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado INTO v_estado_os FROM orden_servicio WHERE id_os = v_id_os;

    SET v_activa   = IF(v_estado <> 'cancelada' AND v_estado_os IN ('programada', 'reprogramada'), 1, 0);
    SET v_aplica   = IF(v_activa = 1 AND v_fecha >= CURDATE(), 1, 0);
    SET v_gestiona = IF(FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 1, 1, 0);
    SET v_aprueba  = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1, 1, 0);
    -- HU-38: solicitud de reprogramación pendiente de esta programación (también las anteriores a la HU-38, que solo traen la OS)
    SELECT MAX(rp.id_reprogramacion) INTO v_pendiente
    FROM os_reprogramacion rp
    WHERE rp.estado = 'pendiente' AND rp.eliminado_en IS NULL
      AND (rp.id_programacion = p_id_programacion OR (rp.id_programacion IS NULL AND rp.id_os = v_id_os));

    -- ── Técnicos de la programación y su situación SSOMA de hoy ───────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_det_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_cruce;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_alerta;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_det_tec (id_usuario BIGINT NOT NULL, rol VARCHAR(10) NOT NULL, PRIMARY KEY (id_usuario));
    INSERT IGNORE INTO tmp_det_tec (id_usuario, rol)
    SELECT id_usuario, rol FROM programacion_tecnico
    WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_det_tec;
    CALL SP_EvaluarSsomaProgramacion(v_id_os, v_fecha);

    SELECT COUNT(*) INTO v_n_tec FROM tmp_det_tec;
    SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) INTO v_principal
    FROM programacion_tecnico pt JOIN usuario u ON u.id_usuario = pt.id_usuario
    WHERE pt.id_programacion = p_id_programacion AND pt.rol = 'principal' AND pt.eliminado_en IS NULL LIMIT 1;

    SELECT COUNT(*) INTO v_n_eq_prog FROM programacion_equipo WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    SELECT COUNT(*) INTO v_n_eq_os   FROM os_equipo           WHERE id_os = v_id_os AND eliminado_en IS NULL;

    IF v_aplica = 1 THEN
        SELECT COUNT(*),
               GROUP_CONCAT(CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ': ', IFNULL(NULLIF(r.motivo_bloqueo, ''), 'documento SSOMA faltante'))
                            ORDER BY u.nombre SEPARATOR '; ')
          INTO v_n_bloq, v_motivo
        FROM tmp_ssoma_res r
        JOIN usuario u ON u.id_usuario = r.id_usuario
        WHERE r.estado IN ('bloqueado', 'pendiente');
    END IF;

    -- ── Cruces de horario con otros servicios de los mismos técnicos (dos lecturas separadas: una temporal por consulta) ──
    CREATE TEMPORARY TABLE tmp_det_cruce (numero VARCHAR(20) NOT NULL, id_usuario BIGINT NOT NULL);
    IF v_estado <> 'cancelada' THEN
        INSERT INTO tmp_det_cruce (numero, id_usuario)
        SELECT o.numero, t.id_usuario
        FROM orden_servicio o
        JOIN tmp_det_tec t ON t.id_usuario = o.id_tecnico_principal
        WHERE o.id_os <> v_id_os AND o.eliminado_en IS NULL
          AND o.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND o.fecha_ejecucion = v_fecha AND o.hora_inicio < v_fin AND v_ini < o.hora_fin_estimada;
        INSERT INTO tmp_det_cruce (numero, id_usuario)
        SELECT o.numero, t.id_usuario
        FROM orden_servicio o
        JOIN os_personal pe ON pe.id_os = o.id_os AND pe.eliminado_en IS NULL
        JOIN tmp_det_tec t ON t.id_usuario = pe.id_usuario
        WHERE o.id_os <> v_id_os AND o.eliminado_en IS NULL
          AND o.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND o.fecha_ejecucion = v_fecha AND o.hora_inicio < v_fin AND v_ini < o.hora_fin_estimada;
    END IF;
    SELECT COUNT(DISTINCT numero), GROUP_CONCAT(DISTINCT numero ORDER BY numero SEPARATOR ', ') INTO v_n_cruces, v_cruces FROM tmp_det_cruce;

    -- ── Cronograma válido ────────────────────────────────────────────────────
    IF v_fin <= v_ini THEN
        SET v_crono_ok = 0, v_crono_txt = 'La hora fin no es posterior a la hora de inicio.';
    ELSEIF v_n_cruces > 0 THEN
        SET v_crono_ok = 0, v_crono_txt = CONCAT('Se cruza con ', v_cruces, '.');
    ELSEIF v_activa = 1 AND v_fecha < CURDATE() THEN
        SET v_crono_ok = 0, v_crono_txt = CONCAT('La fecha ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), ' ya pasó y el servicio no se ejecutó.');
    ELSE
        SET v_crono_txt = CONCAT(DATE_FORMAT(v_fecha, '%d/%m'), ' · ', TIME_FORMAT(v_ini, '%H:%i'), '-', TIME_FORMAT(v_fin, '%H:%i'));
    END IF;

    -- ── Checklist (siempre 4 ítems) ──────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_det_check (
        orden INT NOT NULL, item VARCHAR(30) NOT NULL, titulo VARCHAR(60) NOT NULL,
        cumple TINYINT NOT NULL, requiere_accion TINYINT NOT NULL, detalle VARCHAR(700) NULL
    );
    INSERT INTO tmp_det_check (orden, item, titulo, cumple, requiere_accion, detalle) VALUES
        (1, 'tecnico_asignado', 'Técnico asignado', IF(v_principal IS NULL, 0, 1), IF(v_principal IS NULL, 1, 0),
            IF(v_principal IS NULL, 'No hay técnico principal asignado.',
               CONCAT(v_principal, IF(v_n_tec > 1, CONCAT(' y ', v_n_tec - 1, ' de apoyo'), '')))),
        (2, 'equipos_reservados', 'Equipos reservados',
            IF(v_n_eq_prog > 0 OR v_n_eq_os = 0, 1, 0), IF(v_n_eq_prog > 0 OR v_n_eq_os = 0, 0, 1),
            IF(v_n_eq_prog > 0, CONCAT(v_n_eq_prog, IF(v_n_eq_prog = 1, ' equipo', ' equipos'), ' del listado de la OS'),
               IF(v_n_eq_os = 0, 'La OS no tiene equipos.', 'No hay equipos confirmados para esta programación.'))),
        (3, 'ssoma_habilitado', 'SSOMA habilitado',
            IF(v_aplica = 1 AND v_n_bloq > 0, 0, 1), IF(v_aplica = 1 AND v_n_bloq > 0, 1, 0),
            IF(v_aplica = 1 AND v_n_bloq > 0, CONCAT(v_motivo, ' — Requiere acción'),
               IF(v_aplica = 1, 'Habilitación vigente de todo el equipo', 'Sin validación (la programación ya no está vigente)'))),
        (4, 'cronograma_valido', 'Cronograma válido', v_crono_ok, IF(v_crono_ok = 1, 0, 1), v_crono_txt);

    -- ── Próximo paso ─────────────────────────────────────────────────────────
    SELECT resultado INTO v_ultimo FROM programacion_confirmacion
    WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL ORDER BY id DESC LIMIT 1;

    SET v_proximo = CASE
        WHEN v_estado = 'cancelada'                          THEN 'Sin próximo paso: la programación está cancelada'
        WHEN v_aplica = 1 AND v_n_bloq > 0                   THEN 'Resolver el bloqueo SSOMA: reasignar técnico o reprogramar'
        WHEN v_ultimo = 'pidio_reprogramar' AND v_activa = 1 THEN 'Reprogramar: el cliente lo pidió (HU-38)'
        WHEN v_ultimo = 'cancelo'           AND v_activa = 1 THEN 'Cancelar la programación: el cliente la canceló (HU-38)'
        WHEN v_estado = 'pendiente_confirmacion'             THEN 'Registrar la respuesta del cliente'
        ELSE 'Ejecución en campo (Módulo 11)'
    END;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Programación
    SELECT pr.id_programacion, pr.codigo, pr.estado,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada'             THEN 'Programado'
                          WHEN 'cancelada'              THEN 'Cancelada' END                            AS estado_label,
           os.id_os, os.numero AS numero_os, os.tipo, os.estado AS estado_os,
           os.id_expediente, e.numero AS numero_expediente,
           os.id_cliente, c.razon_social, c.ruc,
           os.id_sede, sc.nombre AS sede, sc.direccion_exacta AS ubicacion,
           COALESCE(os.id_propuesta, e.id_propuesta)                                                      AS id_propuesta,
           p.numero AS numero_propuesta, p.version AS version_propuesta,
           os.id_tipo_servicio, ts.String1 AS tipo_servicio,
           pr.fecha_ejecucion,
           TIME_FORMAT(pr.hora_inicio, '%H:%i')                                                           AS hora_inicio,
           TIME_FORMAT(pr.hora_fin_estimada, '%H:%i')                                                     AS hora_fin,
           ROUND(TIME_TO_SEC(TIMEDIFF(pr.hora_fin_estimada, pr.hora_inicio)) / 3600, 2)                   AS duracion_horas,
           pr.observaciones,
           v_principal                                                                                    AS tecnico_principal,
           v_n_tec                                                                                        AS n_tecnicos,
           v_n_eq_prog                                                                                    AS n_equipos,
           (SELECT COUNT(*) FROM os_concepto oc WHERE oc.id_os = os.id_os AND oc.eliminado_en IS NULL)    AS n_conceptos,
           v_proximo                                                                                      AS proximo_paso,
           pr.creado_en, TRIM(CONCAT(uc.nombre, ' ', uc.apellido))                                        AS creado_por_nombre,
           IF(v_aplica = 1 AND v_n_bloq > 0, 1, 0)                                                        AS bloqueo_ssoma_activo,
           -- Acciones (según los permisos del usuario del token y el estado)
           IF(v_gestiona = 1 AND v_activa = 1, 1, 0)                                                      AS puede_registrar_respuesta,
           IF(v_gestiona = 1 AND v_activa = 1, 1, 0)                                                      AS puede_reasignar,
           IF(v_activa = 1 AND (v_aprueba = 1 OR (v_gestiona = 1 AND v_pendiente IS NULL)), 1, 0)          AS puede_reprogramar,
           IF(v_aprueba = 1, 1, 0)                                                                        AS reprogramacion_directa,
           IF(v_gestiona = 1 AND v_aprueba = 0, 1, 0)                                                     AS reprogramacion_requiere_solicitud,
           IF(v_gestiona = 1 AND v_activa = 1, 1, 0)                                                      AS puede_cancelar,
           IF(v_estado = 'confirmada' AND v_activa = 1 AND v_aprueba = 1, 1, 0)                           AS puede_gestionar_viaticos,
           IF(os.id_expediente IS NOT NULL, 1, 0)                                                         AS puede_ver_expediente,
           v_pendiente                                                                                    AS id_solicitud_pendiente,
           IF(v_aprueba = 1 AND v_pendiente IS NOT NULL AND v_activa = 1, 1, 0)                           AS puede_resolver_solicitud
    FROM programacion pr
    JOIN orden_servicio os          ON os.id_os = pr.id_os
    LEFT JOIN cliente c             ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc       ON sc.id_sede = os.id_sede
    LEFT JOIN expediente_digital e  ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN tabla_maestra ts      ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario uc            ON uc.id_usuario = pr.creado_por
    WHERE pr.id_programacion = p_id_programacion;

    -- 3. Técnicos (principal primero) con la situación SSOMA al programar y la de hoy
    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre,
           COALESCE(cg.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')) AS cargo,
           pt.rol, pt.estado_ssoma AS ssoma_al_programar,
           r.estado AS ssoma_actual, IF(v_aplica = 1, NULLIF(r.motivo_bloqueo, ''), NULL) AS ssoma_motivo
    FROM programacion_tecnico pt
    JOIN usuario u            ON u.id_usuario = pt.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tmp_ssoma_res r  ON r.id_usuario = pt.id_usuario
    WHERE pt.id_programacion = p_id_programacion AND pt.eliminado_en IS NULL
    ORDER BY pt.rol = 'apoyo', u.nombre, u.apellido;

    -- 4. Equipos reservados
    SELECT ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie
    FROM programacion_equipo pe
    JOIN equipo_cliente ec ON ec.id_equipo = pe.id_equipo
    WHERE pe.id_programacion = p_id_programacion AND pe.eliminado_en IS NULL
    ORDER BY ec.codigo_tw, ec.id_equipo;

    -- 5. Conceptos del servicio
    SELECT oc.id AS id_os_concepto, oc.codigo, oc.descripcion, oc.alcance, IFNULL(oc.orden, oc.id) AS orden
    FROM os_concepto oc
    WHERE oc.id_os = v_id_os AND oc.eliminado_en IS NULL
    ORDER BY IFNULL(oc.orden, oc.id);

    -- 6. Checklist de validación
    SELECT item, titulo, cumple, requiere_accion, detalle FROM tmp_det_check ORDER BY orden;

    -- 7. Alertas SSOMA sobrevenidas (críticas = bloquean la ejecución; advertencias = vencen pronto).
    --    Se arman con varias sentencias: MySQL no reabre una temporal en la misma consulta (un UNION lee tmp_ssoma_det dos veces).
    CREATE TEMPORARY TABLE tmp_det_alerta (
        severidad VARCHAR(12) NOT NULL, id_usuario BIGINT NOT NULL, tecnico VARCHAR(200) NULL, requisito VARCHAR(255) NULL,
        situacion VARCHAR(20) NULL, estado_doc VARCHAR(20) NULL, fecha_vencimiento DATE NULL, dias_vencido INT NULL,
        ya_vencio TINYINT NOT NULL DEFAULT 0, mensaje VARCHAR(900) NULL
    );
    INSERT INTO tmp_det_alerta (severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje)
    SELECT 'critica', d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico,
           d.requisito, d.situacion, d.estado_doc, d.fecha_vencimiento,
           IF(d.fecha_vencimiento IS NOT NULL AND d.fecha_vencimiento < CURDATE(), DATEDIFF(CURDATE(), d.fecha_vencimiento), NULL) AS dias_vencido,
           IF(d.estado_doc = 'vencido' OR (d.fecha_vencimiento IS NOT NULL AND d.fecha_vencimiento < CURDATE()), 1, 0) AS ya_vencio,
           CASE WHEN d.estado_doc = 'observado'
                    THEN CONCAT('El documento ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' está observado.')
                WHEN d.estado_doc = 'vencido' OR d.fecha_vencimiento < CURDATE()
                    THEN CONCAT('El ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' venció el ',
                                IFNULL(DATE_FORMAT(d.fecha_vencimiento, '%d/%m/%Y'), '(fecha no registrada)'),
                                IF(d.fecha_vencimiento IS NULL, '', CONCAT(' (hoy +', DATEDIFF(CURDATE(), d.fecha_vencimiento), ' días)')),
                                '. La ejecución queda bloqueada hasta reasignar o reprogramar.')
                ELSE CONCAT('El ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' vence el ',
                            DATE_FORMAT(d.fecha_vencimiento, '%d/%m/%Y'), ', antes de la fecha del servicio. Reasigna o reprograma.')
           END AS mensaje
    FROM tmp_ssoma_det d
    JOIN usuario u ON u.id_usuario = d.id_usuario
    WHERE v_aplica = 1 AND d.situacion = 'bloqueado' AND d.bloquea = 1;
    INSERT INTO tmp_det_alerta (severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje)
    SELECT 'advertencia', d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), d.requisito, d.situacion, d.estado_doc,
           d.fecha_vencimiento, NULL, 0,
           CONCAT('El ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' vence el ',
                  DATE_FORMAT(d.fecha_vencimiento, '%d/%m/%Y'), '; coordina su renovación con SSOMA.')
    FROM tmp_ssoma_det d
    JOIN usuario u ON u.id_usuario = d.id_usuario
    WHERE v_aplica = 1 AND d.situacion = 'por_vencer' AND d.requerido = 1;
    INSERT INTO tmp_det_alerta (severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje)
    SELECT 'critica', r.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)),
           IF(r.bloqueado_en_otra_os = 1, 'Bloqueo SSOMA en otra orden', 'Documento SSOMA faltante'),
           IF(r.bloqueado_en_otra_os = 1, 'bloqueado', 'sin_documento'), NULL, NULL, NULL, 0,
           IF(r.bloqueado_en_otra_os = 1,
              CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' figura bloqueado por SSOMA en otra orden activa.'),
              CONCAT('A ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' le falta el documento que pide el cliente: ', IFNULL(r.faltantes, 'SSOMA'), '.'))
    FROM tmp_ssoma_res r
    JOIN usuario u ON u.id_usuario = r.id_usuario
    WHERE v_aplica = 1 AND (r.bloqueado_en_otra_os = 1 OR r.estado = 'pendiente');
    SELECT severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje
    FROM tmp_det_alerta ORDER BY severidad, tecnico, requisito;

    -- 8. Historial (timeline)
    SELECT x.fecha, x.tipo, x.titulo, x.descripcion, x.usuario, x.estado_anterior, x.estado_nuevo, x.motivo
    FROM (
        SELECT ae.registrado_en AS fecha, 1 AS ord,
               CASE ae.accion WHEN 'programar_os'   THEN 'programacion'
                              WHEN 'respuesta_cliente' THEN 'respuesta_cliente'
                              WHEN 'anular_os'      THEN 'cancelacion'
                              WHEN 'cancelar_programacion' THEN 'cancelacion'
                              WHEN 'solicitar_reprogramacion' THEN 'reprogramacion'
                              WHEN 'reprogramacion_directa' THEN 'reprogramacion'
                              WHEN 'aprobar_reprogramacion' THEN 'aprobacion'
                              WHEN 'rechazar_reprogramacion' THEN 'aprobacion'
                              WHEN 'retirar_solicitud_reprogramacion' THEN 'aprobacion'
                              ELSE 'estado' END                                       AS tipo,
               CASE ae.accion WHEN 'programar_os'   THEN 'Programación creada'
                              WHEN 'respuesta_cliente' THEN 'Respuesta del cliente'
                              WHEN 'anular_os'      THEN 'Orden anulada: programación cancelada'
                              WHEN 'cancelar_programacion' THEN 'Programación cancelada'
                              WHEN 'solicitar_reprogramacion' THEN 'Reprogramación solicitada'
                              WHEN 'reprogramacion_directa' THEN 'Reprogramación (edición directa del Jefe)'
                              WHEN 'aprobar_reprogramacion' THEN 'Reprogramación aprobada'
                              WHEN 'rechazar_reprogramacion' THEN 'Reprogramación rechazada'
                              WHEN 'retirar_solicitud_reprogramacion' THEN 'Solicitud de reprogramación retirada'
                              ELSE ae.accion END                                      AS titulo,
               ae.descripcion, TRIM(CONCAT(ua.nombre, ' ', ua.apellido))              AS usuario,
               ae.estado_anterior, ae.estado_nuevo, JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.motivo')) AS motivo
        FROM auditoria_evento ae
        LEFT JOIN usuario ua ON ua.id_usuario = ae.id_usuario
        WHERE (ae.entidad_tipo = 'programacion' AND ae.id_entidad = p_id_programacion)
           OR (ae.entidad_tipo = 'orden_servicio' AND ae.id_entidad = v_id_os
               AND ((ae.accion = 'programar_os'
                     AND CAST(JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.idProgramacion')) AS UNSIGNED) = p_id_programacion)
                    OR (ae.accion = 'anular_os' AND ae.registrado_en >= v_creado)))
        UNION ALL
        SELECT rp.fecha_solicitud, 2, 'reprogramacion', 'Reprogramación solicitada',
               CONCAT('Propone el ', DATE_FORMAT(rp.fecha_propuesta, '%d/%m/%Y'),
                      IF(rp.hora_propuesta IS NULL, '', CONCAT(' a las ', TIME_FORMAT(rp.hora_propuesta, '%H:%i'))), '. ', rp.comentario),
               TRIM(CONCAT(us.nombre, ' ', us.apellido)), NULL, NULL, mo.String1
        FROM os_reprogramacion rp
        LEFT JOIN usuario us        ON us.id_usuario = rp.id_solicitante
        LEFT JOIN tabla_maestra mo  ON mo.IdMaestro = 13 AND mo.IdEmpresa = 1 AND mo.Num1 = rp.id_motivo
        WHERE rp.id_os = v_id_os AND rp.id_programacion IS NULL AND rp.eliminado_en IS NULL AND rp.fecha_solicitud >= v_creado
        UNION ALL
        SELECT rp.fecha_resolucion, 3, 'aprobacion',
               CASE rp.estado WHEN 'aprobada' THEN 'Reprogramación aprobada' WHEN 'rechazada' THEN 'Reprogramación rechazada'
                              ELSE 'Solicitud de reprogramación cancelada' END,
               rp.comentario_resolucion, TRIM(CONCAT(ur.nombre, ' ', ur.apellido)), 'pendiente', rp.estado, mo.String1
        FROM os_reprogramacion rp
        LEFT JOIN usuario ur        ON ur.id_usuario = rp.resuelto_por
        LEFT JOIN tabla_maestra mo  ON mo.IdMaestro = 13 AND mo.IdEmpresa = 1 AND mo.Num1 = rp.id_motivo
        WHERE rp.id_os = v_id_os AND rp.id_programacion IS NULL AND rp.eliminado_en IS NULL AND rp.fecha_solicitud >= v_creado
          AND rp.estado <> 'pendiente' AND rp.fecha_resolucion IS NOT NULL
    ) x
    ORDER BY x.fecha, x.ord;

    -- 9. Respuestas del cliente registradas (la más reciente primero)
    SELECT pc.id, pc.canal,
           CASE pc.canal WHEN 'correo' THEN 'Correo' WHEN 'whatsapp' THEN 'WhatsApp'
                         WHEN 'llamada' THEN 'Llamada' ELSE 'Presencial' END            AS canal_label,
           pc.resultado,
           CASE pc.resultado WHEN 'acepto' THEN 'Aceptó la programación'
                             WHEN 'pidio_reprogramar' THEN 'Pidió reprogramar' ELSE 'Canceló' END AS resultado_label,
           pc.comentario, pc.fecha_registro, TRIM(CONCAT(ur.nombre, ' ', ur.apellido)) AS registrado_por
    FROM programacion_confirmacion pc
    LEFT JOIN usuario ur ON ur.id_usuario = pc.id_registrado_por
    WHERE pc.id_programacion = p_id_programacion AND pc.eliminado_en IS NULL
    ORDER BY pc.id DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_det_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_cruce;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_alerta;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;
