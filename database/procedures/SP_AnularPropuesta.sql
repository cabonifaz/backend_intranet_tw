-- HU-12 — Anulación de Propuesta
--   p_solo_preparar = 1 devuelve lo que muestra el modal: impacto, si se puede
--     anular y los motivos (MOTIVO_ANULACION, IdMaestro 9).
--   p_solo_preparar = 0 anula: motivo y justificación (mín. 20 caracteres)
--     obligatorios y confirmación crítica en 1.
--   Solo la última versión y que no esté anulada.
--   HU-28 (anulación del proceso completo): una OC vinculada ya no impide anular. Solo bloquea una
--     Orden de Servicio vinculada (no anulada): debe resolverse primero el proceso operativo.
--     Al anular: las OC de la propuesta pasan a 'anulada', se liberan los montos que otras OC le
--     distribuyeron, el proceso operativo del expediente se anula (vuelve a la etapa comercial del RQ, que
--     sigue vivo, migración 71) y se notifica a Operaciones (si estaba liberado) y a los
--     responsables de otras propuestas que pierden cobertura.
--   Efectos: estado 'anulado' con motivo, justificación, fecha y usuario.
--     Un VB pendiente pasa a 'cancelado'.
--     Si el RQ queda sin propuestas vigentes, vuelve de 'con_propuesta' a 'en_proceso'.
--     RQ y expediente conservan su historial. Queda auditado.
--   Resultados: 1 header · 2 resumen · 3 motivos (solo al preparar)
DROP PROCEDURE IF EXISTS SP_AnularPropuestaInterno;

DELIMITER $$

