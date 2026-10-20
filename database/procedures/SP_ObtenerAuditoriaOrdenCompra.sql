-- HU-26 (Sprint 4) Timeline inmutable de la orden de compra (ISO 9001): creación, cargas y reemplazos del PDF,
-- extracción y validaciones de la IA, correcciones manuales, decisiones del comercial, vinculaciones agregadas o
-- quitadas, cambios de estado, reemplazo de la OC autogenerada y anulación. También los accesos al PDF.
-- Todo sale de registros de solo inserción (auditoria_evento, descarga_documento). Se consulta desde el detalle y se
-- descarga en XLSX: p_registrar_exportacion = 1 deja constancia de la descarga (exportar_auditoria_oc).
-- categoria: validacion_ia | comercial | documental (filtros del timeline). nivel: exito | alerta | critico | info | neutro.
-- Resultados: 1 mensaje, 2 cabecera, 3 eventos (más recientes primero).
DROP PROCEDURE IF EXISTS SP_ObtenerAuditoriaOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAuditoriaOrdenCompra(
    IN p_id_usuario            BIGINT,
    IN p_id_oc                 BIGINT,
    IN p_registrar_exportacion TINYINT
)
proc: BEGIN
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_estado_visual VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_visual) INTO v_existe, v_estado_visual FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_registrar_exportacion, 0) = 1 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en)
        VALUES ('orden_compra', p_id_oc, 'exportar_auditoria_oc', 'Descarga del timeline de la orden de compra (XLSX).',
                p_id_usuario, NOW());
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT oc.id_oc, oc.numero_oc, oc.estado, v_estado_visual AS estado_visual, oc.es_autogenerada,
           c.id_cliente, c.razon_social, c.ruc,
           p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta,
           NOW() AS generado_en, CONCAT(u.nombre, ' ', u.apellido) AS generado_por
    FROM orden_compra oc
    LEFT JOIN cliente c             ON c.id_cliente   = oc.id_cliente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = oc.id_propuesta
    LEFT JOIN usuario u             ON u.id_usuario   = p_id_usuario
    WHERE oc.id_oc = p_id_oc;

    -- 3. Eventos
    SELECT t.id_evento, t.fecha, t.accion, t.titulo, t.descripcion, t.categoria, t.nivel,
           t.estado_anterior, t.estado_nuevo, t.metadata, t.url,
           t.id_usuario, IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, u.area, u.rol_sistema AS rol,
           (t.accion IN ('extraccion_ia', 'validacion_ia'))                         AS automatico_ia
    FROM (
        SELECT a.id_auditoria AS id_evento, a.registrado_en AS fecha, a.accion,
               CASE a.accion
                   WHEN 'registrar_oc'            THEN 'Creación y registro de la orden de compra'
                   WHEN 'autogenerar_oc'          THEN 'OC provisional autogenerada'
                   WHEN 'reemplazar_oc_auto'      THEN 'OC autogenerada reemplazada por la OC del cliente'
                   WHEN 'cargar_pdf_oc'           THEN 'Carga del PDF de la orden de compra'
                   WHEN 'reemplazar_pdf'          THEN 'Reemplazo del PDF'
                   WHEN 'subir_oc_corregida'      THEN 'OC corregida por el cliente'
                   WHEN 'extraccion_ia'           THEN 'Extracción de datos por IA'
                   WHEN 'corregir_campo_oc'       THEN 'Corrección manual de un dato extraído'
                   WHEN 'validacion_ia'           THEN CONCAT('Validación IA: ',
                                                         CASE a.estado_nuevo WHEN 'ok' THEN 'sin diferencias'
                                                              WHEN 'critico' THEN 'diferencias críticas' ELSE 'con diferencias' END)
                   WHEN 'decision_oc'             THEN 'Decisión del comercial'
                   WHEN 'vincular_propuesta'      THEN 'Propuesta vinculada'
                   WHEN 'desvincular_propuesta'   THEN 'Propuesta desvinculada'
                   WHEN 'editar_vinculacion'      THEN 'Monto asignado modificado'
                   WHEN 'nueva_version_propuesta' THEN 'Nueva versión de propuesta generada'
                   WHEN 'editar_oc'               THEN 'Orden de compra editada'
                   WHEN 'cambio_estado_oc'        THEN CONCAT('Cambio de estado a ', UPPER(a.estado_nuevo))
                   WHEN 'anular_oc'               THEN 'Orden de compra anulada'
                   WHEN 'exportar_auditoria_oc'   THEN 'Descarga del timeline'
                   -- Eventos anteriores al refinamiento (Sprint 3)
                   WHEN 'validar_oc'              THEN 'Orden de compra validada'
                   WHEN 'observar_oc'             THEN 'Orden de compra observada'
                   WHEN 'levantar_observacion_oc' THEN 'Observación levantada'
                   WHEN 'editar_oc_revalidacion'  THEN 'OC editada y enviada a revalidación'
                   WHEN 'distribuir_oc'           THEN 'Saldo de la OC distribuido'
                   WHEN 'liberar_oc'              THEN 'Expediente liberado para programación'
                   WHEN 'registrar_oc_complementaria' THEN 'OC complementaria registrada'
                   WHEN 'reemplazar_documento_oc' THEN 'Reemplazo del PDF'
                   ELSE REPLACE(a.accion, '_', ' ')
               END                                                                       AS titulo,
               a.descripcion,
               CASE
                   WHEN a.accion IN ('extraccion_ia', 'validacion_ia', 'corregir_campo_oc')              THEN 'validacion_ia'
                   WHEN a.accion IN ('cargar_pdf_oc', 'reemplazar_pdf', 'subir_oc_corregida',
                                     'exportar_auditoria_oc', 'reemplazar_documento_oc')                 THEN 'documental'
                   ELSE                                                                                       'comercial'
               END                                                                       AS categoria,
               CASE
                   WHEN a.accion = 'anular_oc'                                                           THEN 'critico'
                   WHEN a.accion = 'validacion_ia' AND a.estado_nuevo = 'critico'                        THEN 'critico'
                   WHEN a.accion = 'validacion_ia' AND a.estado_nuevo = 'advertencia'                    THEN 'alerta'
                   WHEN a.accion = 'validacion_ia'                                                       THEN 'exito'
                   WHEN a.accion = 'decision_oc' AND a.estado_nuevo = 'validar'                          THEN 'exito'
                   WHEN a.accion = 'decision_oc'                                                         THEN 'alerta'
                   WHEN a.accion = 'cambio_estado_oc' AND a.estado_nuevo = 'validada'                    THEN 'exito'
                   WHEN a.accion = 'cambio_estado_oc' AND a.estado_nuevo IN ('validada_parcial', 'observada') THEN 'alerta'
                   WHEN a.accion IN ('registrar_oc', 'autogenerar_oc')                                   THEN 'info'
                   WHEN a.accion IN ('validar_oc', 'liberar_oc', 'levantar_observacion_oc')              THEN 'exito'
                   WHEN a.accion IN ('observar_oc', 'editar_oc_revalidacion', 'desvincular_propuesta')   THEN 'alerta'
                   WHEN a.accion = 'exportar_auditoria_oc'                                               THEN 'neutro'
                   ELSE                                                                                       'info'
               END                                                                       AS nivel,
               a.estado_anterior, a.estado_nuevo, a.metadata,
               CASE WHEN a.accion IN ('cargar_pdf_oc', 'reemplazar_pdf', 'subir_oc_corregida')
                    THEN CONCAT('/api/crm/ordenes-compra/', p_id_oc, '/pdf') END                AS url,
               a.id_usuario
        FROM auditoria_evento a
        WHERE a.entidad_tipo = 'orden_compra' AND a.id_entidad = p_id_oc
        UNION ALL
        -- OC registradas antes del refinamiento (sin evento de registro)
        SELECT 0, oc.fecha_registro, 'registrar_oc', 'Creación y registro de la orden de compra',
               CONCAT('OC ', oc.numero_oc, ' por ', FORMAT(oc.monto_total, 2), '.'), 'comercial', 'info',
               NULL, NULL, NULL, NULL, oc.creado_por
        FROM orden_compra oc
        WHERE oc.id_oc = p_id_oc
          AND NOT EXISTS (SELECT 1 FROM auditoria_evento a2 WHERE a2.entidad_tipo = 'orden_compra' AND a2.id_entidad = p_id_oc
                            AND a2.accion IN ('registrar_oc', 'autogenerar_oc'))
        UNION ALL
        SELECT 0, dd.registrado_en, 'acceso_documento', 'Visualización o descarga del PDF',
               CONCAT('Visualizó o descargó el PDF (', SUBSTRING_INDEX(dd.url_archivo, '/', -1), ').'), 'documental', 'neutro',
               NULL, NULL, NULL, NULL, dd.id_usuario
        FROM descarga_documento dd
        WHERE dd.entidad_tipo = 'orden_compra' AND dd.id_entidad = p_id_oc
    ) t
    LEFT JOIN usuario u ON u.id_usuario = t.id_usuario
    ORDER BY t.fecha DESC, t.id_evento DESC;
END$$

DELIMITER ;
