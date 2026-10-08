-- HU-12 — Anulación de Propuesta
--   p_solo_preparar = 1 devuelve lo que muestra el modal: impacto, si se puede
--     anular y los motivos (MOTIVO_ANULACION, IdMaestro 9).
--   p_solo_preparar = 0 anula: motivo y justificación (mín. 20 caracteres)
--     obligatorios y confirmación crítica en 1.
--   Solo la última versión, que no esté anulada ni tenga una OC vinculada.
--   Efectos: estado 'anulado' con motivo, justificación, fecha y usuario.
--     Un VB pendiente pasa a 'cancelado'.
--     Si el RQ queda sin propuestas vigentes, vuelve de 'con_propuesta' a 'en_proceso'.
--     RQ y expediente conservan su historial. Queda auditado.
--   Resultados: 1 header · 2 resumen · 3 motivos (solo al preparar)
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
    ELSEIF v_tiene_oc = 1 THEN
        SET v_puede = 0, v_bloqueo = 'La propuesta tiene una orden de compra vinculada y no puede anularse.';
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
                  '. El RQ y el expediente conservarán el historial. La acción será auditada.') AS impacto,
           tm.String1                                           AS motivo_anulacion,
           p.justificacion_anulacion,
           p.fecha_anulacion
    FROM propuesta_comercial p
    JOIN cliente c             ON c.id_cliente = p.id_cliente
    LEFT JOIN requerimiento r  ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN tabla_maestra tm ON tm.IdMaestro = 9 AND tm.IdEmpresa = 1 AND tm.Num1 = p.id_motivo_anulacion
    WHERE p.id_propuesta = p_id_propuesta;

    IF p_solo_preparar = 1 THEN
        SELECT Num1 AS id, String1 AS nombre
        FROM tabla_maestra
        WHERE IdMaestro = 9 AND IdEmpresa = 1 AND eliminado_en IS NULL
        ORDER BY Num1;
    END IF;
END$$

DELIMITER ;
