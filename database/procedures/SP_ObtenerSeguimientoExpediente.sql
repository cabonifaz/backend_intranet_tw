-- HU-30 Tab 📞 Seguimiento de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Pills por propuesta ("Ver seguimiento de"); p_numero = número de la propuesta (por defecto la propuesta activa).
-- El responsable del seguimiento es siempre el de la propuesta (se hereda; no se reasigna aparte).
-- Resultados: 1 mensaje
--   2 propuestas del RQ (pills)
--   3 estado actual: estado global (sin_seguimiento, activo, cerrado_aceptacion, cerrado_rechazo), fechas de envío y
--     de cierre, días en seguimiento, comercial a cargo, contacto del cliente, última interacción, total de
--     interacciones y SLA del seguimiento (CONFIG_SLA expediente / seguimiento)
--   4 timeline de interacciones (envío al cliente, interacciones, correos enviados y cierre) con sus adjuntos (claves),
--     destinatario (contacto de la interacción, correos del "Para" o contacto de la propuesta en el envío), resumen del
--     cuerpo del correo (texto sin HTML, 300 caracteres) y tipo de aceptación
--   5 resultado del seguimiento (0 o 1 fila): aceptación o rechazo, fecha, registrado por, tipo de evidencia, motivo,
--     comentario, monto comprometido y días hasta el cierre
--   6 evidencias del cierre (clave seg-<id> para ver/descargar en /documentos/{clave})
DROP PROCEDURE IF EXISTS SP_ObtenerSeguimientoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSeguimientoExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_numero        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_rq    BIGINT;
    DECLARE v_numero   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima   BIGINT;
    DECLARE v_envio    DATETIME;
    DECLARE v_cierre   BIGINT;
    DECLARE v_sla      INT;

    SET SESSION group_concat_max_len = 1000000;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente;

    IF NULLIF(TRIM(IFNULL(p_numero, '')), '') IS NOT NULL THEN
        SELECT MAX(p.numero) INTO v_numero FROM propuesta_comercial p
        WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL AND p.numero = TRIM(p_numero);
        IF v_numero IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta no pertenece a este expediente.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SELECT p.numero INTO v_numero FROM propuesta_comercial p
        WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL AND p.estado <> 'anulado'
          AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)
        ORDER BY CASE p.estado WHEN 'aceptado' THEN 1 WHEN 'enviado' THEN 2 WHEN 'aprobado' THEN 2
                               WHEN 'pendiente_vb' THEN 3 WHEN 'pendiente_revocacion' THEN 3 WHEN 'rechazado' THEN 6 ELSE 4 END,
                 p.id_propuesta DESC
        LIMIT 1;
    END IF;

    SELECT MAX(p.id_propuesta) INTO v_ultima FROM propuesta_comercial p
    WHERE p.numero = v_numero AND p.eliminado_en IS NULL
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = v_numero AND p2.eliminado_en IS NULL);
    -- Envío al cliente: fecha_envio_cliente (HU-10b); si no está, el evento de auditoría envio_cliente
    SELECT MIN(COALESCE(p.fecha_envio_cliente, p.fecha_envio)) INTO v_envio FROM propuesta_comercial p
    WHERE p.numero = v_numero AND p.eliminado_en IS NULL;
    IF v_envio IS NULL THEN
        SELECT MIN(a.registrado_en) INTO v_envio FROM auditoria_evento a
        JOIN propuesta_comercial p ON p.id_propuesta = a.id_entidad AND p.numero = v_numero
        WHERE a.entidad_tipo = 'propuesta' AND a.accion = 'envio_cliente';
    END IF;
    SELECT s.id_seguimiento INTO v_cierre FROM seguimiento_comercial s
    JOIN propuesta_comercial p ON p.id_propuesta = s.id_propuesta AND p.numero = v_numero
    WHERE s.eliminado_en IS NULL AND s.estado IN ('cerrado_aceptacion', 'cerrado_rechazo')
    ORDER BY s.id_seguimiento DESC LIMIT 1;
    SELECT CAST(MAX(Num2) AS SIGNED) INTO v_sla FROM tabla_maestra
    WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'expediente' AND String2 = 'seguimiento' AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_seg;
    CREATE TEMPORARY TABLE tmp_exp_seg AS
    SELECT s.*, p.numero, p.version
    FROM seguimiento_comercial s
    JOIN propuesta_comercial p ON p.id_propuesta = s.id_propuesta AND p.numero = v_numero
    WHERE s.eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Propuestas (pills)
    SELECT p.numero, MAX(p.version) AS version, (p.numero = v_numero) AS seleccionada
    FROM propuesta_comercial p
    WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL
    GROUP BY p.numero ORDER BY MIN(p.id_propuesta);

    -- 3. Estado actual
    SELECT v_numero AS numero, pu.id_propuesta, pu.version, pu.estado AS estado_propuesta,
           CASE WHEN c.id_seguimiento IS NOT NULL THEN c.estado
                WHEN v_envio IS NOT NULL OR k.total > 0 THEN 'activo' ELSE 'sin_seguimiento' END AS estado_seguimiento,
           v_envio AS fecha_envio, IFNULL(c.fecha_interaccion, c.creado_en) AS fecha_cierre,
           IF(v_envio IS NULL, NULL,
              ROUND(TIMESTAMPDIFF(MINUTE, v_envio, IFNULL(IFNULL(c.fecha_interaccion, c.creado_en), NOW())) / 1440, 1)) AS dias_seguimiento,
           COALESCE(pu.id_responsable, pu.id_creador) AS id_comercial, CONCAT(uc.nombre, ' ', uc.apellido) AS comercial,
           uc.cargo AS cargo_comercial, uc.correo AS correo_comercial, uc.telefono AS telefono_comercial,
           uc.area AS codigo_area_comercial,
           (SELECT MAX(ar.String1) FROM tabla_maestra ar WHERE ar.IdMaestro = 79 AND ar.IdEmpresa = 1
              AND ar.String2 = uc.area)                                                     AS area_comercial,
           pu.id_contacto, ct.nombres AS contacto, ct.cargo AS cargo_contacto, ct.correo AS correo_contacto,
           k.ultima AS ultima_interaccion, IFNULL(k.total, 0) AS total_interacciones,
           v_sla AS sla_horas,
           IF(v_envio IS NULL OR v_sla IS NULL, NULL,
              IFNULL(IFNULL(c.fecha_interaccion, c.creado_en), NOW()) <= v_envio + INTERVAL v_sla HOUR) AS sla_cumplido
    FROM (SELECT 1) d
    LEFT JOIN propuesta_comercial pu ON pu.id_propuesta = v_ultima
    LEFT JOIN seguimiento_comercial c ON c.id_seguimiento = v_cierre
    LEFT JOIN usuario uc ON uc.id_usuario = COALESCE(pu.id_responsable, pu.id_creador)
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = pu.id_contacto
    LEFT JOIN (SELECT COUNT(*) AS total, MAX(IFNULL(fecha_interaccion, creado_en)) AS ultima FROM tmp_exp_seg) k ON TRUE;

    -- 4. Timeline de interacciones
    SELECT t.fecha, t.tipo, t.titulo, t.canal, t.resultado, t.asunto, t.detalle, t.duracion_minutos,
           t.proxima_accion_fecha, t.proxima_accion, t.version, t.id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, t.adjuntos,
           t.destinatario, t.resumen_cuerpo, t.tipo_aceptacion
    FROM (
        SELECT IFNULL(s.fecha_interaccion, s.creado_en) AS fecha,
               CASE s.estado WHEN 'cerrado_aceptacion' THEN 'aceptacion' WHEN 'cerrado_rechazo' THEN 'rechazo' ELSE 'interaccion' END AS tipo,
               CASE s.estado WHEN 'cerrado_aceptacion' THEN 'Aceptación de propuesta'
                             WHEN 'cerrado_rechazo' THEN 'Rechazo de propuesta'
                             ELSE IFNULL(cn.String1, 'Interacción') END AS titulo,
               cn.String1 AS canal, rs.String1 AS resultado, s.asunto, s.notas AS detalle, s.duracion_minutos,
               s.proxima_accion_fecha,
               NULLIF(CONCAT_WS(': ', ta.String1, NULLIF(TRIM(IFNULL(s.proxima_accion_detalle, '')), '')), '') AS proxima_accion,
               s.version, s.creado_por AS id_usuario,
               (SELECT GROUP_CONCAT(CONCAT('seg-', a.id_adjunto, '|', a.nombre_archivo) ORDER BY a.id_adjunto SEPARATOR ';')
                FROM seguimiento_adjunto a WHERE a.id_seguimiento = s.id_seguimiento AND a.eliminado_en IS NULL) AS adjuntos,
               ct.nombres AS destinatario, CAST(NULL AS CHAR(300)) AS resumen_cuerpo, tac.String1 AS tipo_aceptacion
        FROM tmp_exp_seg s
        LEFT JOIN contacto_cliente ct ON ct.id_contacto = s.id_contacto
        LEFT JOIN tabla_maestra tac ON tac.IdMaestro = 95 AND tac.IdEmpresa = 1 AND tac.Num1 = s.id_tipo_aceptacion
        LEFT JOIN tabla_maestra cn ON cn.IdMaestro = 26 AND cn.IdEmpresa = 1 AND cn.Num1 = s.id_canal
        LEFT JOIN tabla_maestra rs ON rs.IdMaestro = 27 AND rs.IdEmpresa = 1 AND rs.Num1 = s.id_resultado
        LEFT JOIN tabla_maestra ta ON ta.IdMaestro = 93 AND ta.IdEmpresa = 1 AND ta.Num1 = s.id_tipo_proxima_accion
        UNION ALL
        SELECT IFNULL(sc.fecha_envio, sc.creado_en), 'correo', 'Correo de seguimiento enviado', 'Correo electrónico', NULL,
               sc.asunto, CONCAT('Para: ', IFNULL(d.destinatarios, '')), NULL, NULL, NULL, p.version, sc.id_usuario,
               CONCAT('mail-', sc.id_correo, '|correo_seguimiento_', sc.id_correo, '.eml'),
               d.destinatarios,
               LEFT(TRIM(REGEXP_REPLACE(REGEXP_REPLACE(IFNULL(sc.cuerpo_html, ''), '<[^>]*>', ' '), '[[:space:]]+', ' ')), 300),
               NULL
        FROM seguimiento_correo sc
        JOIN propuesta_comercial p ON p.id_propuesta = sc.id_propuesta AND p.numero = v_numero
        -- "Para": lista de {correo, nombre} o de textos
        LEFT JOIN LATERAL (
            SELECT GROUP_CONCAT(COALESCE(IF(j.nombre IS NULL, j.correo, CONCAT(j.nombre, ' <', j.correo, '>')), j.texto)
                                SEPARATOR ', ') AS destinatarios
            FROM JSON_TABLE(IF(JSON_VALID(sc.para) AND JSON_TYPE(sc.para) = 'ARRAY', sc.para, JSON_ARRAY()), '$[*]'
                            COLUMNS (correo VARCHAR(200) PATH '$.correo', nombre VARCHAR(200) PATH '$.nombre',
                                     texto VARCHAR(200) PATH '$')) j
        ) d ON TRUE
        WHERE sc.eliminado_en IS NULL AND sc.estado = 'enviado'
        UNION ALL
        SELECT a.registrado_en, 'envio', 'Propuesta enviada al cliente', NULL, NULL, NULL, a.descripcion, NULL, NULL, NULL,
               p.version, a.id_usuario, NULL, cp.nombres, NULL, NULL
        FROM auditoria_evento a
        JOIN propuesta_comercial p ON p.id_propuesta = a.id_entidad AND p.numero = v_numero
        LEFT JOIN contacto_cliente cp ON cp.id_contacto = p.id_contacto
        WHERE a.entidad_tipo = 'propuesta' AND a.accion = 'envio_cliente'
    ) t
    LEFT JOIN usuario u ON u.id_usuario = t.id_usuario
    ORDER BY t.fecha DESC;

    -- 5. Resultado del seguimiento
    SELECT IF(c.estado = 'cerrado_aceptacion', 'aceptacion', 'rechazo') AS resultado, IFNULL(c.fecha_interaccion, c.creado_en) AS fecha_cierre,
           c.creado_por AS id_registrado_por, CONCAT(u.nombre, ' ', u.apellido) AS registrado_por,
           ta.String1 AS tipo_evidencia, mr.String1 AS motivo_rechazo, cn.String1 AS canal, c.notas AS comentario,
           IF(c.estado = 'cerrado_aceptacion', p.total, NULL) AS monto_comprometido, m.String2 AS simbolo_moneda,
           IF(v_envio IS NULL, NULL, ROUND(TIMESTAMPDIFF(MINUTE, v_envio, IFNULL(c.fecha_interaccion, c.creado_en)) / 1440, 1)) AS dias_hasta_cierre,
           c.permite_reactivacion
    FROM seguimiento_comercial c
    JOIN propuesta_comercial p ON p.id_propuesta = c.id_propuesta
    LEFT JOIN usuario u ON u.id_usuario = c.creado_por
    LEFT JOIN tabla_maestra ta ON ta.IdMaestro = 95 AND ta.IdEmpresa = 1 AND ta.Num1 = c.id_tipo_aceptacion
    LEFT JOIN tabla_maestra mr ON mr.IdMaestro = 10 AND mr.IdEmpresa = 1 AND mr.Num1 = c.id_motivo_cierre
    LEFT JOIN tabla_maestra cn ON cn.IdMaestro = 26 AND cn.IdEmpresa = 1 AND cn.Num1 = c.id_canal
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    WHERE c.id_seguimiento = v_cierre;

    -- 6. Evidencias del cierre
    SELECT CONCAT('seg-', a.id_adjunto) AS clave, a.nombre_archivo, a.tipo_contenido, a.tamano_bytes, a.creado_en AS fecha
    FROM seguimiento_adjunto a
    WHERE a.id_seguimiento = v_cierre AND a.eliminado_en IS NULL
    ORDER BY a.id_adjunto;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_seg;
END$$

DELIMITER ;
