-- HU-10b — Datos para el modal "Enviar Propuesta al Cliente".
--   Devuelve lo necesario para armar el correo: cabecera (DE, propuesta, cliente),
--   contactos del cliente (opciones de PARA), plantillas de correo con variables
--   ya reemplazadas.
--   Reglas:
--     * La propuesta debe estar en 'aprobado' y ser la última versión.
--     * El usuario necesita la acción propuesta_enviar_cliente.
--     * Debe ser el comercial autor o tener propuesta_vb_todas.
--   Resultados:
--     1 mensaje
--     2 cabecera
--     3 contactos del cliente
--     4 plantillas de correo
DROP PROCEDURE IF EXISTS SP_PrepararEnvioCliente;

DELIMITER $$

CREATE PROCEDURE SP_PrepararEnvioCliente(
    IN p_id_propuesta BIGINT,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version     INT;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_contacto BIGINT;
    DECLARE v_autor       BIGINT;
    DECLARE v_es_ultima   TINYINT DEFAULT 1;
    DECLARE v_todas       TINYINT DEFAULT 0;

    SELECT estado, numero, version, id_cliente, id_contacto, COALESCE(id_responsable, id_creador)
      INTO v_estado, v_numero, v_version, v_id_cliente, v_id_contacto, v_autor
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'aprobado' THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Solo se puede enviar al cliente una propuesta aprobada. Estado actual: ', v_estado, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_es_ultima = NOT EXISTS (SELECT 1 FROM propuesta_comercial
                                  WHERE numero = v_numero AND version > v_version AND eliminado_en IS NULL);
    IF v_es_ultima = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo se puede enviar la última versión de la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_enviar_cliente') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para enviar propuestas al cliente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_todas = FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas');
    IF p_id_usuario <> v_autor AND v_todas = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el comercial responsable (o gerencia) puede enviar la propuesta al cliente.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Mensaje
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera: propuesta + cliente + contacto principal + usuario (DE)
    SELECT
        p.id_propuesta, p.numero, p.version,
        p.id_cliente, c.razon_social, c.ruc, p.referencia,
        p.total, p.id_moneda,
        tmo.String2 AS moneda_simbolo, tmo.String3 AS moneda,
        p.id_contacto, co.nombres AS contacto,
        TRIM(REPLACE(IFNULL(co.correo, ''), 'mailto:', '')) AS correo_contacto,
        u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario,
        u.correo AS correo_usuario, u.cargo AS cargo_usuario,
        NOW() AS fecha_servidor
    FROM propuesta_comercial p
    JOIN cliente c                      ON c.id_cliente = p.id_cliente
    LEFT JOIN contacto_cliente co       ON co.id_contacto = p.id_contacto AND co.SoftDelete = 0
    LEFT JOIN tabla_maestra tmo         ON tmo.IdMaestro = 1 AND tmo.IdEmpresa = 1 AND tmo.Num1 = p.id_moneda
    LEFT JOIN usuario u                 ON u.id_usuario = p_id_usuario
    WHERE p.id_propuesta = p_id_propuesta;

    -- 3. Contactos del cliente (opciones de PARA)
    SELECT
        co.id_contacto, co.nombres, co.cargo,
        TRIM(REPLACE(IFNULL(co.correo, ''), 'mailto:', ''))               AS correo,
        co.telefono_movil, co.telefono_anexo,
        (co.id_contacto = v_id_contacto)                                  AS es_contacto_propuesta,
        IFNULL(co.es_contacto_principal, 0)                               AS es_contacto_principal
    FROM contacto_cliente co
    WHERE co.id_cliente = v_id_cliente AND co.SoftDelete = 0
      AND LOWER(co.estado) = 'activo'
      AND IFNULL(co.correo, '') <> ''
    ORDER BY (co.id_contacto = v_id_contacto) DESC,
             IFNULL(co.es_contacto_principal, 0) DESC, co.nombres;

    -- 4. Plantillas de correo con variables reemplazadas
    SELECT pl.id_plantilla, pl.codigo, pl.nombre,
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(pl.asunto,
               '{{contacto}}',         IFNULL(co.nombres, 'cliente')),
               '{{numero_propuesta}}', p.numero),
               '{{cliente}}',          IFNULL(c.razon_social, '')),
               '{{referencia}}',       IFNULL(p.referencia, 'su requerimiento')),
               '{{usuario}}',          CONCAT(u.nombre, ' ', u.apellido)),
               '{{cargo_usuario}}',    IFNULL(u.cargo, 'Área Comercial')),
               '{{fecha_envio}}',      DATE_FORMAT(NOW(), '%d/%m/%Y')) AS asunto,
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(pl.cuerpo_html,
               '{{contacto}}',         IFNULL(co.nombres, 'cliente')),
               '{{numero_propuesta}}', p.numero),
               '{{cliente}}',          IFNULL(c.razon_social, '')),
               '{{referencia}}',       IFNULL(p.referencia, 'su requerimiento')),
               '{{usuario}}',          CONCAT(u.nombre, ' ', u.apellido)),
               '{{cargo_usuario}}',    IFNULL(u.cargo, 'Área Comercial')),
               '{{fecha_envio}}',      DATE_FORMAT(NOW(), '%d/%m/%Y')) AS cuerpo_html
    FROM plantilla_correo_seguimiento pl
    JOIN propuesta_comercial p ON p.id_propuesta = p_id_propuesta
    LEFT JOIN cliente c              ON c.id_cliente = p.id_cliente
    LEFT JOIN contacto_cliente co    ON co.id_contacto = p.id_contacto AND co.SoftDelete = 0
    LEFT JOIN usuario u              ON u.id_usuario = p_id_usuario
    WHERE pl.eliminado_en IS NULL AND pl.activo = 1
    ORDER BY pl.orden, pl.id_plantilla;
END$$

DELIMITER ;
