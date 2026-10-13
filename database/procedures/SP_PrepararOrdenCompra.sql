-- HU-22 Datos del modal "Registrar Orden de Compra Recibida".
-- La propuesta debe estar ACEPTADA por el cliente (HU-21) y aún sin orden de compra,
-- ser del área del usuario y el usuario debe tener la acción oc_registrar.
-- Resultados:
--   1 mensaje
--   2 propuesta: cliente, RQ, monto y moneda de la propuesta (base de la cobertura), aceptación,
--     responsable, fecha del servidor y vigencia sugerida
--   3 monedas (MONEDA)
DROP PROCEDURE IF EXISTS SP_PrepararOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararOrdenCompra(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT
)
BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_estado         VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tiene_oc       INT DEFAULT 0;
    DECLARE v_vigencia       INT DEFAULT 30;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
    ELSE
        CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                             v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

        SELECT COUNT(*), MAX(estado_seguimiento), IFNULL(MAX(fecha_primera_oc IS NOT NULL), 0)
          INTO v_existe, v_estado, v_tiene_oc
        FROM tmp_seg;

        IF v_existe = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje,
                   'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        ELSEIF v_tiene_oc = 1 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje, 'La propuesta ya tiene una orden de compra registrada.' AS Mensaje;
        ELSEIF v_estado = 'rechazada' THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje, 'La propuesta fue rechazada o cerrada sin venta.' AS Mensaje;
        ELSEIF v_estado <> 'aceptada' THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje,
                   'Registre primero la aceptación del cliente (Cierre del seguimiento) para poder registrar la orden de compra.' AS Mensaje;
        ELSE
            SELECT CAST(IFNULL(MAX(Num2), 30) AS SIGNED) INTO v_vigencia
            FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_VIGENCIA_DIAS_DEFECTO';

            -- 1. Header
            SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

            -- 2. Propuesta
            SELECT
                t.id_propuesta, t.numero, t.version,
                t.id_cliente, c.razon_social, c.ruc,
                t.id_requerimiento, r.numero AS numero_rq,
                t.total, t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo, m.String1 AS moneda_nombre,
                t.fecha_aceptacion,
                (SELECT ta.String1 FROM seguimiento_comercial s
                 JOIN tabla_maestra ta ON ta.Descripcion = 'TIPO_ACEPTACION_PROPUESTA' AND ta.IdEmpresa = 1
                                      AND ta.Num1 = s.id_tipo_aceptacion
                 WHERE s.id_propuesta = t.id_propuesta AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL
                 ORDER BY s.id_seguimiento DESC LIMIT 1)                   AS tipo_aceptacion,
                t.id_responsable, CONCAT(u.nombre, ' ', u.apellido)        AS responsable,
                CURDATE()                                                  AS fecha_servidor,
                v_vigencia                                                 AS vigencia_dias_defecto
            FROM tmp_seg t
            LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
            LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
            LEFT JOIN usuario u       ON u.id_usuario       = t.id_responsable
            LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda;

            DROP TEMPORARY TABLE IF EXISTS tmp_seg;

            -- 3. Monedas
            SELECT Num1 AS id, String1 AS nombre, String2 AS simbolo, String3 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 1 AND IdEmpresa = 1 AND eliminado_en IS NULL
            ORDER BY Num1;
        END IF;
    END IF;
END$$

DELIMITER ;
