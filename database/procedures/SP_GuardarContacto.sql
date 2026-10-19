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
    IN p_usu_cre                         VARCHAR(100),
    IN p_sedes                           JSON
)
proc: BEGIN
    -- p_sedes: [{"idSede":12,"esPrincipalSede":true}, ...]. NULL = se usa p_id_sede (compatibilidad).
    -- p_es_contacto_principal = principal de la EMPRESA (solo uno por cliente).
    DECLARE v_id BIGINT DEFAULT 0;

    IF p_sedes IS NOT NULL THEN
        IF JSON_LENGTH(p_sedes) = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'El contacto debe estar vinculado al menos a una sede.' AS Mensaje;
            LEAVE proc;
        END IF;

        IF EXISTS (
            SELECT 1 FROM JSON_TABLE(p_sedes, '$[*]' COLUMNS (id_sede BIGINT PATH '$.idSede')) j
            WHERE NOT EXISTS (SELECT 1 FROM sede_cliente s
                              WHERE s.id_sede = j.id_sede AND s.id_cliente = p_id_cliente AND s.SoftDelete = 0)
        ) THEN
            SELECT 1 AS IdTipoMensaje, 'Una de las sedes no pertenece al cliente.' AS Mensaje;
            LEAVE proc;
        END IF;

        -- La primera sede del arreglo queda como sede de referencia (compatibilidad)
        SET p_id_sede = JSON_EXTRACT(p_sedes, '$[0].idSede');
    END IF;

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

    -- Sedes vinculadas
    IF p_sedes IS NOT NULL THEN
        DELETE FROM contacto_sede WHERE id_contacto = v_id;
        INSERT IGNORE INTO contacto_sede (id_contacto, id_sede, es_principal_sede)
        SELECT v_id, j.id_sede, IF(j.principal, 1, 0)
        FROM JSON_TABLE(p_sedes, '$[*]' COLUMNS (
                id_sede   BIGINT  PATH '$.idSede',
                principal BOOLEAN PATH '$.esPrincipalSede' DEFAULT 'false' ON EMPTY)) j;
    ELSEIF IFNULL(p_id_sede, 0) <> 0 THEN
        INSERT IGNORE INTO contacto_sede (id_contacto, id_sede, es_principal_sede) VALUES (v_id, p_id_sede, 0);
    END IF;

    -- Un solo principal por sede
    UPDATE contacto_sede cs
    JOIN contacto_sede mio ON mio.id_sede = cs.id_sede AND mio.id_contacto = v_id AND mio.es_principal_sede = 1
    SET cs.es_principal_sede = 0
    WHERE cs.id_contacto <> v_id AND cs.es_principal_sede = 1;

    -- Un solo principal de la empresa
    IF p_es_contacto_principal = 1 THEN
        UPDATE contacto_cliente
        SET es_contacto_principal = 0
        WHERE id_cliente = p_id_cliente AND id_contacto <> v_id AND es_contacto_principal = 1;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Contacto guardado correctamente.' AS Mensaje;
    SELECT v_id AS id_contacto;
END$$
DELIMITER ;
