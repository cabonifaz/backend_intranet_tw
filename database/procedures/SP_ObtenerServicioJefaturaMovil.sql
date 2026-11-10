-- ============================================================
-- SP_ObtenerServicioJefaturaMovil  (App Mobile HU-30 — Seguimiento del servicio: detalle de una OS · solo lectura)
-- El jefe ve el detalle de un servicio de HOY de su alcance (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil): técnico (para llamarlo), estado,
-- hora programada, llegada, SLA, los hitos que marca la app del técnico y lo necesario para el modal "Cambiar estado operativo".
-- Reutiliza el motor de Seguimiento Operativo (HU-51/52). Quien lo ve no necesita seg_bandeja; sí lo exigen los cambios (ver puede_cambiar_estado).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 hitos · 4 estados a los que se puede avanzar · 5 motivos del cambio manual.
--   Cabecera: estado (el de la bandeja HU-51) y estado_os (el de la OS). telefono_tecnico = ficha del usuario. contacto_* = contacto en planta de la OS.
--   sla_pct = PUNTUALIDAD DE LLEGADA (estimación, no hay un SLA de ejecución definido por servicio): 100 si llegó a la hora programada o antes; si llegó tarde baja
--     proporcionalmente al atraso sobre la duración estimada del servicio (mínimo 60 min); NULL mientras no haya llegada.
--   avance_pct = estimación por hitos (igual que SP_ObtenerServiciosJefaturaMovil).
--   Hitos (estado: hecho · actual · pendiente; tono: verde · azul · naranja · rojo · gris): asignado y autorizado (visto bueno de la autorización de salida) · en ruta · demoras
--     registradas (app o Asistente, HU-05/HU-53) · llegada a planta (GPS válido a N m, HU-06) · trabajo en el equipo (equipos ejecutados) · informe y firmas (informe_tecnico).
--   Estados permitidos: SOLO avanzar (regla de SP_RegistrarAsistenteServicioRuta, HU-53): salida · en_ruta · llegada · ingreso · inicio · finalizado, por encima del nivel actual.
--   puede_cambiar_estado = 1 si el usuario tiene seg_registrar y seg_bandeja (los exige SP_RegistrarAsistenteServicioRuta) y el servicio no está finalizado.
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerServicioJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerServicioJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_ini_utc     DATETIME;
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nivel       INT DEFAULT 0;
    DECLARE v_puede       TINYINT DEFAULT 0;
    DECLARE v_informe     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_hito;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_sg_os o JOIN tmp_jf_alc a ON a.id_os = o.id_os WHERE o.id_os = p_id_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no es de hoy o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ini_utc INTO v_ini_utc FROM tmp_sg_cfg LIMIT 1;
    SELECT os_estado INTO v_estado_os FROM tmp_sg_os WHERE id_os = p_id_os;

    -- Nivel del servicio (0 programado · 1 salida · 2 en ruta · 3 llegada · 4 ingreso a planta · 5 inicio · 6 finalizado): mismos niveles que HU-53
    SET v_nivel = CASE v_estado_os
        WHEN 'en_ejecucion' THEN 5 WHEN 'pausada' THEN 5 WHEN 'finalizada' THEN 6
        WHEN 'en_ruta' THEN
            CASE WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                              WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'INGRESO_PLANTA') THEN 4
                 WHEN (SELECT x.hora_llegada_real FROM orden_servicio x WHERE x.id_os = p_id_os) IS NOT NULL THEN 3
                 WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                              WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'EN_RUTA') THEN 2
                 ELSE 1 END
        ELSE 0 END;
    SET v_puede = IF(v_estado_os <> 'finalizada' AND FN_PermisoAccion(p_id_usuario, 'seg_registrar') = 1 AND FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 1, 1, 0);
    SELECT it.estado INTO v_informe FROM informe_tecnico it WHERE it.id_os = p_id_os AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1;

    -- ── Hitos del servicio ────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_hito;
    CREATE TEMPORARY TABLE tmp_jf_hito (
        id      INT NOT NULL AUTO_INCREMENT,
        ord     INT NOT NULL,
        hora    VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        titulo  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        estado  VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        tono    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        PRIMARY KEY (id)
    );

    -- 1 Asignado y autorizado (la programación confirmada; con la autorización de salida aprobada, quién dio el visto bueno)
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 1, DATE_FORMAT(x.resuelto_en, '%H:%i'), 'asignado', 'Asignado y autorizado',
           IF(x.jefe IS NULL, 'Programación confirmada', CONCAT('visto bueno de ', x.jefe)), 'hecho', 'verde'
    FROM (SELECT 1 AS uno) d
    LEFT JOIN (SELECT a.resuelto_en, NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS jefe
               FROM autorizacion_salida_os a LEFT JOIN usuario j ON j.id_usuario = a.id_jefe
               WHERE a.id_os = p_id_os AND a.eliminado_en IS NULL AND a.estado = 'aprobada'
               ORDER BY a.resuelto_en DESC LIMIT 1) x ON 1 = 1;

    -- 2 En ruta
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 2, DATE_FORMAT(CONVERT_TZ(o.salida_utc, '+00:00', '-05:00'), '%H:%i'), 'en_ruta', 'En ruta',
           IF(o.fase = 'sin_salir', 'Aún no sale de la sede', 'salida de la sede'),
           IF(o.fase = 'sin_salir', 'actual', 'hecho'), IF(o.fase = 'sin_salir', 'azul', 'verde')
    FROM tmp_sg_os o WHERE o.id_os = p_id_os;

    -- 3 / 5 Demoras e incidencias de hoy (antes de la llegada si fueron en ruta; después si fueron en planta o incidencias)
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT IF(i.fase = 'llegada', 3, 5), DATE_FORMAT(i.fecha, '%H:%i'), 'demora',
           LEFT(CASE i.fase WHEN 'llegada' THEN 'Demora · En ruta' WHEN 'ingreso' THEN 'Demora · Ingreso a planta'
                            ELSE CONCAT(IF(i.impacto = 'detiene', 'Incidencia · ', 'Demora · '), i.tipo) END, 120),
           LEFT(CONCAT(IF(i.duracion_min IS NULL, '', CONCAT('+', i.duracion_min, ' min · ')),
                       IF(i.origen = 'asistente', 'registrada por el asistente', 'registrada por el técnico')), 300),
           'hecho', IF(i.impacto = 'detiene', 'rojo', 'naranja')
    FROM tmp_sg_inc i WHERE i.id_os = p_id_os ORDER BY i.fecha;

    -- 4 Llegada a planta (GPS válido a N m, HU-06)
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 4, DATE_FORMAT(o.llegada_dt, '%H:%i'), 'llegada', 'Llegada a planta',
           IF(o.llegada_dt IS NULL, 'Aún no llega', IF(ev.distancia_metros IS NULL, 'llegada confirmada', CONCAT('GPS válido a ', ev.distancia_metros, ' m'))),
           IF(o.llegada_dt IS NOT NULL, 'hecho', IF(o.fase = 'en_ruta', 'actual', 'pendiente')),
           IF(o.llegada_dt IS NOT NULL, 'verde', IF(o.fase = 'en_ruta', 'azul', 'gris'))
    FROM tmp_sg_os o
    LEFT JOIN (SELECT e.distancia_metros
               FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
               WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc
               ORDER BY e.id_evento DESC LIMIT 1) ev ON 1 = 1
    WHERE o.id_os = p_id_os;

    -- 6 Trabajo en el equipo
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 6, DATE_FORMAT(o.inicio_dt, '%H:%i'), 'trabajo', 'Trabajo en el equipo',
           IF(o.n_equipos = 0, NULL, CONCAT(o.n_ejecutados, ' de ', o.n_equipos, IF(o.n_equipos = 1, ' equipo ejecutado', ' equipos ejecutados'))),
           CASE o.fase WHEN 'finalizado' THEN 'hecho' WHEN 'en_ejecucion' THEN 'actual' ELSE 'pendiente' END,
           CASE o.fase WHEN 'finalizado' THEN 'verde' WHEN 'en_ejecucion' THEN 'azul' ELSE 'gris' END
    FROM tmp_sg_os o WHERE o.id_os = p_id_os;

    -- 7 Informe y firmas
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 7, NULL, 'informe', 'Informe y firmas',
           CASE WHEN v_informe = 'aprobado' THEN 'Informe aprobado'
                WHEN v_informe IN ('pendiente_revision', 'en_revision') THEN 'En revisión'
                WHEN v_informe = 'observado' THEN 'Observado: requiere correcciones'
                WHEN v_informe = 'borrador' THEN 'Borrador del técnico'
                ELSE 'Pendiente' END,
           CASE WHEN v_informe = 'aprobado' THEN 'hecho' WHEN v_informe IN ('pendiente_revision', 'en_revision', 'observado') THEN 'actual' ELSE 'pendiente' END,
           CASE WHEN v_informe = 'aprobado' THEN 'verde' WHEN v_informe = 'observado' THEN 'naranja' WHEN v_informe IN ('pendiente_revision', 'en_revision') THEN 'azul' ELSE 'gris' END;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Cabecera
    SELECT o.id_os AS id_os, o.numero AS numero, o.tipo AS tipo, o.razon_social AS cliente,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS lugar,
           o.estado_seg AS estado, o.os_estado AS estado_os,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico, t.cargo AS cargo_tecnico, NULLIF(TRIM(ut.telefono), '') AS telefono_tecnico,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS hora_programada, DATE_FORMAT(o.llegada_dt, '%H:%i') AS llegada,
           IF(o.llegada_dt IS NULL OR o.hora_inicio IS NULL, NULL,
              GREATEST(0, 100 - ROUND(100 * GREATEST(0, TIMESTAMPDIFF(MINUTE, TIMESTAMP(c.hoy, o.hora_inicio), o.llegada_dt))
                                      / GREATEST(60, IFNULL(TIME_TO_SEC(TIMEDIFF(o.hora_fin_est, o.hora_inicio)) DIV 60, 60))))) AS sla_pct,
           CASE o.fase WHEN 'finalizado' THEN 100
                       WHEN 'en_ejecucion' THEN 30 + ROUND(60 * IF(o.n_equipos = 0, 0, o.n_ejecutados / o.n_equipos))
                       WHEN 'en_planta' THEN 30 WHEN 'en_ruta' THEN 15 ELSE 0 END AS avance_pct,
           o.n_equipos AS equipos, o.n_ejecutados AS ejecutados,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono,
           v_puede AS puede_cambiar_estado, DATE_FORMAT(c.ahora, '%H:%i') AS actualizado
    FROM   tmp_sg_os o
    JOIN   tmp_sg_cfg c
    JOIN   orden_servicio osr ON osr.id_os = o.id_os
    LEFT JOIN tmp_sg_tec t ON t.id_usuario = o.id_tecnico
    LEFT JOIN usuario ut ON ut.id_usuario = o.id_tecnico
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    WHERE  o.id_os = p_id_os;

    -- 3 Hitos
    SELECT h.codigo AS codigo, h.titulo AS titulo, h.detalle AS detalle, h.hora AS hora, h.estado AS estado, h.tono AS tono
    FROM   tmp_jf_hito h ORDER BY h.ord, h.id;

    -- 4 Estados a los que se puede avanzar (solo hacia adelante)
    SELECT x.codigo AS codigo, x.nombre AS nombre
    FROM (SELECT 1 AS n, 'salida' AS codigo, 'Salida de base' AS nombre UNION ALL
          SELECT 2, 'en_ruta', 'En ruta' UNION ALL SELECT 3, 'llegada', 'Llegada a planta' UNION ALL
          SELECT 4, 'ingreso', 'Ingreso a planta' UNION ALL SELECT 5, 'inicio', 'Inicio de servicio' UNION ALL
          SELECT 6, 'finalizado', 'Finalizado') x
    WHERE x.n > v_nivel AND v_estado_os <> 'finalizada'
    ORDER BY x.n;

    -- 5 Motivos del cambio manual
    SELECT m.Num1 AS id_motivo, m.String1 AS nombre
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_hito;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
