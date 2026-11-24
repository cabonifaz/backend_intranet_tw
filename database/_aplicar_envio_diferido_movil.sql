-- App móvil sin señal: detalle de los registros enviados tarde (HU-18 · trazabilidad). Ejecutar con Alt+X (No al aviso de variables) y reiniciar la API.
-- Qué hace: migración 128 (tabla envio_diferido_movil) y crea 2 procedimientos nuevos: SP_RegistrarEnvioDiferidoMovil (lo llama la API sola cuando la app manda la cabecera
-- X-TW-Capturado-En) y SP_ListarEnviosDiferidosMovil (lo leen Jefatura y la intranet). No cambia ningún SP existente ni datos: la app actual sigue funcionando igual.
-- Se genera concatenando database/migrations/128_envio_diferido_movil.sql (sin su verificación) y los 2 SP de database/procedures.

-- ============================================================
-- Migración 128 — App móvil sin señal: detalle de los registros enviados tarde (HU-18 · trazabilidad)
--   Cuando el técnico registra algo sin señal, la app lo guarda en el teléfono y lo envía solo al volver la conexión. Esta tabla deja constancia de CADA envío tardío:
--   qué fue (llegada, demora, variables, ensayos, cabecera, evidencia, acción de equipo, jornada, gasto…), de qué servicio y equipo, cuándo se tomó en campo (capturado_utc),
--   cuándo llegó al servidor (recibido_utc), cuánto tardó (retraso_seg), por qué se retrasó (motivo) y cuántos intentos hizo la app.
--   La API la llena sola cuando la app manda la hora de captura en la cabecera X-TW-Capturado-En (SP_RegistrarEnvioDiferidoMovil); la leen Jefatura y la intranet
--   (SP_ListarEnviosDiferidosMovil). No cambia ningún dato existente. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS envio_diferido_movil (
    id_envio      BIGINT       NOT NULL AUTO_INCREMENT,
    id_usuario    BIGINT       NOT NULL,
    id_os         BIGINT       NULL,
    id_os_equipo  BIGINT       NULL,
    tipo          VARCHAR(30)  NOT NULL,
    metodo        VARCHAR(6)   NOT NULL,
    ruta          VARCHAR(200) NOT NULL,
    capturado_utc DATETIME     NOT NULL,
    recibido_utc  DATETIME     NOT NULL,
    retraso_seg   INT          NOT NULL DEFAULT 0,
    motivo        VARCHAR(30)  NOT NULL DEFAULT 'sin_senal',
    intentos      INT          NOT NULL DEFAULT 0,
    creado_en     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_envio),
    KEY ix_edm_os (id_os, capturado_utc),
    KEY ix_edm_usuario (id_usuario, recibido_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ============================================================
-- SP_RegistrarEnvioDiferidoMovil  (App móvil sin señal — trazabilidad · escritura)
-- Deja constancia de un registro de campo que la app envió DESPUÉS de tomarlo (sin señal). La API lo llama sola, después de que el envío se aceptó, cuando la app manda
-- la cabecera X-TW-Capturado-En; no es un endpoint. Nunca rechaza ni cambia el registro original: si algo no cuadra, simplemente no guarda.
--   - p_capturado_utc: hora UTC en que el técnico lo tomó (una hora futura se toma como "ahora"; más de 30 días atrás se ignora).
--   - p_motivo: 'sin_senal' (por defecto) | 'servidor_no_disponible' (el servidor falló y se reintentó) | 'otro'. Cualquier otro texto se guarda como 'otro'.
--   - p_intentos: veces que la app intentó enviarlo (0 a 99).
--   - El tipo sale de la ruta: llegada, demora, equipo_iniciar | equipo_pausar | equipo_reanudar, variables, ensayos, cabecera, evidencia, jornada, gasto, otro.
--   - Idempotente: el mismo usuario, la misma ruta y la misma hora de captura se guardan una sola vez (un reenvío no duplica).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarEnvioDiferidoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarEnvioDiferidoMovil(
    IN p_id_usuario    BIGINT,
    IN p_metodo        VARCHAR(6),
    IN p_ruta          VARCHAR(200),
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_capturado_utc DATETIME,
    IN p_motivo        VARCHAR(30),
    IN p_intentos      INT
)
proc: BEGIN
    DECLARE v_ahora    DATETIME;
    DECLARE v_captura  DATETIME;
    DECLARE v_tipo     VARCHAR(30);
    DECLARE v_motivo   VARCHAR(30);
    DECLARE v_ruta     VARCHAR(200);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_ahora = UTC_TIMESTAMP();

    IF IFNULL(p_id_usuario, 0) <= 0 OR p_capturado_utc IS NULL OR IFNULL(TRIM(p_ruta), '') = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Datos insuficientes para registrar el envío.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_captura = LEAST(p_capturado_utc, v_ahora);
    IF v_captura < DATE_SUB(v_ahora, INTERVAL 30 DAY) THEN
        SELECT 2 AS IdTipoMensaje, 'Envío ignorado: la hora de captura es demasiado antigua.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ruta   = LOWER(LEFT(TRIM(p_ruta), 200));
    SET v_motivo = IF(LOWER(TRIM(IFNULL(p_motivo, ''))) IN ('sin_senal', 'servidor_no_disponible', 'otro'), LOWER(TRIM(p_motivo)),
                      IF(IFNULL(TRIM(p_motivo), '') = '', 'sin_senal', 'otro'));
    SET v_tipo = CASE
        WHEN v_ruta LIKE '%/llegada%'               THEN 'llegada'
        WHEN v_ruta LIKE '%/demoras%'               THEN 'demora'
        WHEN v_ruta LIKE '%/equipos/%/iniciar'      THEN 'equipo_iniciar'
        WHEN v_ruta LIKE '%/equipos/%/pausar'       THEN 'equipo_pausar'
        WHEN v_ruta LIKE '%/equipos/%/reanudar'     THEN 'equipo_reanudar'
        WHEN v_ruta LIKE '%/variables-ambientales%' THEN 'variables'
        WHEN v_ruta LIKE '%/ensayos%'               THEN 'ensayos'
        WHEN v_ruta LIKE '%/cabecera-informe%'      THEN 'cabecera'
        WHEN v_ruta LIKE '%/evidencias%'            THEN 'evidencia'
        WHEN v_ruta LIKE '%/jornada/%'              THEN 'jornada'
        WHEN v_ruta LIKE '%/viaticos/gastos%'       THEN 'gasto'
        ELSE 'otro'
    END;

    IF EXISTS (SELECT 1 FROM envio_diferido_movil e
               WHERE e.id_usuario = p_id_usuario AND e.ruta = v_ruta AND e.capturado_utc = v_captura) THEN
        SELECT 2 AS IdTipoMensaje, 'Envío ya registrado.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO envio_diferido_movil (id_usuario, id_os, id_os_equipo, tipo, metodo, ruta, capturado_utc, recibido_utc, retraso_seg, motivo, intentos)
    VALUES (p_id_usuario, NULLIF(p_id_os, 0), NULLIF(p_id_os_equipo, 0), v_tipo, UPPER(LEFT(IFNULL(p_metodo, ''), 6)), v_ruta, v_captura, v_ahora,
            GREATEST(0, TIMESTAMPDIFF(SECOND, v_captura, v_ahora)), v_motivo, LEAST(99, GREATEST(0, IFNULL(p_intentos, 0))));

    SELECT 2 AS IdTipoMensaje, 'Envío registrado.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_ListarEnviosDiferidosMovil  (App móvil sin señal — trazabilidad · solo lectura)
-- Lista los registros que la app envió tarde (sin señal) de un servicio, del más reciente al más antiguo. La usan la app de Jefatura (Seguimiento del servicio) y la intranet
-- (Seguimiento Operativo / detalle del servicio). Con p_id_os_equipo se limita a ese equipo. Máximo 200 filas.
-- Las horas salen en hora de Lima. retraso_seg = cuánto pasó entre que el técnico lo tomó y que llegó al servidor.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 envíos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ListarEnviosDiferidosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ListarEnviosDiferidosMovil(
    IN p_id_os     BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT e.id_envio, e.id_usuario,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS tecnico,
           e.id_os, e.id_os_equipo, e.tipo, e.metodo,
           CONVERT_TZ(e.capturado_utc, '+00:00', '-05:00') AS capturado_en,
           CONVERT_TZ(e.recibido_utc,  '+00:00', '-05:00') AS recibido_en,
           e.retraso_seg, e.motivo, e.intentos
    FROM   envio_diferido_movil e
    LEFT JOIN usuario u ON u.id_usuario = e.id_usuario
    WHERE  e.id_os = p_id_os
      AND  (IFNULL(p_id_os_equipo, 0) = 0 OR e.id_os_equipo = p_id_os_equipo)
    ORDER BY e.capturado_utc DESC, e.id_envio DESC
    LIMIT 200;
END$$

DELIMITER ;

-- Verificación (solo lectura, no crea nada): los 3 valores deben ser 1, 2 y 0
SELECT 'Tabla envio_diferido_movil (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'envio_diferido_movil') AS valor
UNION ALL
SELECT 'Procedimientos nuevos (deben ser 2)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME IN ('SP_RegistrarEnvioDiferidoMovil', 'SP_ListarEnviosDiferidosMovil'))
UNION ALL
SELECT 'Registros enviados tarde guardados hasta ahora (debe ser 0 al aplicar)',
       (SELECT COUNT(*) FROM envio_diferido_movil);
