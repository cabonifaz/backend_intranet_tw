-- HU-32 (Sprint 4) Bloqueos automáticos del expediente por la orden de compra. Uso interno, sin resultados ni transacción.
-- Lo llaman los SP de Órdenes de Compra cada vez que cambia el estado de una OC (decisión, reemplazo o anulación):
--   · Vinculación observada con "Solicitar corrección al cliente" o "Nueva versión de propuesta" → BLOQUEO abierto en el
--     expediente de esa propuesta (no pasa a Orden de Servicio hasta corregir).
--   · Vinculación observada informativa ("Guardar con observaciones") → EXCEPCIÓN abierta.
--   · Si la OC ya no tiene vinculaciones observadas para ese expediente (validada, anulada o reemplazada), el bloqueo o
--     excepción abierto se resuelve solo, con la fecha y el motivo (para la pestaña Bloqueos de la auditoría).
-- El expediente no registra ni resuelve bloqueos a mano: se resuelven en el módulo origen.
DROP PROCEDURE IF EXISTS SP_SincronizarBloqueosOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_SincronizarBloqueosOrdenCompra(
    IN p_id_oc      BIGINT,
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_numero    VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vigente   TINYINT DEFAULT 0;
    DECLARE v_estado    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_reemplazo VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT oc.numero_oc, (oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL), oc.estado,
           (SELECT n.numero_oc FROM orden_compra n WHERE n.id_oc = oc.reemplazada_por)
      INTO v_numero, v_vigente, v_estado, v_reemplazo
    FROM orden_compra oc WHERE oc.id_oc = p_id_oc;

    -- Vinculaciones observadas vigentes de la OC, por expediente
    DROP TEMPORARY TABLE IF EXISTS tmp_sync_blq;
    CREATE TEMPORARY TABLE tmp_sync_blq AS
    SELECT x.id_expediente, MAX(x.bloquea) AS bloquea, MAX(x.id_responsable) AS id_responsable
    FROM (
        SELECT FN_ExpedienteDePropuesta(op.id_propuesta) AS id_expediente,
               (op.tipo_observacion IN ('correccion_cliente', 'nueva_version')) AS bloquea,
               COALESCE(oc.id_responsable, p.id_responsable, p.id_creador) AS id_responsable
        FROM oc_propuesta op
        JOIN orden_compra oc ON oc.id_oc = op.id_oc
        JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
        WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL AND op.estado_validacion = 'observada' AND v_vigente = 1
    ) x
    WHERE x.id_expediente IS NOT NULL
    GROUP BY x.id_expediente;

    -- 1. Resuelve lo que ya no aplica (o cambió de clase: se cierra y se abre el nuevo)
    UPDATE expediente_bloqueador b
    LEFT JOIN tmp_sync_blq t ON t.id_expediente = b.id_expediente
    SET b.resuelto = 1, b.fecha_resolucion = NOW(), b.resuelto_por = p_id_usuario, b.modificado_por = p_id_usuario,
        b.sustento = CASE
            WHEN t.id_expediente IS NOT NULL                       THEN 'La observación de la OC cambió de tipo.'
            WHEN v_estado = 'anulada' OR v_vigente IS NULL         THEN CONCAT('Resuelto en Órdenes de Compra: la OC ', IFNULL(v_numero, ''), ' fue anulada.')
            WHEN v_reemplazo IS NOT NULL                           THEN CONCAT('Resuelto en Órdenes de Compra: la OC ', IFNULL(v_numero, ''),
                                                                                ' fue reemplazada por la OC ', v_reemplazo, '.')
            ELSE CONCAT('Resuelto en Órdenes de Compra: la OC ', IFNULL(v_numero, ''), ' fue validada.') END
    WHERE b.origen_tipo = 'orden_compra' AND b.id_origen = p_id_oc AND b.resuelto = 0 AND b.eliminado_en IS NULL
      AND (t.id_expediente IS NULL OR b.clase <> IF(t.bloquea = 1, 'bloqueo', 'excepcion'));

    -- 2. Abre el bloqueo o la excepción donde falte
    INSERT INTO expediente_bloqueador (id_expediente, clase, descripcion, tipo, etapa, impacto, critico, origen_tipo, id_origen,
                                       id_responsable, resuelto, creado_en, creado_por)
    SELECT t.id_expediente, IF(t.bloquea = 1, 'bloqueo', 'excepcion'),
           LEFT(CONCAT('OC ', v_numero, ' observada', IF(t.bloquea = 1, ' (requiere corrección)', ' (observación informativa)')), 300),
           'oc_observada', 'orden_compra',
           IF(t.bloquea = 1, 'No se puede pasar a Orden de Servicio hasta corregir y validar la OC.',
                             'La OC tiene observaciones informativas registradas por el comercial.'),
           t.bloquea, 'orden_compra', p_id_oc, t.id_responsable, 0, NOW(), p_id_usuario
    FROM tmp_sync_blq t
    WHERE NOT EXISTS (SELECT 1 FROM expediente_bloqueador b
                      WHERE b.id_expediente = t.id_expediente AND b.origen_tipo = 'orden_compra' AND b.id_origen = p_id_oc
                        AND b.resuelto = 0 AND b.eliminado_en IS NULL);

    DROP TEMPORARY TABLE IF EXISTS tmp_sync_blq;
END$$

DELIMITER ;
