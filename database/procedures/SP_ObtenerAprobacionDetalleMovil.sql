-- ============================================================
-- SP_ObtenerAprobacionDetalleMovil  (App Mobile HU-31 — detalle de una evidencia forzada, un ensayo con error o un gasto para el jefe · lectura)
--   p_tipo: evidencia (id = id_evidencia) | ensayo (id = id_informe) | gasto (id = id_gasto).
--   Ver y resolver evidencia/ensayo: encargado del área de la RQ, supervisión general (Jefe/Coordinador de Operaciones, supervisor de Operaciones) o
--   administrador. Gasto: solo quien revisa gastos (prog_aprobar_reprogramacion). A quien no corresponde se le responde como si no existiera.
--   puede_resolver: sigue pendiente (gasto: pendiente u observado, programación confirmada y rendición abierta).
-- Resultados: 1 mensaje · 2 cabecera (1 fila; columnas que no aplican al tipo van en NULL) ·
--   3 líneas: gasto = reparto (id_viatico_linea, concepto, monto, asignado); ensayo = lecturas fuera del EMP (tipo, punto, carga, lectura, error, tolerancia);
--     evidencia = sin filas ·
--   4 fotos: orden, es_video, tiene_cuadro (gasto: sus fotos; evidencia: la toma; ensayo: sin filas). El archivo se pide por
--     GET api/movil/aprobaciones/evidencias/{id}/archivo[?cuadro=true] o GET api/movil/aprobaciones/gastos/{id}/fotos/{orden}.
--   Requiere las migraciones 113 y 114.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAprobacionDetalleMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAprobacionDetalleMovil(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id         BIGINT
)
proc: BEGIN
    DECLARE v_tipo      VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_id_os     BIGINT;
    DECLARE v_area_os   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ve        TINYINT DEFAULT 0;
    DECLARE v_prog      BIGINT;
    DECLARE v_abierta   TINYINT DEFAULT 0;
    DECLARE v_noexiste  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
                        DEFAULT 'No se encontró la aprobación o no corresponde a tu área.';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('evidencia', 'ensayo', 'gasto') OR IFNULL(p_id, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, v_noexiste AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;
    SET v_general = IFNULL(v_general, 0);

    IF v_tipo = 'evidencia' THEN
        SELECT MAX(id_os) INTO v_id_os FROM evidencia_fotografica WHERE id_evidencia = p_id AND override_aprobado = 1 AND eliminado_en IS NULL;
    ELSEIF v_tipo = 'ensayo' THEN
        SELECT MAX(id_os) INTO v_id_os FROM informe_tecnico WHERE id_informe = p_id AND error_critico_motivo IS NOT NULL AND eliminado_en IS NULL;
    ELSE
        SELECT MAX(id_os) INTO v_id_os FROM gasto_viatico WHERE id_gasto = p_id AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
    END IF;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, v_noexiste AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT asr.area_usuario INTO v_area_os
    FROM orden_servicio os
    LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
    LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
    WHERE os.id_os = v_id_os;

    IF v_tipo = 'gasto' THEN
        SET v_ve = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');
        SELECT COALESCE(g.id_programacion, (SELECT MAX(p2.id_programacion) FROM programacion p2
                                            WHERE p2.id_os = g.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL))
          INTO v_prog FROM gasto_viatico g WHERE g.id_gasto = p_id;
        SET v_abierta = IF(EXISTS (SELECT 1 FROM programacion WHERE id_programacion = v_prog AND estado = 'confirmada' AND eliminado_en IS NULL)
                           AND NOT EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL), 1, 0);
    ELSE
        SET v_ve = IF(v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe)), 1, 0);
    END IF;
    IF v_ve = 0 THEN
        SELECT 1 AS IdTipoMensaje, v_noexiste AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2. Cabecera
    IF v_tipo = 'evidencia' THEN
        SELECT 'evidencia' AS tipo, f.id_evidencia AS id,
               CONCAT('Evidencia forzada: ', IFNULL(f.codigo, 'foto')) AS titulo,
               IFNULL(f.revision_jefe, 'pendiente') AS estado,
               os.id_os, os.numero AS numero_os, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) AS cliente, sc.nombre AS sede,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), '') AS tecnico,
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i') AS hora_inicio,
               COALESCE(f.forzada_en, f.timestamp_captura) AS solicitada_en,
               f.motivo_forzado AS motivo,
               CONCAT_WS(' · ', IF(ec.codigo_tw IS NULL, NULL, CONCAT('Equipo ', ec.codigo_tw)), IF(IFNULL(f.pagina, 1) > 1, CONCAT('hoja ', f.pagina), NULL)) AS detalle,
               f.comentario_jefe AS comentario,
               NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS resuelto_por, f.revisado_jefe_en AS resuelto_en,
               IF(f.revision_jefe IS NULL, 1, 0) AS puede_resolver,
               f.codigo AS codigo_evidencia, f.motivo_rechazo_ia, f.es_video, ec.codigo_tw AS equipo,
               CAST(NULL AS SIGNED) AS n_criticas,
               CAST(NULL AS CHAR(20)) AS codigo, CAST(NULL AS CHAR(10)) AS origen, CAST(NULL AS CHAR(100)) AS concepto,
               CAST(NULL AS DECIMAL(12,2)) AS monto, CAST(NULL AS DATE) AS fecha_gasto, CAST(NULL AS CHAR(300)) AS descripcion,
               CAST(NULL AS CHAR(300)) AS motivo_sin_foto, CAST(NULL AS DECIMAL(12,2)) AS monto_ia, CAST(NULL AS SIGNED) AS coincide_ia,
               CAST(NULL AS CHAR(20)) AS codigo_programacion
        FROM evidencia_fotografica f
        JOIN orden_servicio os      ON os.id_os = f.id_os
        LEFT JOIN cliente cl        ON cl.id_cliente = os.id_cliente
        LEFT JOIN sede_cliente sc   ON sc.id_sede = os.id_sede
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = f.id_equipo
        LEFT JOIN usuario t         ON t.id_usuario = COALESCE(f.id_usuario_override, f.id_usuario)
        LEFT JOIN usuario j         ON j.id_usuario = f.revisado_jefe_por
        WHERE f.id_evidencia = p_id;

        SELECT CAST(NULL AS SIGNED) AS id_viatico_linea FROM DUAL WHERE 1 = 0;

        SELECT 1 AS orden, f.es_video, IF(NULLIF(TRIM(IFNULL(f.ruta_cuadro, '')), '') IS NULL, 0, 1) AS tiene_cuadro
        FROM evidencia_fotografica f
        WHERE f.id_evidencia = p_id AND NULLIF(TRIM(IFNULL(f.url_archivo, '')), '') IS NOT NULL;

    ELSEIF v_tipo = 'ensayo' THEN
        SELECT 'ensayo' AS tipo, it.id_informe AS id,
               'Ensayo con error crítico' AS titulo,
               IFNULL(it.error_critico_revision, 'pendiente') AS estado,
               os.id_os, os.numero AS numero_os, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) AS cliente, sc.nombre AS sede,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), '') AS tecnico,
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i') AS hora_inicio,
               COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en) AS solicitada_en,
               it.error_critico_motivo AS motivo,
               IF(ec.codigo_tw IS NULL, NULL, CONCAT('Equipo ', ec.codigo_tw)) AS detalle,
               it.error_critico_comentario AS comentario,
               NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS resuelto_por, it.error_critico_revisado_en AS resuelto_en,
               IF(it.error_critico_revision IS NULL, 1, 0) AS puede_resolver,
               CAST(NULL AS CHAR(20)) AS codigo_evidencia, CAST(NULL AS CHAR(300)) AS motivo_rechazo_ia, CAST(NULL AS SIGNED) AS es_video,
               ec.codigo_tw AS equipo,
               (SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL) AS n_criticas,
               CAST(NULL AS CHAR(20)) AS codigo, CAST(NULL AS CHAR(10)) AS origen, CAST(NULL AS CHAR(100)) AS concepto,
               CAST(NULL AS DECIMAL(12,2)) AS monto, CAST(NULL AS DATE) AS fecha_gasto, CAST(NULL AS CHAR(300)) AS descripcion,
               CAST(NULL AS CHAR(300)) AS motivo_sin_foto, CAST(NULL AS DECIMAL(12,2)) AS monto_ia, CAST(NULL AS SIGNED) AS coincide_ia,
               CAST(NULL AS CHAR(20)) AS codigo_programacion
        FROM informe_tecnico it
        JOIN orden_servicio os      ON os.id_os = it.id_os
        LEFT JOIN cliente cl        ON cl.id_cliente = os.id_cliente
        LEFT JOIN sede_cliente sc   ON sc.id_sede = os.id_sede
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
        LEFT JOIN usuario t         ON t.id_usuario = it.id_tecnico
        LEFT JOIN usuario j         ON j.id_usuario = it.error_critico_revisado_por
        WHERE it.id_informe = p_id;

        SELECT ie.tipo, ie.punto, ie.carga, ie.lectura, ie.error, ie.tolerancia
        FROM informe_ensayo ie
        WHERE ie.id_informe = p_id AND ie.critico = 1 AND ie.eliminado_en IS NULL
        ORDER BY ie.tipo, ie.orden, ie.id_ensayo;

        SELECT CAST(NULL AS SIGNED) AS orden FROM DUAL WHERE 1 = 0;

    ELSE
        SELECT 'gasto' AS tipo, g.id_gasto AS id,
               CONCAT('Gasto: ', IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, g.concepto_texto, IFNULL(cg.String1, 'Concepto'))) AS titulo,
               g.estado,
               os.id_os, os.numero AS numero_os, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) AS cliente, sc.nombre AS sede,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), '') AS tecnico,
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i') AS hora_inicio,
               COALESCE(g.modificado_en, g.creado_en) AS solicitada_en,
               g.motivo_sin_foto AS motivo,
               IF(g.coincide_ia = 0, CONCAT('La IA leyó S/ ', FORMAT(g.monto_ia, 2), ' en la boleta.'), NULL) AS detalle,
               g.comentario_revision AS comentario,
               NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS resuelto_por, g.revisado_en AS resuelto_en,
               IF(v_abierta = 1 AND g.estado IN ('pendiente', 'observado'), 1, 0) AS puede_resolver,
               CAST(NULL AS CHAR(20)) AS codigo_evidencia, CAST(NULL AS CHAR(300)) AS motivo_rechazo_ia, CAST(NULL AS SIGNED) AS es_video,
               CAST(NULL AS CHAR(30)) AS equipo, CAST(NULL AS SIGNED) AS n_criticas,
               CONCAT('GS-', LPAD(g.id_gasto, 6, '0')) AS codigo, g.origen,
               IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, CONCAT('Otro: ', g.concepto_texto), IFNULL(cg.String1, 'Concepto')) AS concepto,
               g.monto, COALESCE(g.fecha_gasto, g.fecha_solicitud) AS fecha_gasto, g.descripcion, g.motivo_sin_foto, g.monto_ia, g.coincide_ia,
               pr.codigo AS codigo_programacion
        FROM gasto_viatico g
        JOIN orden_servicio os     ON os.id_os = g.id_os
        LEFT JOIN cliente cl       ON cl.id_cliente = os.id_cliente
        LEFT JOIN sede_cliente sc  ON sc.id_sede = os.id_sede
        LEFT JOIN usuario t        ON t.id_usuario = g.id_usuario
        LEFT JOIN usuario j        ON j.id_usuario = g.revisado_por
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
        LEFT JOIN programacion pr  ON pr.id_programacion = v_prog
        WHERE g.id_gasto = p_id;

        SELECT rp.id_viatico_linea, IFNULL(cg.String1, 'Viático') AS concepto, rp.monto, l.monto AS asignado
        FROM gasto_viatico_reparto rp
        LEFT JOIN gasto_viatico l   ON l.id_gasto = rp.id_viatico_linea
        LEFT JOIN tabla_maestra cg  ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = l.id_concepto
        WHERE rp.id_gasto = p_id AND rp.eliminado_en IS NULL
        ORDER BY rp.id_reparto;

        SELECT x.orden, 0 AS es_video, 0 AS tiene_cuadro
        FROM (SELECT f.orden FROM gasto_viatico_foto f WHERE f.id_gasto = p_id AND f.eliminado_en IS NULL
              UNION
              SELECT 1 FROM gasto_viatico g2
              WHERE g2.id_gasto = p_id AND NULLIF(TRIM(IFNULL(g2.url_comprobante, '')), '') IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto f2 WHERE f2.id_gasto = p_id AND f2.eliminado_en IS NULL)) x
        ORDER BY x.orden;
    END IF;
END$$

DELIMITER ;
