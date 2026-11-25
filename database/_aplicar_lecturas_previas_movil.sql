-- App móvil sin señal: lecturas por adelantado (HU-18 · descarga previa). Ejecutar con Alt+X (No al aviso de variables) y reiniciar la API.
-- Qué hace: crea SP_ContextoEquipoPrevioMovil y agrega el parámetro p_previo (TINYINT, último) a 4 lecturas móviles: SP_ObtenerObjetivosMovil, SP_ObtenerTrabajoEquipoMovil,
-- SP_ObtenerCabeceraInformeMovil y SP_ObtenerEvidenciasMovil. Con p_previo = 1 entregan sus datos aunque aún no haya llegada o el equipo no esté iniciado (la app los guarda con señal
-- para usarlos sin señal); con 0 se comportan EXACTAMENTE como antes. Son solo lecturas: ninguna escritura cambia. No toca datos.
-- IMPORTANTE: ejecutar este script DESPUÉS de cualquier _aplicar_*.sql antiguo de objetivos, trabajo del equipo, evidencias o informe del equipo (esos recrean los SP con la firma
-- anterior, sin p_previo, y la API fallaría). Reiniciar la API después. Se genera concatenando los 5 SP de database/procedures.

-- ============================================================
-- SP_ContextoEquipoPrevioMovil  (App Mobile HU-18 · trabajo sin señal — apoyo, no es un endpoint · SOLO LECTURA)
-- Igual que SP_ContextoEquipoMovil pero SIN el Hard Stop de la llegada ni el de "equipo iniciado": sirve para que la app descargue por adelantado, con señal, lo que el técnico
-- necesitará sin señal (cabecera del informe y evidencias del equipo). Lo llaman solo las lecturas con p_previo = 1; ninguna escritura lo usa, así que nunca habilita trabajar.
--   - La OS debe ser del técnico y estar programada, reprogramada, en ruta, en ejecución o pausada.
--   - El equipo debe ser un objetivo de la OS. p_estado_equipo trae su estado real (por_iniciar, en_ejecucion, pausado…) y p_habilitado queda como lo arma SP_ArmarObjetivosMovil
--     (0 antes de la llegada): por eso lo que se descarga sale con "puede registrar / puede editar" en 0.
--   p_mensaje trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL). Mismos parámetros que SP_ContextoEquipoMovil.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoEquipoPrevioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoEquipoPrevioMovil(
    IN  p_id_usuario    BIGINT,
    IN  p_id_os         BIGINT,
    IN  p_id_os_equipo  BIGINT,
    OUT p_mensaje       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_equipo     BIGINT,
    OUT p_estado_equipo VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_habilitado    TINYINT,
    OUT p_numero        INT,
    OUT p_nombre_equipo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_servicio      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_estado_equipo = NULL, p_habilitado = 0, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL, p_servicio = NULL;

    SELECT os.estado, os.numero INTO v_estado_os, p_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
    ELSEIF v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        SET p_mensaje = 'El servicio no está disponible para trabajar.';
    ELSE
        CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, p_habilitado, v_motivo);
        SELECT t.id_equipo, t.estado, t.numero, t.nombre, COALESCE(t.tipo_corto, t.tipo_intervencion)
        INTO   p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo, p_servicio
        FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
        IF p_id_equipo IS NULL THEN
            SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerObjetivosMovil  (App Mobile HU-07 — Lista de objetivos y selección de equipos · lectura)
