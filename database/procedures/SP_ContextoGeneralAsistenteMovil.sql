-- ============================================================
-- SP_ContextoGeneralAsistenteMovil  (App Mobile — Asistente IA conversacional · solo lectura)
-- Lo que el asistente "sabe" del usuario cuando le escribe sin elegir equipo: se arma como líneas de texto (sección + línea) que el back le entrega a la IA
-- como DATOS (nunca como instrucciones). No inventa nada: todo sale de las mismas reglas de las pantallas de la app.
--   Técnico : servicios programados (estado, horario, confirmación del cliente, objetivos) con distancia y llegada estimada a la planta si la app envía su
--             ubicación (línea recta × 1,3 a SEG_VELOCIDAD_PROMEDIO_KMH, igual que el seguimiento), equipos ingresados/recepcionados, viáticos y gastos y procedimientos.
--   Jefatura: además, todos los servicios de HOY de su alcance con el técnico, su fase (en ruta, en planta, ejecutando…), demoras, alertas críticas y los equipos
--             recepcionados hoy. Quién es jefe lo resuelve SP_ResolverJefaturaMovil (el mismo criterio del menú de Jefatura).
--   p_lat / p_lon : ubicación actual del teléfono (opcional; NULL = no se calcula distancia).
-- Resultados: 1 mensaje · 2 perfil (nombre, cargo, area_jefatura, ahora_lima) · 3 líneas (seccion, linea).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoGeneralAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoGeneralAsistenteMovil(
    IN p_id_usuario BIGINT,
    IN p_lat        DECIMAL(10,7),
    IN p_lon        DECIMAL(10,7)
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_hoy         DATE;
    DECLARE v_ahora       DATETIME;
    DECLARE v_vel         DECIMAL(18,6) DEFAULT 30;

    -- Si UNA sección falla (p. ej. un dato que no se pudo leer) el chat sigue con las demás: el error queda como línea AVISO_SISTEMA para diagnóstico
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        INSERT INTO tmp_ctx_ia (seccion, linea) VALUES ('AVISO_SISTEMA', LEFT(CONCAT('una parte de los datos no se pudo leer: [MySQL ', @err_code, '] ', @err_msg), 700));
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP() - INTERVAL 5 HOUR;
    SET v_hoy   = DATE(v_ahora);
    CALL SP_LeerParametroProgramacion('SEG_VELOCIDAD_PROMEDIO_KMH', 30, v_vel);
    SET v_vel = GREATEST(5, IFNULL(v_vel, 30));

    DROP TEMPORARY TABLE IF EXISTS tmp_ctx_ia;
    CREATE TEMPORARY TABLE tmp_ctx_ia (
        n       INT AUTO_INCREMENT PRIMARY KEY,
        seccion VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        linea   VARCHAR(700) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL
    );

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);

    -- ── Servicios del usuario como técnico (principal o parte del personal): mismo universo que "Servicios programados" ──
    INSERT INTO tmp_ctx_ia (seccion, linea)
    SELECT 'MIS_SERVICIOS',
           LEFT(CONCAT_WS(' · ',
               os.numero,
               COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social),
               CONCAT('planta/sede: ', COALESCE(NULLIF(sc.nombre, ''), NULLIF(sc.direccion_exacta, ''), 'sin dato')),
               CONCAT('fecha ', DATE_FORMAT(os.fecha_ejecucion, '%d/%m/%Y'), IF(os.hora_inicio IS NULL, '', CONCAT(' ', TIME_FORMAT(os.hora_inicio, '%H:%i'))),
                      IF(os.hora_fin_estimada IS NULL, '', CONCAT(' a ', TIME_FORMAT(os.hora_fin_estimada, '%H:%i')))),
               CONCAT('estado ', os.estado),
               IF(IFNULL(os.confirmacion_cliente, 0) = 1, 'cliente confirmó', 'cliente NO ha confirmado (pendiente)'),
               CONCAT('objetivos ', (SELECT COUNT(*) FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.eliminado_en IS NULL
                                     AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = oe.id)),
                      ' (ejecutados ', (SELECT COUNT(*) FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.eliminado_en IS NULL AND oe.estado_ejecucion = 'ejecutado'
                                        AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = oe.id)), ')'),
               (SELECT CONCAT('tipo de servicio ', t.String1) FROM tabla_maestra t
                WHERE t.Descripcion = 'TIPO_SERVICIO' AND t.IdEmpresa = 1 AND t.Num1 = os.id_tipo_servicio ORDER BY t.IdMaestro DESC LIMIT 1),
               IF(p_lat IS NULL OR p_lon IS NULL OR sc.latitud IS NULL OR sc.longitud IS NULL, NULL,
                  CONCAT('distancia a la planta ≈ ',
                         ROUND(ST_Distance_Sphere(POINT(p_lon, p_lat), POINT(sc.longitud, sc.latitud)) / 1000, 1), ' km en línea recta; llegada estimada ≈ ',
                         GREATEST(1, CEIL(ST_Distance_Sphere(POINT(p_lon, p_lat), POINT(sc.longitud, sc.latitud)) * 1.3 / 1000 / v_vel * 60)),
                         ' min a ', v_vel, ' km/h (referencial)')),
               IF(p_lat IS NOT NULL AND p_lon IS NOT NULL AND (sc.latitud IS NULL OR sc.longitud IS NULL), 'la planta aún no tiene coordenadas registradas: no se puede calcular la distancia', NULL)
           ), 700)
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede   = os.id_sede
    WHERE  os.eliminado_en IS NULL
      AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
      AND  NOT EXISTS (SELECT 1 FROM os_constancia k WHERE k.id_os = os.id_os AND k.cerrada_en IS NOT NULL)
      AND  (os.fecha_ejecucion >= v_hoy OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ORDER BY (os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')) DESC, os.fecha_ejecucion, os.hora_inicio
    LIMIT 15;

    -- ── Objetivos (equipos) de esos servicios y su recepción/ingreso ──
    INSERT INTO tmp_ctx_ia (seccion, linea)
    SELECT 'MIS_EQUIPOS',
           LEFT(CONCAT_WS(' · ',
               os.numero,
               LEFT(COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion, 'Equipo'), 80),
               CONCAT_WS(' ', NULLIF(ec.marca, ''), NULLIF(ec.modelo, '')),
               CONCAT('serie ', NULLIF(TRIM(ec.num_serie), '')),
               CONCAT('código ', NULLIF(ec.codigo_tw, '')),
               CONCAT('ejecución: ', IFNULL(oe.estado_ejecucion, 'por iniciar')),
               IF(ing.id IS NULL, 'aún sin registrar el ingreso',
                  CONCAT('ingreso registrado ', DATE_FORMAT(CONVERT_TZ(ing.ingresado_utc, '+00:00', '-05:00'), '%d/%m %H:%i'), ' como ',
                         CASE ing.estado_ingreso WHEN 'operativo' THEN 'operativo' WHEN 'con_observaciones' THEN 'operativo con observaciones' ELSE 'inoperativo' END,
                         IF(NULLIF(TRIM(ing.observacion), '') IS NULL, '', CONCAT(' (', LEFT(ing.observacion, 120), ')'))))
           ), 700)
    FROM   orden_servicio os
    JOIN   os_equipo oe ON oe.id_os = os.id_os AND oe.eliminado_en IS NULL AND oe.id_equipo IS NOT NULL
                       AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = oe.id)
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN suministros    su ON su.id_suministro = ec.id_suministro
    LEFT JOIN (SELECT i.id_os_equipo, MAX(i.id) AS id_ingreso FROM os_equipo_ingreso i WHERE i.eliminado_en IS NULL GROUP BY i.id_os_equipo) li ON li.id_os_equipo = oe.id
    LEFT JOIN os_equipo_ingreso ing ON ing.id = li.id_ingreso
    WHERE  os.eliminado_en IS NULL
      AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
      AND  NOT EXISTS (SELECT 1 FROM os_constancia k WHERE k.id_os = os.id_os AND k.cerrada_en IS NOT NULL)
      AND  (os.fecha_ejecucion >= v_hoy OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ORDER BY os.fecha_ejecucion, os.id_os, oe.id
    LIMIT 40;

    -- ── Viáticos y gastos del usuario (mismas reglas de "Viáticos y Gastos") ──
    CALL SP_ObtenerViaticosUsuarioMovil(p_id_usuario, @ctx_saldo, @ctx_activos, @ctx_final, @ctx_rev_monto, @ctx_rev_n, @ctx_obs_n);
    DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;
    INSERT INTO tmp_ctx_ia (seccion, linea)
    VALUES ('MIS_VIATICOS',
            CONCAT('saldo por rendir S/ ', IFNULL(@ctx_saldo, 0), ' · viáticos activos ', IFNULL(@ctx_activos, 0), ' · rendiciones finalizadas ', IFNULL(@ctx_final, 0),
                   ' · gastos en revisión ', IFNULL(@ctx_rev_n, 0), ' (S/ ', IFNULL(@ctx_rev_monto, 0), ') · gastos observados ', IFNULL(@ctx_obs_n, 0)));

    -- ── Procedimientos vigentes en la app ──
    INSERT INTO tmp_ctx_ia (seccion, linea)
    SELECT 'PROCEDIMIENTOS',
           LEFT(CONCAT_WS(' · ', pm.codigo, CONCAT('versión ', pm.version), CONCAT('año ', pm.anio), NULLIF(pm.norma_base, ''), LEFT(pm.descripcion, 160)), 700)
    FROM   procedimiento_metrologico pm
    WHERE  pm.SoftDelete = 0 AND pm.estado = 'activo'
    ORDER BY pm.codigo, pm.anio DESC, pm.version DESC
    LIMIT 40;

    -- ── Jefatura: todo el alcance de hoy ──
    IF v_area IS NOT NULL THEN
        CALL SP_ArmarSeguimientoOperativo();
        CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);

        INSERT INTO tmp_ctx_ia (seccion, linea)
        SELECT 'JEFATURA_SERVICIOS_HOY',
               LEFT(CONCAT_WS(' · ',
                   o.numero, o.razon_social,
                   CONCAT('técnico ', IFNULL(NULLIF(o.tecnico, ''), 'sin asignar')),
                   CONCAT('planta/sede: ', COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, ''), 'sin dato')),
                   CONCAT('situación ', o.estado_seg, ' (fase ', IFNULL(o.fase, '-'), ')'),
                   IF(o.hora_inicio IS NULL, NULL, CONCAT('programado ', TIME_FORMAT(o.hora_inicio, '%H:%i'))),
                   IF(o.llegada_dt IS NULL, NULL, CONCAT('llegó ', DATE_FORMAT(o.llegada_dt, '%H:%i'))),
                   IF(o.fase = 'en_ruta' AND o.eta_min IS NOT NULL, CONCAT('llegada estimada en ', o.eta_min, ' min', IF(o.dist_m IS NULL, '', CONCAT(' (a ', ROUND(o.dist_m / 1000, 1), ' km)'))), NULL),
                   CONCAT('equipos ', o.n_ejecutados, '/', o.n_equipos, ' ejecutados'),
                   IF(o.n_demoras > 0, CONCAT(o.n_demoras, ' demora(s) registrada(s)'), NULL),
                   IF(o.crit = 1, 'TIENE ALERTA CRÍTICA', NULL)
               ), 700)
        FROM   tmp_sg_os o
        JOIN   tmp_jf_alc a ON a.id_os = o.id_os
        ORDER BY o.prio, o.hora_inicio, o.id_os
        LIMIT 60;

        INSERT INTO tmp_ctx_ia (seccion, linea)
        SELECT 'JEFATURA_EQUIPOS_RECEPCIONADOS_HOY',
               LEFT(CONCAT_WS(' · ',
                   os.numero, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social),
                   LEFT(COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion, 'Equipo'), 80),
                   CONCAT_WS(' ', NULLIF(ec.marca, ''), NULLIF(ec.modelo, '')),
                   CONCAT('código ', NULLIF(ec.codigo_tw, '')),
                   CONCAT('recepcionó ', NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '')),
                   CONCAT('a las ', DATE_FORMAT(CONVERT_TZ(i.ingresado_utc, '+00:00', '-05:00'), '%H:%i')),
                   CONCAT('estado ', CASE i.estado_ingreso WHEN 'operativo' THEN 'operativo' WHEN 'con_observaciones' THEN 'operativo con observaciones' ELSE 'inoperativo' END),
                   IF(NULLIF(TRIM(i.observacion), '') IS NULL, NULL, CONCAT('obs: ', LEFT(i.observacion, 120)))
               ), 700)
        FROM   os_equipo_ingreso i
        JOIN   tmp_jf_alc a ON a.id_os = i.id_os
        JOIN   orden_servicio os ON os.id_os = i.id_os
        LEFT JOIN cliente        c  ON c.id_cliente = os.id_cliente
        LEFT JOIN os_equipo      oe ON oe.id = i.id_os_equipo
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
        LEFT JOIN suministros    su ON su.id_suministro = ec.id_suministro
        LEFT JOIN usuario        u  ON u.id_usuario = i.id_usuario
        WHERE  i.eliminado_en IS NULL
          AND  DATE(CONVERT_TZ(i.ingresado_utc, '+00:00', '-05:00')) = v_hoy
        ORDER BY i.ingresado_utc DESC
        LIMIT 60;

        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS nombre,
           IFNULL(u.cargo, '')                                            AS cargo,
           v_area                                                         AS area_jefatura,
           DATE_FORMAT(v_ahora, '%Y-%m-%d %H:%i')                         AS ahora_lima,
           DAYNAME(v_ahora)                                               AS dia
    FROM   usuario u
    WHERE  u.id_usuario = p_id_usuario;

    SELECT seccion, linea FROM tmp_ctx_ia ORDER BY n;

    DROP TEMPORARY TABLE IF EXISTS tmp_ctx_ia;
END$$

DELIMITER ;
