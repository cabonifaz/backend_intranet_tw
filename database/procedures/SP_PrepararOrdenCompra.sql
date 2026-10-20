-- HU-23 (Sprint 4) Datos de la ficha "Registrar Orden de Compra".
-- La propuesta de origen debe estar ACEPTADA por el cliente, ser del área del usuario y tener saldo por cubrir.
-- p_id_oc_reemplaza (HU-27): OC autogenerada que se reemplazará por la OC del cliente; su vinculación se conserva.
-- Resultados:
--   1 mensaje
--   2 propuesta de origen (cliente, RQ, contacto, total, saldo, moneda, condición de pago, IGV, vencimiento)
--   3 OC autogenerada a reemplazar (vacío si no aplica)
--   4 otras propuestas aceptadas del mismo cliente con saldo ("Agregar propuesta vinculada")
--   5 monedas   6 condiciones de pago
DROP PROCEDURE IF EXISTS SP_PrepararOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararOrdenCompra(
    IN p_id_usuario      BIGINT,
    IN p_id_propuesta    BIGINT,
    IN p_id_oc_reemplaza BIGINT
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_id_cliente BIGINT;
    DECLARE v_saldo      DECIMAL(14,2);
    DECLARE v_auto_ok    INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_oc_reemplaza, 0) > 0 THEN
        SELECT COUNT(*) INTO v_auto_ok
        FROM orden_compra oc
        JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL
        WHERE oc.id_oc = p_id_oc_reemplaza AND oc.es_autogenerada = 1 AND oc.reemplazada_por IS NULL
          AND oc.estado <> 'anulada' AND oc.eliminado_en IS NULL;
        IF v_auto_ok = 0 THEN
            SELECT 1 AS IdTipoMensaje,
                   'La OC autogenerada no existe, ya fue reemplazada o no corresponde a la propuesta.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    CALL SP_CalcularPropuestasDisponiblesOc(p_id_usuario, NULL, p_id_oc_reemplaza);

    SELECT COUNT(*), MAX(id_cliente), MAX(saldo) INTO v_existe, v_id_cliente, v_saldo
    FROM tmp_oc_disp WHERE id_propuesta = p_id_propuesta;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
        SELECT 1 AS IdTipoMensaje,
               IF(EXISTS (SELECT 1 FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta),
                  'La propuesta no está aceptada por el cliente, no es de tu área o ya está cubierta por órdenes de compra.',
                  'La propuesta no existe.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Propuesta de origen
    SELECT d.id_propuesta, d.numero, d.version, d.id_cliente, d.razon_social, d.ruc,
           d.id_requerimiento, d.numero_rq, d.id_contacto, d.contacto, d.cargo_contacto,
           d.total, d.saldo, d.id_moneda, d.moneda, d.moneda_simbolo,
           p.id_condicion_pago,
           (SELECT MAX(cp.String1) FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1
              AND cp.Num1 = p.id_condicion_pago)                                    AS condicion_pago, p.aplica_igv, p.igv_pct, p.fecha_expiracion,
           d.fecha_aceptacion, d.id_responsable, d.responsable, d.tipo_servicio, d.referencia,
           (SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = d.id_propuesta AND i.seccion = 'principal'
              AND IFNULL(i.es_espaciado, 0) = 0)                                     AS items,
           CURDATE()                                                                 AS fecha_servidor
    FROM tmp_oc_disp d
    JOIN propuesta_comercial p ON p.id_propuesta = d.id_propuesta
    WHERE d.id_propuesta = p_id_propuesta;

    -- 3. OC autogenerada a reemplazar
    SELECT oc.id_oc, oc.numero_oc, oc.monto_total, oc.fecha_registro
    FROM orden_compra oc
    WHERE oc.id_oc = IFNULL(p_id_oc_reemplaza, 0);

    -- 4. Otras propuestas del mismo cliente
    SELECT id_propuesta, numero, version, id_requerimiento, numero_rq, id_contacto, contacto,
           total, saldo, id_moneda, moneda, moneda_simbolo, fecha_aceptacion, responsable, tipo_servicio
    FROM tmp_oc_disp
    WHERE id_cliente = v_id_cliente AND id_propuesta <> p_id_propuesta
    ORDER BY fecha_aceptacion DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;

    -- 5. Monedas
    SELECT Num1 AS id, String1 AS nombre, String2 AS simbolo, String3 AS codigo
    FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND eliminado_en IS NULL ORDER BY Num1;

    -- 6. Condiciones de pago
    SELECT Num1 AS id, MAX(String1) AS nombre, MAX(String2) AS codigo
    FROM tabla_maestra WHERE IdMaestro = 39 AND IdEmpresa = 1 AND eliminado_en IS NULL GROUP BY Num1 ORDER BY Num1;
END$$

DELIMITER ;
