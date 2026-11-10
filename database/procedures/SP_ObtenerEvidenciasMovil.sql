-- ============================================================
-- SP_ObtenerEvidenciasMovil  (App Mobile HU-11 / HU-12 / HU-13 — panel de evidencias del equipo · lectura)
-- El panel del "Registro fotográfico": las 9 evidencias (SP_CatalogoEvidenciasMovil) con su estado, el avance "N de 9 completas" y lo que necesita el
-- botón "Guardar y volver" (puede_guardar = las 9 completas). Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop, equipo iniciado).
--   estado de cada evidencia: pendiente | aprobada | rechazada | forzada | omitida  (omitida = la IA no estuvo disponible; cuenta como completa)
--   Para una evidencia FORZADA (HU-12) trae lo de "Ver detalles": motivo del técnico, rechazo de la IA, quién la aceptó, cuándo y los intentos previos.
--   Informe a mano: paginas = hojas válidas; la tarjeta muestra la primera.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 evidencias (9 filas).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEvidenciasMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_total    INT;
    DECLARE v_compl    INT;
    DECLARE v_forz     INT;
    DECLARE v_rech     INT;
    DECLARE v_oblig    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT rq.numero INTO v_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    WHERE  os.id_os = p_id_os LIMIT 1;

    CALL SP_ResumenEvidenciasMovil(p_id_os, v_id_eq, v_total, v_compl, v_forz, v_rech, v_oblig);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT p_id_os AS id_os, p_id_os_equipo AS id_os_equipo, v_num_os AS numero_os, v_nombre AS nombre, v_numero AS numero, v_servicio AS servicio_sigla,
           NULLIF(TRIM(ec.num_serie), '') AS num_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw, ec.marca, ec.modelo,
           v_est_eq AS estado, IF(v_est_eq = 'en_ejecucion' AND v_hab = 1, 1, 0) AS puede_registrar, v_rq AS numero_rq,
           v_total AS total, v_compl AS completas, v_forz AS forzadas, v_rech AS rechazadas, v_oblig AS obligatorias_faltan,
           IF(v_compl = v_total, 1, 0) AS puede_guardar
    FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq;

    -- 3. Las 9 evidencias (la última captura de cada una)
    SELECT c.orden, c.codigo, c.nombre, c.descripcion, c.obligatoria, c.medio,
           CASE WHEN f.id_evidencia IS NULL THEN 'pendiente'
                WHEN f.override_aprobado = 1 THEN 'forzada'
                ELSE f.validacion_ia END AS estado,
           f.id_evidencia, f.intento, f.es_video, f.duracion_seg,
           (SELECT COUNT(*) FROM evidencia_fotografica p
            WHERE p.id_os = p_id_os AND p.id_equipo = v_id_eq AND p.codigo = c.codigo AND p.vigente = 1 AND p.eliminado_en IS NULL
              AND (p.override_aprobado = 1 OR p.validacion_ia <> 'rechazada')) AS paginas,
           f.motivo_rechazo_ia, f.motivo_forzado,
           TRIM(CONCAT(IFNULL(uf.nombre, ''), ' ', IFNULL(uf.apellido, ''))) AS forzada_por,
           IF(f.forzada_en IS NULL, NULL, CONVERT_TZ(f.forzada_en, '+00:00', '-05:00')) AS forzada_en,
           IF(f.id_evidencia IS NULL, 0, f.intento - 1) AS intentos_previos,
           CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS capturada_en,
           CAST(f.resultado_ia AS CHAR) AS resultado_ia,
           IF(f.ruta_cuadro IS NULL, 0, 1) AS tiene_cuadro
    FROM   tmp_cat_evid c
    LEFT JOIN evidencia_fotografica f
           ON f.id_evidencia = (SELECT MAX(f2.id_evidencia) FROM evidencia_fotografica f2
                                WHERE f2.id_os = p_id_os AND f2.id_equipo = v_id_eq AND f2.codigo = c.codigo
                                  AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL)
    LEFT JOIN usuario uf ON uf.id_usuario = f.id_usuario_override
    ORDER BY c.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
END$$

DELIMITER ;
