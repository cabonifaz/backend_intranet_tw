-- HU-16 — 1 si el usuario está a cargo de resolver (o reasignar) el visto bueno.
--   Con propuesta_vb_todas: siempre.
--   VB reasignado: solo el nuevo aprobador.
--   VB original: el jefe directo del comercial o su suplente vigente.
--   No valida la acción propuesta_vb_resolver ni que la propuesta sea propia.
DROP FUNCTION IF EXISTS FN_PuedeResolverVistoBueno;

DELIMITER $$

CREATE FUNCTION FN_PuedeResolverVistoBueno(p_id_vb BIGINT, p_id_usuario BIGINT) RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_origen BIGINT;
    DECLARE v_jefe   BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 1 THEN
        RETURN 1;
    END IF;

    SELECT vb.id_vb_origen, a.id_supervisor INTO v_origen, v_jefe
    FROM visto_bueno vb
    JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
    JOIN usuario a ON a.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE vb.id_vb = p_id_vb;

    IF v_origen IS NOT NULL THEN
        RETURN IF(FN_AprobadorVistoBueno(p_id_vb) = p_id_usuario, 1, 0);
    END IF;

    RETURN IF(p_id_usuario = v_jefe OR p_id_usuario = FN_AprobadorVistoBueno(p_id_vb), 1, 0);
END$$

DELIMITER ;
