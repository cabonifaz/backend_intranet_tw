-- Expediente Digital (interno): crea el expediente de un RQ si aún no existe.
-- Se llama al registrar el RQ (SP_GuardarRequerimiento). Número EXP-AAAA-NNNN con el id del expediente
-- (no se repite aunque dos RQ se registren al mismo tiempo).
-- No devuelve resultados.
DROP PROCEDURE IF EXISTS SP_CrearExpedienteRequerimiento;

DELIMITER $$

CREATE PROCEDURE SP_CrearExpedienteRequerimiento(
    IN p_id_requerimiento BIGINT,
    IN p_id_usuario       BIGINT
)
proc: BEGIN
    DECLARE v_id_exp BIGINT;

    IF EXISTS (SELECT 1 FROM expediente_digital
               WHERE id_requerimiento = p_id_requerimiento AND eliminado_en IS NULL) THEN
        LEAVE proc;
    END IF;

    INSERT INTO expediente_digital (numero, id_requerimiento, id_cliente, etapa_actual, estado,
                                    area_responsable, fecha_creacion, creado_por)
    SELECT CONCAT('EXP-TMP-', r.id_requerimiento), r.id_requerimiento, r.id_cliente, 'requerimiento', 'activo',
           'comercial', NOW(), p_id_usuario
    FROM requerimiento r
    WHERE r.id_requerimiento = p_id_requerimiento;

    IF ROW_COUNT() = 0 THEN
        LEAVE proc;
    END IF;

    SET v_id_exp = LAST_INSERT_ID();
    UPDATE expediente_digital
    SET numero = CONCAT('EXP-', YEAR(fecha_creacion), '-', LPAD(id_expediente, 4, '0'))
    WHERE id_expediente = v_id_exp;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
    SELECT 'expediente', v_id_exp, 'crear_expediente', NULL, 'requerimiento',
           CONCAT('Expediente creado con el requerimiento ', r.numero, '.'), p_id_usuario, NOW()
    FROM requerimiento r WHERE r.id_requerimiento = p_id_requerimiento;
END$$

DELIMITER ;
