-- HU-31 Repositorio integrado de documentos del expediente.
-- Acción expediente_bandeja. Solo lista los documentos que el usuario puede ver (ver SP_CargarDocumentosExpediente).
-- Resultados: 1 mensaje · 2 resumen (con permiso para adjuntar) · 3 categorías (pestañas, con cantidad)
--   · 4 documentos · 5 tipos de documento que se pueden adjuntar · 6 etapas · 7 visibilidades
DROP PROCEDURE IF EXISTS SP_ObtenerDocumentosExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDocumentosExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
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

    CALL SP_CargarDocumentosExpediente(p_id_usuario, p_id_expediente);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT e.id_expediente, e.numero, c.razon_social, c.ruc, e.etapa_actual,
           (FN_PermisoAccion(p_id_usuario, 'expediente_documento_adjuntar') = 1 AND e.estado <> 'cerrado') AS puede_adjuntar
    FROM expediente_digital e
    LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    LEFT JOIN cliente c ON c.id_cliente = COALESCE(e.id_cliente, r.id_cliente)
    WHERE e.id_expediente = p_id_expediente;

    -- 3. Categorías (CATEGORIA_DOCUMENTO_EXPEDIENTE) con cantidad
    SELECT t.String2 AS codigo, t.String1 AS nombre,
           (SELECT COUNT(*) FROM tmp_exp_doc d WHERE d.categoria = t.String2) AS cantidad
    FROM tabla_maestra t WHERE t.IdMaestro = 101 AND t.IdEmpresa = 1 ORDER BY t.Num1;

    -- 4. Documentos (más recientes primero)
    SELECT d.clave, d.nombre, d.nombre_archivo, d.tipo, d.categoria, d.origen, d.etapa, et.String1 AS etapa_nombre,
           d.version, d.estado, d.fecha, d.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario,
           d.tamano_bytes, d.tipo_contenido, d.descripcion, d.visibilidad, d.es_interno,
           (d.ruta IS NOT NULL OR d.id_propuesta IS NOT NULL) AS descargable
    FROM tmp_exp_doc d
    LEFT JOIN usuario u        ON u.id_usuario = d.id_usuario
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = d.etapa
    ORDER BY (d.estado = 'HISTÓRICO'), d.fecha DESC;

    -- 5. Tipos de documento para adjuntar (TIPO_DOCUMENTO_ADJUNTO con Num2 = 1, tal cual)
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo, String3 AS categoria
    FROM tabla_maestra WHERE IdMaestro = 96 AND IdEmpresa = 1 AND IFNULL(Num2, 0) = 1 ORDER BY Num1;

    -- 6. Etapas (ETAPA_EXPEDIENTE sin "Cerrado", tal cual)
    SELECT String2 AS codigo, String1 AS nombre
    FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 AND String2 <> 'cerrado' ORDER BY Num1;

    -- 7. Visibilidad: Interno (1) o un área (2-4) de VISIBILIDAD_DOCUMENTO
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo, IF(Num1 = 1, 'interno', 'area') AS tipo
    FROM tabla_maestra WHERE IdMaestro = 35 AND IdEmpresa = 1 AND Num1 BETWEEN 1 AND 4 ORDER BY Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;
END$$

DELIMITER ;
