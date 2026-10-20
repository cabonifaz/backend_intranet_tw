-- HU-24 (Sprint 4) "Re-validar ahora" del modal de Validación IA: vuelve a validar la OC guardada contra una propuesta
-- vinculada (o todas si p_id_propuesta es NULL) y guarda la corrida en el historial. No cambia el estado de la OC ni de
-- las vinculaciones: la decisión la toma el comercial desde la ficha.
-- p_evaluaciones_ia (opcional): evaluación de conceptos de la IA por propuesta.
-- Reglas: acción oc_validar; OC del área del usuario, no anulada, no autogenerada.
-- Resultados: 1 mensaje, 2 corridas registradas (una por propuesta).
DROP PROCEDURE IF EXISTS SP_RevalidarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_RevalidarOrdenCompra(
    IN p_id_usuario      BIGINT,
    IN p_id_oc           BIGINT,
    IN p_id_propuesta    BIGINT,
    IN p_evaluaciones_ia JSON
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_auto     TINYINT;
    DECLARE v_datos    JSON;
    DECLARE v_n        INT;
    DECLARE v_i        INT DEFAULT 1;
    DECLARE v_id_prop  BIGINT;
    DECLARE v_asignado DECIMAL(14,2);
    DECLARE v_eval     JSON;
    DECLARE v_id_val   BIGINT;
    DECLARE v_res      VARCHAR(20);
    DECLARE v_sug      VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_validar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para re-validar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado), MAX(es_autogenerada) INTO v_existe, v_estado, v_auto FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_auto = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La OC autogenerada no se valida: reemplázala por la OC del cliente.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_rev;
    CREATE TEMPORARY TABLE tmp_oc_rev AS
    SELECT ROW_NUMBER() OVER (ORDER BY id) AS n, id_propuesta, monto_asignado
    FROM oc_propuesta
    WHERE id_oc = p_id_oc AND eliminado_en IS NULL AND (IFNULL(p_id_propuesta, 0) = 0 OR id_propuesta = p_id_propuesta);

    SELECT COUNT(*) INTO v_n FROM tmp_oc_rev;
    IF v_n = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_rev;
        SELECT 1 AS IdTipoMensaje, 'La propuesta no está vinculada a la orden de compra.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_datos = FN_DatosOrdenCompraJson(p_id_oc);

    START TRANSACTION;
    WHILE v_i <= v_n DO
        SELECT id_propuesta, monto_asignado INTO v_id_prop, v_asignado FROM tmp_oc_rev WHERE n = v_i;
        SET v_eval = NULL;
        IF p_evaluaciones_ia IS NOT NULL AND JSON_TYPE(p_evaluaciones_ia) = 'ARRAY' THEN
            SELECT j.obj INTO v_eval
            FROM JSON_TABLE(p_evaluaciones_ia, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta', obj JSON PATH '$')) j
            WHERE j.id = v_id_prop LIMIT 1;
        END IF;
        CALL SP_RegistrarValidacionOrdenCompra(p_id_oc, v_id_prop, v_datos, v_asignado, v_eval, 'revalidacion',
                                               p_id_usuario, v_id_val, v_res, v_sug);
        SET v_i = v_i + 1;
    END WHILE;
    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;

    SELECT 2 AS IdTipoMensaje, 'Validación ejecutada.' AS Mensaje;
    SELECT v.id_validacion, v.id_propuesta, CONCAT(p.numero, ' v', p.version) AS numero, v.corrida, v.resultado,
           v.coincidencias, v.advertencias, v.criticas, v.total_campos, v.sugerencia, v.fecha_validacion
    FROM orden_compra_validacion v
    JOIN tmp_oc_rev t ON t.id_propuesta = v.id_propuesta
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    WHERE v.id_oc = p_id_oc
      AND v.id_validacion = (SELECT MAX(v2.id_validacion) FROM orden_compra_validacion v2
                             WHERE v2.id_oc = p_id_oc AND v2.id_propuesta = v.id_propuesta)
    ORDER BY t.n;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_rev;
END$$

DELIMITER ;