CREATE PROCEDURE SP_AnularPropuestaInterno(
    IN p_id_propuesta    BIGINT,
    IN p_id_motivo       INT,
    IN p_justificacion   TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_confirmacion    TINYINT,
    IN p_solo_preparar   TINYINT,
    IN p_id_usuario      BIGINT
)
proc: BEGIN
    DECLARE v_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_id_rq         BIGINT;
    DECLARE v_es_ultima     TINYINT DEFAULT 1;
    DECLARE v_tiene_oc      TINYINT DEFAULT 0;
    DECLARE v_vb_pendiente  TINYINT DEFAULT 0;
    DECLARE v_puede         TINYINT DEFAULT 1;
    DECLARE v_bloqueo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo_label  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rq_revertido  TINYINT DEFAULT 0;
    -- HU-28
    DECLARE v_id_os         BIGINT;
    DECLARE v_numero_os     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ocs           VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_ocs         INT DEFAULT 0;
    DECLARE v_props_afect   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aplic_otras   INT DEFAULT 0;
    DECLARE v_id_exp        BIGINT;
    DECLARE v_exp_liberado  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_solo_preparar = IFNULL(p_solo_preparar, 0);

    SELECT estado, numero, version, id_requerimiento
      INTO v_estado, v_numero, v_version, v_id_rq
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── ¿Se puede anular? ───────────────────────────────────────────────
    SET v_es_ultima = NOT EXISTS (SELECT 1 FROM propuesta_comercial
                                  WHERE numero = v_numero AND version > v_version AND eliminado_en IS NULL);

    -- OC de la propuesta (las registradas a partir de ella), OS vinculadas y otras propuestas que esas OC cubren
    SELECT COUNT(*), GROUP_CONCAT(numero_oc ORDER BY id_oc SEPARATOR ', ') INTO v_n_ocs, v_ocs
    FROM orden_compra WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL AND estado <> 'anulada';

    SELECT COUNT(*) INTO v_aplic_otras
    FROM oc_propuesta op JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
    WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL AND IFNULL(oc.id_propuesta, 0) <> p_id_propuesta;

    SELECT GROUP_CONCAT(DISTINCT CONCAT(p2.numero, ' v', p2.version) ORDER BY p2.numero SEPARATOR ', ') INTO v_props_afect
    FROM oc_propuesta op
    JOIN orden_compra oc       ON oc.id_oc = op.id_oc AND oc.id_propuesta = p_id_propuesta
                              AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
    JOIN propuesta_comercial p2 ON p2.id_propuesta = op.id_propuesta
    WHERE op.eliminado_en IS NULL AND op.id_propuesta <> p_id_propuesta;

    -- Expediente del RQ (nace con el RQ, migración 71)
    SELECT MAX(e.id_expediente), MAX(e.etapa_actual NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'seguimiento', 'orden_compra'))
      INTO v_id_exp, v_exp_liberado
    FROM expediente_digital e
    WHERE e.eliminado_en IS NULL AND e.estado <> 'cerrado'
      AND e.id_expediente = FN_ExpedienteDePropuesta(p_id_propuesta);

    SELECT os.id_os, os.numero, os.estado INTO v_id_os, v_numero_os, v_estado_os
    FROM orden_servicio os
    JOIN expediente_digital e ON e.id_expediente = os.id_expediente AND e.eliminado_en IS NULL
    WHERE os.eliminado_en IS NULL AND os.estado <> 'anulada'
      -- OS del expediente de la propuesta y de los expedientes que dependen de sus OC por distribución (HU-27)
      AND (e.id_expediente = FN_ExpedienteDePropuesta(p_id_propuesta)
           OR e.id_expediente IN (SELECT FN_ExpedienteDePropuesta(op.id_propuesta)
                                  FROM oc_propuesta op
                                  JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.id_propuesta = p_id_propuesta
                                                      AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                                  WHERE op.eliminado_en IS NULL))
    ORDER BY FIELD(os.estado, 'en_ejecucion', 'en_ruta', 'pausada', 'bloqueada', 'programada', 'reprogramada', 'finalizada'),
             os.id_os DESC
    LIMIT 1;

    SET v_tiene_oc = EXISTS (SELECT 1 FROM orden_compra oc
                             WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                               AND (oc.id_propuesta = p_id_propuesta
                                    OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                                    WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL)));

    SET v_vb_pendiente = EXISTS (SELECT 1 FROM visto_bueno
                                 WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente' AND eliminado_en IS NULL);

    IF v_estado = 'anulado' THEN
        SET v_puede = 0, v_bloqueo = 'La propuesta ya está anulada.';
    ELSEIF v_es_ultima = 0 THEN
        SET v_puede = 0, v_bloqueo = 'Solo se puede anular la última versión de la propuesta.';
    ELSEIF v_id_os IS NOT NULL THEN
        SET v_puede = 0,
            v_bloqueo = CONCAT('No es posible anular directamente: la Orden de Servicio ', v_numero_os, ' (',
                               REPLACE(v_estado_os, '_', ' '), ') está vinculada. Resuelva primero el proceso operativo.');
    END IF;

    -- ── Anular ──────────────────────────────────────────────────────────
    IF p_solo_preparar = 0 THEN
        IF v_puede = 0 THEN
            SELECT 1 AS IdTipoMensaje, v_bloqueo AS Mensaje;
            LEAVE proc;
        END IF;

        IF FN_PermisoAccion(p_id_usuario, 'propuesta_anular') = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'No tiene permiso para anular propuestas.' AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT String1 INTO v_motivo_label
        FROM tabla_maestra
        WHERE IdMaestro = 9 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL
        LIMIT 1;

        IF v_motivo_label IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo de anulación.' AS Mensaje;
            LEAVE proc;
        END IF;

        IF CHAR_LENGTH(TRIM(IFNULL(p_justificacion, ''))) < 20 THEN
            SELECT 1 AS IdTipoMensaje, 'La justificación detallada es obligatoria (mínimo 20 caracteres).' AS Mensaje;
            LEAVE proc;
        END IF;

        IF IFNULL(p_confirmacion, 0) <> 1 THEN
            SELECT 1 AS IdTipoMensaje, 'Marque la Confirmación Crítica para anular la propuesta.' AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT CONCAT(nombre, ' ', apellido) INTO v_usu_nombre FROM usuario WHERE id_usuario = p_id_usuario;

        START TRANSACTION;

        UPDATE propuesta_comercial SET
            estado                  = 'anulado',
            id_motivo_anulacion     = p_id_motivo,
            justificacion_anulacion = TRIM(p_justificacion),
            fecha_anulacion         = NOW(),
            anulado_por             = p_id_usuario,
            modificado_en           = NOW(),
            modificado_por          = p_id_usuario
        WHERE id_propuesta = p_id_propuesta;

        -- HU-28: OC de la propuesta anuladas y montos distribuidos por otras OC liberados
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        SELECT 'orden_compra', oc.id_oc, 'anular_oc', oc.estado, 'anulada',
               CONCAT('Anulada por la anulación de la propuesta ', v_numero, ' v', v_version, ' (', v_motivo_label, ').'),
               p_id_usuario, NOW()
        FROM orden_compra oc
        WHERE oc.id_propuesta = p_id_propuesta AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada';

        UPDATE orden_compra SET estado = 'anulada', fecha_anulacion = NOW(), anulado_por = p_id_usuario,
                                justificacion_anulacion = LEFT(CONCAT('Anulada por la anulación de la propuesta ', v_numero, ' v', v_version,
                                                                      ' (', v_motivo_label, ').'), 1000),
                                modificado_por = p_id_usuario
        WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL AND estado <> 'anulada';

        -- Los bloqueos que dejaron esas OC en los expedientes ya no aplican (OC anuladas)
        UPDATE expediente_bloqueador SET resuelto = 1, fecha_resolucion = NOW(), resuelto_por = p_id_usuario,
                                         sustento = 'OC anulada con la propuesta.', modificado_por = p_id_usuario
        WHERE origen_tipo = 'orden_compra' AND resuelto = 0 AND eliminado_en IS NULL
          AND id_origen IN (SELECT id_oc FROM (SELECT id_oc FROM orden_compra WHERE id_propuesta = p_id_propuesta) y);

        UPDATE expediente_digital e
        SET e.estado = CASE
                WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                             AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'bloqueo')   THEN 'bloqueado'
                WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                             AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'excepcion') THEN 'con_excepcion'
                ELSE 'activo' END
        WHERE e.estado = 'bloqueado'
          AND e.id_expediente IN (SELECT b.id_expediente FROM expediente_bloqueador b
                                  WHERE b.origen_tipo = 'orden_compra'
                                    AND b.id_origen IN (SELECT id_oc FROM orden_compra WHERE id_propuesta = p_id_propuesta));

        UPDATE oc_propuesta op
        JOIN orden_compra oc ON oc.id_oc = op.id_oc
        SET op.eliminado_en = NOW(), op.eliminado_por = p_id_usuario
        WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL AND IFNULL(oc.id_propuesta, 0) <> p_id_propuesta;

        -- Expediente cerrado (conserva su historial) solo si ya estaba liberado a programación. Antes de eso
        -- el expediente es del RQ y sigue abierto: el RQ vuelve a 'en_proceso' y puede tener otra propuesta.
        IF v_id_exp IS NOT NULL AND IFNULL(v_exp_liberado, 0) = 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
            VALUES ('expediente', v_id_exp, 'propuesta_anulada', NULL, NULL,
                    CONCAT('Propuesta ', v_numero, ' v', v_version, ' anulada. El expediente sigue abierto con el RQ.'), p_id_usuario, NOW());
        END IF;
        -- Expediente ya liberado: se anula el proceso operativo. El expediente es del RQ (que sigue vivo y puede tener
        -- otra propuesta), así que vuelve a la etapa comercial: se cancelan la etapa operativa en curso, sus bloqueos y
        -- excepciones, y se desvincula la OC anulada. Conserva todo su historial.
        IF v_id_exp IS NOT NULL AND IFNULL(v_exp_liberado, 0) = 1 THEN
            UPDATE expediente_bloqueador SET resuelto = 1, fecha_resolucion = NOW(), resuelto_por = p_id_usuario,
                                             sustento = 'Proceso anulado con la propuesta.', modificado_por = p_id_usuario
            WHERE id_expediente = v_id_exp AND resuelto = 0 AND eliminado_en IS NULL;

            UPDATE expediente_etapa SET fecha_fin = NOW(), resultado = 'cancelado',
                                        comentario = LEFT(CONCAT('Cancelada por la anulación de la propuesta ', v_numero, ' v', v_version, '.'), 1000),
                                        UsuMod = CAST(p_id_usuario AS CHAR), FchMod = NOW()
            WHERE id_expediente = v_id_exp AND fecha_fin IS NULL AND SoftDelete = 0;

            UPDATE expediente_digital SET etapa_actual = 'requerimiento', estado = 'activo', area_responsable = 'comercial',
                                          id_responsable_actual = NULL, id_orden_compra = NULL, fecha_etapa = NULL,
                                          sla_horas = NULL, fecha_limite_sla = NULL, modificado_por = p_id_usuario
            WHERE id_expediente = v_id_exp;

            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                          registrado_en, metadata)
            VALUES ('expediente', v_id_exp, 'anular_proceso', NULL, 'requerimiento',
                    CONCAT('Proceso operativo anulado por la anulación de la propuesta ', v_numero, ' v', v_version,
                           '. El expediente vuelve a la etapa comercial del RQ.'), p_id_usuario, NOW(),
                    JSON_OBJECT('etapa', 'requerimiento'));
        END IF;

        -- Avisos: Operaciones (si el expediente ya estaba liberado) y responsables de propuestas que pierden cobertura
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, LEFT(CONCAT('Proceso anulado: ', v_numero), 150),
               CONCAT(v_usu_nombre, ' anuló la propuesta ', v_numero, ' v', v_version, ' (', v_motivo_label, ').',
                      IFNULL(CONCAT(' OC anuladas: ', v_ocs, '.'), ''), ' El proceso operativo del expediente fue anulado y no debe programarse.'),
               'propuesta', p_id_propuesta, NOW(), p_id_usuario
        FROM usuario u
        WHERE v_exp_liberado = 1 AND u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador');

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT DISTINCT COALESCE(p2.id_responsable, p2.id_creador), 5,
               LEFT(CONCAT('Cobertura perdida: ', p2.numero), 150),
               CONCAT('La propuesta ', p2.numero, ' v', p2.version, ' perdió la cobertura de la OC ', oc.numero_oc,
                      ' por la anulación de la propuesta ', v_numero, '.'),
               'propuesta', p2.id_propuesta, NOW(), p_id_usuario
        FROM oc_propuesta op
        JOIN orden_compra oc       ON oc.id_oc = op.id_oc AND oc.id_propuesta = p_id_propuesta
        JOIN propuesta_comercial p2 ON p2.id_propuesta = op.id_propuesta
        WHERE op.eliminado_en IS NULL AND op.id_propuesta <> p_id_propuesta
          AND COALESCE(p2.id_responsable, p2.id_creador) <> p_id_usuario;

        UPDATE visto_bueno
           SET estado = 'cancelado', fecha_respuesta = NOW(),
               comentario = CONCAT(IFNULL(CONCAT(comentario, ' | '), ''), 'Cancelado por anulación de la propuesta.'),
               modificado_en = NOW(), modificado_por = p_id_usuario
         WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente' AND eliminado_en IS NULL;

        -- El RQ vuelve a 'en_proceso' si ya no le queda ninguna propuesta vigente
        IF NOT EXISTS (SELECT 1 FROM propuesta_comercial
                       WHERE id_requerimiento = v_id_rq AND eliminado_en IS NULL AND estado <> 'anulado') THEN
            UPDATE requerimiento
               SET estado = 'en_proceso', modificado_en = NOW(), modificado_por = p_id_usuario
             WHERE id_requerimiento = v_id_rq AND estado = 'con_propuesta';
            SET v_rq_revertido = ROW_COUNT() > 0;
        END IF;

        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta', 'Propuesta anulada', 'block',
                CONCAT('Propuesta ', v_numero, ' v', v_version, ' anulada: ', v_motivo_label, '.'),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('propuesta', p_id_propuesta, 'anulacion', v_estado, 'anulado',
                CONCAT('Propuesta ', v_numero, ' v', v_version, ' anulada (', v_motivo_label, '): ', TRIM(p_justificacion)),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_motivo',          p_id_motivo,
                            'motivo',             v_motivo_label,
                            'justificacion',      TRIM(p_justificacion),
                            'vb_cancelado',       v_vb_pendiente = 1,
                            'oc_anuladas',        v_ocs,
                            'expediente_proceso_anulado', IF(IFNULL(v_exp_liberado, 0) = 1, v_id_exp, NULL),
                            'propuestas_afectadas', v_props_afect,
                            'rq_a_en_proceso',    v_rq_revertido = 1));

        COMMIT;
    END IF;

    -- ── Resultado ───────────────────────────────────────────────────────
    SELECT 2 AS IdTipoMensaje,
           IF(p_solo_preparar = 1, 'Éxito.', 'Propuesta anulada.') AS Mensaje;

    SELECT p.id_propuesta, p.numero, p.version, p.estado,
           c.razon_social                                       AS cliente,
           r.numero                                             AS numero_requerimiento,
           (SELECT e.numero FROM expediente_digital e
             WHERE e.eliminado_en IS NULL AND (e.id_propuesta = p.id_propuesta OR e.id_requerimiento = p.id_requerimiento)
             ORDER BY e.id_expediente DESC LIMIT 1)             AS numero_expediente,
           v_vb_pendiente                                       AS tiene_vb_pendiente,
           IF(p_solo_preparar = 1, v_puede, 0)                  AS puede_anular,
           IF(p_solo_preparar = 1, v_bloqueo, NULL)             AS motivo_bloqueo,
           CONCAT('La propuesta se detendrá en el workflow',
                  IF(v_vb_pendiente = 1, ' y se cancelará el visto bueno pendiente', ''),
                  IF(v_n_ocs > 0, CONCAT(', se anularán las órdenes de compra ', v_ocs), ''),
                  IF(v_aplic_otras > 0, ', se liberarán los montos que otras OC le asignaron', ''),
                  IF(v_props_afect IS NOT NULL, CONCAT(', las propuestas ', v_props_afect, ' perderán la cobertura de esas OC'), ''),
                  IF(v_id_exp IS NOT NULL AND IFNULL(v_exp_liberado, 0) = 1, ' y se anulará el proceso operativo del expediente', ''),
                  '. El RQ y el expediente conservarán el historial. La acción será auditada.') AS impacto,
           -- HU-28: impacto crítico y bloqueo operativo
           p.total                                              AS monto_total,
           mo.String2                                           AS moneda_simbolo,
           IF(v_n_ocs > 0 OR v_id_exp IS NOT NULL OR v_aplic_otras > 0, 1, 0) AS impacto_critico,
           'Esta acción es irreversible y afectará directamente la cobertura comercial, el historial del expediente y las programaciones logísticas activas para este cliente.' AS impacto_critico_mensaje,
           v_ocs                                                AS ordenes_compra_afectadas,
           v_props_afect                                        AS propuestas_afectadas,
           v_id_os                                              AS id_os_bloqueante,
           v_numero_os                                          AS numero_os_bloqueante,
           v_estado_os                                          AS estado_os_bloqueante,
           CONCAT('Confirmo que he revisado el impacto operativo y entiendo que la anulación de la ', p.numero,
                  ' desvinculará todas las proyecciones financieras asociadas.') AS texto_confirmacion,
           tm.String1                                           AS motivo_anulacion,
           p.justificacion_anulacion,
           p.fecha_anulacion
    FROM propuesta_comercial p
    JOIN cliente c             ON c.id_cliente = p.id_cliente
    LEFT JOIN requerimiento r  ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN tabla_maestra tm ON tm.IdMaestro = 9 AND tm.IdEmpresa = 1 AND tm.Num1 = p.id_motivo_anulacion
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = p.id_moneda
    WHERE p.id_propuesta = p_id_propuesta;

    IF p_solo_preparar = 1 THEN
        SELECT Num1 AS id, String1 AS nombre
        FROM tabla_maestra
        WHERE IdMaestro = 9 AND IdEmpresa = 1 AND eliminado_en IS NULL
        ORDER BY Num1;
    END IF;
END$$

DELIMITER ;


-- SP_AnularPropuesta: punto de entrada. Toma el mismo bloqueo por cliente (GET_LOCK) que el registro, la distribución y la
-- liberación de OC, para que no se crucen con ellas. La lógica está en SP_AnularPropuestaInterno.
DROP PROCEDURE IF EXISTS SP_AnularPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_AnularPropuesta(
    IN p_id_propuesta    BIGINT,
    IN p_id_motivo       INT,
    IN p_justificacion   TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_confirmacion    TINYINT,
    IN p_solo_preparar   TINYINT,
    IN p_id_usuario      BIGINT
)
proc: BEGIN
    DECLARE v_bloqueo VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DO RELEASE_LOCK(v_bloqueo);
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_bloqueo = CONCAT('tw_oc_cliente_', IFNULL((SELECT id_cliente FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), 0));
    IF IFNULL(GET_LOCK(v_bloqueo, 15), 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'Hay otra operación en curso sobre las órdenes de compra de este cliente. Intente nuevamente en unos segundos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_AnularPropuestaInterno(p_id_propuesta, p_id_motivo, p_justificacion, p_confirmacion, p_solo_preparar, p_id_usuario);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
