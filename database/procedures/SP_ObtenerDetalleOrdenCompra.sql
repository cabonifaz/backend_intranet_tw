-- HU-23 Detalle de una Orden de Compra.
-- Resultados:
--   1 mensaje
--   2 resumen (HU-26: con la observación abierta): datos generales, cobertura económica (propuesta vs. OC, diferencia/saldo, utilización),
--     estado, vigencia, responsable, PDF y referencia del servicio
--   3 aplicaciones: propuestas vinculadas a la OC con su monto asignado (HU-27: cubierto por otras OC y pendiente)
--   4 checklist de validación (codigo, descripcion, cumple, detalle)
--   5 vinculaciones del proceso: RQ, propuesta, expediente y OS (disponible = 0 si aún no existe)
--   6 documentos: PDF de la OC, PDF de las propuestas y evidencias de la aceptación
--   7 workflow: etapas con estado completado | actual | observado | bloqueado | pendiente
--   8 historial (HU-24: incluye las ediciones de la OC)
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
BEGIN
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_propuesta   BIGINT;
    DECLARE v_id_rq          BIGINT;
    DECLARE v_id_expediente  BIGINT;
    DECLARE v_id_moneda      INT;
    DECLARE v_numero_oc      VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_monto_oc       DECIMAL(14,2);
    DECLARE v_monto_prop     DECIMAL(14,2);
    DECLARE v_fecha_oc       DATE;
    DECLARE v_vigencia_hasta DATE;
    DECLARE v_tiene_pdf      TINYINT;
    DECLARE v_validada       TINYINT;
    DECLARE v_vencida        TINYINT;
    DECLARE v_estado_visual  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cob_proy       VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_lista          TINYINT;
    DECLARE v_n_os           INT DEFAULT 0;
    DECLARE v_fecha_registro DATETIME;
    DECLARE v_creado_por     BIGINT;
    DECLARE v_fecha_valid    DATETIME;
    DECLARE v_fecha_acept    DATETIME;
    DECLARE v_fecha_envio    DATETIME;
    DECLARE v_fecha_rq       DATETIME;
    DECLARE v_id_os          BIGINT;
    DECLARE v_estado_os      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_os       DATETIME;
    DECLARE v_fecha_lib      DATETIME;
    -- checklist
    DECLARE v_n_prop         INT DEFAULT 0;
    DECLARE v_otro_cliente   INT DEFAULT 0;
    DECLARE v_otra_moneda    INT DEFAULT 0;
    DECLARE v_no_ultima      INT DEFAULT 0;
    DECLARE v_no_valida      INT DEFAULT 0;
    DECLARE v_expirada       INT DEFAULT 0;
    DECLARE v_no_aceptada    INT DEFAULT 0;
    DECLARE v_duplicadas     INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
    ELSE
        CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);

        SELECT COUNT(*), MAX(id_cliente), MAX(id_propuesta), MAX(id_requerimiento), MAX(id_expediente),
               MAX(id_moneda), MAX(numero_oc), MAX(monto_oc), MAX(monto_requerido_neto), MAX(fecha_oc),
               MAX(vigencia_hasta), MAX(tiene_pdf), MAX(validada), MAX(vencida), MAX(estado_visual),
               MAX(cobertura_proyectada), MAX(lista_programacion), MAX(ordenes_servicio),
               MAX(fecha_registro), MAX(creado_por), MAX(fecha_liberacion)
          INTO v_existe, v_id_cliente, v_id_propuesta, v_id_rq, v_id_expediente,
               v_id_moneda, v_numero_oc, v_monto_oc, v_monto_prop, v_fecha_oc,
               v_vigencia_hasta, v_tiene_pdf, v_validada, v_vencida, v_estado_visual,
               v_cob_proy, v_lista, v_n_os,
               v_fecha_registro, v_creado_por, v_fecha_lib
        FROM tmp_oc;

        IF v_existe = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_oc;
            IF EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND eliminado_en IS NULL) THEN
                SELECT 1 AS IdTipoMensaje, 'La orden de compra no pertenece a tu área.' AS Mensaje;
            ELSE
                SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe.' AS Mensaje;
            END IF;
        ELSE
            -- Propuestas vinculadas
            DROP TEMPORARY TABLE IF EXISTS tmp_oc_prop;
            CREATE TEMPORARY TABLE tmp_oc_prop AS
            SELECT p.id_propuesta, p.numero, p.version, p.estado, p.id_cliente, p.id_moneda, p.total,
                   p.fecha_expiracion, p.id_requerimiento,
                   COALESCE(p.fecha_envio_cliente, p.fecha_envio)                            AS fecha_envio,
                   (p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                                 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL))    AS ultima_version,
                   (SELECT op.monto_asignado FROM oc_propuesta op
                    WHERE op.id_oc = p_id_oc AND op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL
                    ORDER BY op.id DESC LIMIT 1)                                             AS monto_asignado,
                   (SELECT op.creado_en FROM oc_propuesta op
                    WHERE op.id_oc = p_id_oc AND op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL
                    ORDER BY op.id DESC LIMIT 1)                                             AS fecha_asignacion,
                   (SELECT MAX(s.fecha_interaccion) FROM seguimiento_comercial s
                    WHERE s.id_propuesta = p.id_propuesta AND s.estado = 'cerrado_aceptacion'
                      AND s.eliminado_en IS NULL)                                            AS fecha_aceptacion
            FROM propuesta_comercial p
            WHERE p.id_propuesta = v_id_propuesta
               OR p.id_propuesta IN (SELECT op.id_propuesta FROM oc_propuesta op
                                     WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL);

            SELECT COUNT(*),
                   IFNULL(SUM(id_cliente <> v_id_cliente), 0),
                   IFNULL(SUM(id_moneda <> v_id_moneda), 0),
                   IFNULL(SUM(ultima_version = 0), 0),
                   IFNULL(SUM(estado IN ('anulado', 'vencido', 'rechazado', 'borrador', 'pendiente_vb')), 0),
                   IFNULL(SUM(fecha_expiracion IS NOT NULL AND fecha_expiracion < v_fecha_oc), 0),
                   IFNULL(SUM(fecha_aceptacion IS NULL AND estado <> 'aprobado'), 0),
                   MIN(fecha_envio), MAX(fecha_aceptacion)
              INTO v_n_prop, v_otro_cliente, v_otra_moneda, v_no_ultima, v_no_valida, v_expirada, v_no_aceptada,
                   v_fecha_envio, v_fecha_acept
            FROM tmp_oc_prop;

            SELECT COUNT(*) INTO v_duplicadas
            FROM orden_compra
            WHERE id_cliente = v_id_cliente AND numero_oc = v_numero_oc AND id_oc <> p_id_oc
              AND eliminado_en IS NULL AND estado <> 'anulada';

            SELECT MAX(registrado_en) INTO v_fecha_valid
            FROM auditoria_evento
            WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc AND accion = 'validar_oc';

            SELECT fecha_creacion INTO v_fecha_rq FROM requerimiento WHERE id_requerimiento = v_id_rq;

            SELECT os.id_os, os.estado, os.fecha_creacion INTO v_id_os, v_estado_os, v_fecha_os
            FROM orden_servicio os
            JOIN expediente_digital e ON e.id_expediente = os.id_expediente AND e.eliminado_en IS NULL
            WHERE os.eliminado_en IS NULL AND os.estado <> 'anulada'
              AND e.id_expediente = FN_ExpedienteDePropuesta(v_id_propuesta)
            ORDER BY os.id_os DESC LIMIT 1;

            -- 1. Header
            SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

            -- 2. Resumen
            SELECT
                t.id_oc, t.numero_oc, oc.referencia, t.estado_bd AS estado, t.estado_visual,
                t.fecha_oc, t.fecha_recepcion, t.vigencia_desde, t.vigencia_hasta, t.vigencia_dias,
                IF(t.vigencia_hasta IS NULL, NULL, DATEDIFF(t.vigencia_hasta, CURDATE())) AS dias_para_vencer,
                t.observaciones,
                t.id_cliente, c.razon_social, c.ruc,
                t.id_requerimiento, r.numero AS numero_rq,
                LEFT(r.descripcion, 300)                     AS referencia_servicio,
                t.id_propuesta, t.numero_propuesta, t.version_propuesta,
                t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo, m.String1 AS moneda_nombre,
                t.monto_oc, t.monto_propuesta, t.monto_requerido_neto - t.monto_oc AS diferencia_propuesta,
                t.monto_oc - t.monto_requerido_neto         AS diferencia,
                -- HU-27: distribución y OC complementaria
                t.tipo_oc, t.id_oc_origen,
                -- HU-28: liberación para programación
                t.fecha_liberacion, CONCAT(ul.nombre, ' ', ul.apellido) AS liberado_por,
                (SELECT o.numero_oc FROM orden_compra o WHERE o.id_oc = t.id_oc_origen) AS numero_oc_origen,
                t.monto_requerido_neto, t.cobertura_otros, t.monto_asignado_oc, t.saldo_disponible, t.faltante,
                t.monto_aplicado, t.saldo,
                t.cobertura_pct, t.utilizacion_pct, t.cobertura_codigo, t.cobertura_proyectada,
                t.id_responsable, CONCAT(u.nombre, ' ', u.apellido)   AS responsable,
                t.creado_por AS id_registrado_por, CONCAT(ur.nombre, ' ', ur.apellido) AS registrado_por,
                t.fecha_registro,
                t.id_validado_por, CONCAT(uv.nombre, ' ', uv.apellido) AS validado_por,
                v_fecha_valid                               AS fecha_validacion,
                t.id_motivo_observacion, mo.String1         AS motivo_observacion,
                -- HU-26: observación abierta (id para levantarla, todos los motivos, detalle y responsable de corrección)
                (SELECT MAX(o.id_observacion) FROM orden_compra_observacion o
                 WHERE o.id_oc = t.id_oc AND o.estado = 'abierta' AND o.eliminado_en IS NULL)        AS id_observacion_abierta,
                (SELECT GROUP_CONCAT(tm.String1 ORDER BY tm.Num1 SEPARATOR ', ')
                 FROM orden_compra_observacion o
                 JOIN orden_compra_observacion_motivo om ON om.id_observacion = o.id_observacion AND om.eliminado_en IS NULL
                 JOIN tabla_maestra tm ON tm.IdMaestro = 14 AND tm.IdEmpresa = 1 AND tm.Num1 = om.id_motivo
                 WHERE o.id_oc = t.id_oc AND o.estado = 'abierta' AND o.eliminado_en IS NULL)        AS motivos_observacion,
                (SELECT o.detalle FROM orden_compra_observacion o
                 WHERE o.id_oc = t.id_oc AND o.estado = 'abierta' AND o.eliminado_en IS NULL
                 ORDER BY o.id_observacion DESC LIMIT 1)                                              AS detalle_observacion,
                (SELECT CONCAT(ur2.nombre, ' ', ur2.apellido) FROM orden_compra_observacion o
                 JOIN usuario ur2 ON ur2.id_usuario = o.id_responsable_correccion
                 WHERE o.id_oc = t.id_oc AND o.estado = 'abierta' AND o.eliminado_en IS NULL
                 ORDER BY o.id_observacion DESC LIMIT 1)                                              AS responsable_correccion,
                oc.nombre_archivo_pdf, oc.tamano_pdf_bytes,
                IF(t.tiene_pdf = 1, CONCAT('/api/crm/ordenes-compra/', t.id_oc, '/pdf'), NULL) AS url_pdf,
                t.lista_programacion,
                t.ordenes_servicio
            FROM tmp_oc t
            JOIN orden_compra oc      ON oc.id_oc           = t.id_oc
            LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
            LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
            LEFT JOIN usuario u       ON u.id_usuario       = t.id_responsable
            LEFT JOIN usuario ur      ON ur.id_usuario      = t.creado_por
            LEFT JOIN usuario uv      ON uv.id_usuario      = t.id_validado_por
            LEFT JOIN usuario ul      ON ul.id_usuario      = t.liberado_por
            LEFT JOIN tabla_maestra m  ON m.IdMaestro  = 1  AND m.IdEmpresa  = 1 AND m.Num1  = t.id_moneda
            LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 14 AND mo.IdEmpresa = 1 AND mo.Num1 = t.id_motivo_observacion;

            DROP TEMPORARY TABLE IF EXISTS tmp_oc;

            -- 3. Aplicaciones (propuestas vinculadas)
            SELECT p.id_propuesta, p.numero, p.version, p.estado,
                   p.total AS monto_propuesta, p.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo,
                   -- HU-27: lo cubierto por otras OC y lo pendiente de la propuesta
                   (SELECT IFNULL(SUM(op2.monto_asignado), 0) FROM oc_propuesta op2
                    JOIN orden_compra o2 ON o2.id_oc = op2.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op2.id_propuesta)
                    WHERE op2.id_propuesta = p.id_propuesta AND op2.id_oc <> p_id_oc AND op2.eliminado_en IS NULL) AS cubierto_otras_oc,
                   GREATEST(p.total - IFNULL(p.monto_asignado, 0)
                            - (SELECT IFNULL(SUM(op2.monto_asignado), 0) FROM oc_propuesta op2
                               JOIN orden_compra o2 ON o2.id_oc = op2.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op2.id_propuesta)
                               WHERE op2.id_propuesta = p.id_propuesta AND op2.id_oc <> p_id_oc AND op2.eliminado_en IS NULL), 0) AS pendiente,
                   IFNULL(p.monto_asignado, IF(p.id_moneda = v_id_moneda, LEAST(p.total, v_monto_oc), NULL)) AS monto_asignado,
                   p.fecha_asignacion, p.fecha_aceptacion,
                   (p.id_propuesta = v_id_propuesta) AS es_principal
            FROM tmp_oc_prop p
            LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
            ORDER BY es_principal DESC, p.numero, p.version;

            -- 4. Checklist de validación
            SELECT 'cliente_coincide' AS codigo, 'Razón social del cliente coincide' AS descripcion,
                   (v_n_prop > 0 AND v_otro_cliente = 0) AS cumple,
                   IF(v_n_prop > 0 AND v_otro_cliente = 0, 'El cliente de la OC es el de la propuesta.',
                      'El cliente de la OC no coincide con el de la propuesta.') AS detalle
            UNION ALL
            SELECT 'moneda_coincide', 'Tipo de moneda coincide',
                   (v_n_prop > 0 AND v_otra_moneda = 0),
                   IF(v_n_prop > 0 AND v_otra_moneda = 0, 'La OC está en la moneda de la propuesta.',
                      'La OC está en una moneda distinta a la de la propuesta.')
            UNION ALL
            SELECT 'propuesta_vigente', 'Propuesta técnica/económica vigente',
                   (v_n_prop > 0 AND v_no_ultima + v_no_valida + v_expirada + v_no_aceptada = 0),
                   CASE WHEN v_n_prop = 0       THEN 'La OC no tiene propuesta vinculada.'
                        WHEN v_no_valida > 0    THEN 'La propuesta está anulada, vencida, rechazada o en borrador.'
                        WHEN v_no_ultima > 0    THEN 'Existe una versión más reciente de la propuesta.'
                        WHEN v_expirada > 0     THEN 'La propuesta había expirado a la fecha de la OC.'
                        WHEN v_no_aceptada > 0  THEN 'La propuesta no tiene registrada la aceptación del cliente.'
                        ELSE 'La propuesta es la última versión, está vigente y aceptada por el cliente.' END
            UNION ALL
            SELECT 'monto_suficiente', 'Monto suficiente para cobertura',
                   (v_otra_moneda = 0 AND v_monto_oc >= v_monto_prop),
                   CASE WHEN v_otra_moneda > 0 THEN 'No se puede comparar: las monedas son distintas.'
                        WHEN v_monto_oc >= v_monto_prop THEN 'El monto de la OC cubre la propuesta.'
                        ELSE CONCAT('Faltan ', FORMAT(v_monto_prop - v_monto_oc, 2), ' para cubrir la propuesta.') END
            UNION ALL
            SELECT 'pdf_adjunto', 'Archivo PDF adjunto y legible',
                   (v_tiene_pdf = 1),
                   IF(v_tiene_pdf = 1, 'PDF verificado al registrar la OC.', 'La OC no tiene PDF adjunto.')
            UNION ALL
            SELECT 'numero_unico', 'N.° de OC no duplicado en sistema',
                   (v_duplicadas = 0),
                   IF(v_duplicadas = 0, 'No hay otra OC del cliente con este número.',
                      'Existe otra OC del cliente con el mismo número.')
            UNION ALL
            SELECT 'oc_vigente', 'Orden de compra vigente',
                   (v_vigencia_hasta IS NULL OR v_vigencia_hasta >= CURDATE()),
                   IF(v_vigencia_hasta IS NULL, 'La OC no indica vigencia.',
                      IF(v_vigencia_hasta >= CURDATE(),
                         CONCAT('Vigente hasta el ', DATE_FORMAT(v_vigencia_hasta, '%d/%m/%Y'), '.'),
                         CONCAT('Venció el ', DATE_FORMAT(v_vigencia_hasta, '%d/%m/%Y'), '.')));

            -- 5. Vinculaciones del proceso
            SELECT 'requerimiento' AS tipo, r.id_requerimiento AS id_entidad, r.numero AS codigo,
                   'Requerimiento' AS descripcion, r.estado, 1 AS disponible, NULL AS url
            FROM requerimiento r WHERE r.id_requerimiento = v_id_rq
            UNION ALL
            SELECT 'propuesta', p.id_propuesta, CONCAT(p.numero, ' v', p.version),
                   'Propuesta comercial', p.estado, 1, CONCAT('/api/crm/propuestas/', p.id_propuesta, '/pdf')
            FROM tmp_oc_prop p
            UNION ALL
            SELECT 'expediente', e.id_expediente, e.numero, 'Expediente digital', e.estado, 1, NULL
            FROM expediente_digital e WHERE e.id_expediente = v_id_expediente
            UNION ALL
            SELECT 'expediente', NULL, NULL, 'Expediente digital', 'pendiente', 0, NULL
            FROM DUAL WHERE v_id_expediente IS NULL
            UNION ALL
            SELECT 'orden_servicio', os.id_os, os.numero, 'Orden de servicio', os.estado, 1, NULL
            FROM orden_servicio os WHERE os.id_os = v_id_os
            UNION ALL
            SELECT 'orden_servicio', NULL, NULL, 'Orden de servicio', 'pendiente', 0, NULL
            FROM DUAL WHERE v_id_os IS NULL;

            -- 6. Documentos
            SELECT d.* FROM (
                SELECT 'orden_compra_pdf' AS tipo,
                       COALESCE(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')) AS nombre,
                       oc.tamano_pdf_bytes AS tamano_bytes, oc.fecha_registro AS fecha,
                       CONCAT('/api/crm/ordenes-compra/', oc.id_oc, '/pdf') AS url
                FROM orden_compra oc WHERE oc.id_oc = p_id_oc AND oc.url_archivo_pdf IS NOT NULL
                UNION ALL
                SELECT 'propuesta_pdf', CONCAT(p.numero, '-V', p.version, '.pdf'), NULL, p.fecha_envio,
                       CONCAT('/api/crm/propuestas/', p.id_propuesta, '/pdf')
                FROM tmp_oc_prop p
                UNION ALL
                SELECT 'evidencia_aceptacion', a.nombre_archivo, a.tamano_bytes, a.creado_en,
                       CONCAT('/api/crm/seguimiento/adjuntos/', a.id_adjunto)
                FROM seguimiento_adjunto a
                JOIN seguimiento_comercial s ON s.id_seguimiento = a.id_seguimiento
                                            AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL
                WHERE a.eliminado_en IS NULL
                  AND (s.id_propuesta = v_id_propuesta
                       OR s.id_propuesta IN (SELECT op.id_propuesta FROM oc_propuesta op
                                             WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL))
            ) d
            ORDER BY d.fecha DESC;

            -- 7. Workflow
            SELECT w.orden, w.codigo, w.etapa, w.estado, w.fecha FROM (
                SELECT 1 AS orden, 'requerimiento' AS codigo, 'Requerimiento' AS etapa,
                       IF(v_id_rq IS NULL, 'pendiente', 'completado') AS estado, v_fecha_rq AS fecha
                UNION ALL
                SELECT 2, 'propuesta_enviada', 'Propuesta enviada al cliente', 'completado', v_fecha_envio
                UNION ALL
                SELECT 3, 'aceptacion', 'Aceptación del cliente',
                       IF(v_fecha_acept IS NULL, 'pendiente', 'completado'), v_fecha_acept
                UNION ALL
                SELECT 4, 'oc_registrada', 'OC registrada', 'completado', v_fecha_registro
                UNION ALL
                SELECT 5, 'validacion_oc', 'Validación de la OC',
                       CASE WHEN v_estado_visual = 'anulada'   THEN 'pendiente'
                            WHEN v_estado_visual = 'observada' THEN 'observado'
                            WHEN v_validada = 1                THEN 'completado'
                            ELSE 'actual' END,
                       IF(v_validada = 1, v_fecha_valid, NULL)
                UNION ALL
                SELECT 6, 'liberacion_programacion', 'Liberada para programación',
                       CASE WHEN v_n_os > 0 OR v_fecha_lib IS NOT NULL THEN 'completado'
                            WHEN v_validada = 1 AND v_estado_visual = 'bloqueada' THEN 'bloqueado'
                            WHEN v_lista = 1                         THEN 'actual'
                            ELSE 'pendiente' END,
                       v_fecha_lib
                UNION ALL
                SELECT 7, 'orden_servicio', 'Orden de servicio',
                       CASE WHEN v_id_os IS NULL AND v_fecha_lib IS NOT NULL THEN 'actual'
                            WHEN v_id_os IS NULL                     THEN 'pendiente'
                            WHEN v_estado_os = 'finalizada'          THEN 'completado'
                            ELSE 'actual' END,
                       v_fecha_os
            ) w
            ORDER BY w.orden;

            -- 8. Historial
            SELECT h.* FROM (
                SELECT oc.fecha_registro AS fecha, 'registro' AS tipo,
                       'Orden de compra registrada' AS titulo,
                       CONCAT('OC ', oc.numero_oc, ' por ', IFNULL(m.String2, ''), ' ', FORMAT(oc.monto_total, 2),
                              '. Pendiente de validación.') AS descripcion,
                       oc.creado_por AS id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario
                FROM orden_compra oc
                LEFT JOIN usuario u       ON u.id_usuario = oc.creado_por
                LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = oc.id_moneda
                WHERE oc.id_oc = p_id_oc
                UNION ALL
                SELECT MIN(n.fecha_creacion), 'notificacion', 'Notificación enviada',
                       CONCAT('Se notificó a ', COUNT(*), ' usuario(s): ',
                              GROUP_CONCAT(DISTINCT CONCAT(u.nombre, ' ', u.apellido) ORDER BY u.nombre SEPARATOR ', '), '.'),
                       MAX(n.creado_por), NULL
                FROM notificacion n
                JOIN usuario u ON u.id_usuario = n.id_usuario_destino
                WHERE n.entidad_tipo = 'orden_compra' AND n.id_entidad = p_id_oc AND n.eliminado_en IS NULL
                GROUP BY DATE_FORMAT(n.fecha_creacion, '%Y-%m-%d %H:%i')
                UNION ALL
                SELECT a.registrado_en, a.accion,
                       CASE a.accion
                           WHEN 'editar_oc'              THEN 'Orden de compra editada'
                           WHEN 'editar_oc_revalidacion' THEN 'Editada y enviada a revalidación'
                           WHEN 'validar_oc'             THEN 'Orden de compra validada'
                           WHEN 'observar_oc'            THEN 'Orden de compra observada'
                           WHEN 'levantar_observacion_oc' THEN 'Observación levantada'
                           WHEN 'reemplazar_pdf_oc'      THEN 'Documento de la OC reemplazado'
                           WHEN 'exportar_auditoria_oc'  THEN 'Historial de auditoría descargado'
                           WHEN 'distribuir_oc'          THEN 'Saldo de la OC distribuido'
                           WHEN 'liberar_oc'             THEN 'Liberada para programación'
                           WHEN 'anular_oc'              THEN 'Orden de compra anulada'
                           WHEN 'registrar_oc_complementaria' THEN 'OC complementaria registrada'
                           ELSE CONCAT(UPPER(LEFT(REPLACE(a.accion, '_', ' '), 1)), SUBSTRING(REPLACE(a.accion, '_', ' '), 2))
                       END,
                       COALESCE(a.descripcion,
                                CONCAT(IFNULL(a.estado_anterior, ''), ' → ', IFNULL(a.estado_nuevo, ''))),
                       a.id_usuario, CONCAT(u.nombre, ' ', u.apellido)
                FROM auditoria_evento a
                LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
                WHERE a.entidad_tipo = 'orden_compra' AND a.id_entidad = p_id_oc
            ) h
            ORDER BY h.fecha DESC;

            DROP TEMPORARY TABLE IF EXISTS tmp_oc_prop;
        END IF;
    END IF;
END$$

DELIMITER ;
