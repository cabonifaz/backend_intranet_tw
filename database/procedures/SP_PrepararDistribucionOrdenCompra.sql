-- HU-27 Modal "Distribuir Monto de OC".
-- Acción oc_distribuir y OC del área del usuario.
-- Resultados:
--   1 mensaje
--   2 OC: monto total, monto aplicado (asignado a propuestas), saldo disponible, uso de fondos y si se puede distribuir
--   3 aplicaciones: propuestas ya vinculadas a la OC (vinculada = 1) y propuestas destino posibles (vinculada = 0):
--     aceptadas por el cliente, del mismo cliente y moneda, con monto pendiente de cubrir.
--     estado: cubierto | parcial | pendiente
DROP PROCEDURE IF EXISTS SP_PrepararDistribucionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararDistribucionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp INT;
    DECLARE v_meta          INT;
    DECLARE v_sla_horas     INT;
    DECLARE v_alerta_horas  INT;
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_estado        VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vencida       TINYINT DEFAULT 0;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_id_moneda     INT;
    DECLARE v_id_prop       BIGINT;
    DECLARE v_obs           INT DEFAULT 0;
    DECLARE v_motivo_no     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_distribuir') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para distribuir el saldo de órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(vencida), MAX(id_cliente), MAX(id_moneda), MAX(id_propuesta)
      INTO v_existe, v_estado, v_vencida, v_id_cliente, v_id_moneda, v_id_prop
    FROM tmp_oc;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_obs FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL;
    SET v_motivo_no = CASE WHEN v_estado = 'anulada' THEN 'La orden de compra está anulada.'
                           WHEN v_vencida = 1     THEN 'La orden de compra está vencida.'
                           WHEN v_obs > 0         THEN 'La orden de compra tiene una observación abierta.'
                           ELSE NULL END;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OC
    SELECT t.id_oc, t.numero_oc, t.tipo_oc, t.estado_bd AS estado, t.estado_visual,
           t.id_cliente, c.razon_social, c.ruc,
           t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo,
           t.monto_oc                                                   AS monto_total,
           t.monto_asignado_oc                                          AS monto_aplicado,
           t.saldo_disponible,
           IF(t.monto_oc > 0, ROUND(t.monto_asignado_oc * 100 / t.monto_oc, 1), 0) AS uso_pct,
           IF(v_motivo_no IS NULL AND t.saldo_disponible > 0, 1, 0)     AS puede_distribuir,
           COALESCE(v_motivo_no, IF(t.saldo_disponible > 0, NULL, 'La orden de compra no tiene saldo disponible.')) AS motivo_no_disponible
    FROM tmp_oc t
    LEFT JOIN cliente c       ON c.id_cliente = t.id_cliente
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    -- Propuestas aceptadas en alcance (para los destinos posibles)
    CALL SP_CalcularSeguimientoComercial(p_id_usuario, NULL, v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

    DROP TEMPORARY TABLE IF EXISTS tmp_dist;
    CREATE TEMPORARY TABLE tmp_dist AS
    SELECT p.id_propuesta, 1 AS vinculada, (p.id_propuesta = v_id_prop) AS es_principal
    FROM propuesta_comercial p
    WHERE p.id_propuesta = v_id_prop
       OR p.id_propuesta IN (SELECT op.id_propuesta FROM oc_propuesta op WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL);

    INSERT INTO tmp_dist (id_propuesta, vinculada, es_principal)
    SELECT t.id_propuesta, 0, 0
    FROM tmp_seg t
    WHERE t.estado_seguimiento = 'aceptada' AND t.id_cliente = v_id_cliente AND t.id_moneda = v_id_moneda
      AND t.id_propuesta NOT IN (SELECT op.id_propuesta FROM oc_propuesta op WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL)
      AND IFNULL(t.id_propuesta <> v_id_prop, 1)
      AND t.total > (SELECT IFNULL(SUM(op2.monto_asignado), 0) FROM oc_propuesta op2
                     JOIN orden_compra o2 ON o2.id_oc = op2.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op2.id_propuesta)
                     WHERE op2.id_propuesta = t.id_propuesta AND op2.eliminado_en IS NULL) + 0.005;

    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;

    -- 3. Aplicaciones registradas y destinos posibles
    SELECT x.*,
           GREATEST(x.requerido - x.aplicado - x.aplicado_otras_oc, 0) AS pendiente,
           CASE WHEN x.requerido - x.aplicado - x.aplicado_otras_oc < 0.005 THEN 'cubierto'
                WHEN x.aplicado + x.aplicado_otras_oc > 0                  THEN 'parcial'
                ELSE 'pendiente' END                                     AS estado_cobertura
    FROM (
        SELECT d.id_propuesta, CONCAT(p.numero, ' v', p.version) AS documento, 'Propuesta' AS tipo,
               p.numero, p.version, c.razon_social AS cliente,
               LEFT(r.descripcion, 120) AS concepto,
               p.total AS requerido,
               IFNULL((SELECT SUM(op.monto_asignado) FROM oc_propuesta op
                       WHERE op.id_oc = p_id_oc AND op.id_propuesta = d.id_propuesta AND op.eliminado_en IS NULL), 0) AS aplicado,
               IFNULL((SELECT SUM(op2.monto_asignado) FROM oc_propuesta op2
                       JOIN orden_compra o2 ON o2.id_oc = op2.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op2.id_propuesta)
                       WHERE op2.id_propuesta = d.id_propuesta AND op2.id_oc <> p_id_oc AND op2.eliminado_en IS NULL), 0) AS aplicado_otras_oc,
               d.vinculada, d.es_principal,
               p.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable
        FROM tmp_dist d
        JOIN propuesta_comercial p ON p.id_propuesta = d.id_propuesta
        LEFT JOIN cliente c        ON c.id_cliente = p.id_cliente
        LEFT JOIN requerimiento r  ON r.id_requerimiento = p.id_requerimiento
        LEFT JOIN usuario u        ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    ) x
    ORDER BY x.vinculada DESC, x.es_principal DESC, x.numero;

    DROP TEMPORARY TABLE IF EXISTS tmp_dist;
END$$

DELIMITER ;
