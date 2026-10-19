-- Migración 48 — Aplicación de Descuento específico a Opcionales (paralelo al HU-11)
--   Mismo flujo que SP_AplicarDescuentoPropuesta pero sobre el bloque de opcionales:
--     columnas: descuento_opcionales (monto), descuento_opcionales_pct, id_motivo_descuento_opcionales
--     subtotal base: subtotal_opcionales
--     total recalculado: total_opcionales (sin IGV — los opcionales no suman al total facturable)
--   p_tipo: 'porcentaje' | 'monto' | 'ninguno' (quitar)
--   p_solo_previsualizar = 1 calcula sin guardar.
--   Mismo permiso que el descuento principal: 'propuesta_aplicar_descuento'.
DROP PROCEDURE IF EXISTS SP_AplicarDescuentoOpcionalesPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_AplicarDescuentoOpcionalesPropuesta(
    IN p_id_propuesta        BIGINT,
    IN p_tipo                VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_valor               DECIMAL(14,2),
    IN p_id_motivo           INT,
    IN p_solo_previsualizar  TINYINT,
    IN p_id_usuario          BIGINT
)
proc: BEGIN
    DECLARE v_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_motivo_label  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sub_op        DECIMAL(14,2);
    DECLARE v_desc_act      DECIMAL(14,2);
    DECLARE v_pct_act       DECIMAL(5,2);
    DECLARE v_total_act     DECIMAL(14,2);
    DECLARE v_motivo_act    INT;
    DECLARE v_pct           DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_desc          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total         DECIMAL(14,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    SET p_solo_previsualizar = IFNULL(p_solo_previsualizar, 0);

    -- ── Propuesta ───────────────────────────────────────────────────────
    SELECT estado, numero, version,
           subtotal_opcionales, descuento_opcionales, descuento_opcionales_pct,
           total_opcionales, id_motivo_descuento_opcionales
      INTO v_estado, v_numero, v_version,
           v_sub_op, v_desc_act, v_pct_act, v_total_act, v_motivo_act
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'borrador' THEN
        SELECT 1 AS IdTipoMensaje,
               'Solo se puede aplicar descuento a una propuesta en borrador. Genere una nueva versión para modificarla.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_solo_previsualizar = 0 AND FN_PermisoAccion(p_id_usuario, 'propuesta_aplicar_descuento') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe Comercial o un administrador puede aplicar descuentos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Validaciones del descuento ──────────────────────────────────────
    IF p_tipo NOT IN ('porcentaje', 'monto', 'ninguno') THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el tipo de descuento (porcentaje o monto fijo).' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_tipo = 'porcentaje' THEN
        IF IFNULL(p_valor, 0) <= 0 OR p_valor > 100 THEN
            SELECT 1 AS IdTipoMensaje, 'El porcentaje debe ser mayor a 0 y como máximo 100.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_pct  = p_valor;
        SET v_desc = ROUND(v_sub_op * p_valor / 100, 2);
    ELSEIF p_tipo = 'monto' THEN
        IF IFNULL(p_valor, 0) <= 0 THEN
            SELECT 1 AS IdTipoMensaje, 'El monto del descuento debe ser mayor a 0.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_valor > v_sub_op THEN
            SELECT 1 AS IdTipoMensaje, 'El descuento no puede ser mayor que el subtotal de opcionales.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_desc = p_valor;
    END IF;

    IF p_tipo <> 'ninguno' THEN
        SELECT String1 INTO v_motivo_label
        FROM tabla_maestra
        WHERE IdMaestro = 8 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL
        LIMIT 1;

        IF v_motivo_label IS NULL AND p_solo_previsualizar = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo del descuento.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- ── Nuevo total de opcionales ───────────────────────────────────────
    -- Los opcionales no suman al total facturable, por eso no se calcula IGV.
    SET v_total = v_sub_op - v_desc;

    -- ── Guardar ─────────────────────────────────────────────────────────
    IF p_solo_previsualizar = 0 THEN
        START TRANSACTION;

        UPDATE propuesta_comercial SET
            descuento_opcionales            = v_desc,
            descuento_opcionales_pct        = v_pct,
            id_motivo_descuento_opcionales  = IF(p_tipo = 'ninguno', NULL, p_id_motivo),
            total_opcionales                = v_total,
            modificado_en                   = NOW(),
            modificado_por                  = p_id_usuario
        WHERE id_propuesta = p_id_propuesta;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('propuesta', p_id_propuesta,
                IF(p_tipo = 'ninguno', 'quitar_descuento_opcionales', 'aplicar_descuento_opcionales'),
                v_estado, v_estado,
                IF(p_tipo = 'ninguno',
                   CONCAT('Descuento de opcionales retirado de ', v_numero, ' v', v_version, '.'),
                   CONCAT('Descuento de opcionales ', IF(p_tipo = 'porcentaje', CONCAT(v_pct, '%'), 'por monto fijo'),
                          ' (', v_desc, ') aplicado a ', v_numero, ' v', v_version, ': ', v_motivo_label, '.')),
                p_id_usuario, NOW(),
                JSON_OBJECT('tipo',                p_tipo,
                            'valor',               p_valor,
                            'id_motivo',           p_id_motivo,
                            'motivo',              v_motivo_label,
                            'descuento_anterior',  v_desc_act,
                            'pct_anterior',        v_pct_act,
                            'motivo_anterior',     v_motivo_act,
                            'total_anterior',      v_total_act,
                            'descuento_nuevo',     v_desc,
                            'total_nuevo',         v_total));

        COMMIT;
    END IF;

    SELECT 2 AS IdTipoMensaje,
           CASE
               WHEN p_solo_previsualizar = 1 THEN 'Previsualización del descuento de opcionales.'
               WHEN p_tipo = 'ninguno'       THEN 'Descuento de opcionales retirado.'
               ELSE 'Descuento de opcionales aplicado correctamente.'
           END AS Mensaje;

    -- Resultado — mismo shape que SP_AplicarDescuentoPropuesta pero sin IGV.
    -- Los campos igv_* van en 0 porque los opcionales no suman al IGV principal.
    SELECT v_sub_op     AS subtotal_actual,
           v_desc_act   AS descuento_actual,
           v_pct_act    AS porcentaje_actual,
           0            AS igv_actual,
           v_total_act  AS total_actual,
           p_tipo       AS tipo,
           v_pct        AS porcentaje,
           v_desc       AS descuento_nuevo,
           v_sub_op - v_desc AS subtotal_nuevo,
           0            AS igv_nuevo,
           v_total      AS total_nuevo,
           0            AS igv_pct,
           IF(p_tipo = 'ninguno', NULL, p_id_motivo)    AS id_motivo_descuento,
           IF(p_tipo = 'ninguno', NULL, v_motivo_label) AS motivo_descuento,
           IF(p_solo_previsualizar = 1, 0, 1)            AS guardado;
END$$

DELIMITER ;