-- Objetivos de la OS del técnico que inició sesión (el id sale del token), numerados y con su estado.
--   - Hard Stop (HU-06): sin llegada registrada en este viaje NO se entregan los objetivos (responde la regla de negocio con el motivo).
--   - p_buscar (opcional, máx. 100): filtra la LISTA por N/S, código del cliente, COD TW, marca, modelo, ubicación o tipo de equipo
--     (sin comodines: se busca el texto tal cual). Los contadores y el tiempo estimado siempre son de TODOS los objetivos.
--   - p_previo = 1 (HU-18, descarga por adelantado con señal): NO aplica ese Hard Stop; entrega la lista aunque aún no haya llegada (los botones salen deshabilitados) para que la
--     app la tenga guardada sin señal. Solo con la OS programada, reprogramada, en ruta, en ejecución o pausada. 0 = el comportamiento de siempre.
--   - Los objetivos los arma SP_ArmarObjetivosMovil (una sola vez); aquí solo se leen.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 contadores (1 fila) · 4 equipos (con puede_iniciar/pausar/reanudar) ·
--             5 cambios (historial del equipo y cambios de estado desde la app, el más reciente primero, máx. 300 de la OS).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerObjetivosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerObjetivosMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_buscar     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_previo     TINYINT
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado TINYINT;
    DECLARE v_motivo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_buscar     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estimado   INT DEFAULT 0;
    DECLARE v_ahora_utc  DATETIME;

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

    SET v_buscar = LOWER(TRIM(IFNULL(p_buscar, '')));
    IF CHAR_LENGTH(v_buscar) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda puede tener hasta 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);

    IF IFNULL(p_previo, 0) = 1 AND v_estado NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'El servicio no está disponible para trabajar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hard Stop: sin llegada no hay objetivos (salvo la descarga por adelantado, p_previo = 1)
    IF v_llegada_utc IS NULL AND IFNULL(p_previo, 0) = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    SELECT IFNULL(SUM(tiempo_estimado_min), 0) INTO v_estimado FROM tmp_obj_mov;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           sc.nombre                                                         AS sede,
           CONVERT_TZ(v_salida_utc, '+00:00', '-05:00')                      AS salida_en,
           CONVERT_TZ(v_llegada_utc, '+00:00', '-05:00')                     AS llegada_en,
           IF(v_salida_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_salida_utc, v_llegada_utc))) AS traslado_min,
           IF(v_llegada_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_llegada_utc, v_ahora_utc))) AS en_planta_min,
           v_estimado                                                        AS estimado_min
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede   = os.id_sede
    WHERE  os.id_os = p_id_os;

    -- 3. Contadores (de todos los objetivos)
    SELECT IFNULL(SUM(estado = 'completado'), 0)                                  AS completados,
           IFNULL(SUM(estado <> 'completado' AND observado_cuenta = 0), 0)        AS pendientes,
           IFNULL(SUM(estado <> 'completado' AND observado_cuenta = 1), 0)        AS observados,
           COUNT(*)                                                               AS total
    FROM   tmp_obj_mov;

    -- 4. Equipos (con el filtro de búsqueda)
    SELECT t.id_os_equipo, t.id_equipo, t.numero, t.tipo_intervencion, t.tipo_corto, t.nombre, t.codigo_tw, t.codigo_cliente, t.marca, t.modelo,
           t.num_serie, t.ubicacion, t.estado_equipo, t.bloqueado, t.en_campo, t.falta_equipo, t.estado, t.tiempo_estimado_min, t.tiempo_real_min,
           CONVERT_TZ(t.iniciado_utc, '+00:00', '-05:00') AS iniciado_en, t.motivo_pausa, t.requiere_aprobacion, t.ultima_intervencion, t.ultima_parte,
           t.alertas_pendientes, t.puede_iniciar, t.puede_pausar, t.puede_reanudar
    FROM   tmp_obj_mov t
    WHERE  v_buscar = ''
       OR  LOCATE(v_buscar, LOWER(CONCAT_WS(' ', t.num_serie, t.codigo_cliente, t.codigo_tw, t.marca, t.modelo, t.ubicacion, t.nombre))) > 0
    ORDER BY t.numero;

    -- 5. Cambios: historial del equipo (intranet) y cambios de estado hechos desde la app
    SELECT x.id_os_equipo, x.fecha, x.campo, x.valor_anterior, x.valor_nuevo, x.detalle, x.usuario
    FROM (
        SELECT oe.id AS id_os_equipo, h.registrado_en AS fecha, h.campo_modificado AS campo, h.valor_anterior, h.valor_nuevo,
               LEFT(IFNULL(h.motivo, ''), 300) AS detalle, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS usuario
        FROM   os_equipo oe
        JOIN   equipo_historial h ON h.id_equipo = oe.id_equipo
        LEFT JOIN usuario u ON u.id_usuario = h.registrado_por
        WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
        UNION ALL
        SELECT a.id_entidad, a.registrado_en, 'Estado', a.estado_anterior, a.estado_nuevo, LEFT(IFNULL(a.descripcion, ''), 300),
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
        FROM   auditoria_evento a
        LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
        WHERE  a.entidad_tipo = 'os_equipo'
          AND  a.id_entidad IN (SELECT o2.id FROM os_equipo o2 WHERE o2.id_os = p_id_os AND o2.eliminado_en IS NULL)
    ) x
    ORDER BY x.fecha DESC
    LIMIT 300;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerTrabajoEquipoMovil  (App Mobile HU-08 — "Trabajo en el equipo": cabecera y las 5 etapas · lectura)
