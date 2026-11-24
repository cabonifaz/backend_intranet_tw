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
