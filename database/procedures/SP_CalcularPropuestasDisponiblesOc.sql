-- HU-23 (Sprint 4) Propuestas que se pueden vincular a una orden de compra. Uso interno.
-- Llena tmp_oc_disp con las propuestas ACEPTADAS por el cliente (seguimiento comercial), del área del usuario,
-- que aún tienen saldo por cubrir con OC. El que llama hace DROP TEMPORARY TABLE tmp_oc_disp.
-- p_id_cliente NULL = todos los clientes. p_excluir_oc: la OC que se edita (su asignación no descuenta el saldo).
-- p_sin_autogenerada = 1 (registro de la OC real del cliente, ticket A): las OC autogeneradas (OC-AUTO) vigentes no
--   descuentan el saldo, porque se dan de baja al registrar la OC real (FN_SaldoPropuestaOcSinAutogenerada).
-- id_oc_autogenerada / numero_oc_autogenerada: la OC-AUTO vigente de la propuesta (la que se reemplazará).
-- items: ítems (servicios) de la propuesta, sin las filas de espaciado.
DROP PROCEDURE IF EXISTS SP_CalcularPropuestasDisponiblesOc;

DELIMITER $$

CREATE PROCEDURE SP_CalcularPropuestasDisponiblesOc(
    IN p_id_usuario BIGINT,
    IN p_id_cliente BIGINT,
    IN p_excluir_oc BIGINT,
    IN p_sin_autogenerada TINYINT
)
BEGIN
    DECLARE v_dias_sin_resp INT;
    DECLARE v_meta          INT;
    DECLARE v_sla_horas     INT;
    DECLARE v_alerta_horas  INT;

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, NULL, v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
    CREATE TEMPORARY TABLE tmp_oc_disp AS
    SELECT t.id_propuesta, t.numero, t.version, t.id_cliente, c.razon_social, c.ruc,
           t.id_requerimiento, r.numero AS numero_rq,
           t.total,
           IF(IFNULL(p_sin_autogenerada, 0) = 1, FN_SaldoPropuestaOcSinAutogenerada(t.id_propuesta, p_excluir_oc),
              FN_SaldoPropuestaOc(t.id_propuesta, p_excluir_oc))                AS saldo,
           t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo,
           t.fecha_aceptacion, t.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           p.id_contacto, ct.nombres AS contacto, ct.cargo AS cargo_contacto,
           p.tipo_servicio, p.referencia,
           (SELECT MIN(oc.id_oc) FROM orden_compra oc
             JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.id_propuesta = t.id_propuesta AND op.eliminado_en IS NULL
             WHERE oc.estado = 'autogenerada' AND oc.reemplazada_por IS NULL AND oc.eliminado_en IS NULL) AS id_oc_autogenerada,
           CAST(NULL AS CHAR(50))                                              AS numero_oc_autogenerada,
           (SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = t.id_propuesta AND i.seccion = 'principal'
              AND IFNULL(i.es_espaciado, 0) = 0 AND i.eliminado_en IS NULL)     AS items
    FROM tmp_seg t
    JOIN propuesta_comercial p     ON p.id_propuesta     = t.id_propuesta
    LEFT JOIN cliente c            ON c.id_cliente       = t.id_cliente
    LEFT JOIN requerimiento r      ON r.id_requerimiento = t.id_requerimiento
    LEFT JOIN usuario u            ON u.id_usuario       = t.id_responsable
    LEFT JOIN contacto_cliente ct  ON ct.id_contacto     = p.id_contacto
    LEFT JOIN tabla_maestra m      ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda
    WHERE t.estado_seguimiento = 'aceptada'
      AND p.estado NOT IN ('anulado', 'revocada')
      -- Solo la última versión vigente de cada propuesta (la anterior queda reemplazada por la nueva)
      AND NOT EXISTS (SELECT 1 FROM propuesta_comercial pn
                      WHERE pn.numero = p.numero AND pn.version > p.version AND pn.eliminado_en IS NULL
                        AND pn.estado NOT IN ('anulado', 'revocada'))
      AND (IFNULL(p_id_cliente, 0) = 0 OR t.id_cliente = p_id_cliente);

    DELETE FROM tmp_oc_disp WHERE saldo <= 0;

    UPDATE tmp_oc_disp d JOIN orden_compra oc ON oc.id_oc = d.id_oc_autogenerada
    SET d.numero_oc_autogenerada = oc.numero_oc;

    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
END$$

DELIMITER ;
