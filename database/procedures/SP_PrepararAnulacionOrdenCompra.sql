-- HU-28 (Sprint 4) Datos del modal "Anular Orden de Compra": monto a anular, propuestas afectadas,
-- órdenes de servicio en ejecución (impacto crítico) y motivos tipificados (MOTIVO_ANULACION_OC, 102).
-- Reglas: acción oc_anular; OC del área del usuario, no anulada, no reemplazada y no autogenerada.
-- generara_oc_autogenerada (por propuesta): la propuesta está aceptada y queda sin OC vigente, así que al anular se
--   generará una OC autogenerada nueva por su saldo (ver SP_AnularOrdenCompra).
-- Resultados: 1 mensaje, 2 resumen del impacto, 3 propuestas afectadas, 4 OS en ejecución, 5 motivos.
DROP PROCEDURE IF EXISTS SP_PrepararAnulacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararAnulacionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_reemp  BIGINT;
    DECLARE v_auto   TINYINT DEFAULT 0;
    DECLARE v_os     INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'oc_anular') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para anular órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado), MAX(reemplazada_por), MAX(es_autogenerada) INTO v_existe, v_estado, v_reemp, v_auto FROM tmp_oc;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra ya está anulada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_reemp IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra ya fue reemplazada por la OC del cliente.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_auto = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje,
               'La OC autogenerada no se anula: reemplázala por la OC del cliente o anula la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_anu_os;
    CREATE TEMPORARY TABLE tmp_oc_anu_os AS
    SELECT DISTINCT os.id_os, os.numero, os.estado, os.fecha_ejecucion, e.numero AS numero_expediente
    FROM oc_propuesta op
    JOIN expediente_digital e ON e.id_expediente = FN_ExpedienteDePropuesta(op.id_propuesta)
    JOIN orden_servicio os    ON os.id_expediente = e.id_expediente AND os.eliminado_en IS NULL
                             AND os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL;

    SELECT COUNT(*) INTO v_os FROM tmp_oc_anu_os;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen del impacto
    SELECT t.id_oc, t.numero_oc, t.es_autogenerada, c.razon_social, t.id_moneda,
           (SELECT MAX(m.String2) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda) AS moneda_simbolo,
           t.monto_oc, t.monto_asignado, t.propuestas_vinculadas,
           v_os                                                    AS os_en_ejecucion,
           (v_os > 0)                                              AS impacto_critico,
           NOW()                                                   AS fecha_servidor
    FROM tmp_oc t
    JOIN cliente c ON c.id_cliente = t.id_cliente;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    -- 3. Propuestas afectadas: pierden la cobertura de esta OC
    SELECT op.id_propuesta, p.numero, p.version, op.monto_asignado, op.estado_validacion,
           FN_SaldoPropuestaOc(op.id_propuesta, NULL)              AS saldo_actual,
           FN_SaldoPropuestaOc(op.id_propuesta, p_id_oc)           AS saldo_despues,
           (p.estado = 'aceptado'
            AND NOT EXISTS (SELECT 1 FROM propuesta_comercial pn
                            WHERE pn.numero = p.numero AND pn.version > p.version AND pn.eliminado_en IS NULL
                              AND pn.estado NOT IN ('anulado', 'revocada'))
            AND NOT EXISTS (SELECT 1 FROM oc_propuesta o2 JOIN orden_compra c2 ON c2.id_oc = o2.id_oc
                            WHERE o2.id_propuesta = op.id_propuesta AND o2.eliminado_en IS NULL AND o2.id_oc <> p_id_oc
                              AND c2.eliminado_en IS NULL AND c2.estado <> 'anulada' AND c2.reemplazada_por IS NULL)
            AND FN_SaldoPropuestaOc(op.id_propuesta, p_id_oc) > 0) AS generara_oc_autogenerada
    FROM oc_propuesta op
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id;

    -- 4. OS en ejecución
    SELECT id_os, numero, estado, fecha_ejecucion, numero_expediente FROM tmp_oc_anu_os ORDER BY id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_anu_os;

    -- 5. Motivos de anulación
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra WHERE IdMaestro = 102 AND IdEmpresa = 1 AND eliminado_en IS NULL ORDER BY Num1;
END$$

DELIMITER ;
