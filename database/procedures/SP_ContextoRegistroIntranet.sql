-- ============================================================
-- SP_ContextoRegistroIntranet  (HU-55 — registrar el informe de un equipo desde la intranet · SOLO LECTURA)
-- Todo lo que necesita la pantalla "Registrar informe" de la Asistente de Seguimiento / Jefe de Operaciones ANTES de comenzar: la OS, el cliente y la planta, el equipo, el técnico
-- asignado, si el servicio lleva informe físico, el estado de las 5 etapas, el informe (borrador o generado), si se puede iniciar el registro, quién lo tiene abierto y los catálogos.
-- NO escribe nada (ni llegada, ni inicio del equipo, ni bloqueo): eso lo hace SP_IniciarRegistroIntranet. Acceso: acción seg_registrar_informe (FN_PermisoAccion).
-- Reutiliza SP_ArmarObjetivosMovil (estado del equipo), SP_ArmarEtapasEquipoMovil (las 5 etapas) y SP_TipoOrdenMovil: la regla de cada una vive solo allí. No modifica ningún SP móvil.
-- Reglas de puede_iniciar (motivo_no_puede dice la primera que falla): técnico asignado · OS en programada, reprogramada, en_ruta, en_ejecucion o pausada (anulada, borrador, emitida,
--   bloqueada por SSOMA y finalizada NO: la finalizada está pendiente de decisión) · el equipo es un objetivo de la OS, no está bloqueado ni completado y su informe no está generado
--   (para corregirlo existe el informe complementario) · el técnico no tiene OTRO equipo en ejecución (otro_equipo_abierto: pausarlo con SP_PausarEquipoAbiertoIntranet) · nadie más tiene
--   el registro abierto con actividad en los últimos 30 min. Si el registro propio está abierto, puede_iniciar sigue en 1 (volver a entrar es idempotente).
-- Horas de registro_ultima_actividad en hora de Lima. actividad_previa_tecnico = el equipo ya tiene variables, evidencias o ensayos y nunca se abrió un registro desde la intranet
--   (es decir, el técnico ya trabajó desde su app: avisar a la Asistente antes de mezclar).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: 2 contexto (1 fila) · 3 etapas (orden, codigo, nombre, estado, detalle) ·
--   4 catálogos en formato largo (catalogo, codigo, nombre, clasificacion, orden): procedencia, tipo_equipo, forma_plato, checklist_os, checklist_om, severidad, estado_equipo,
--   clasificacion_falla, componente_falla (clasificacion = padre) y motivo_manual.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_ContextoRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_chk  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tecnico     BIGINT       DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT       DEFAULT NULL;
    DECLARE v_tipo        VARCHAR(2)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida      DATETIME     DEFAULT NULL;
    DECLARE v_llegada     DATETIME     DEFAULT NULL;
    DECLARE v_hab         TINYINT      DEFAULT 0;
    DECLARE v_motivo_obj  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hay_obj     TINYINT      DEFAULT 0;
    DECLARE v_estado_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_bloqueado   TINYINT      DEFAULT 0;
    DECLARE v_req_aprob   TINYINT      DEFAULT 0;
    DECLARE v_informe     BIGINT       DEFAULT NULL;
    DECLARE v_gen         DATETIME     DEFAULT NULL;
    DECLARE v_num_inf     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_puede       TINYINT      DEFAULT 1;
    DECLARE v_motivo_no   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_reg_id      BIGINT       DEFAULT NULL;
    DECLARE v_reg_user    BIGINT       DEFAULT NULL;
    DECLARE v_reg_act     DATETIME     DEFAULT NULL;
    DECLARE v_reg_activo  TINYINT      DEFAULT 0;
    DECLARE v_reg_propio  TINYINT      DEFAULT 0;
    DECLARE v_reg_nombre  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_previa      TINYINT      DEFAULT 0;
    DECLARE v_otro        VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes   INT          DEFAULT 0;
    DECLARE v_ahora       DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov, tmp_etapas_mov, tmp_pend_eq, tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();

    SELECT os.estado, os.numero, os.id_tecnico_principal INTO v_estado_os, v_numero_os, v_tecnico
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_estado_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_equipo INTO v_id_equipo
    FROM   os_equipo oe
    WHERE  oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL;
    IF v_id_equipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);

    -- Estado del equipo y de la OS: una sola vez, en SP_ArmarObjetivosMovil (solo lectura; deja tmp_obj_mov)
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_chk, v_salida, v_llegada, v_hab, v_motivo_obj);
    SELECT 1, t.estado, t.bloqueado, t.requiere_aprobacion INTO v_hay_obj, v_estado_eq, v_bloqueado, v_req_aprob
    FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;

    -- Informe técnico del equipo (borrador o generado; el complementario no tiene id_os ni id_equipo y no entra aquí)
    SELECT it.id_informe, it.generado_en, it.numero_informe INTO v_informe, v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    -- Quién tiene abierto el registro (activo y con actividad en los últimos 30 min)
    SELECT r.id_registro, r.id_registrador, r.ultima_actividad INTO v_reg_id, v_reg_user, v_reg_act
    FROM   registro_informe_intranet r
    WHERE  r.id_os_equipo = p_id_os_equipo AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1;
    IF v_reg_id IS NOT NULL AND v_reg_act >= v_ahora - INTERVAL 30 MINUTE THEN
        SET v_reg_activo = 1;
        SET v_reg_propio = IF(v_reg_user = p_id_registrador, 1, 0);
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_reg_nombre FROM usuario u WHERE u.id_usuario = v_reg_user LIMIT 1;
    ELSE
        SET v_reg_id = NULL, v_reg_user = NULL, v_reg_act = NULL;
    END IF;

    -- El técnico ya trabajó desde su app en este equipo (hay datos y nunca se abrió un registro desde la intranet)
    IF NOT EXISTS (SELECT 1 FROM registro_informe_intranet r WHERE r.id_os_equipo = p_id_os_equipo)
       AND (EXISTS (SELECT 1 FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL)
            OR EXISTS (SELECT 1 FROM evidencia_fotografica f WHERE f.id_os = p_id_os AND f.id_equipo = v_id_equipo AND f.eliminado_en IS NULL)
            OR EXISTS (SELECT 1 FROM informe_ensayo ie JOIN informe_tecnico it2 ON it2.id_informe = ie.id_informe
                       WHERE it2.id_os = p_id_os AND it2.id_equipo = v_id_equipo AND it2.eliminado_en IS NULL AND ie.eliminado_en IS NULL)) THEN
        SET v_previa = 1;
    END IF;

    -- Otro equipo del técnico en ejecución (la regla móvil: un técnico trabaja en un solo equipo a la vez)
    IF v_tecnico IS NOT NULL THEN
        SELECT CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')') INTO v_otro
        FROM   os_equipo x
        JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
        JOIN   orden_servicio o2 ON o2.id_os = x.id_os
        WHERE  x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
          AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
        LIMIT 1;
    END IF;

    -- ¿Se puede iniciar el registro? La primera regla que falla da el motivo
    IF v_tecnico IS NULL THEN
        SET v_puede = 0, v_motivo_no = 'El servicio no tiene un técnico asignado.';
    ELSEIF v_estado_os = 'finalizada' THEN
        SET v_puede = 0, v_motivo_no = 'La OS ya está finalizada: esta función aún no cubre ese caso.';
    ELSEIF v_estado_os = 'anulada' THEN
        SET v_puede = 0, v_motivo_no = 'La OS está anulada.';
    ELSEIF v_estado_os = 'bloqueada' THEN
        SET v_puede = 0, v_motivo_no = 'La OS está bloqueada por SSOMA.';
    ELSEIF v_estado_os IN ('borrador', 'emitida') THEN
        SET v_puede = 0, v_motivo_no = 'La OS todavía no está programada ni tiene técnico asignado.';
    ELSEIF v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        SET v_puede = 0, v_motivo_no = 'El estado de la OS no permite registrar el informe.';
    ELSEIF v_hay_obj = 0 THEN
        SET v_puede = 0, v_motivo_no = 'El equipo no forma parte de los objetivos de este servicio.';
    ELSEIF v_gen IS NOT NULL THEN
        SET v_puede = 0, v_motivo_no = 'Este equipo ya tiene el informe generado. Para corregirlo usa el informe complementario.';
    ELSEIF v_estado_eq = 'completado' THEN
        SET v_puede = 0, v_motivo_no = 'Este equipo ya está completado.';
    ELSEIF v_bloqueado = 1 THEN
        SET v_puede = 0, v_motivo_no = 'Este equipo está bloqueado y no se puede intervenir.';
    ELSEIF v_estado_eq = 'pausado' AND v_req_aprob = 1 THEN
        SET v_puede = 0, v_motivo_no = 'El equipo está pausado esperando la aprobación de un supervisor.';
    ELSEIF v_reg_activo = 1 AND v_reg_propio = 0 THEN
        SET v_puede = 0, v_motivo_no = CONCAT('Otra persona (', IFNULL(v_reg_nombre, 'otro usuario'), ') está registrando este equipo.');
    ELSEIF v_otro IS NOT NULL THEN
        SET v_puede = 0, v_motivo_no = CONCAT('El técnico ya tiene en ejecución el equipo ', v_otro, ': pausa ese equipo antes de continuar con otro.');
    END IF;

    -- Las 5 etapas (deja tmp_etapas_mov y tmp_pend_eq; sin datos salen pendiente / bloqueado, sin error)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_equipo, v_conformes);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto
    SELECT os.id_os, os.numero AS numero_os, v_tipo AS tipo_orden, v_rq AS numero_rq, os.estado AS estado_os,
           c.razon_social AS cliente, c.ruc AS ruc, sc.nombre AS planta, sc.direccion_exacta AS direccion_planta,
           p_id_os_equipo AS id_os_equipo, v_id_equipo AS id_equipo, IFNULL(t.nombre, 'Equipo') AS equipo_nombre, IFNULL(t.numero, 0) AS numero_equipo,
           NULLIF(TRIM(ec.num_serie), '') AS numero_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw, ec.marca, ec.modelo,
           v_tecnico AS id_tecnico, NULLIF(TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))), '') AS tecnico,
           IF(os.informe_fisico = 0, 0, 1) AS informe_fisico,
           IFNULL(v_estado_eq, 'por_iniciar') AS estado_equipo,
           IF(v_estado_eq IN ('en_ejecucion', 'pausado', 'completado'), 1, 0) AS iniciado,
           IF(v_gen IS NULL, 0, 1) AS informe_generado, v_num_inf AS numero_informe, v_informe AS id_informe,
           v_puede AS puede_iniciar, v_motivo_no AS motivo_no_puede,
           v_reg_activo AS registro_activo, v_reg_user AS registrador_id, v_reg_nombre AS registrador_nombre, v_reg_propio AS registro_propio,
           CONVERT_TZ(v_reg_act, '+00:00', '-05:00') AS registro_ultima_actividad,
           v_previa AS actividad_previa_tecnico, v_otro AS otro_equipo_abierto
    FROM   orden_servicio os
    JOIN   equipo_cliente ec          ON ec.id_equipo = v_id_equipo
    LEFT JOIN cliente c               ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc         ON sc.id_sede = os.id_sede
    LEFT JOIN usuario ut              ON ut.id_usuario = v_tecnico
    LEFT JOIN tmp_obj_mov t           ON t.id_os_equipo = p_id_os_equipo
    WHERE  os.id_os = p_id_os;

    -- 3. Etapas
    SELECT e.orden, e.codigo, e.nombre, e.estado, e.detalle FROM tmp_etapas_mov e ORDER BY e.orden;

    -- 4. Catálogos (formato largo). Las formas del plato, severidades y estados del equipo son los valores que validan los SP móviles de ensayos y cabecera.
    SELECT 'procedencia' AS catalogo, 'N.I' AS codigo, 'No indicado' AS nombre, NULL AS clasificacion, 1 AS orden
    UNION ALL
    SELECT 'tipo_equipo', m.String2, m.String1, NULL, ROW_NUMBER() OVER (ORDER BY m.String1)
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'forma_plato', 'rectangular', 'Rectangular', NULL, 1
    UNION ALL
    SELECT 'forma_plato', 'circular', 'Circular', NULL, 2
    UNION ALL
    SELECT 'forma_plato', 'triangular', 'Triangular', NULL, 3
    UNION ALL
    SELECT IF(m.String3 = 'OM', 'checklist_om', 'checklist_os'), m.String2, m.String1, NULL, m.Num1
    FROM   tabla_maestra m WHERE m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 IN ('OS', 'OM') AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'severidad', 'baja', 'Baja', NULL, 1
    UNION ALL
    SELECT 'severidad', 'media', 'Media', NULL, 2
    UNION ALL
    SELECT 'severidad', 'alta', 'Alta', NULL, 3
    UNION ALL
    SELECT 'severidad', 'critica', 'Crítica', NULL, 4
    UNION ALL
    SELECT 'estado_equipo', 'operativo', 'Operativo', NULL, 1
    UNION ALL
    SELECT 'estado_equipo', 'con_observaciones', 'Con observaciones', NULL, 2
    UNION ALL
    SELECT 'estado_equipo', 'inoperativo', 'Inoperativo', NULL, 3
    UNION ALL
    SELECT 'clasificacion_falla', m.String2, m.String1, NULL, ROW_NUMBER() OVER (ORDER BY m.String1)
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'componente_falla', m.String2, m.String1, m.String3, ROW_NUMBER() OVER (ORDER BY m.String1)
    FROM   tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'motivo_manual', m.String2, m.String1, NULL, m.Num1
    FROM   tabla_maestra m WHERE m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY catalogo, orden, nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov, tmp_etapas_mov, tmp_pend_eq;
END$$

DELIMITER ;
