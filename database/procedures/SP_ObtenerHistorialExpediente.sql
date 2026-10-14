-- HU-33 Historial del expediente (auditoría ISO 9001): cronológico e inmutable.
-- Acción expediente_bandeja. Filtros opcionales: tipo de evento, usuario, etapa y rango de fechas (inclusive).
-- p_exportar = 1 registra la exportación en la auditoría (accion exportar_historial).
-- Resultados: 1 mensaje · 2 resumen · 3 eventos (más recientes primero) · 4 tipos de evento · 5 usuarios · 6 etapas
DROP PROCEDURE IF EXISTS SP_ObtenerHistorialExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerHistorialExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_tipo_evento   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario_evento BIGINT,
    IN p_etapa         VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_desde         DATE,
    IN p_hasta         DATE,
    IN p_exportar      TINYINT
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_desde IS NOT NULL AND p_hasta IS NOT NULL AND p_desde > p_hasta THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha desde no puede ser posterior a la fecha hasta.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarEventosExpediente(p_id_usuario, p_id_expediente);

    IF IFNULL(p_exportar, 0) = 1 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('expediente', p_id_expediente, 'exportar_historial', 'Historial del expediente exportado.', p_id_usuario, NOW(),
                JSON_OBJECT('tipo_evento', p_tipo_evento, 'id_usuario', p_id_usuario_evento,
                            'etapa_filtro', p_etapa, 'desde', p_desde, 'hasta', p_hasta));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT e.id_expediente, e.numero, c.razon_social, c.ruc
    FROM expediente_digital e
    LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    LEFT JOIN cliente c ON c.id_cliente = COALESCE(e.id_cliente, r.id_cliente)
    WHERE e.id_expediente = p_id_expediente;

    -- 3. Eventos filtrados
    SELECT ev.fecha, ev.tipo_evento, ev.accion, ev.titulo, ev.descripcion, ev.etapa, et.String1 AS etapa_nombre,
           ev.id_usuario, IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario,
           ev.entidad, ev.referencia, ev.urgente
    FROM tmp_exp_evt ev
    LEFT JOIN usuario u        ON u.id_usuario = ev.id_usuario
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = ev.etapa
    WHERE (NULLIF(TRIM(IFNULL(p_tipo_evento, '')), '') IS NULL OR ev.tipo_evento = TRIM(p_tipo_evento))
      AND (IFNULL(p_id_usuario_evento, 0) = 0 OR ev.id_usuario = p_id_usuario_evento)
      AND (NULLIF(TRIM(IFNULL(p_etapa, '')), '') IS NULL OR ev.etapa = TRIM(p_etapa))
      AND (p_desde IS NULL OR ev.fecha >= p_desde)
      AND (p_hasta IS NULL OR ev.fecha < p_hasta + INTERVAL 1 DAY)
    ORDER BY ev.fecha DESC;

    -- 4. Tipos de evento
    SELECT v.codigo, v.nombre FROM (
        SELECT 1 AS o, 'creacion' AS codigo, 'Creación' AS nombre UNION ALL
        SELECT 2, 'requerimiento', 'Requerimiento'       UNION ALL
        SELECT 3, 'visto_bueno',   'Visto bueno'         UNION ALL
        SELECT 4, 'orden_compra',  'Orden de compra'     UNION ALL
        SELECT 5, 'etapa',         'Cambio de etapa'     UNION ALL
        SELECT 6, 'bloqueo',       'Bloqueos y excepciones' UNION ALL
        SELECT 7, 'documento',     'Documentos'          UNION ALL
        SELECT 8, 'reasignacion',  'Reasignación'        UNION ALL
        SELECT 9, 'anulacion',     'Anulación'           UNION ALL
        SELECT 10, 'otro',         'Otros'
    ) v ORDER BY v.o;

    -- 5. Usuarios que aparecen en el historial
    SELECT DISTINCT u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre
    FROM tmp_exp_evt ev JOIN usuario u ON u.id_usuario = ev.id_usuario
    ORDER BY nombre;

    -- 6. Etapas (ETAPA_EXPEDIENTE, tal cual)
    SELECT String2 AS codigo, String1 AS nombre
    FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 ORDER BY Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_evt;
END$$

DELIMITER ;
