-- HU-24 Datos de la pantalla "Editar Orden de Compra".
-- Acción oc_editar y OC del área del usuario. Una OC anulada no se puede editar.
-- Resultados:
--   1 mensaje
--   2 OC: datos editables, datos bloqueados (propuesta, RQ, cliente), resumen de situación
--     (monto propuesta, monto OC, aplicado, saldo y cobertura) y avisos:
--       requiere_revalidacion_al_cambiar = 1 si la OC está validada (cambiar monto o moneda la regresa a validación)
--       puede_cambiar_monto = 0 si la OC ya tiene órdenes de servicio
--   3 monedas
DROP PROCEDURE IF EXISTS SP_PrepararEdicionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararEdicionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_estado VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd) INTO v_existe, v_estado FROM tmp_oc;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada y no se puede editar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OC
    SELECT
        t.id_oc, oc.numero_oc, oc.referencia,
        oc.fecha_oc, oc.fecha_recepcion, oc.vigencia_dias, oc.vigencia_hasta,
        oc.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo, m.String1 AS moneda_nombre,
        oc.monto_total AS monto_oc, oc.observaciones,
        oc.nombre_archivo_pdf, oc.tamano_pdf_bytes,
        IF(oc.url_archivo_pdf IS NULL, NULL, CONCAT('/api/crm/ordenes-compra/', t.id_oc, '/pdf')) AS url_pdf,
        -- bloqueados
        t.id_propuesta, t.numero_propuesta, t.version_propuesta,
        t.id_requerimiento, r.numero AS numero_rq,
        t.id_cliente, c.razon_social, c.ruc,
        pm.id_moneda AS id_moneda_propuesta, mp.String2 AS moneda_simbolo_propuesta,
        -- resumen de situación
        t.monto_propuesta, t.monto_aplicado, t.saldo, t.cobertura_pct, t.utilizacion_pct,
        t.cobertura_codigo, t.cobertura_proyectada,
        t.estado_bd AS estado, t.estado_visual,
        t.id_motivo_observacion, mo.String1 AS motivo_observacion,
        t.validada                                  AS requiere_revalidacion_al_cambiar,
        IF(t.ordenes_servicio > 0, 0, 1)            AS puede_cambiar_monto,
        t.ordenes_servicio,
        CURDATE()                                   AS fecha_servidor
    FROM tmp_oc t
    JOIN orden_compra oc            ON oc.id_oc           = t.id_oc
    LEFT JOIN propuesta_comercial pm ON pm.id_propuesta   = t.id_propuesta
    LEFT JOIN requerimiento r       ON r.id_requerimiento = t.id_requerimiento
    LEFT JOIN cliente c             ON c.id_cliente       = t.id_cliente
    LEFT JOIN tabla_maestra m  ON m.IdMaestro  = 1  AND m.IdEmpresa  = 1 AND m.Num1  = oc.id_moneda
    LEFT JOIN tabla_maestra mp ON mp.IdMaestro = 1  AND mp.IdEmpresa = 1 AND mp.Num1 = pm.id_moneda
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 14 AND mo.IdEmpresa = 1 AND mo.Num1 = t.id_motivo_observacion;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    -- 3. Monedas
    SELECT Num1 AS id, String1 AS nombre, String2 AS simbolo, String3 AS codigo
    FROM tabla_maestra
    WHERE IdMaestro = 1 AND IdEmpresa = 1 AND eliminado_en IS NULL
    ORDER BY Num1;
END$$

DELIMITER ;
