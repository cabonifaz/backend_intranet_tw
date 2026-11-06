-- HU-60 (Sprint 5) Vincula la precotización técnica con la propuesta comercial que se creó a partir de ella.
-- El front llama a este SP después de guardar la nueva propuesta (POST /api/crm/propuestas) con los datos de la precarga.
-- Acceso: precot_convertir. Reglas:
--   · la precotización está pendiente (no convertida) y en el alcance del usuario
--   · la propuesta existe, no está eliminada y es del mismo cliente y del mismo RQ de origen
-- Efectos: estado 'convertido_propuesta' con la propuesta, fecha y usuario; evento en el historial del informe (categoría
-- precotización) y de la precotización; aviso al supervisor que la generó.
-- Resultados: 1 mensaje, 2 precotización convertida.
DROP PROCEDURE IF EXISTS SP_ConvertirPrecotizacion;

DELIMITER $$

CREATE PROCEDURE SP_ConvertirPrecotizacion(
    IN p_id_usuario       BIGINT,
    IN p_id_precotizacion BIGINT,
    IN p_id_propuesta     BIGINT
)
proc: BEGIN
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_estado      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_rq       BIGINT;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_informe  BIGINT;
    DECLARE v_id_creador  BIGINT;
    DECLARE v_prop_rq     BIGINT;
    DECLARE v_prop_cli    BIGINT;
    DECLARE v_prop_num    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_prop_ver    INT;
    DECLARE v_prop_existe INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'precot_convertir') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para convertir precotizaciones en propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBasePrecotizaciones(p_id_usuario, IFNULL(p_id_precotizacion, 0));
    SELECT COUNT(*) INTO v_existe FROM tmp_pct_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La precotización no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(id_requerimiento), MAX(id_cliente), MAX(numero), MAX(version)
      INTO v_prop_existe, v_prop_rq, v_prop_cli, v_prop_num, v_prop_ver
    FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;
    IF v_prop_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT estado, numero, id_requerimiento, id_cliente, id_informe, id_creador
      INTO v_estado, v_numero, v_id_rq, v_id_cliente, v_id_informe, v_id_creador
    FROM precotizacion WHERE id_precotizacion = p_id_precotizacion FOR UPDATE;

    IF v_estado = 'convertido_propuesta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La precotización ya fue convertida en propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT (v_prop_cli <=> v_id_cliente) OR (v_id_rq IS NOT NULL AND NOT (v_prop_rq <=> v_id_rq)) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La propuesta debe ser del mismo cliente y del mismo requerimiento de origen de la precotización.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE precotizacion
    SET estado = 'convertido_propuesta', id_propuesta_generada = p_id_propuesta, fecha_conversion = NOW(),
        id_convertido_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE id_precotizacion = p_id_precotizacion;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('precotizacion', p_id_precotizacion, 'convertida', v_estado, 'convertido_propuesta',
            CONCAT('Convertida en la propuesta ', v_prop_num, ' v', v_prop_ver), p_id_usuario, NOW(),
            JSON_OBJECT('id_propuesta', p_id_propuesta));
    IF v_id_informe IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', v_id_informe, 'precotizacion_convertida',
                CONCAT('Comercial convirtió la precotización ', v_numero, ' en la propuesta ', v_prop_num, ' v', v_prop_ver),
                p_id_usuario, NOW(), JSON_OBJECT('categoria', 'precotizacion', 'id_propuesta', p_id_propuesta));
    END IF;

    IF v_id_creador IS NOT NULL AND v_id_creador <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_creador, 5, CONCAT('Precotización ', v_numero, ' convertida'),
                CONCAT('Comercial generó la propuesta ', v_prop_num, ' v', v_prop_ver, ' a partir de tu precotización ', v_numero, '.'),
                'precotizacion', p_id_precotizacion, NOW(), p_id_usuario);
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Precotización ', v_numero, ' convertida en la propuesta ', v_prop_num, ' v', v_prop_ver, '.') AS Mensaje;
    SELECT p_id_precotizacion AS id_precotizacion, v_numero AS numero, 'convertido_propuesta' AS estado,
           p_id_propuesta AS id_propuesta, v_prop_num AS numero_propuesta, v_prop_ver AS version_propuesta;
END$$

DELIMITER ;
