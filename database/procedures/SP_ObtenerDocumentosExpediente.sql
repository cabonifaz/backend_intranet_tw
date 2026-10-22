-- HU-31 Modal "Repositorio de Documentos del Expediente" (solo lectura: los documentos se cargan en los módulos origen).
-- Acción expediente_bandeja. Lista solo lo que el usuario puede ver (ver SP_CargarDocumentosExpediente).
-- Filtros (opcionales): p_categoria (todos, comerciales, operativos, ssoma, tecnicos), p_busqueda (nombre, tipo u origen),
--   p_desde / p_hasta (fecha de carga), p_estado, p_formato (PDF, XLSX, DOCX, EML, JPG, PNG, OTRO) y p_orden
--   ('desc' = más recientes primero, por defecto; 'asc' invierte).
-- Los contadores de las pestañas aplican los demás filtros. p_exportar = 1 registra la exportación de la lista (XLSX).
-- Resultados: 1 mensaje · 2 resumen · 3 pestañas (Todos + 4 categorías, con cantidad) · 4 documentos · 5 estados
--   · 6 formatos
DROP PROCEDURE IF EXISTS SP_ObtenerDocumentosExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDocumentosExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_categoria     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_desde         DATE,
    IN p_hasta         DATE,
    IN p_estado        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_formato       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_orden         VARCHAR(4)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_exportar      TINYINT
)
proc: BEGIN
    DECLARE v_categoria VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda  VARCHAR(102) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_asc       TINYINT;
    DECLARE v_total     INT DEFAULT 0;
    DECLARE v_filtrados INT DEFAULT 0;

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

    SET v_categoria = LOWER(IFNULL(NULLIF(TRIM(p_categoria), ''), 'todos'));
    SET v_busqueda  = IF(NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));
    SET v_asc       = (LOWER(IFNULL(p_orden, '')) = 'asc');

    CALL SP_CargarDocumentosExpediente(p_id_usuario, p_id_expediente);
    SELECT COUNT(*) INTO v_total FROM tmp_exp_doc;

    -- Filtros que no son la pestaña
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc_f;
    CREATE TEMPORARY TABLE tmp_exp_doc_f AS
    SELECT d.* FROM tmp_exp_doc d
    WHERE (v_busqueda IS NULL OR d.nombre LIKE v_busqueda OR d.nombre_archivo LIKE v_busqueda OR d.tipo LIKE v_busqueda
           OR d.origen LIKE v_busqueda)
      AND (p_desde IS NULL OR d.fecha >= p_desde)
      AND (p_hasta IS NULL OR d.fecha < p_hasta + INTERVAL 1 DAY)
      AND (NULLIF(TRIM(IFNULL(p_estado, '')), '') IS NULL OR d.estado = TRIM(p_estado))
      AND (NULLIF(TRIM(IFNULL(p_formato, '')), '') IS NULL OR d.formato = UPPER(TRIM(p_formato)));

    SELECT COUNT(*) INTO v_filtrados FROM tmp_exp_doc_f;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc_cnt;
    CREATE TEMPORARY TABLE tmp_exp_doc_cnt AS SELECT categoria, COUNT(*) AS cantidad FROM tmp_exp_doc_f GROUP BY categoria;

    IF IFNULL(p_exportar, 0) = 1 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('expediente', p_id_expediente, 'exportar_documentos', 'Lista de documentos del expediente exportada.',
                p_id_usuario, NOW(),
                JSON_OBJECT('categoria', v_categoria, 'busqueda', p_busqueda, 'desde', p_desde, 'hasta', p_hasta,
                            'estado', p_estado, 'formato', p_formato));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT e.id_expediente, e.numero, c.razon_social, c.ruc, v_total AS total_documentos
    FROM expediente_digital e
    LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    LEFT JOIN cliente c ON c.id_cliente = COALESCE(e.id_cliente, r.id_cliente)
    WHERE e.id_expediente = p_id_expediente;

    -- 3. Pestañas con cantidad (Todos + CATEGORIA_DOCUMENTO_EXPEDIENTE)
    SELECT 'todos' AS codigo, 'Todos' AS nombre, v_filtrados AS cantidad, 0 AS orden
    UNION ALL
    SELECT t.String2, t.String1, IFNULL(k.cantidad, 0), t.Num1
    FROM tabla_maestra t
    LEFT JOIN tmp_exp_doc_cnt k ON k.categoria = t.String2
    WHERE t.IdMaestro = 101 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL
    ORDER BY orden;

    -- 4. Documentos de la pestaña (más recientes primero, o al revés con p_orden = 'asc')
    SELECT d.clave, d.nombre, d.nombre_archivo, d.tipo, d.categoria, d.origen, d.modulo, d.etapa_origen,
           d.etapa, et.String1 AS etapa_nombre, d.version, d.estado, d.fecha, d.id_usuario,
           CONCAT(u.nombre, ' ', u.apellido) AS usuario, u.cargo AS cargo_usuario, a.String1 AS area_usuario,
           d.tamano_bytes, d.tipo_contenido, d.formato, d.descripcion, d.visibilidad, d.es_interno,
           (d.ruta IS NOT NULL OR d.id_propuesta IS NOT NULL OR d.id_correo IS NOT NULL) AS descargable,
           (d.formato IN ('PDF', 'JPG', 'PNG')) AS previsualizable
    FROM tmp_exp_doc_f d
    LEFT JOIN usuario u        ON u.id_usuario = d.id_usuario
    LEFT JOIN tabla_maestra a  ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = u.area
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = d.etapa
    WHERE v_categoria = 'todos' OR d.categoria = v_categoria
    ORDER BY IF(v_asc = 1, d.fecha, NULL) ASC, IF(v_asc = 1, NULL, d.fecha) DESC, d.clave;

    -- 5. Estados presentes (para el filtro, tal cual)
    SELECT DISTINCT d.estado AS codigo, d.estado AS nombre FROM tmp_exp_doc d WHERE d.estado IS NOT NULL ORDER BY d.estado;

    -- 6. Formatos presentes
    SELECT DISTINCT d.formato AS codigo, d.formato AS nombre FROM tmp_exp_doc d ORDER BY d.formato;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc_cnt;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc_f;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;
END$$

DELIMITER ;
