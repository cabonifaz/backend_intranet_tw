-- Expediente Digital (interno, HU-29/30/32): bloqueos y excepciones del expediente, abiertos y resueltos.
-- p_id_expediente NULL = todos (bandeja). Llena tmp_exp_blq (el que llama hace DROP TEMPORARY TABLE tmp_exp_blq).
-- El expediente es de consulta: los bloqueos salen solos de los módulos origen y se resuelven allí.
--   bloqueo    impide avanzar: OC observada que requiere corrección o nueva versión (expediente_bloqueador, la registra
--              SP_SincronizarBloqueosOrdenCompra), VB rechazado, OS bloqueada y personal no apto en SSOMA.
--   excepcion  se puede seguir pero queda registrada: OC observada informativa, VB devuelto para ajuste,
--              documento SSOMA observado o vencido e incidencias operativas.
-- Los bloqueos registrados a mano antes del refinamiento (expediente_bloqueador) se siguen mostrando.
-- Columnas: id_expediente, clave, clase, tipo, tipo_nombre, etapa, entidad_tipo, id_entidad, entidad, motivo, impacto,
--   critico, fecha, fecha_resolucion, resolucion, activo, id_usuario (quien lo registró), id_responsable, origen.
DROP PROCEDURE IF EXISTS SP_CargarBloqueosExpediente;

DELIMITER $$