-- Pantalla a la que entra el técnico con "Trabajar en el equipo". El técnico sale del token; la OS debe ser suya.
--   - Hard Stop (HU-06): sin llegada registrada no se entrega nada. El equipo debe haberse iniciado (en ejecución, pausado o completado).
--   - Tipo de orden según la RQ: el área de la RQ (area_servicio_rq) define OS (servicio técnico) u OM (metrología).
--   - Servicio: sigla y nombre del tipo de intervención del equipo; si no tiene, el tipo de servicio de la OS.
--   - Etapas (siempre las 5): variables (HU-09), fotos (HU-11), ensayos (HU-10), cabecera (HU-15) y correlativo (HU-14). Las calcula SP_ArmarEtapasEquipoMovil, UNA sola vez
--     (la misma regla del Hard Stop de cierre, HU-16: SP_ValidarCierreEquipoMovil / SP_GenerarInformeEquipoMovil).
--       estado: conforme | en_curso | pendiente | bloqueado | no_conforme (ensayos finalizados con error crítico).
--       disponible = 0 → la etapa aún no tiene pantalla en la app (hoy las 5 la tienen).
--   - Avance = etapas conformes de 5. "Finalizar trabajo" se habilita cuando las 5 están conformes (puede_finalizar).
--   - puede_registrar = el equipo está EN EJECUCIÓN y el servicio en curso: solo así se guardan datos de las etapas.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 variables ambientales (0 o 1 fila) · 4 etapas (5 filas).
--   - p_previo = 1 (HU-18, descarga por adelantado con señal): NO aplica el Hard Stop de la llegada ni el de "equipo iniciado"; entrega el trabajo del equipo con puede_registrar = 0 para que
--     la app lo tenga guardado sin señal. Solo con la OS programada, reprogramada, en ruta, en ejecución o pausada. 0 = el comportamiento de siempre.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTrabajoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTrabajoEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_previo       TINYINT
)
proc: BEGIN
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_orden  VARCHAR(2)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_numero_rq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sigla       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_int    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes   INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT os.estado INTO v_estado_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Objetivo (equipo) de esa OS, con su estado: SP_ArmarObjetivosMovil (una sola vez)
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);
    IF IFNULL(p_previo, 0) = 1 AND v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'El servicio no está disponible para trabajar.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_llegada_utc IS NULL AND IFNULL(p_previo, 0) = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT t.id_equipo, t.estado, COALESCE(t.tipo_corto, t.tipo_intervencion), t.tipo_intervencion INTO v_id_equipo, v_estado, v_sigla, v_tipo_int
    FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
    IF v_id_equipo IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado NOT IN ('en_ejecucion', 'pausado', 'completado') AND IFNULL(p_previo, 0) = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el trabajo en este equipo desde los objetivos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Tipo de orden según la RQ (servicio técnico → OS, metrología → OM): una sola vez, en SP_TipoOrdenMovil
    CALL SP_TipoOrdenMovil(p_id_os, v_tipo_orden, v_numero_rq);

    -- Las 5 etapas (estado, detalle y pendientes): una sola vez, en SP_ArmarEtapasEquipoMovil (la comparten el Hard Stop de cierre y la generación del informe)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_equipo, v_conformes);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT os.id_os, os.numero AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente,
           v_tipo_orden AS tipo_orden, v_numero_rq AS numero_rq,
           v_sigla AS servicio_sigla,
           COALESCE(v_tipo_int, (SELECT ts.String1 FROM tabla_maestra ts
                                 WHERE ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio LIMIT 1)) AS servicio,
           e.id_os_equipo, e.nombre, e.num_serie, e.codigo_cliente, e.codigo_tw, e.marca, e.modelo, e.ubicacion, e.estado,
           e.tiempo_estimado_min, e.tiempo_real_min, CONVERT_TZ(e.iniciado_utc, '+00:00', '-05:00') AS iniciado_en,
           IF(e.estado = 'en_ejecucion' AND v_habilitado = 1, 1, 0) AS puede_registrar,
           v_conformes AS etapas_conformes,
           5 AS etapas_total,
           IF(v_conformes = 5 AND e.estado = 'en_ejecucion', 1, 0) AS puede_finalizar
    FROM   tmp_obj_mov e
    JOIN   orden_servicio os ON os.id_os = p_id_os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  e.id_os_equipo = p_id_os_equipo;

    -- 3. Variables ambientales vigentes (hora de Lima)
    SELECT va.temperatura_c, va.humedad_pct, IFNULL(va.procedencia, 'N.I') AS procedencia,
           CONVERT_TZ(va.registrado_en, '+00:00', '-05:00') AS registrado_en
    FROM   variable_ambiental va
    WHERE  va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL
    ORDER BY va.id_variable DESC LIMIT 1;

    -- 4. Etapas
    SELECT s.orden, s.codigo, s.nombre, s.estado, s.detalle, s.disponible FROM tmp_etapas_mov s ORDER BY s.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerCabeceraInformeMovil  (App Mobile HU-15 — Cabecera del informe: Datos · Detalle Serv. · Observación y pruebas · solo lectura)
