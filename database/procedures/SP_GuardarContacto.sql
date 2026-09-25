-- ============================================================
-- SP_GuardarContacto
-- Inserta o actualiza un contacto de cliente (HU-81)
-- id_contacto = 0 → INSERT, > 0 → UPDATE
-- ============================================================

DROP PROCEDURE IF EXISTS SP_GuardarContacto;

DELIMITER $$
CREATE PROCEDURE SP_GuardarContacto(
    IN p_id_contacto                     BIGINT,
    IN p_id_cliente                      BIGINT,
    IN p_id_sede                         BIGINT,
    IN p_nombres                         VARCHAR(200),
    IN p_documento_identidad             VARCHAR(20),
    IN p_cargo                           VARCHAR(100),
    IN p_area                            VARCHAR(100),
    IN p_correo                          VARCHAR(200),
    IN p_telefono_movil                  VARCHAR(50),
    IN p_telefono_anexo                  VARCHAR(50),
    IN p_es_contacto_principal           BIT,
    IN p_autorizado_aprobar_cotizaciones BIT,
    IN p_recibe_alertas_calibracion      BIT,
    IN p_autorizado_recepcion_tecnica    BIT,
    IN p_usu_cre                         VARCHAR(100)
)
BEGIN
    DECLARE v_id BIGINT DEFAULT 0;

    IF p_id_contacto = 0 THEN
        INSERT INTO contacto_cliente (
            id_cliente, id_sede,
            nombres, documento_identidad, cargo, area,
            correo, telefono_movil, telefono_anexo,
            es_contacto_principal, autorizado_aprobar_cotizaciones,
            recibe_alertas_calibracion, autorizado_recepcion_tecnica,
            estado, SoftDelete, UsuCre, FchCre
        ) VALUES (
            p_id_cliente, NULLIF(p_id_sede, 0),
            p_nombres, p_documento_identidad, p_cargo, p_area,
            p_correo, p_telefono_movil, p_telefono_anexo,
            p_es_contacto_principal, p_autorizado_aprobar_cotizaciones,
            p_recibe_alertas_calibracion, p_autorizado_recepcion_tecnica,
            'Activo', 0, p_usu_cre, NOW()
        );
        SET v_id = LAST_INSERT_ID();
    ELSE
        UPDATE contacto_cliente SET
            id_sede                          = NULLIF(p_id_sede, 0),
            nombres                          = p_nombres,
            documento_identidad              = p_documento_identidad,
            cargo                            = p_cargo,
            area                             = p_area,
            correo                           = p_correo,
            telefono_movil                   = p_telefono_movil,
            telefono_anexo                   = p_telefono_anexo,
            es_contacto_principal            = p_es_contacto_principal,
            autorizado_aprobar_cotizaciones  = p_autorizado_aprobar_cotizaciones,
            recibe_alertas_calibracion       = p_recibe_alertas_calibracion,
            autorizado_recepcion_tecnica     = p_autorizado_recepcion_tecnica,
            UsuMod                           = p_usu_cre,
            FchMod                           = NOW()
        WHERE id_contacto = p_id_contacto AND SoftDelete = 0;
        SET v_id = p_id_contacto;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Contacto guardado correctamente.' AS Mensaje;
    SELECT v_id AS id_contacto;
END$$
DELIMITER ;