CREATE PROCEDURE SP_CargarBloqueosExpediente(
    IN p_id_expediente BIGINT
)
BEGIN
    -- Propuestas (todas sus versiones) de cada expediente
    DROP TEMPORARY TABLE IF EXISTS tmp_blq_props;
    CREATE TEMPORARY TABLE tmp_blq_props (PRIMARY KEY (id_propuesta)) AS
    SELECT MIN(e.id_expediente) AS id_expediente, p.id_propuesta
    FROM expediente_digital e
    JOIN propuesta_comercial p ON p.eliminado_en IS NULL
         AND (p.id_requerimiento = e.id_requerimiento OR (e.id_requerimiento IS NULL AND p.id_propuesta = e.id_propuesta))
    WHERE e.eliminado_en IS NULL AND (p_id_expediente IS NULL OR e.id_expediente = p_id_expediente)
    GROUP BY p.id_propuesta;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
    CREATE TEMPORARY TABLE tmp_exp_blq (
        id_expediente    BIGINT,
        clave            VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        clase            VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo             VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo_nombre      VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etapa            VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        entidad_tipo     VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_entidad       BIGINT,
        entidad          VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        motivo           VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        impacto          VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        critico          TINYINT,
        fecha            DATETIME,
        fecha_resolucion DATETIME,
        resolucion       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        activo           TINYINT,
        id_usuario       BIGINT,
        id_responsable   BIGINT,
        origen           VARCHAR(60)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        KEY (id_expediente)
    );

    -- 1. Registrados (OC observada automática y los manuales antiguos)
    INSERT INTO tmp_exp_blq
    SELECT b.id_expediente, CONCAT('blq-', b.id_bloqueador), b.clase, b.tipo,
           CASE b.tipo
               WHEN 'oc_observada'       THEN IF(b.clase = 'bloqueo', 'OC observada (requiere corrección)', 'OC observada (informativa)')
               WHEN 'ssoma'              THEN 'SSOMA no apto'
               WHEN 'documento_faltante' THEN 'Documento faltante'
               WHEN 'cobertura_oc'       THEN 'Cobertura de OC'
               WHEN 'sin_aprobacion'     THEN 'Sin aprobación'
               ELSE 'Otro' END,
           IFNULL(b.etapa, 'orden_compra'),
           IF(b.origen_tipo = 'orden_compra', 'orden_compra', 'expediente'), IF(b.origen_tipo = 'orden_compra', b.id_origen, b.id_expediente),
           IF(b.origen_tipo = 'orden_compra', (SELECT CONCAT('OC ', oc.numero_oc) FROM orden_compra oc WHERE oc.id_oc = b.id_origen),
              (SELECT e.numero FROM expediente_digital e WHERE e.id_expediente = b.id_expediente)),
           LEFT(b.descripcion, 1000), b.impacto, b.critico, b.creado_en, b.fecha_resolucion,
           LEFT(NULLIF(TRIM(IFNULL(b.sustento, '')), ''), 1000), (b.resuelto = 0), b.creado_por, b.id_responsable,
           IF(b.origen_tipo = 'orden_compra', 'Órdenes de Compra', 'Expediente')
    FROM expediente_bloqueador b
    WHERE b.eliminado_en IS NULL
      AND (p_id_expediente IS NULL OR b.id_expediente = p_id_expediente);

    -- 2. Visto bueno rechazado (bloqueo) o devuelto para ajuste (excepción): se resuelve al volver a pedir el VB
    --    de la misma propuesta (nueva versión) o al anularla
    DROP TEMPORARY TABLE IF EXISTS tmp_blq_vb;
    CREATE TEMPORARY TABLE tmp_blq_vb AS
    SELECT t.id_expediente, v.id_vb, v.estado, v.id_motivo_rechazo, v.comentario_respuesta, v.fecha_respuesta,
           IFNULL(v.resuelto_por, v.id_aprobador) AS id_usuario,
           p.id_propuesta, p.numero, p.version, COALESCE(p.id_responsable, p.id_creador) AS id_responsable,
           (SELECT MIN(v2.fecha_solicitud) FROM visto_bueno v2
            JOIN propuesta_comercial p2 ON p2.id_propuesta = v2.id_propuesta
            WHERE p2.numero = p.numero AND v2.tipo = 'aprobacion' AND v2.eliminado_en IS NULL
              AND v2.fecha_solicitud > v.fecha_respuesta) AS fecha_nuevo_vb,
           (SELECT IFNULL(p3.fecha_anulacion, p3.modificado_en) FROM propuesta_comercial p3
            WHERE p3.numero = p.numero AND p3.eliminado_en IS NULL
            ORDER BY p3.version DESC, p3.id_propuesta DESC LIMIT 1)                                        AS fecha_ultima_mod,
           (SELECT p3.estado FROM propuesta_comercial p3
            WHERE p3.numero = p.numero AND p3.eliminado_en IS NULL
            ORDER BY p3.version DESC, p3.id_propuesta DESC LIMIT 1)                                        AS estado_ultima
    FROM visto_bueno v
    JOIN tmp_blq_props t ON t.id_propuesta = v.id_propuesta
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    WHERE v.tipo = 'aprobacion' AND v.eliminado_en IS NULL AND v.estado IN ('rechazado', 'devuelto')
      AND v.fecha_respuesta IS NOT NULL;

    INSERT INTO tmp_exp_blq
    SELECT x.id_expediente, CONCAT('vb-', x.id_vb), IF(x.estado = 'rechazado', 'bloqueo', 'excepcion'),
           IF(x.estado = 'rechazado', 'vb_rechazado', 'vb_devuelto'),
           IF(x.estado = 'rechazado', 'VB rechazado', 'VB devuelto para ajuste'),
           'visto_bueno', 'propuesta', x.id_propuesta, CONCAT(x.numero, ' v', x.version),
           LEFT(CONCAT_WS('. ', mr.String1, NULLIF(TRIM(IFNULL(x.comentario_respuesta, '')), '')), 1000),
           IF(x.estado = 'rechazado', 'La propuesta no puede enviarse al cliente: requiere una nueva versión y un nuevo VB.',
                                      'La propuesta debe corregirse y volver a visto bueno.'),
           (x.estado = 'rechazado'), x.fecha_respuesta,
           COALESCE(x.fecha_nuevo_vb, IF(x.estado_ultima = 'anulado', x.fecha_ultima_mod, NULL)),
           CASE WHEN x.fecha_nuevo_vb IS NOT NULL THEN 'Resuelto en Propuestas: se volvió a solicitar el visto bueno.'
                WHEN x.estado_ultima = 'anulado' THEN 'Resuelto en Propuestas: la propuesta fue anulada.'
                ELSE NULL END,
           (x.fecha_nuevo_vb IS NULL AND IFNULL(x.estado_ultima, '') <> 'anulado'), x.id_usuario, x.id_responsable,
           'Visto Bueno'
    FROM tmp_blq_vb x
    LEFT JOIN tabla_maestra mr ON mr.IdMaestro = 10 AND mr.IdEmpresa = 1 AND mr.Num1 = x.id_motivo_rechazo;

    DROP TEMPORARY TABLE IF EXISTS tmp_blq_vb;

    -- 3. OS bloqueada
    INSERT INTO tmp_exp_blq
    SELECT os.id_expediente, CONCAT('os-', os.id_os), 'bloqueo', 'os_bloqueada', 'OS bloqueada', 'programacion',
           'orden_servicio', os.id_os, os.numero, LEFT(IFNULL(os.notas_operativas, 'La orden de servicio está bloqueada.'), 1000),
           'No se puede ejecutar el servicio hasta desbloquear la OS.', 1, IFNULL(os.modificado_en, os.creado_en), NULL, NULL, 1,
           IFNULL(os.modificado_por, os.creado_por), os.id_responsable_comercial, 'Órdenes de Servicio'
    FROM orden_servicio os
    WHERE os.eliminado_en IS NULL AND os.estado = 'bloqueada'
      AND (p_id_expediente IS NULL OR os.id_expediente = p_id_expediente);

    -- 4. Personal no apto en SSOMA (bloqueo)
    INSERT INTO tmp_exp_blq
    SELECT os.id_expediente, CONCAT('ssp-', op.id), 'bloqueo', 'ssoma_no_apto', 'SSOMA no apto', 'ssoma',
           'orden_servicio', os.id_os, CONCAT(os.numero, ' · ', IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Personal')),
           CONCAT('Personal no habilitado por SSOMA (', IFNULL(op.rol_en_servicio, 'sin rol'), ').'),
           'El personal no puede salir a campo hasta su habilitación SSOMA.', 1,
           IFNULL(op.modificado_en, op.creado_en), NULL, NULL, 1, IFNULL(op.modificado_por, op.creado_por), NULL, 'SSOMA'
    FROM os_personal op
    JOIN orden_servicio os ON os.id_os = op.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('anulada', 'finalizada')
    LEFT JOIN usuario u ON u.id_usuario = op.id_usuario
    WHERE op.eliminado_en IS NULL AND op.estado_ssoma = 'bloqueado'
      AND (p_id_expediente IS NULL OR os.id_expediente = p_id_expediente);

    -- 5. Documento SSOMA observado o vencido (excepción)
    INSERT INTO tmp_exp_blq
    SELECT os.id_expediente, CONCAT('ssd-', sd.id_ssoma_doc), 'excepcion', 'ssoma_documento',
           IF(sd.estado = 'observado', 'Documento SSOMA observado', 'Documento SSOMA vencido'), 'ssoma',
           'orden_servicio', os.id_os,
           CONCAT(os.numero, ' · ', IFNULL(t36.String1, 'Documento SSOMA'), ' · ', IFNULL(CONCAT(u.nombre, ' ', u.apellido), '')),
           LEFT(IFNULL(sd.motivo_observacion,
                       IF(sd.fecha_vencimiento IS NULL, 'Documento vencido.',
                          CONCAT('Vencido el ', DATE_FORMAT(sd.fecha_vencimiento, '%d/%m/%Y'), '.'))), 1000),
           'Debe actualizarse antes de la salida a campo.', 0, IFNULL(sd.modificado_en, sd.fecha_carga), NULL, NULL, 1,
           IFNULL(sd.modificado_por, sd.creado_por), NULL, 'SSOMA'
    FROM ssoma_documento sd
    JOIN orden_servicio os ON os.id_os = sd.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('anulada', 'finalizada')
    LEFT JOIN tabla_maestra t36 ON t36.IdMaestro = 36 AND t36.IdEmpresa = 1 AND t36.Num1 = sd.id_requisito
    LEFT JOIN usuario u ON u.id_usuario = sd.id_usuario
    WHERE sd.eliminado_en IS NULL
      AND (sd.estado IN ('observado', 'vencido') OR (sd.fecha_vencimiento IS NOT NULL AND sd.fecha_vencimiento < CURDATE()))
      AND (p_id_expediente IS NULL OR os.id_expediente = p_id_expediente);

    -- 6. Incidencias operativas (excepción; resueltas quedan en el historial)
    INSERT INTO tmp_exp_blq
    SELECT os.id_expediente, CONCAT('inc-', i.id_incidencia), 'excepcion', 'incidencia',
           IFNULL(t33.String1, 'Incidencia operativa'), 'ejecucion', 'orden_servicio', os.id_os, os.numero,
           LEFT(i.descripcion, 1000), IFNULL(CONCAT('Nivel de alerta: ', t34.String1), NULL), 0, i.fecha_registro,
           IF(i.estado = 'resuelta', IFNULL(i.modificado_en, i.fecha_registro), NULL),
           IF(i.estado = 'resuelta', 'Resuelta en Ejecución.', NULL), (i.estado <> 'resuelta'), i.id_usuario, NULL, 'Ejecución'
    FROM incidencia_operativa i
    JOIN orden_servicio os ON os.id_os = i.id_os AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t33 ON t33.IdMaestro = 33 AND t33.IdEmpresa = 1 AND t33.Num1 = i.id_tipo
    LEFT JOIN tabla_maestra t34 ON t34.IdMaestro = 34 AND t34.IdEmpresa = 1 AND t34.Num1 = i.id_nivel_alerta
    WHERE i.eliminado_en IS NULL
      AND (p_id_expediente IS NULL OR os.id_expediente = p_id_expediente);

    DROP TEMPORARY TABLE IF EXISTS tmp_blq_props;
END$$

DELIMITER ;
