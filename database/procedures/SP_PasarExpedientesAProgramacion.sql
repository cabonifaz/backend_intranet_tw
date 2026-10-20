-- HU-25/27 (Sprint 4) Expedientes que pasan a Programación por la orden de compra. Uso interno, sin resultados.
-- Reemplaza la antigua "liberación" (ya no está en el refinamiento): el expediente de cada propuesta con su
-- vinculación VALIDADA (o cubierta por una OC autogenerada vigente, que habilita programar y ejecutar) pasa a
-- Programación con el área Operaciones y su SLA, si sigue en la etapa comercial y no tiene bloqueos abiertos.
-- Notifica a Operaciones (supervisores y administradores).
DROP PROCEDURE IF EXISTS SP_PasarExpedientesAProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_PasarExpedientesAProgramacion(
    IN p_id_oc      BIGINT,
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_sla       INT;
    DECLARE v_numero_oc VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_auto      TINYINT;

    SELECT numero_oc, (es_autogenerada = 1 AND reemplazada_por IS NULL) INTO v_numero_oc, v_auto
    FROM orden_compra WHERE id_oc = p_id_oc AND estado <> 'anulada' AND eliminado_en IS NULL;

    SELECT CAST(IFNULL(MAX(Num2), 4) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'expediente' AND String2 = 'programacion';

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_prog;
    CREATE TEMPORARY TABLE tmp_oc_prog (
        id_expediente  BIGINT PRIMARY KEY,
        id_propuesta   BIGINT,
        etapa_anterior VARCHAR(30)
    );

    IF v_numero_oc IS NOT NULL THEN
        INSERT IGNORE INTO tmp_oc_prog (id_expediente, id_propuesta, etapa_anterior)
        SELECT e.id_expediente, op.id_propuesta, e.etapa_actual
        FROM oc_propuesta op
        JOIN expediente_digital e ON e.id_expediente = FN_ExpedienteDePropuesta(op.id_propuesta)
        WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
          AND (op.estado_validacion = 'validada' OR v_auto = 1)
          AND e.eliminado_en IS NULL AND e.estado <> 'cerrado'
          AND e.etapa_actual IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra')
          AND NOT EXISTS (SELECT 1 FROM expediente_bloqueador b
                          WHERE b.id_expediente = e.id_expediente AND b.resuelto = 0 AND b.eliminado_en IS NULL
                            AND b.clase = 'bloqueo');
    END IF;

    IF EXISTS (SELECT 1 FROM tmp_oc_prog) THEN
        UPDATE expediente_digital e
        JOIN tmp_oc_prog t ON t.id_expediente = e.id_expediente
        SET e.id_orden_compra       = IFNULL(e.id_orden_compra, p_id_oc),
            e.id_propuesta          = IFNULL(e.id_propuesta, t.id_propuesta),
            e.etapa_actual          = 'programacion',
            e.area_responsable      = 'operaciones',
            e.id_responsable_actual = NULL,
            e.fecha_etapa           = NOW(),
            e.sla_horas             = v_sla,
            e.fecha_limite_sla      = NOW() + INTERVAL v_sla HOUR,
            e.modificado_por        = p_id_usuario;

        INSERT INTO expediente_etapa (id_expediente, etapa, area, id_responsable, fecha_inicio, sla_horas, fecha_limite,
                                      resultado, comentario, UsuCre, FchCre)
        SELECT t.id_expediente, 'programacion', 'operaciones', NULL, NOW(), v_sla, NOW() + INTERVAL v_sla HOUR, 'en_curso',
               CONCAT('Pasa a Programación con la OC ', v_numero_oc, IF(v_auto = 1, ' (autogenerada).', ' validada.')),
               CAST(p_id_usuario AS CHAR), NOW()
        FROM tmp_oc_prog t;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        SELECT 'expediente', t.id_expediente, 'pasar_programacion', t.etapa_anterior, 'programacion',
               CONCAT('El expediente pasa a Programación con la OC ', v_numero_oc, '.'),
               p_id_usuario, NOW(), JSON_OBJECT('id_oc', p_id_oc, 'id_propuesta', t.id_propuesta)
        FROM tmp_oc_prog t;

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5,
               CONCAT('Expediente listo para programar: ', e.numero),
               CONCAT('La OC ', v_numero_oc, ' habilita la programación del expediente ', e.numero, '. SLA: ', v_sla, ' h.'),
               'expediente', e.id_expediente, NOW(), p_id_usuario
        FROM tmp_oc_prog t
        JOIN expediente_digital e ON e.id_expediente = t.id_expediente
        JOIN usuario u ON u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador')
                      AND u.estado = 'activo' AND u.eliminado_en IS NULL AND u.id_usuario <> p_id_usuario;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_prog;
END$$

DELIMITER ;
