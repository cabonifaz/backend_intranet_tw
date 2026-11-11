-- ============================================================
-- SP_EvaluarLlegadaMovil  (App Mobile HU-06 — apoyo, no es un endpoint)
-- Regla de la llegada validada por GPS, UNA sola vez (la usan la validación y el registro). Solo lectura.
--   Referencia = coordenada de la planta: sede_cliente.latitud/longitud (migración 110) de la OS o, si no tiene, la del requerimiento (RQ); luego la tabla sede; si ninguna la tiene, la llegada ya registrada de la OS
--   (orden_servicio.latitud_llegada/longitud_llegada), igual que la bandeja de Seguimiento Operativo.
--   Parámetros (PARAMETRO_PROGRAMACION, migración 97): LLEGADA_RADIO_METROS (200) y LLEGADA_PRECISION_MAX_METROS (100).
--   Resultado:
--     precision_baja  ± de la precisión supera el máximo: no se puede registrar (hay que volver a capturar en un lugar abierto)
--     sin_referencia  la planta no tiene coordenada: se puede registrar, queda sin validar distancia
--     valida          dentro del radio permitido
--     fuera_rango     fuera del radio: no se puede registrar
--     autorizada      fuera del radio, pero Jefatura aprobó la llegada forzada (llegada_forzada_os, aprobada y sin usar): se puede registrar UNA vez
--   p_registrable: 1 = se puede confirmar la llegada. p_mensaje: texto para el técnico. Distancia por Haversine (m).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EvaluarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarLlegadaMovil(
    IN  p_id_os          BIGINT,
    IN  p_latitud        DECIMAL(10,7),
    IN  p_longitud       DECIMAL(10,7),
    IN  p_precision      DECIMAL(8,1),
    OUT p_resultado      VARCHAR(20),
    OUT p_registrable    TINYINT,
    OUT p_distancia      INT,
    OUT p_radio          INT,
    OUT p_precision_max  INT,
    OUT p_lat_ref        DECIMAL(10,7),
    OUT p_lon_ref        DECIMAL(10,7),
    OUT p_mensaje        VARCHAR(250)
)
BEGIN
    DECLARE v_radio DECIMAL(18,6);
    DECLARE v_pmax  DECIMAL(18,6);

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);
    CALL SP_LeerParametroProgramacion('LLEGADA_PRECISION_MAX_METROS', 100, v_pmax);
    SET p_radio         = ROUND(v_radio);
    SET p_precision_max = ROUND(v_pmax);
    SET p_distancia     = NULL;
    SET p_lat_ref       = NULL;
    SET p_lon_ref       = NULL;

    SELECT COALESCE(sc.latitud, s.latitud, sc2.latitud, os.latitud_llegada), COALESCE(sc.longitud, s.longitud, sc2.longitud, os.longitud_llegada) INTO p_lat_ref, p_lon_ref
    FROM   orden_servicio os
    LEFT JOIN sede_cliente sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN sede s           ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    LEFT JOIN requerimiento rq ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    WHERE  os.id_os = p_id_os;

    IF p_precision IS NOT NULL AND p_precision > p_precision_max THEN
        SET p_resultado   = 'precision_baja';
        SET p_registrable = 0;
        SET p_mensaje     = CONCAT('La señal GPS es débil (± ', ROUND(p_precision), ' m; máximo ', p_precision_max,
                                   ' m). Sal a un lugar abierto y vuelve a capturar tu ubicación.');
    ELSEIF p_lat_ref IS NULL OR p_lon_ref IS NULL THEN
        SET p_resultado   = 'sin_referencia';
        SET p_registrable = 1;
        SET p_mensaje     = 'La planta no tiene coordenadas registradas: tu llegada se registrará sin validar la distancia y quedará marcada para Operaciones.';
    ELSE
        SET p_distancia = ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(p_lat_ref - p_latitud) / 2), 2)
                          + COS(RADIANS(p_latitud)) * COS(RADIANS(p_lat_ref)) * POW(SIN(RADIANS(p_lon_ref - p_longitud) / 2), 2))));
        IF p_distancia <= p_radio THEN
            SET p_resultado   = 'valida';
            SET p_registrable = 1;
            SET p_mensaje     = CONCAT('Te encuentras dentro del rango permitido (a ', FORMAT(p_distancia, 0), ' m de la planta).');
        ELSE
            SET p_resultado   = 'fuera_rango';
            SET p_registrable = 0;
            SET p_mensaje     = CONCAT('Estás a ', FORMAT(p_distancia, 0), ' m de la planta (máximo ', p_radio, ' m). Acércate para registrar tu llegada.');
            -- Llegada forzada aprobada por Jefatura (HU-06): se puede registrar aunque esté fuera del radio, una sola vez
            IF EXISTS (SELECT 1 FROM llegada_forzada_os f WHERE f.id_os = p_id_os AND f.estado = 'aprobada' AND f.usada_en IS NULL AND f.eliminado_en IS NULL) THEN
                SET p_resultado   = 'autorizada';
                SET p_registrable = 1;
                SET p_mensaje     = CONCAT('Jefatura autorizó tu llegada (estás a ', FORMAT(p_distancia, 0), ' m de la planta). Ya puedes confirmarla.');
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;
