-- Expediente Digital (HU-30, tab Visto Bueno): aprobador que se muestra para un visto bueno.
--   Resuelto (aprobado, rechazado, devuelto, cancelado…): quien lo resolvió (resuelto_por); en VB antiguos sin ese dato,
--     el aprobador asignado, el último usuario que lo modificó o quien dejó el evento vb_* en la auditoría de la propuesta.
--   Pendiente: el aprobador asignado o, si el VB está en la bandeja del área (migración 49), el aprobador efectivo
--     (FN_AprobadorVistoBueno: reasignado, suplente vigente o jefe directo del comercial).
DROP FUNCTION IF EXISTS FN_AprobadorVistoBuenoExpediente;

DELIMITER $$

CREATE FUNCTION FN_AprobadorVistoBuenoExpediente(p_id_vb BIGINT) RETURNS BIGINT
READS SQL DATA
BEGIN
    DECLARE v_estado     VARCHAR(30);
    DECLARE v_resuelto   BIGINT;
    DECLARE v_aprobador  BIGINT;
    DECLARE v_modificado BIGINT;
    DECLARE v_id_prop    BIGINT;
    DECLARE v_respuesta  DATETIME;
    DECLARE v_auditoria  BIGINT;

    SELECT estado, resuelto_por, id_aprobador, modificado_por, id_propuesta, fecha_respuesta
      INTO v_estado, v_resuelto, v_aprobador, v_modificado, v_id_prop, v_respuesta
    FROM visto_bueno WHERE id_vb = p_id_vb;

    IF v_estado IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_estado = 'pendiente' THEN
        RETURN COALESCE(v_aprobador, FN_AprobadorVistoBueno(p_id_vb));
    END IF;

    IF v_resuelto IS NULL AND v_aprobador IS NULL AND v_respuesta IS NOT NULL THEN
        SELECT a.id_usuario INTO v_auditoria FROM auditoria_evento a
        WHERE a.entidad_tipo = 'propuesta' AND a.id_entidad = v_id_prop AND a.accion LIKE 'vb\_%'
          AND a.registrado_en BETWEEN v_respuesta - INTERVAL 5 MINUTE AND v_respuesta + INTERVAL 5 MINUTE
        ORDER BY ABS(TIMESTAMPDIFF(SECOND, a.registrado_en, v_respuesta)) LIMIT 1;
    END IF;

    RETURN COALESCE(v_resuelto, v_aprobador, v_auditoria, v_modificado, FN_AprobadorVistoBueno(p_id_vb));
END$$

DELIMITER ;
