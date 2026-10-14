-- HU-32 Datos del modal "Resolver bloqueo" o "Cerrar excepción".
-- Acción expediente_resolver_bloqueo. El bloqueo o la excepción debe estar abierto.
-- Resultados: 1 mensaje · 2 contexto (expediente, cliente, etapa, bloqueo, responsable, detectado, impacto y el
--   documento en falta: tipo documental, técnico, vencimiento y estado) · 3 opciones del select, tal cual:
--   bloqueo → TIPO_RESOLUCION_BLOQUEO (98) · excepción → RESULTADO_CIERRE_EXCEPCION (99)
DROP PROCEDURE IF EXISTS SP_PrepararResolucionBloqueo;

DELIMITER $$

CREATE PROCEDURE SP_PrepararResolucionBloqueo(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_bloqueador BIGINT
)
proc: BEGIN
    DECLARE v_clase    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resuelto TINYINT;
    DECLARE v_origen   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_resolver_bloqueo') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para resolver bloqueos o cerrar excepciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT clase, resuelto, origen_tipo INTO v_clase, v_resuelto, v_origen
    FROM expediente_bloqueador
    WHERE id_bloqueador = p_id_bloqueador AND id_expediente = p_id_expediente AND eliminado_en IS NULL;

    IF v_clase IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El bloqueo no existe en este expediente.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_resuelto = 1 THEN
        SELECT 1 AS IdTipoMensaje, IF(v_clase = 'excepcion', 'La excepción ya fue cerrada.', 'El bloqueo ya fue resuelto.') AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto
    SELECT b.id_bloqueador, b.clase, x.id_expediente, x.numero, c.razon_social, c.ruc,
           IFNULL(b.etapa, x.etapa) AS etapa, et.String1 AS etapa_nombre,
           b.descripcion, b.tipo, b.tipo_documental, b.impacto, b.critico, mo.String1 AS motivo,
           IFNULL(b.id_responsable, x.id_responsable) AS id_responsable,
           CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           b.creado_en AS fecha_deteccion, b.origen_tipo,
           -- Documento en falta (cuando el bloqueo viene de un documento SSOMA)
           IF(b.origen_tipo = 'ssoma_documento', CONCAT(tu.nombre, ' ', tu.apellido), NULL)       AS tecnico,
           IF(b.origen_tipo = 'ssoma_documento', sd.fecha_vencimiento, NULL)                       AS fecha_vencimiento,
           CASE WHEN b.origen_tipo <> 'ssoma_documento' OR sd.id_ssoma_doc IS NULL THEN 'PENDIENTE'
                WHEN sd.estado = 'vencido' OR sd.fecha_vencimiento < CURDATE() THEN 'VENCIDO'
                ELSE UPPER(sd.estado) END                                                         AS estado_documento,
           (b.origen_tipo = 'orden_compra')                                                       AS se_resuelve_en_oc
    FROM expediente_bloqueador b
    JOIN tmp_exp x              ON x.id_expediente = b.id_expediente
    LEFT JOIN cliente c         ON c.id_cliente = x.id_cliente
    LEFT JOIN tabla_maestra et  ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = IFNULL(b.etapa, x.etapa)
    LEFT JOIN tabla_maestra mo  ON mo.IdEmpresa = 1 AND mo.Num1 = b.id_motivo AND mo.IdMaestro = IF(b.clase = 'excepcion', 17, 16)
    LEFT JOIN usuario u         ON u.id_usuario = IFNULL(b.id_responsable, x.id_responsable)
    LEFT JOIN ssoma_documento sd ON b.origen_tipo = 'ssoma_documento' AND sd.id_ssoma_doc = b.id_origen
    LEFT JOIN usuario tu        ON tu.id_usuario = sd.id_usuario
    WHERE b.id_bloqueador = p_id_bloqueador;

    -- 3. Opciones
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra
    WHERE IdEmpresa = 1 AND IdMaestro = IF(v_clase = 'excepcion', 99, 98)
    ORDER BY Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
