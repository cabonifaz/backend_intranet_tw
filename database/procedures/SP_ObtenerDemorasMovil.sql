-- ============================================================
-- SP_ObtenerDemorasMovil  (App Mobile HU-05 — Registro de demoras en ruta · lectura)
-- Contexto para la pantalla "Registrar demora" de una OS del técnico que inició sesión (el id sale del token):
--   - Quién puede registrar y de qué tipo: "llegada" (llegar a planta) con el servicio EN RUTA y sin llegada registrada;
--     "ingreso" (ingreso a planta) con el servicio en ruta o en ejecución, llegada registrada y sin inicio del trabajo.
--   - Horas (Lima): ETA original, ETA vigente (con las demoras de llegada) e inicio de trabajo previsto (para las de ingreso).
--     Las reglas de las horas están en SP_ObtenerEtaDemorasMovil.
-- Resultados:
--   1. Mensaje
--   2. Contexto (1 fila): id_os, numero_os, estado_os, cliente, sede, salida_en, en_ruta_minutos, llegada_en, en_planta_minutos,
--        eta_original, minutos_demora, eta_vigente, inicio_previsto, ahora, puede_llegada, puede_ingreso, motivo_no_registra
--   3. Motivos del catálogo MOTIVO_DEMORA_RUTA con su ámbito (traslado | ingreso | ambos)
--   4. Demoras ya registradas de la OS (la más reciente primero)
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerDemorasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDemorasMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_eta_orig   DATETIME;
    DECLARE v_min_lleg   INT DEFAULT 0;
    DECLARE v_llegada    DATETIME;
    DECLARE v_inicio_vig DATETIME;
    DECLARE v_salida     DATETIME;
    DECLARE v_ahora      DATETIME;
    DECLARE v_inicio_trab TINYINT DEFAULT 0;
    DECLARE v_puede_lleg TINYINT DEFAULT 0;
    DECLARE v_puede_ing  TINYINT DEFAULT 0;

    SELECT os.estado INTO v_estado
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP() - INTERVAL 5 HOUR;

    CALL SP_ObtenerEtaDemorasMovil(p_id_os, v_eta_orig, v_min_lleg, v_llegada, v_inicio_vig);

    SELECT MAX(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00')) INTO v_salida
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_inicio_trab
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SET v_puede_lleg = IF(v_estado = 'en_ruta' AND v_llegada IS NULL, 1, 0);
    SET v_puede_ing  = IF(v_estado IN ('en_ruta', 'en_ejecucion') AND v_llegada IS NOT NULL AND v_inicio_trab = 0, 1, 0);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto
    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           s.nombre                                                          AS sede,
           v_salida                                                          AS salida_en,
           IF(v_salida IS NOT NULL AND v_llegada IS NULL, GREATEST(TIMESTAMPDIFF(MINUTE, v_salida, v_ahora), 0),
              IF(v_salida IS NOT NULL AND v_llegada IS NOT NULL, GREATEST(TIMESTAMPDIFF(MINUTE, v_salida, v_llegada), 0), NULL)) AS en_ruta_minutos,
           v_llegada                                                         AS llegada_en,
           IF(v_llegada IS NOT NULL, GREATEST(TIMESTAMPDIFF(MINUTE, v_llegada, v_ahora), 0), NULL)                              AS en_planta_minutos,
           v_eta_orig                                                        AS eta_original,
           v_min_lleg                                                        AS minutos_demora,
           IF(v_eta_orig IS NULL, NULL, v_eta_orig + INTERVAL v_min_lleg MINUTE)                                                AS eta_vigente,
           GREATEST(IFNULL(v_inicio_vig, v_ahora), v_ahora)                  AS inicio_previsto,
           v_ahora                                                           AS ahora,
           v_puede_lleg                                                      AS puede_llegada,
           v_puede_ing                                                       AS puede_ingreso,
           CASE WHEN v_puede_lleg = 1 OR v_puede_ing = 1 THEN NULL
                WHEN v_estado IN ('programada', 'reprogramada') THEN 'Las demoras se registran durante el traslado: primero inicia el traslado.'
                WHEN v_estado = 'en_ruta' THEN 'Ya registraste tu llegada: solo puedes registrar demoras de ingreso a planta, si todavía no inicias el trabajo.'
                ELSE 'Las demoras se registran durante el traslado o al ingresar a la planta, antes de iniciar el trabajo.' END AS motivo_no_registra
    FROM   orden_servicio os
    LEFT JOIN cliente      c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente s ON s.id_sede    = os.id_sede
    WHERE  os.id_os = p_id_os;

    -- 3. Motivos y su ámbito
    SELECT t.Num1 AS id_motivo, t.String1 AS nombre, t.String2 AS codigo, IFNULL(NULLIF(t.String3, ''), 'ambos') AS ambito
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 15 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL
    ORDER BY t.Num1;

    -- 4. Demoras de la OS
    SELECT d.id_demora,
           d.tipo,
           m.String1                          AS motivo,
           d.duracion_minutos,
           d.descripcion,
           d.fecha_registro,
           d.eta_anterior,
           d.eta_recalculada,
           IF(d.fotografia_url IS NULL OR d.fotografia_url = '', 0, 1) AS tiene_foto,
           d.latitud,
           d.longitud
    FROM   demora_registro d
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 15 AND m.IdEmpresa = 1 AND m.Num1 = d.id_motivo
    WHERE  d.id_os = p_id_os AND d.eliminado_en IS NULL
    ORDER BY d.fecha_registro DESC, d.id_demora DESC;
END$$

DELIMITER ;
