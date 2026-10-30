-- HU-27 (Sprint 4) Crea la OC autogenerada (OC-AUTO-NNNN-AAAA) de una propuesta aceptada. Uso interno: no abre
-- transacción ni devuelve resultados (la llaman SP_AutogenerarOrdenCompraInterno y SP_AnularOrdenCompraInterno dentro
-- de su transacción).
-- La OC queda en estado 'autogenerada', sin PDF, por p_monto (el saldo de la propuesta), vinculada a la propuesta,
-- pasa los expedientes a Programación y notifica a Operaciones, Administración y al responsable de la propuesta.
-- p_motivo: texto para la auditoría y las observaciones de la OC.
DROP PROCEDURE IF EXISTS SP_CrearOcAutogenerada;

DELIMITER $$

CREATE PROCEDURE SP_CrearOcAutogenerada(
    IN  p_id_propuesta BIGINT,
    IN  p_monto        DECIMAL(14,2),
    IN  p_motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_id_usuario   BIGINT,
    OUT p_id_oc        BIGINT,
    OUT p_numero_oc    VARCHAR(50)
)
BEGIN
    DECLARE v_correl      INT;
    DECLARE v_numero_prop VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp     BIGINT;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT CONCAT(p.numero, ' v', p.version), COALESCE(p.id_responsable, p.id_creador), c.razon_social, m.String2
      INTO v_numero_prop, v_id_resp, v_cliente, v_simbolo
    FROM propuesta_comercial p
    LEFT JOIN cliente c       ON c.id_cliente = p.id_cliente
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    WHERE p.id_propuesta = p_id_propuesta;

    -- Correlativo del año: OC-AUTO-0001-2026 (incluye las dadas de baja para no repetir números)
    SELECT IFNULL(MAX(CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(numero_oc, '-', 3), '-', -1) AS UNSIGNED)), 0) + 1
      INTO v_correl
    FROM orden_compra
    WHERE es_autogenerada = 1 AND numero_oc LIKE CONCAT('OC-AUTO-%-', YEAR(CURDATE()))
    FOR UPDATE;
    SET p_numero_oc = CONCAT('OC-AUTO-', LPAD(v_correl, 4, '0'), '-', YEAR(CURDATE()));

    INSERT INTO orden_compra (
        numero_oc, es_autogenerada, id_propuesta, id_cliente, id_moneda, monto_total,
        id_condicion_pago, igv_incluido, igv_pct, factura_igual_oc,
        fecha_oc, fecha_recepcion, observaciones, estado, fecha_registro, creado_por)
    SELECT p_numero_oc, 1, p.id_propuesta, p.id_cliente, p.id_moneda, p_monto,
           p.id_condicion_pago, p.aplica_igv, IF(p.aplica_igv = 1, p.igv_pct, NULL), 1,
           CURDATE(), CURDATE(),
           LEFT(CONCAT(p_motivo, ' Debe reemplazarse por la OC del cliente antes de facturar.'), 500),
           'autogenerada', NOW(), p_id_usuario
    FROM propuesta_comercial p WHERE p.id_propuesta = p_id_propuesta;

    SET p_id_oc = LAST_INSERT_ID();

    INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, estado_validacion, creado_por)
    VALUES (p_id_oc, p_id_propuesta, p_monto, 'pendiente', p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'autogenerar_oc', NULL, 'autogenerada',
            CONCAT('OC provisional ', p_numero_oc, ' generada para la propuesta ', v_numero_prop,
                   ' por ', IFNULL(v_simbolo, ''), ' ', FORMAT(p_monto, 2), ' (100% de cobertura). ', p_motivo),
            p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', p_id_propuesta, 'monto', p_monto));

    CALL SP_PasarExpedientesAProgramacion(p_id_oc, p_id_usuario);

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           CONCAT('OC provisional: ', p_numero_oc),
           CONCAT(IFNULL(v_usuario, 'El sistema'), ' generó la OC provisional ', p_numero_oc, ' de ', IFNULL(v_cliente, 'el cliente'),
                  ' (propuesta ', v_numero_prop, '). Permite ejecutar el servicio; se reemplazará por la OC del cliente.'),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = v_id_resp);
END$$

DELIMITER ;