-- Todo lo que muestran las 3 pestañas de la cabecera del informe del equipo (informe_tecnico y sus hijas, migraciones 93 / 100 / 104). El técnico sale del token; el
-- contexto (OS suya, Hard Stop de llegada, equipo iniciado) lo valida SP_ContextoEquipoMovil, UNA sola vez; el tipo de orden OS / OM, SP_TipoOrdenMovil.
--   Datos: N° de informe (NNNN-AAAA al generar; antes NULL), RQ, orden, cliente (empresa, dirección, contacto), equipo (marca, modelo, serie, código, capacidad, d, e,
--     COD TW, ubicación, clase), datos del informe (propuesta, comercial, técnico, fecha, horas, tipo de servicio) y "Quién atiende en planta" (lo guardado o, si no hay,
--     el contacto de la OS).
--   puede_editar = el equipo está EN EJECUCIÓN y el informe aún no se generó (HU-16). Sin informe todavía, todo sale vacío: se crea al primer guardado.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 checklist de Detalle Serv. (catálogo CHECKLIST_SERVICIO del tipo OS / OM, con lo marcado) · 4 recomendaciones ·
--   5 fallas · 6 fotos de las fallas · 7 pruebas de las fallas · 8 ensayos de HU-10 (Pruebas generales, formato resumido) · 9 opciones (tipos de equipo, clasificación y
--   componente de las fallas).
--   p_previo = 1 (HU-18, descarga por adelantado con señal): usa SP_ContextoEquipoPrevioMovil (sin el Hard Stop de la llegada ni el de "equipo iniciado"); puede_editar sale 0 mientras el
--   equipo no esté en ejecución. 0 = el comportamiento de siempre.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCabeceraInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCabeceraInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_previo       TINYINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_gen      DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    IF IFNULL(p_previo, 0) = 1 THEN
        CALL SP_ContextoEquipoPrevioMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    ELSE
        CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    END IF;
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);

    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera: Datos, Detalle Serv. (JSON), Diagnóstico final
    SELECT p_id_os AS id_os, v_num_os AS numero_os, v_tipo AS tipo_orden, v_rq AS numero_rq,
           v_informe AS id_informe, it.numero_informe, IF(v_gen IS NULL, 0, 1) AS generado,
           IF(v_estado = 'en_ejecucion' AND v_hab = 1 AND v_gen IS NULL, 1, 0) AS puede_editar,
           c.razon_social AS empresa, c.ruc AS ruc, sc.direccion_exacta AS direccion,
           co.nombres AS contacto, co.cargo AS contacto_cargo, NULLIF(TRIM(co.telefono_movil), '') AS contacto_telefono, NULLIF(TRIM(co.correo), '') AS contacto_correo,
           ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), '') AS num_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw,
           ec.alcance_maximo AS capacidad_max, ec.division_minima AS d, IF(ec.division_verif_igual = 1, ec.division_minima, ec.division_verif) AS e,
           NULLIF(ec.ubicacion_especifica, '') AS ubicacion, ec.clase_exactitud AS clase, ec.clasificacion AS tipo_equipo,
           pr.numero AS propuesta, NULLIF(TRIM(CONCAT(IFNULL(ucom.nombre, ''), ' ', IFNULL(ucom.apellido, ''))), '') AS comercial,
           NULLIF(TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))), '') AS tecnico,
           os.fecha_ejecucion AS fecha,
           TIME_FORMAT(COALESCE(os.hora_llegada_real, os.hora_inicio), '%H:%i') AS hora_inicio,
           TIME_FORMAT(COALESCE(os.hora_fin_real, os.hora_fin_estimada), '%H:%i') AS hora_fin,
           ts.String1 AS tipo_servicio,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), co.nombres)                  AS responsable_nombre,
           COALESCE(NULLIF(TRIM(it.responsable_cargo), ''), co.cargo)                     AS responsable_cargo,
           COALESCE(NULLIF(TRIM(it.responsable_telefono), ''), NULLIF(TRIM(co.telefono_movil), '')) AS responsable_telefono,
           it.detalle_servicio, it.comentario_pruebas, IFNULL(it.sin_recomendaciones, 0) AS sin_recomendaciones, IFNULL(it.sin_fallas, 0) AS sin_fallas,
           it.severidad_general, it.estado_equipo_final,
           IFNULL(it.rev_jefatura, 0) AS rev_jefatura, IFNULL(it.requiere_precotizacion, 0) AS requiere_precotizacion,
           IFNULL(it.segunda_visita, 0) AS segunda_visita, IFNULL(it.aplica_garantia, 0) AS aplica_garantia, it.cabecera_guardada_en AS guardada_en,
           it.error_critico_motivo AS error_critico, it.ensayos_finalizado_en AS ensayos_finalizados_en
    FROM   orden_servicio os
    JOIN   equipo_cliente ec          ON ec.id_equipo = v_id_eq
    LEFT JOIN informe_tecnico it      ON it.id_informe = v_informe
    LEFT JOIN cliente c               ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc         ON sc.id_sede = os.id_sede
    LEFT JOIN contacto_cliente co     ON co.id_contacto = os.id_contacto
    LEFT JOIN expediente_digital ed   ON ed.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial pr  ON pr.id_propuesta = COALESCE(os.id_propuesta, ed.id_propuesta)
    LEFT JOIN usuario ucom            ON ucom.id_usuario = pr.id_creador
    LEFT JOIN usuario ut              ON ut.id_usuario = p_id_usuario
    LEFT JOIN tabla_maestra ts        ON ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    WHERE  os.id_os = p_id_os;

    -- 3. Checklist de Detalle Serv.: el del tipo de orden (OS / OM), con lo marcado
    SELECT m.String2 AS codigo, m.String1 AS titulo, m.Num1 AS orden,
           IF(EXISTS (SELECT 1 FROM informe_procedimiento ip
                      WHERE ip.id_informe = v_informe AND ip.codigo = m.String2 AND ip.realizado = 1 AND ip.eliminado_en IS NULL), 1, 0) AS marcado
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    -- 4. Recomendaciones inmediatas
    SELECT r.id_recomendacion, r.codigo, r.titulo, r.descripcion, r.prioridad, r.plazo
    FROM   informe_recomendacion r
    WHERE  r.id_informe = v_informe AND r.origen = 'tecnico' AND r.eliminado_en IS NULL
    ORDER BY r.orden, r.id_recomendacion;

    -- 5. Fallas
    SELECT o.id_observacion, o.codigo, o.orden, o.clasificacion, o.componente, o.titulo AS componente_nombre, o.detalle_extra AS clasificacion_nombre,
           o.descripcion, o.nivel_afectacion
    FROM   informe_observacion o
    WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL
    ORDER BY o.orden, o.id_observacion;

    -- 6. Fotos de las fallas
    SELECT f.id_observacion, f.id_evidencia
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'falla' AND f.eliminado_en IS NULL AND f.id_observacion IS NOT NULL
      AND  EXISTS (SELECT 1 FROM informe_observacion o WHERE o.id_observacion = f.id_observacion AND o.id_informe = v_informe AND o.eliminado_en IS NULL)
    ORDER BY f.id_observacion, f.id_evidencia;

    -- 7. Pruebas que justifican cada falla
    SELECT p.id_observacion, p.tipo, p.orden, p.posicion, p.carga, p.indicacion, p.error, p.emp, p.resultado
    FROM   informe_observacion_prueba p
    JOIN   informe_observacion o ON o.id_observacion = p.id_observacion
    WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL AND p.eliminado_en IS NULL
    ORDER BY o.orden, p.tipo, p.orden, p.id_prueba;

    -- 8. Pruebas generales (formato resumido): lo que guardó Ensayos y Calibración (HU-10)
    SELECT en.tipo, IFNULL(en.grupo, 0) AS grupo, en.orden, en.punto, en.carga, en.lectura, en.error, en.tolerancia, en.resultado, en.critico
    FROM   informe_ensayo en
    WHERE  en.id_informe = v_informe AND en.origen = 'tecnico' AND en.eliminado_en IS NULL
    ORDER BY (en.tipo = 'excentricidad'), en.grupo, en.orden, en.id_ensayo;

    -- 9. Opciones de las listas
    SELECT 'tipo_equipo' AS lista, m.String2 AS codigo, m.String1 AS nombre, NULL AS padre
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'clasificacion', m.String2, m.String1, NULL
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'componente', m.String2, m.String1, m.String3
    FROM   tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY lista, nombre;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerEvidenciasMovil  (App Mobile HU-11 / HU-12 / HU-13 — panel de evidencias del equipo · lectura)
