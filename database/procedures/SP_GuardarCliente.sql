-- ============================================================
-- SP_GuardarCliente
-- Inserta o actualiza un cliente.
-- Si p_id_cliente = 0 → INSERT; caso contrario → UPDATE.
-- Valida RUC único (excluyendo registros soft-deleted y el
-- registro actual en edición).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarCliente;

DELIMITER //

CREATE PROCEDURE SP_GuardarCliente(
    IN p_id_cliente           BIGINT,
    IN p_tipo_documento       VARCHAR(20),
    IN p_ruc                  VARCHAR(11),
    IN p_tipo_cliente         VARCHAR(50),
    IN p_razon_social         VARCHAR(300),
    IN p_nombre_comercial     VARCHAR(200),
    IN p_condicion_fiscal     VARCHAR(50),
    IN p_condicion_contribuyente VARCHAR(50),
    IN p_condicion_pago       VARCHAR(50),
    IN p_linea_credito_usd    DECIMAL(15,2),
    IN p_telefono_central     VARCHAR(30),
    IN p_domicilio_fiscal     VARCHAR(500),
    IN p_es_vip               TINYINT(1),
    IN p_regla_vip            VARCHAR(100),
    IN p_descuento_vip_pct    DECIMAL(5,2),
    IN p_patron_masas_asignado VARCHAR(100),
    IN p_ssoma_pase_ingreso   TINYINT(1),
    IN p_ssoma_trabajo_altura TINYINT(1),
    IN p_ssoma_espacio_confinado TINYINT(1),
    IN p_ssoma_induccion_previa TINYINT(1),
    IN p_ssoma_notas          TEXT,
    IN p_usu_cre              VARCHAR(100)
)
BEGIN
    -- Validar RUC duplicado (activos únicamente)
    IF EXISTS (
        SELECT 1 FROM clientes
        WHERE ruc = p_ruc
          AND SoftDelete = 0
          AND (p_id_cliente = 0 OR id_cliente <> p_id_cliente)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El RUC ya está registrado para otro cliente activo.' AS Mensaje;
    ELSEIF p_id_cliente = 0 THEN
        INSERT INTO clientes (
            tipo_documento, ruc, tipo_cliente, razon_social, nombre_comercial,
            condicion_fiscal, condicion_contribuyente, condicion_pago,
            linea_credito_usd, telefono_central, domicilio_fiscal,
            es_vip, regla_vip, descuento_vip_pct, patron_masas_asignado,
            ssoma_pase_ingreso, ssoma_trabajo_altura, ssoma_espacio_confinado,
            ssoma_induccion_previa, ssoma_notas,
            estado, SoftDelete, UsuCre, FchCre
        ) VALUES (
            p_tipo_documento, p_ruc, p_tipo_cliente, p_razon_social, p_nombre_comercial,
            p_condicion_fiscal, p_condicion_contribuyente, p_condicion_pago,
            p_linea_credito_usd, p_telefono_central, p_domicilio_fiscal,
            p_es_vip, p_regla_vip, p_descuento_vip_pct, p_patron_masas_asignado,
            p_ssoma_pase_ingreso, p_ssoma_trabajo_altura, p_ssoma_espacio_confinado,
            p_ssoma_induccion_previa, p_ssoma_notas,
            'Activo', 0, p_usu_cre, NOW()
        );

        SELECT 2 AS IdTipoMensaje, 'Cliente registrado correctamente.' AS Mensaje;
        SELECT LAST_INSERT_ID() AS id_cliente;
    ELSE
        UPDATE clientes SET
            tipo_documento         = p_tipo_documento,
            ruc                    = p_ruc,
            tipo_cliente           = p_tipo_cliente,
            razon_social           = p_razon_social,
            nombre_comercial       = p_nombre_comercial,
            condicion_fiscal       = p_condicion_fiscal,
            condicion_contribuyente = p_condicion_contribuyente,
            condicion_pago         = p_condicion_pago,
            linea_credito_usd      = p_linea_credito_usd,
            telefono_central       = p_telefono_central,
            domicilio_fiscal       = p_domicilio_fiscal,
            es_vip                 = p_es_vip,
            regla_vip              = p_regla_vip,
            descuento_vip_pct      = p_descuento_vip_pct,
            patron_masas_asignado  = p_patron_masas_asignado,
            ssoma_pase_ingreso     = p_ssoma_pase_ingreso,
            ssoma_trabajo_altura   = p_ssoma_trabajo_altura,
            ssoma_espacio_confinado = p_ssoma_espacio_confinado,
            ssoma_induccion_previa = p_ssoma_induccion_previa,
            ssoma_notas            = p_ssoma_notas,
            UsuMod                 = p_usu_cre,
            FchMod                 = NOW()
        WHERE id_cliente = p_id_cliente AND SoftDelete = 0;

        SELECT 2 AS IdTipoMensaje, 'Cliente actualizado correctamente.' AS Mensaje;
        SELECT p_id_cliente AS id_cliente;
    END IF;
END //

DELIMITER ;
