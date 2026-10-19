-- HU-16 — Aprobador efectivo de un visto bueno.
--   VB reasignado (id_vb_origen con valor): el aprobador elegido al reasignar.
--   VB original: el suplente vigente del jefe directo del comercial, o el jefe directo.
DROP FUNCTION IF EXISTS FN_AprobadorVistoBueno;

DELIMITER $$

CREATE FUNCTION FN_AprobadorVistoBueno(p_id_vb BIGINT) RETURNS BIGINT
READS SQL DATA
BEGIN
    DECLARE v_origen    BIGINT;
    DECLARE v_aprobador BIGINT;
    DECLARE v_jefe      BIGINT;
    DECLARE v_suplente  BIGINT;

    SELECT vb.id_vb_origen, vb.id_aprobador, a.id_supervisor
      INTO v_origen, v_aprobador, v_jefe
    FROM visto_bueno vb
    JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
    JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE vb.id_vb = p_id_vb;

    IF v_origen IS NOT NULL THEN
        RETURN v_aprobador;
    END IF;

    SELECT us.id_suplente INTO v_suplente
    FROM usuario_suplente us
    JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
    WHERE us.id_titular = v_jefe AND us.SoftDelete = 0 AND us.activo = 1
      AND us.fecha_inicio <= CURDATE() AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
    ORDER BY us.fecha_inicio DESC LIMIT 1;

    RETURN COALESCE(v_suplente, v_jefe);
END$$

DELIMITER ;