-- El panel del "Registro fotográfico": las 9 evidencias (SP_CatalogoEvidenciasMovil) con su estado, el avance "N de 9 completas" y lo que necesita el
-- botón "Guardar y volver" (puede_guardar = todas completas: 9, u 8 si el servicio no tiene informe físico, ver SP_ResumenEvidenciasMovil; la cabecera trae informe_fisico). Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop, equipo iniciado).
--   estado de cada evidencia: pendiente | aprobada | rechazada | forzada | omitida  (omitida = la IA no estuvo disponible; cuenta como completa)
--   Para una evidencia FORZADA (HU-12) trae lo de "Ver detalles": motivo del técnico, rechazo de la IA, quién la aceptó, cuándo y los intentos previos.
--   Informe a mano: paginas = hojas válidas; la tarjeta muestra la primera.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 evidencias (9 filas) · 4 fotos adicionales (0 a 20 filas; no cuentan en el avance ni en "Guardar y volver").
--   p_previo = 1 (HU-18, descarga por adelantado con señal): usa SP_ContextoEquipoPrevioMovil (sin el Hard Stop de la llegada ni el de "equipo iniciado"); puede_registrar sale 0 mientras el
--   equipo no esté en ejecución. 0 = el comportamiento de siempre.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEvidenciasMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_previo       TINYINT
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

    IF IFNULL(p_previo, 0) = 1 THEN
        CALL SP_ContextoEquipoPrevioMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    ELSE
        CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    END IF;
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
           IF(v_compl = v_total, 1, 0) AS puede_guardar,
           IF(EXISTS (SELECT 1 FROM orden_servicio os WHERE os.id_os = p_id_os AND os.informe_fisico = 0), 0, 1) AS informe_fisico
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

    -- 4. Fotos adicionales (opcionales, no cuentan en las 9): de la más antigua a la más reciente
    SELECT f.id_evidencia, f.pagina AS numero, CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS capturada_en
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL
    ORDER BY f.pagina, f.id_evidencia;

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
END$$

