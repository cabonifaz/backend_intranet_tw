-- ============================================================
-- SP_BuscarEquipoQrMovil  (App Mobile HU-07 — selección de equipo escaneando su código o QR · lectura)
-- Busca, entre los objetivos de la OS del técnico, el equipo cuyo N/S, código del cliente o COD TW coincide con lo escaneado.
--   - Coincidencia exacta (sin distinguir mayúsculas) con N/S, código del cliente o COD TW; o, si el QR trae un texto más largo (una URL
--     con el código al final), que contenga el COD TW o el código del cliente (de 5 o más caracteres).
--   - Etiqueta QR de TW (enlace q.me-qr.com/… o tw.com.pe/e/…): se reconoce si ya está vinculada a un equipo de la OS (equipo_qr: la primera lectura en el
--     registro fotográfico la vincula).
--   - Hard Stop (HU-06): sin llegada registrada no se entregan equipos.
--   - Si no está en la lista de la OS responde la regla de negocio (la app ofrece buscarlo o registrarlo como equipo nuevo).
-- Resultados: 1 mensaje · 2 el equipo (mismas columnas que el resultado 4 de SP_ObtenerObjetivosMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_BuscarEquipoQrMovil;

DELIMITER $$

CREATE PROCEDURE SP_BuscarEquipoQrMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado TINYINT;
    DECLARE v_motivo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT DEFAULT NULL;
    DECLARE v_clave      VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_existe
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_codigo = UPPER(TRIM(IFNULL(p_codigo, '')));
    IF CHAR_LENGTH(v_codigo) = 0 OR CHAR_LENGTH(v_codigo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El código escaneado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);
    IF v_llegada_utc IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;

    -- Etiqueta QR de TW (enlace q.me-qr.com/… o tw.com.pe/e/…): no trae el código del equipo; se reconoce si ya está vinculada a un equipo (equipo_qr, SP_NormalizarQrMovil)
    CALL SP_NormalizarQrMovil(p_codigo, v_clave);

    SELECT t.id_os_equipo INTO v_id
    FROM   tmp_obj_mov t
    WHERE  UPPER(t.num_serie) = v_codigo OR UPPER(t.codigo_cliente) = v_codigo OR UPPER(t.codigo_tw) = v_codigo
       OR  (CHAR_LENGTH(t.codigo_tw) >= 5 AND LOCATE(UPPER(t.codigo_tw), v_codigo) > 0)
       OR  (CHAR_LENGTH(IFNULL(t.codigo_cliente, '')) >= 5 AND LOCATE(UPPER(t.codigo_cliente), v_codigo) > 0)
       OR  (v_clave IS NOT NULL AND t.id_equipo IN (SELECT q.id_equipo FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL))
    ORDER BY (UPPER(t.num_serie) = v_codigo OR UPPER(t.codigo_cliente) = v_codigo OR UPPER(t.codigo_tw) = v_codigo) DESC, t.numero
    LIMIT 1;

    IF v_id IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'El código escaneado no corresponde a ningún equipo de esta O/S. Búscalo en la lista o regístralo como equipo nuevo (NEW).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Equipo encontrado en la lista de la O/S.' AS Mensaje;
    SELECT t.id_os_equipo, t.id_equipo, t.numero, t.tipo_intervencion, t.tipo_corto, t.nombre, t.codigo_tw, t.codigo_cliente, t.marca, t.modelo,
           t.num_serie, t.ubicacion, t.estado_equipo, t.bloqueado, t.en_campo, t.falta_equipo, t.estado, t.tiempo_estimado_min, t.tiempo_real_min,
           CONVERT_TZ(t.iniciado_utc, '+00:00', '-05:00') AS iniciado_en, t.motivo_pausa, t.requiere_aprobacion, t.ultima_intervencion, t.ultima_parte,
           t.alertas_pendientes, t.puede_iniciar, t.puede_pausar, t.puede_reanudar
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = v_id;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;
