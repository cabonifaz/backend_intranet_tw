-- HU-52 (Sprint 5) Resolver una aprobación desde la pestaña Aprobaciones del Detalle del Servicio en Ruta.
--   p_tipo (lista cerrada): salida | llegada | evidencia | ensayo · p_id: el id que devolvió SP_ObtenerAprobacionesServicioRuta.
--   Comentario obligatorio (1 a 500 caracteres). Acceso: seg_bandeja y el servicio en la jornada de hoy (SP_PrepararDetalleServicioRuta).
--   Anti-IDOR: el id debe ser de ESA OS. Salida y llegada: además debe ser la última solicitud PENDIENTE de la OS, porque los SP que ya existen
--   (SP_ResolverAutorizacionSalida, SP_ResolverLlegadaForzada) resuelven esa. Evidencia y ensayo: SP_ResolverEvidenciaForzada y SP_ResolverEnsayoConError.
--   La regla de quién puede resolver (área del encargado) la valida cada SP de resolver. Todos notifican al técnico y dejan auditoría.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje), la del SP que resuelve.
DROP PROCEDURE IF EXISTS SP_ResolverAprobacionServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ResolverAprobacionServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tipo       VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id         BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo    VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aprobar TINYINT DEFAULT 0;
    DECLARE v_ultimo  BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('salida', 'llegada', 'evidencia', 'ensayo') THEN
        SELECT 1 AS IdTipoMensaje, 'Tipo de aprobación no válido. Use salida, llegada, evidencia o ensayo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La aprobación indicada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF v_com IS NULL OR CHAR_LENGTH(v_com) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe un comentario (hasta 500 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_aprobar = IF(IFNULL(p_aprobar, 0) = 1, 1, 0);

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LimpiarSeguimientoOperativo();

    IF v_tipo = 'salida' THEN
        SELECT MAX(id_autorizacion) INTO v_ultimo FROM autorizacion_salida_os WHERE id_os = p_id_os AND eliminado_en IS NULL;
        IF v_ultimo IS NULL OR v_ultimo <> p_id
           OR NOT EXISTS (SELECT 1 FROM autorizacion_salida_os WHERE id_autorizacion = p_id AND estado = 'pendiente') THEN
            SELECT 1 AS IdTipoMensaje, 'La solicitud de salida no existe en este servicio o ya fue resuelta.' AS Mensaje;
            LEAVE proc;
        END IF;
        CALL SP_ResolverAutorizacionSalida(p_id_usuario, p_id_os, v_aprobar, v_com);
    ELSEIF v_tipo = 'llegada' THEN
        SELECT MAX(id_solicitud) INTO v_ultimo FROM llegada_forzada_os WHERE id_os = p_id_os AND eliminado_en IS NULL;
        IF v_ultimo IS NULL OR v_ultimo <> p_id
           OR NOT EXISTS (SELECT 1 FROM llegada_forzada_os WHERE id_solicitud = p_id AND estado = 'pendiente') THEN
            SELECT 1 AS IdTipoMensaje, 'La solicitud de llegada forzada no existe en este servicio o ya fue resuelta.' AS Mensaje;
            LEAVE proc;
        END IF;
        CALL SP_ResolverLlegadaForzada(p_id_usuario, p_id_os, v_aprobar, v_com);
    ELSEIF v_tipo = 'evidencia' THEN
        CALL SP_ResolverEvidenciaForzada(p_id_usuario, p_id_os, p_id, v_aprobar, v_com);
    ELSE
        CALL SP_ResolverEnsayoConError(p_id_usuario, p_id_os, p_id, v_aprobar, v_com);
    END IF;
END$$

DELIMITER ;