DELIMITER ;



-- Verificación (solo lectura, no crea nada): los 3 valores deben ser 1, 4 y 4
SELECT 'SP_ContextoEquipoPrevioMovil existe (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ContextoEquipoPrevioMovil') AS valor
UNION ALL
SELECT 'Lecturas con el parámetro p_previo (deben ser 4)',
       (SELECT COUNT(*) FROM information_schema.PARAMETERS WHERE SPECIFIC_SCHEMA = DATABASE() AND PARAMETER_NAME = 'p_previo'
          AND SPECIFIC_NAME IN ('SP_ObtenerObjetivosMovil', 'SP_ObtenerTrabajoEquipoMovil', 'SP_ObtenerCabeceraInformeMovil', 'SP_ObtenerEvidenciasMovil'))
UNION ALL
SELECT 'p_previo es el ÚLTIMO parámetro de cada una (deben ser 4)',
       (SELECT COUNT(*) FROM information_schema.PARAMETERS p
        WHERE p.SPECIFIC_SCHEMA = DATABASE() AND p.PARAMETER_NAME = 'p_previo'
          AND p.SPECIFIC_NAME IN ('SP_ObtenerObjetivosMovil', 'SP_ObtenerTrabajoEquipoMovil', 'SP_ObtenerCabeceraInformeMovil', 'SP_ObtenerEvidenciasMovil')
          AND p.ORDINAL_POSITION = (SELECT MAX(q.ORDINAL_POSITION) FROM information_schema.PARAMETERS q
                                    WHERE q.SPECIFIC_SCHEMA = p.SPECIFIC_SCHEMA AND q.SPECIFIC_NAME = p.SPECIFIC_NAME));
