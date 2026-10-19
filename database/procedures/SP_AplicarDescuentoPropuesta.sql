-- HU-11 — Aplicación de Descuento Comercial
--   Aplica, previsualiza o quita el descuento global de una propuesta en borrador.
--   p_tipo: 'porcentaje' | 'monto' | 'ninguno' (quitar el descuento)
--   p_solo_previsualizar = 1 calcula los nuevos montos sin guardar (modal en tiempo real).
--   Motivo obligatorio (MOTIVO_DESCUENTO, IdMaestro 8) salvo al quitar.
--   Guardar exige la acción propuesta_aplicar_descuento (Jefe Comercial o administrador).
--   La fórmula es la misma de SP_GuardarPropuesta: el descuento se resta del subtotal
--   y el IGV se calcula sobre el resultado (o se extrae si los precios incluyen IGV).
DROP PROCEDURE IF EXISTS SP_AplicarDescuentoPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_AplicarDescuentoPropuesta(
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
    DECLARE v_igv_pct       DECIMAL(5,2);
    DECLARE v_aplica_igv    TINYINT;
    DECLARE v_incluye_igv   TINYINT;
    DECLARE v_sub           DECIMAL(14,2);
    DECLARE v_desc_act      DECIMAL(14,2);
    DECLARE v_pct_act       DECIMAL(5,2);
    DECLARE v_igv_act       DECIMAL(14,2);
    DECLARE v_total_act     DECIMAL(14,2);
    DECLARE v_motivo_act    INT;
    DECLARE v_pct           DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_desc          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_base          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_igv           DECIMAL(14,2) DEFAULT 0;
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
    SELECT estado, numero, version, igv_pct, aplica_igv, precios_incluyen_igv,
           subtotal, descuento_monto, descuento_pct, igv_monto, total, id_motivo_descuento
      INTO v_estado, v_numero, v_version, v_igv_pct, v_aplica_igv, v_incluye_igv,
           v_sub, v_desc_act, v_pct_act, v_igv_act, v_total_act, v_motivo_act
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
        SET v_desc = ROUND(v_sub * p_valor / 100, 2);
    ELSEIF p_tipo = 'monto' THEN
        IF IFNULL(p_valor, 0) <= 0 THEN
            SELECT 1 AS IdTipoMensaje, 'El monto del descuento debe ser mayor a 0.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_valor > v_sub THEN
            SELECT 1 AS IdTipoMensaje, 'El descuento no puede ser mayor que el subtotal.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_desc = p_valor;
    END IF;

    IF p_tipo <> 'ninguno' THEN
        SELECT String1 INTO v_motivo_label
        FROM tabla_maestra
        WHERE IdMaestro = 8 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL
        LIMIT 1;

        -- En la previsualización el motivo aún puede no estar elegido
        IF v_motivo_label IS NULL AND p_solo_previsualizar = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo del descuento.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- ── Nuevos montos (misma fórmula que SP_GuardarPropuesta) ───────────
    SET v_base = v_sub - v_desc;
    IF IFNULL(v_incluye_igv, 0) = 1 THEN
        SET v_total = v_base;
        SET v_igv   = ROUND(v_base - v_base / (1 + v_igv_pct / 100), 2);
    ELSEIF IFNULL(v_aplica_igv, 1) = 1 THEN
        SET v_igv   = ROUND(v_base * v_igv_pct / 100, 2);
        SET v_total = v_base + v_igv;
    ELSE
        SET v_igv   = 0;
        SET v_total = v_base;
    END IF;

    -- ── Guardar ─────────────────────────────────────────────────────────
    IF p_solo_previsualizar = 0 THEN
        START TRANSACTION;

        UPDATE propuesta_comercial SET
            descuento_pct       = v_pct,
            descuento_monto     = v_desc,
            id_motivo_descuento = IF(p_tipo = 'ninguno', NULL, p_id_motivo),
            igv_monto           = v_igv,
            total               = v_total,
            modificado_en       = NOW(),
            modificado_por      = p_id_usuario
        WHERE id_propuesta = p_id_propuesta;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('propuesta', p_id_propuesta,
                IF(p_tipo = 'ninguno', 'quitar_descuento', 'aplicar_descuento'),
                v_estado, v_estado,
                IF(p_tipo = 'ninguno',
                   CONCAT('Descuento retirado de ', v_numero, ' v', v_version, '.'),
                   CONCAT('Descuento ', IF(p_tipo = 'porcentaje', CONCAT(v_pct, '%'), 'por monto fijo'),
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
               WHEN p_solo_previsualizar = 1 THEN 'Previsualización del descuento.'
               WHEN p_tipo = 'ninguno'       THEN 'Descuento retirado.'
               ELSE 'Descuento aplicado correctamente.'
           END AS Mensaje;

    SELECT v_sub        AS subtotal_actual,
           v_desc_act   AS descuento_actual,
           v_pct_act    AS porcentaje_actual,
           v_igv_act    AS igv_actual,
           v_total_act  AS total_actual,
           p_tipo       AS tipo,
           v_pct        AS porcentaje,
           v_desc       AS descuento_nuevo,
           v_base       AS subtotal_nuevo,
           v_igv        AS igv_nuevo,
           v_total      AS total_nuevo,
           v_igv_pct    AS igv_pct,
           IF(p_tipo = 'ninguno', NULL, p_id_motivo)    AS id_motivo_descuento,
           IF(p_tipo = 'ninguno', NULL, v_motivo_label) AS motivo_descuento,
           IF(p_solo_previsualizar = 1, 0, 1)            AS guardado;
END$$

DELIMITER ;
