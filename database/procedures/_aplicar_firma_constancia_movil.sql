-- Aplicar en la base (Firma de informes y constancia de servicio HU-17 de la app móvil). Incluye la migración 105. Sin datos de prueba.
-- Ejecutar completo con Alt+X. NO subir al repositorio. Después REINICIAR la API.
-- ORDEN: aplica ANTES el script de la HU-15 / HU-16 (informe_tecnico: numero_informe, generado_en y responsable_*) y el de los correlativos (HU-14 / HU-34:
--   informe_tecnico.numero_certificado), y DESPUÉS este. Si falta algo, el script se detiene con un mensaje claro y no cambia nada.
-- Qué hace: crea os_firma_responsable y os_constancia, 3 parámetros en tabla_maestra y 10 procedimientos. NO modifica ningún procedimiento existente.

-- ############################################################
-- 0) Requisitos
-- ############################################################
DROP PROCEDURE IF EXISTS tmp_hu17_requisitos;
DELIMITER $$
CREATE PROCEDURE tmp_hu17_requisitos()
BEGIN
    IF (SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
          AND COLUMN_NAME IN ('numero_informe', 'generado_en', 'responsable_nombre', 'responsable_cargo', 'responsable_telefono')) < 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes el script de la HU-15 / HU-16 (informe_tecnico: numero_informe, generado_en, responsable_*).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'numero_certificado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes _aplicar_correlativos_movil.sql (HU-14 / HU-34: informe_tecnico.numero_certificado).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe el catálogo PARAMETRO_PROGRAMACION en tabla_maestra.';
    END IF;
END$$
DELIMITER ;
CALL tmp_hu17_requisitos();
DROP PROCEDURE IF EXISTS tmp_hu17_requisitos;

-- ############################################################
-- 1) Migración 105
-- ############################################################
-- ============================================================
-- Migración 105 — Firma de informes y constancia de servicio para la app móvil (App Mobile HU-17)
--   El técnico hace firmar los informes técnicos generados (HU-15 / HU-16) a sus RESPONSABLES ("Quién atiende en planta": informe_tecnico.responsable_*),
--   y la constancia de servicio al cliente. La firma del dispositivo se guarda como TRAZOS normalizados (JSON, puntos de 0 a 1) más su hash; no hay imagen.
--   1. os_firma_responsable: una fila por responsable y OS (UNIQUE id_os + clave). modo = dispositivo (trazos) · fisico (foto del formato en papel) ·
--      ausente (cliente ausente: queda constancia de la aceptación tácita, la firma sigue pendiente). "Editar firma" actualiza la fila (version + 1) y la
--      anterior queda en auditoria_evento.
--   2. os_constancia: una fila por OS: firma del cliente (dispositivo o formato físico), cuándo se generó, cuándo se cerró el servicio, el PDF y el envío.
--   3. Parámetros (tabla_maestra PARAMETRO_PROGRAMACION, columna Num2): FIRMA_ACEPTACION_TACITA_HORAS (48), FIRMA_SIMILITUD_MAXIMA_PCT (90: una firma igual o
--      más parecida que esto a la de OTRO responsable de la misma OS se rechaza) y CONSTANCIA_ENVIO_CORREO (0 = no envía correos; 1 = envía la constancia al cliente).
--   Requiere la migración de la HU-15 (informe_tecnico: numero_informe, generado_en, responsable_*). No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. os_firma_responsable ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_firma_responsable (
    id_firma         BIGINT        NOT NULL AUTO_INCREMENT,
    id_os            BIGINT        NOT NULL,
    clave            CHAR(32)      NOT NULL,
    nombre           VARCHAR(150)  NOT NULL,
    cargo            VARCHAR(100)  NULL,
    telefono         VARCHAR(30)   NULL,
    modo             ENUM('dispositivo','fisico','ausente') NOT NULL,
    trazos           JSON          NULL,
    hash_firma       CHAR(64)      NULL,
    nombre_firmante  VARCHAR(150)  NULL,
    ruta_foto        VARCHAR(300)  NULL,
    motivo           VARCHAR(300)  NULL,
    version          INT           NOT NULL DEFAULT 1,
    firmado_en       DATETIME      NOT NULL,
    firmado_por      BIGINT        NOT NULL,
    -- AUDITORÍA
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    PRIMARY KEY (id_firma),
    UNIQUE KEY ux_firma_os_clave (id_os, clave)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. os_constancia ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_constancia (
    id_constancia    BIGINT        NOT NULL AUTO_INCREMENT,
    id_os            BIGINT        NOT NULL,
    modo             ENUM('dispositivo','fisico') NULL,
    firmante_nombre  VARCHAR(150)  NULL,
    trazos           JSON          NULL,
    hash_firma       CHAR(64)      NULL,
    ruta_foto        VARCHAR(300)  NULL,
    firmado_en       DATETIME      NULL,
    firmado_por      BIGINT        NULL,
    generada_en      DATETIME      NULL,
    generada_por     BIGINT        NULL,
    cerrada_en       DATETIME      NULL,
    ruta_pdf         VARCHAR(300)  NULL,
    envio_estado     ENUM('en_espera','enviado','error','desactivado','sin_correo') NOT NULL DEFAULT 'en_espera',
    envio_destino    VARCHAR(200)  NULL,
    envio_en         DATETIME      NULL,
    envio_detalle    VARCHAR(300)  NULL,
    -- AUDITORÍA
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    PRIMARY KEY (id_constancia),
    UNIQUE KEY ux_constancia_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Parámetros ──────────────────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @num_param := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', @num_param + v.n, v.valor, v.texto, v.codigo
FROM (SELECT 1 AS n, 48 AS valor, 'Horas de aceptación tácita de los informes desde que se genera el primero (HU-17)' AS texto, 'FIRMA_ACEPTACION_TACITA_HORAS' AS codigo
      UNION ALL SELECT 2, 90, 'Similitud máxima (%) entre las firmas de responsables distintos de una misma orden (HU-17)', 'FIRMA_SIMILITUD_MAXIMA_PCT'
      UNION ALL SELECT 3, 0,  'Enviar la constancia de servicio al correo del cliente al cerrar (1 = sí, 0 = no)', 'CONSTANCIA_ENVIO_CORREO') v
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.String2 = v.codigo);



-- ############################################################
-- 2) SP_ContextoFirmaMovil
-- ############################################################
-- ============================================================
-- SP_ContextoFirmaMovil  (App Mobile HU-17 — apoyo, NO es un endpoint)
-- Valida, UNA sola vez, que el técnico pueda firmar los informes y la constancia de una OS: el servicio es suyo (técnico principal o personal de apoyo) y no está anulado.
--   p_mensaje trae el texto para el técnico cuando algo lo impide (lo demás queda NULL). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoFirmaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoFirmaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_id_os      BIGINT,
    OUT p_mensaje    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET p_mensaje = NULL, p_numero_os = NULL;
    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SET p_mensaje = 'Servicio no encontrado.';
    ELSE
        SELECT os.estado, os.numero INTO v_estado, p_numero_os
        FROM   orden_servicio os
        WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
        IF v_estado IS NULL THEN
            SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
        ELSEIF v_estado = 'anulada' THEN
            SET p_mensaje = 'El servicio está anulado.';
        END IF;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 3) SP_ArmarFirmasOsMovil
-- ############################################################
-- ============================================================
-- SP_ArmarFirmasOsMovil  (App Mobile HU-17 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, el estado de firmas de los informes técnicos de una OS en dos tablas temporales (quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf, tmp_fm_resp):
--   tmp_fm_inf  : un informe por equipo de la OS (os_equipo con equipo): numero_informe, equipo, código, completo (informe GENERADO — HU-15/HU-16 — y con el
--                 responsable "Quién atiende en planta"), motivo del INCOMPLETO, responsable (nombre, cargo, teléfono), clave y si está firmado.
--   tmp_fm_resp : los RESPONSABLES distintos (clave = MD5 de nombre y cargo en minúsculas) de los informes completos, con sus informes, su firma
--                 (dispositivo / fisico / ausente), la hora, los trazos y si está "resuelto" (firmado, o cliente ausente con el plazo de aceptación tácita vencido).
--   Aceptación tácita: plazo = FIRMA_ACEPTACION_TACITA_HORAS (48 por defecto) desde que se generó el PRIMER informe (informe_tecnico.generado_en, UTC);
--   p_segundos = lo que queda (0 si ya venció; NULL si no hay informes generados).
--   Listo (p_listo = 1) = hay informes, TODOS completos y TODOS los responsables resueltos.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarFirmasOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarFirmasOsMovil(
    IN  p_id_os    BIGINT,
    OUT p_horas    INT,
    OUT p_vence    DATETIME,
    OUT p_segundos INT,
    OUT p_n_inf    INT,
    OUT p_n_comp   INT,
    OUT p_n_firm   INT,
    OUT p_n_resp   INT,
    OUT p_n_ok     INT,
    OUT p_listo    TINYINT
)
BEGIN
    DECLARE v_primero DATETIME DEFAULT NULL;
    DECLARE v_ahora   DATETIME DEFAULT UTC_TIMESTAMP();

    SELECT IFNULL(MAX(m.Num2), 48) INTO p_horas
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'FIRMA_ACEPTACION_TACITA_HORAS' AND m.eliminado_en IS NULL;
    IF p_horas < 1 OR p_horas > 720 THEN SET p_horas = 48; END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    CREATE TEMPORARY TABLE tmp_fm_inf (
        n              INT NOT NULL AUTO_INCREMENT,
        id_os_equipo   BIGINT,
        id_equipo      BIGINT,
        id_informe     BIGINT NULL,
        numero_informe VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        equipo         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_equipo  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        completo       TINYINT NOT NULL DEFAULT 0,
        motivo         VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resp_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resp_cargo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resp_telefono  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        clave          CHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        generado_en    DATETIME NULL,
        firmado        TINYINT NOT NULL DEFAULT 0,
        PRIMARY KEY (n)
    );

    INSERT INTO tmp_fm_inf (id_os_equipo, id_equipo, id_informe, numero_informe, equipo, codigo_equipo, completo, motivo, resp_nombre, resp_cargo, resp_telefono, clave, generado_en)
    SELECT oe.id, oe.id_equipo, it.id_informe, it.numero_informe,
           LEFT(COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion), 200), COALESCE(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw),
           IF(it.id_informe IS NOT NULL AND NULLIF(TRIM(it.responsable_nombre), '') IS NOT NULL, 1, 0),
           CASE WHEN it.id_informe IS NULL THEN 'Falta finalizar el trabajo en el equipo (HU-16)'
                WHEN NULLIF(TRIM(it.responsable_nombre), '') IS NULL THEN 'Falta «Quién atiende en planta» en la cabecera del informe'
                ELSE NULL END,
           NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(it.responsable_cargo), ''), NULLIF(TRIM(it.responsable_telefono), ''),
           IF(it.id_informe IS NOT NULL AND NULLIF(TRIM(it.responsable_nombre), '') IS NOT NULL,
              MD5(CONCAT(LOWER(TRIM(it.responsable_nombre)), '|', LOWER(TRIM(IFNULL(it.responsable_cargo, ''))))), NULL),
           it.generado_en
    FROM   os_equipo oe
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN informe_tecnico it ON it.id_informe = (SELECT MAX(x.id_informe) FROM informe_tecnico x
                                                     WHERE x.id_os = oe.id_os AND x.id_equipo = oe.id_equipo AND x.eliminado_en IS NULL AND x.generado_en IS NOT NULL)
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_equipo IS NOT NULL
    ORDER BY oe.id;

    -- Aceptación tácita: desde el primer informe generado
    SELECT MIN(i.generado_en) INTO v_primero FROM tmp_fm_inf i WHERE i.completo = 1;
    SET p_vence = IF(v_primero IS NULL, NULL, v_primero + INTERVAL p_horas HOUR);
    SET p_segundos = IF(p_vence IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(SECOND, v_ahora, p_vence)));

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    CREATE TEMPORARY TABLE tmp_fm_resp (
        clave        CHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        nombre       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        telefono     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        n_informes   INT NOT NULL DEFAULT 0,
        informes     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        modo         VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        firmado      TINYINT NOT NULL DEFAULT 0,
        ausente      TINYINT NOT NULL DEFAULT 0,
        resuelto     TINYINT NOT NULL DEFAULT 0,
        firmado_en   DATETIME NULL,
        firmante     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        trazos       JSON NULL,
        PRIMARY KEY (clave)
    );
    INSERT INTO tmp_fm_resp (clave, nombre, cargo, telefono, n_informes, informes)
    SELECT i.clave, MIN(i.resp_nombre), MIN(i.resp_cargo), MIN(i.resp_telefono), COUNT(*),
           LEFT(GROUP_CONCAT(i.numero_informe ORDER BY i.numero_informe SEPARATOR ' · '), 300)
    FROM   tmp_fm_inf i
    WHERE  i.completo = 1
    GROUP BY i.clave;

    UPDATE tmp_fm_resp r
    JOIN   os_firma_responsable f ON f.id_os = p_id_os AND f.clave = r.clave
    SET    r.modo = f.modo, r.firmado = IF(f.modo IN ('dispositivo', 'fisico'), 1, 0), r.ausente = IF(f.modo = 'ausente', 1, 0),
           r.firmado_en = f.firmado_en, r.firmante = f.nombre_firmante, r.motivo = f.motivo, r.trazos = f.trazos;
    UPDATE tmp_fm_resp SET resuelto = IF(firmado = 1 OR (ausente = 1 AND IFNULL(p_segundos, 1) = 0), 1, 0);
    UPDATE tmp_fm_inf i JOIN tmp_fm_resp r ON r.clave = i.clave SET i.firmado = r.firmado;

    SELECT COUNT(*), IFNULL(SUM(completo), 0), IFNULL(SUM(firmado), 0) INTO p_n_inf, p_n_comp, p_n_firm FROM tmp_fm_inf;
    SELECT COUNT(*), IFNULL(SUM(resuelto), 0) INTO p_n_resp, p_n_ok FROM tmp_fm_resp;
    SET p_listo = IF(p_n_inf > 0 AND p_n_comp = p_n_inf AND p_n_resp > 0 AND p_n_ok = p_n_resp, 1, 0);
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_ObtenerFirmasMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerFirmasMovil  (App Mobile HU-17 — "Lista de informes" · solo lectura)
-- El técnico ve los informes técnicos de su OS y quién debe firmar cada uno. El estado de firmas lo arma, una sola vez, SP_ArmarFirmasOsMovil.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 informes (uno por equipo) · 4 responsables (con sus trazos, para el "Firmados · Editar firma").
--   Cabecera: plazo_horas y segundos_restantes de la aceptación tácita (desde el primer informe generado; NULL sin informes) · tacita_activa (hay plazo corriendo y
--     algo pendiente) · informes (total) · completos · firmados · responsables · resueltos · listo (todo completo y resuelto) · constancia_firmada ·
--     constancia_generada · cerrado (servicio cerrado).
--   Informe: estado COMPLETO (generado, con responsable) o INCOMPLETO con su motivo; firma pendiente | firmado | ausente.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFirmasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFirmasMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_c_firma DATETIME DEFAULT NULL; DECLARE v_c_gen DATETIME DEFAULT NULL; DECLARE v_c_cierre DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    SELECT c.firmado_en, c.generada_en, c.cerrada_en INTO v_c_firma, v_c_gen, v_c_cierre FROM os_constancia c WHERE c.id_os = p_id_os;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os AS id_os, v_num AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente,
           v_horas AS plazo_horas, v_seg AS segundos_restantes,
           IF(v_seg IS NOT NULL AND v_seg > 0 AND v_ok < v_resp, 1, 0) AS tacita_activa,
           v_inf AS informes, v_comp AS completos, v_firm AS firmados, v_resp AS responsables, v_ok AS resueltos, v_listo AS listo,
           IF(v_c_firma IS NULL, 0, 1) AS constancia_firmada, IF(v_c_gen IS NULL, 0, 1) AS constancia_generada, IF(v_c_cierre IS NULL, 0, 1) AS cerrado
    FROM   orden_servicio os LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os;

    SELECT i.id_os_equipo AS id_os_equipo, i.id_informe AS id_informe, i.numero_informe AS numero_informe, i.equipo AS equipo, i.codigo_equipo AS codigo_equipo,
           i.completo AS completo, i.motivo AS motivo, i.resp_nombre AS responsable, i.resp_cargo AS cargo, i.resp_telefono AS telefono, i.clave AS clave,
           IF(i.completo = 0, 'incompleto', IF(i.firmado = 1, 'firmado', IF(r.ausente = 1, 'ausente', 'pendiente'))) AS firma,
           CONVERT_TZ(r.firmado_en, '+00:00', '-05:00') AS firmado_en
    FROM   tmp_fm_inf i LEFT JOIN tmp_fm_resp r ON r.clave = i.clave
    ORDER BY i.n;

    SELECT r.clave AS clave, r.nombre AS nombre, r.cargo AS cargo, r.telefono AS telefono, r.n_informes AS n_informes, r.informes AS informes,
           IF(r.firmado = 1, 'firmado', IF(r.ausente = 1, 'ausente', 'pendiente')) AS firma, r.modo AS modo, r.resuelto AS resuelto,
           CONVERT_TZ(r.firmado_en, '+00:00', '-05:00') AS firmado_en, r.firmante AS firmante, r.motivo AS motivo, CAST(r.trazos AS CHAR) AS trazos
    FROM   tmp_fm_resp r
    ORDER BY r.nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
END$$

DELIMITER ;

-- ############################################################
-- 5) SP_ObtenerFirmasComparablesMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerFirmasComparablesMovil  (App Mobile HU-17 — apoyo del caso de uso, solo lectura)
-- Lo que necesita el servicio de similitud antes de aceptar una firma por dispositivo: el umbral (FIRMA_SIMILITUD_MAXIMA_PCT, 90 por defecto) y las firmas
-- por dispositivo YA registradas en la misma OS por OTROS responsables (nombre y trazos). La comparación la hace el servicio .NET ComparadorFirmas.
-- Resultados: 1 mensaje · 2 umbral (1 fila) · 3 firmas de otros responsables.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFirmasComparablesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFirmasComparablesMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_umbral INT DEFAULT 90;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT IFNULL(MAX(m.Num2), 90) INTO v_umbral
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'FIRMA_SIMILITUD_MAXIMA_PCT' AND m.eliminado_en IS NULL;
    IF v_umbral < 50 OR v_umbral > 100 THEN SET v_umbral = 90; END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_umbral AS umbral_pct;
    SELECT f.nombre AS nombre, CAST(f.trazos AS CHAR) AS trazos
    FROM   os_firma_responsable f
    WHERE  f.id_os = p_id_os AND f.clave <> IFNULL(p_clave, '') AND f.modo = 'dispositivo' AND f.trazos IS NOT NULL
    ORDER BY f.id_firma;
END$$

DELIMITER ;

-- ############################################################
-- 6) SP_GuardarFirmaResponsableMovil
-- ############################################################
-- ============================================================
-- SP_GuardarFirmaResponsableMovil  (App Mobile HU-17 — "Confirmar firma" / "Cliente ausente" / "Formato físico" / "Editar firma")
-- Registra la firma de UN responsable para TODOS sus informes completos de la OS (una sola firma por responsable y OS; "Editar firma" la reemplaza y la anterior
-- queda en auditoria_evento). El estado (responsables, informes completos, plazo) lo arma SP_ArmarFirmasOsMovil, una sola vez.
--   p_modo = dispositivo : p_trazos (JSON de trazos normalizados, ≤ 30 000 caracteres) y p_hash (SHA-256 en hexadecimal). La regla "firmas iguales entre responsables
--                          distintos" la aplica el caso de uso .NET (ComparadorFirmas) ANTES de llamar a este SP.
--            fisico      : p_ruta_foto (foto del formato en papel, guardada por el caso de uso) y p_nombre (quien firmó, 3 a 150 caracteres).
--            ausente     : "Cliente ausente": deja constancia de la aceptación tácita (quién, cuándo y p_motivo de 5 a 300 caracteres); la firma sigue PENDIENTE y el
--                          plazo de aceptación tácita corre. No se puede usar si el responsable ya firmó.
--   Orden de bloqueos: orden_servicio → firma del responsable. Auditoría: auditoria_evento (entidad os_firma_responsable).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) firma, responsables, resueltos, firmados (informes), listo, cierre_listo
--   (todo resuelto + constancia firmada y generada y el servicio aún sin cerrar: el caso de uso genera el PDF y registra el cierre), ruta_foto_anterior.
-- Requiere la migración 105 y la de la HU-15.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarFirmaResponsableMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarFirmaResponsableMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(32)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modo       VARCHAR(12)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_trazos     MEDIUMTEXT    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_hash       VARCHAR(64)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre     VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_foto  VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo     VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_lock   BIGINT DEFAULT NULL;
    DECLARE v_nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cargo  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tel    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_firmado TINYINT DEFAULT 0;
    DECLARE v_ninf   INT DEFAULT 0;
    DECLARE v_modo_ant  VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hash_ant  CHAR(64) DEFAULT NULL;
    DECLARE v_foto_ant  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_firma_ant DATETIME DEFAULT NULL;
    DECLARE v_ahora  DATETIME DEFAULT UTC_TIMESTAMP();
    DECLARE v_c_firma DATETIME DEFAULT NULL; DECLARE v_c_gen DATETIME DEFAULT NULL; DECLARE v_c_cierre DATETIME DEFAULT NULL;
    DECLARE v_cierre TINYINT DEFAULT 0;
    DECLARE v_texto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_modo = LOWER(TRIM(IFNULL(p_modo, '')));
    SET p_nombre = NULLIF(TRIM(IFNULL(p_nombre, '')), '');
    SET p_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF IFNULL(p_clave, '') NOT REGEXP '^[0-9a-f]{32}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El responsable no es válido.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo NOT IN ('dispositivo', 'fisico', 'ausente') THEN
        SELECT 1 AS IdTipoMensaje, 'La forma de firma no es válida.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'dispositivo' AND (p_trazos IS NULL OR CHAR_LENGTH(p_trazos) < 20 OR CHAR_LENGTH(p_trazos) > 30000 OR NOT JSON_VALID(p_trazos)
                                      OR IFNULL(p_hash, '') NOT REGEXP '^[0-9a-f]{64}$') THEN
        SELECT 1 AS IdTipoMensaje, 'Dibuja la firma del responsable.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'fisico' AND (NULLIF(TRIM(IFNULL(p_ruta_foto, '')), '') IS NULL OR p_nombre IS NULL OR CHAR_LENGTH(p_nombre) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto del formato físico e indica el nombre de quien firmó.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'ausente' AND (p_motivo IS NULL OR CHAR_LENGTH(p_motivo) < 5) THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo por el que el responsable está ausente (mínimo 5 caracteres).' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os FOR UPDATE;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    SELECT r.nombre, r.cargo, r.telefono, r.firmado, r.n_informes INTO v_nombre, v_cargo, v_tel, v_firmado, v_ninf FROM tmp_fm_resp r WHERE r.clave = p_clave;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    IF v_nombre IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese responsable no tiene informes generados en este servicio.' AS Mensaje; LEAVE proc;
    ELSEIF p_modo = 'ausente' AND v_firmado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_nombre, ' ya firmó sus informes.') AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM os_constancia c WHERE c.id_os = p_id_os AND c.cerrada_en IS NOT NULL) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya está cerrado: no se pueden cambiar las firmas.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.modo, f.hash_firma, f.ruta_foto, f.firmado_en INTO v_modo_ant, v_hash_ant, v_foto_ant, v_firma_ant
    FROM   os_firma_responsable f WHERE f.id_os = p_id_os AND f.clave = p_clave FOR UPDATE;

    INSERT INTO os_firma_responsable (id_os, clave, nombre, cargo, telefono, modo, trazos, hash_firma, nombre_firmante, ruta_foto, motivo, firmado_en, firmado_por, creado_por)
    VALUES (p_id_os, p_clave, v_nombre, v_cargo, v_tel, p_modo, IF(p_modo = 'dispositivo', p_trazos, NULL), IF(p_modo = 'dispositivo', p_hash, NULL),
            IF(p_modo = 'fisico', p_nombre, NULL), IF(p_modo = 'fisico', p_ruta_foto, NULL), IF(p_modo = 'ausente', p_motivo, NULL), v_ahora, p_id_usuario, p_id_usuario)
    ON DUPLICATE KEY UPDATE modo = VALUES(modo), trazos = VALUES(trazos), hash_firma = VALUES(hash_firma), nombre_firmante = VALUES(nombre_firmante),
                            ruta_foto = VALUES(ruta_foto), motivo = VALUES(motivo), firmado_en = VALUES(firmado_en), firmado_por = VALUES(firmado_por),
                            modificado_por = p_id_usuario, version = version + 1;

    SET v_texto = CASE p_modo WHEN 'dispositivo' THEN CONCAT('Firma por dispositivo de ', v_nombre, IF(v_modo_ant IS NULL, '.', ' (reemplaza la firma anterior).'))
                              WHEN 'fisico'      THEN CONCAT('Formato físico firmado por ', p_nombre, ' (responsable ', v_nombre, ').')
                              ELSE CONCAT('Cliente ausente: ', v_nombre, ' · aceptación tácita. Motivo: ', p_motivo) END;
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_firma_responsable', p_id_os, IF(v_modo_ant IS NULL, 'firmar_informes', 'editar_firma'), v_modo_ant, p_modo, LEFT(CONCAT(v_texto, ' ', v_num), 900), p_id_usuario, NOW(),
            JSON_OBJECT('clave', p_clave, 'responsable', v_nombre, 'modo', p_modo, 'hash_nuevo', p_hash, 'hash_anterior', v_hash_ant, 'firmado_anterior_en', v_firma_ant));

    -- Estado después de firmar (una sola regla: SP_ArmarFirmasOsMovil)
    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    SELECT c.firmado_en, c.generada_en, c.cerrada_en INTO v_c_firma, v_c_gen, v_c_cierre FROM os_constancia c WHERE c.id_os = p_id_os;
    SET v_cierre = IF(v_listo = 1 AND v_c_firma IS NOT NULL AND v_c_gen IS NOT NULL AND v_c_cierre IS NULL, 1, 0);
    COMMIT;

    SELECT 2 AS IdTipoMensaje, CASE p_modo WHEN 'ausente' THEN CONCAT('Cliente ausente registrado para ', v_nombre, ': la firma sigue pendiente.')
                                           ELSE CONCAT('Firma de ', v_nombre, ' registrada para ', v_ninf, IF(v_ninf = 1, ' informe.', ' informes.')) END AS Mensaje;
    SELECT IF(p_modo = 'ausente', 'ausente', 'firmado') AS firma, v_resp AS responsables, v_ok AS resueltos, v_firm AS firmados, v_listo AS listo, v_cierre AS cierre_listo,
           v_foto_ant AS ruta_foto_anterior;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_ObtenerConstanciaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerConstanciaMovil  (App Mobile HU-17 — "Constancia de servicio", "Falta una firma" y "Servicio cerrado" · solo lectura)
-- Datos de la constancia de una OS del técnico. El estado de firmas de los informes lo arma SP_ArmarFirmasOsMovil (una sola vez).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 equipos intervenidos (los informes completos) · 4 responsables que faltan firmar.
--   Cabecera: cliente, dirección fiscal, contacto en planta (nombre, cargo, teléfono, correo), RQ, OS, fecha (Lima) y el resumen de informes (firmados de N) ·
--     la firma del cliente (modo, quién firmó, cuándo, trazos; foto = hay formato físico) · generada_en · cerrada_en · envío (en_espera | enviado | error |
--     desactivado | sin_correo, a qué correo y cuándo) · puede_generar (hay firma del cliente y al menos un informe completo) · envio_activo (parámetro
--     CONSTANCIA_ENVIO_CORREO = 1: el caso de uso envía la constancia al correo del contacto al cerrar el servicio).
--   Equipo: marca, modelo, serie, capacidad, d y e (división mínima y de verificación), ubicación, procedencia (variables ambientales HU-09) y el certificado
--     del informe (informe_tecnico.numero_certificado, HU-14).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConstanciaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os AS id_os, v_num AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente, c.direccion_fiscal AS direccion,
           cc.nombres AS contacto_nombre, cc.cargo AS contacto_cargo, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono, NULLIF(TRIM(cc.correo), '') AS contacto_correo,
           (SELECT rq.numero FROM expediente_digital ed JOIN requerimiento rq ON rq.id_requerimiento = ed.id_requerimiento WHERE ed.id_expediente = os.id_expediente LIMIT 1) AS numero_rq,
           DATE_FORMAT(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'), '%Y-%m-%d') AS fecha,
           v_inf AS informes, v_comp AS completos, v_firm AS firmados, v_resp AS responsables, v_ok AS resueltos,
           k.modo AS modo, k.firmante_nombre AS firmante, CONVERT_TZ(k.firmado_en, '+00:00', '-05:00') AS firmado_en, CAST(k.trazos AS CHAR) AS trazos,
           IF(k.ruta_foto IS NULL, 0, 1) AS tiene_foto,
           IF(k.firmado_en IS NULL, 0, 1) AS firmada, CONVERT_TZ(k.generada_en, '+00:00', '-05:00') AS generada_en, CONVERT_TZ(k.cerrada_en, '+00:00', '-05:00') AS cerrada_en,
           IFNULL(k.envio_estado, 'en_espera') AS envio_estado, k.envio_destino AS envio_destino, CONVERT_TZ(k.envio_en, '+00:00', '-05:00') AS envio_en, k.envio_detalle AS envio_detalle,
           IF(k.firmado_en IS NOT NULL AND v_comp > 0 AND k.cerrada_en IS NULL, 1, 0) AS puede_generar,
           IF(IFNULL((SELECT MAX(m.Num2) FROM tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CONSTANCIA_ENVIO_CORREO' AND m.eliminado_en IS NULL), 0) = 1, 1, 0) AS envio_activo
    FROM   orden_servicio os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = os.id_contacto AND cc.SoftDelete = 0
    LEFT JOIN os_constancia k ON k.id_os = os.id_os
    WHERE  os.id_os = p_id_os;

    SELECT e.equipo AS equipo, ec.marca AS marca, ec.modelo AS modelo, NULLIF(TRIM(ec.num_serie), '') AS serie, ec.alcance_maximo AS capacidad,
           ec.division_minima AS d, ec.division_verif AS e, NULLIF(ec.ubicacion_especifica, '') AS ubicacion, e.codigo_equipo AS codigo,
           (SELECT va.procedencia FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = e.id_equipo AND va.eliminado_en IS NULL ORDER BY va.id_variable DESC LIMIT 1) AS procedencia,
           it.numero_certificado AS certificado
    FROM   tmp_fm_inf e
    JOIN   equipo_cliente ec ON ec.id_equipo = e.id_equipo
    LEFT JOIN informe_tecnico it ON it.id_informe = e.id_informe
    WHERE  e.completo = 1
    ORDER BY e.n;

    SELECT r.nombre AS nombre, r.cargo AS cargo, r.informes AS informes
    FROM   tmp_fm_resp r WHERE r.resuelto = 0 ORDER BY r.nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_GuardarConstanciaMovil
-- ############################################################
-- ============================================================
-- SP_GuardarConstanciaMovil  (App Mobile HU-17 — firma del cliente, formato físico y "Generar constancia")
-- Una fila por OS (os_constancia). El estado de los informes lo arma SP_ArmarFirmasOsMovil (una sola vez). Se necesita al menos un informe completo.
--   p_accion = firma   : firma del cliente por dispositivo (p_trazos ≤ 30 000 caracteres + p_hash SHA-256) y p_nombre (quien firmó, 3 a 150).
--              fisico  : foto del formato en papel (p_ruta_foto, guardada por el caso de uso) y p_nombre (quien firmó). Es OPCIONAL: se suma a la firma del cliente.
--              generar : "Generar constancia": exige la firma del cliente; deja la constancia generada (una sola vez).
--   Con el servicio ya cerrado no se cambia nada. Orden de bloqueos: orden_servicio → constancia. Auditoría: auditoria_evento (entidad os_constancia).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) generada, listo (todos los informes completos y los responsables resueltos),
--   cierre_listo (listo + firmada + generada y sin cerrar: el caso de uso genera el PDF y registra el cierre), ruta_foto_anterior.
-- Requiere la migración 105 y la de la HU-15.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarConstanciaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_trazos     MEDIUMTEXT   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_hash       VARCHAR(64)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_foto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_lock   BIGINT DEFAULT NULL;
    DECLARE v_firmada DATETIME DEFAULT NULL; DECLARE v_gen DATETIME DEFAULT NULL; DECLARE v_cierre DATETIME DEFAULT NULL;
    DECLARE v_foto_ant VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora  DATETIME DEFAULT UTC_TIMESTAMP();
    DECLARE v_texto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cierre_listo TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_accion = LOWER(TRIM(IFNULL(p_accion, '')));
    SET p_nombre = NULLIF(TRIM(IFNULL(p_nombre, '')), '');
    IF p_accion NOT IN ('firma', 'fisico', 'generar') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción de la constancia no es válida.' AS Mensaje; LEAVE proc;
    ELSEIF p_accion = 'firma' AND (p_trazos IS NULL OR CHAR_LENGTH(p_trazos) < 20 OR CHAR_LENGTH(p_trazos) > 30000 OR NOT JSON_VALID(p_trazos)
                                   OR IFNULL(p_hash, '') NOT REGEXP '^[0-9a-f]{64}$' OR p_nombre IS NULL OR CHAR_LENGTH(p_nombre) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'El cliente debe firmar e indicar su nombre.' AS Mensaje; LEAVE proc;
    ELSEIF p_accion = 'fisico' AND (NULLIF(TRIM(IFNULL(p_ruta_foto, '')), '') IS NULL OR p_nombre IS NULL OR CHAR_LENGTH(p_nombre) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto del formato físico e indica el nombre de quien firmó.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os FOR UPDATE;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    IF v_comp = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Aún no hay informes técnicos generados en este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT IGNORE INTO os_constancia (id_os, creado_por) VALUES (p_id_os, p_id_usuario);
    SELECT k.firmado_en, k.generada_en, k.cerrada_en, k.ruta_foto INTO v_firmada, v_gen, v_cierre, v_foto_ant FROM os_constancia k WHERE k.id_os = p_id_os FOR UPDATE;
    IF v_cierre IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya está cerrado: la constancia no se puede cambiar.' AS Mensaje; LEAVE proc;
    END IF;

    IF p_accion = 'firma' THEN
        UPDATE os_constancia SET modo = 'dispositivo', firmante_nombre = p_nombre, trazos = p_trazos, hash_firma = p_hash, firmado_en = v_ahora, firmado_por = p_id_usuario,
               modificado_por = p_id_usuario WHERE id_os = p_id_os;
        SET v_firmada = v_ahora, v_texto = CONCAT('Firma del cliente (', p_nombre, ') por dispositivo.');
    ELSEIF p_accion = 'fisico' THEN
        UPDATE os_constancia SET ruta_foto = p_ruta_foto, firmante_nombre = p_nombre, firmado_en = IFNULL(firmado_en, v_ahora), firmado_por = IFNULL(firmado_por, p_id_usuario),
               modo = IF(trazos IS NULL, 'fisico', modo), modificado_por = p_id_usuario WHERE id_os = p_id_os;
        SET v_firmada = IFNULL(v_firmada, v_ahora), v_texto = CONCAT('Formato físico de la constancia firmado por ', p_nombre, '.');
    ELSE
        IF v_firmada IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Primero el cliente debe firmar la constancia.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_gen IS NULL THEN
            UPDATE os_constancia SET generada_en = v_ahora, generada_por = p_id_usuario, modificado_por = p_id_usuario WHERE id_os = p_id_os;
            SET v_gen = v_ahora;
        END IF;
        SET v_texto = 'Constancia de servicio generada.';
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_constancia', p_id_os, CONCAT('constancia_', p_accion), NULL, p_accion, LEFT(CONCAT(v_texto, ' ', v_num), 900), p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'hash', p_hash, 'firmante', p_nombre));

    SET v_cierre_listo = IF(v_listo = 1 AND v_firmada IS NOT NULL AND v_gen IS NOT NULL, 1, 0);
    COMMIT;

    SELECT 2 AS IdTipoMensaje, v_texto AS Mensaje;
    SELECT IF(v_gen IS NULL, 0, 1) AS generada, v_listo AS listo, v_cierre_listo AS cierre_listo, IF(p_accion = 'fisico', v_foto_ant, NULL) AS ruta_foto_anterior;
END$$

DELIMITER ;

-- ############################################################
-- 9) SP_RegistrarCierreConstanciaMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarCierreConstanciaMovil  (App Mobile HU-17 — "Servicio cerrado")
-- Lo llama el caso de uso cuando TODO está listo (informes completos y con sus responsables resueltos, constancia firmada y generada): ya generó el PDF de la
-- constancia (p_ruta_pdf) y, si el parámetro CONSTANCIA_ENVIO_CORREO = 1 y el correo está configurado, intentó enviarla al contacto del cliente. Aquí solo se
-- PERSISTE el cierre (os_constancia.cerrada_en, ruta del PDF y resultado del envío) revalidando la regla con SP_ArmarFirmasOsMovil. Idempotente: si ya estaba cerrado
-- devuelve éxito sin cambiar nada.
--   NO cambia orden_servicio.estado: no existe una regla de cierre iniciada por el técnico (la finalización la registra Seguimiento Operativo, HU-53 / Jefatura).
--   p_envio_estado: en_espera | enviado | error | desactivado | sin_correo.   Auditoría: auditoria_evento (entidad os_constancia, acción cierre_servicio).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) cerrado, cerrada_en (hora de Lima).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarCierreConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarCierreConstanciaMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_os          BIGINT,
    IN p_ruta_pdf       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_envio_estado   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_envio_destino  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_envio_detalle  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_lock   BIGINT DEFAULT NULL;
    DECLARE v_firmada DATETIME DEFAULT NULL; DECLARE v_gen DATETIME DEFAULT NULL; DECLARE v_cierre DATETIME DEFAULT NULL;
    DECLARE v_ahora  DATETIME DEFAULT UTC_TIMESTAMP();

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_envio_estado, '') NOT IN ('en_espera', 'enviado', 'error', 'desactivado', 'sin_correo') THEN
        SELECT 1 AS IdTipoMensaje, 'El estado del envío no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os FOR UPDATE;
    SELECT k.firmado_en, k.generada_en, k.cerrada_en INTO v_firmada, v_gen, v_cierre FROM os_constancia k WHERE k.id_os = p_id_os FOR UPDATE;
    IF v_cierre IS NOT NULL THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'El servicio ya estaba cerrado.' AS Mensaje;
        SELECT 1 AS cerrado, CONVERT_TZ(v_cierre, '+00:00', '-05:00') AS cerrada_en;
        LEAVE proc;
    END IF;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    IF v_firmada IS NULL OR v_gen IS NULL OR v_listo = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Todavía falta una firma o la constancia: el servicio no se puede cerrar.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE os_constancia SET cerrada_en = v_ahora, ruta_pdf = p_ruta_pdf, envio_estado = p_envio_estado, envio_destino = NULLIF(TRIM(p_envio_destino), ''),
           envio_en = IF(p_envio_estado = 'enviado', v_ahora, NULL), envio_detalle = LEFT(NULLIF(TRIM(p_envio_detalle), ''), 300), modificado_por = p_id_usuario
    WHERE  id_os = p_id_os;
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_constancia', p_id_os, 'cierre_servicio', NULL, 'cerrado',
            LEFT(CONCAT('Servicio ', v_num, ' cerrado: ', v_firm, ' informe(s) firmado(s) y constancia firmada. Envío: ', p_envio_estado, '.'), 900), p_id_usuario, NOW(),
            JSON_OBJECT('envio_estado', p_envio_estado, 'envio_destino', p_envio_destino, 'pdf', p_ruta_pdf));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Servicio cerrado.' AS Mensaje;
    SELECT 1 AS cerrado, CONVERT_TZ(v_ahora, '+00:00', '-05:00') AS cerrada_en;
END$$

DELIMITER ;

-- ############################################################
-- 10) SP_ObtenerArchivoConstanciaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerArchivoConstanciaMovil  (App Mobile HU-17 — descarga del PDF o de la foto del formato físico · solo lectura)
-- Ruta interna del archivo de la constancia de una OS del técnico. p_tipo = pdf | foto.
-- Resultados: 1 mensaje · 2 (solo éxito) ruta.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoConstanciaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tipo       VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg  VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ruta VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    IF IFNULL(p_tipo, '') NOT IN ('pdf', 'foto') THEN
        SELECT 1 AS IdTipoMensaje, 'El archivo pedido no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    SELECT IF(p_tipo = 'pdf', k.ruta_pdf, k.ruta_foto) INTO v_ruta FROM os_constancia k WHERE k.id_os = p_id_os;
    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La constancia todavía no tiene ese archivo.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;

-- ############################################################
-- 11) SP_ResumenFirmasOsMovil
-- ############################################################
-- ============================================================
-- SP_ResumenFirmasOsMovil  (App Mobile HU-17 — acceso "Firma de informes" en el menú de la orden · solo lectura, ligero)
-- Cuántos informes técnicos tiene la OS (completos, es decir generados) y cuántos están firmados, y si el servicio ya está cerrado. La regla de firmas es la de
-- SP_ArmarFirmasOsMovil (una sola vez). Resultados: 1 mensaje · 2 (solo éxito) informes, completos, firmados, resueltos, responsables, cerrado.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResumenFirmasOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResumenFirmasOsMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_cierre DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    SELECT k.cerrada_en INTO v_cierre FROM os_constancia k WHERE k.id_os = p_id_os;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_inf AS informes, v_comp AS completos, v_firm AS firmados, v_ok AS resueltos, v_resp AS responsables, IF(v_cierre IS NULL, 0, 1) AS cerrado;
END$$

DELIMITER ;


-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Los 10 procedimientos con la fecha/hora de hoy (deben ser 10)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ContextoFirmaMovil', 'SP_ArmarFirmasOsMovil', 'SP_ObtenerFirmasMovil', 'SP_ObtenerFirmasComparablesMovil',
      'SP_GuardarFirmaResponsableMovil', 'SP_ObtenerConstanciaMovil', 'SP_GuardarConstanciaMovil', 'SP_RegistrarCierreConstanciaMovil', 'SP_ObtenerArchivoConstanciaMovil',
      'SP_ResumenFirmasOsMovil')
ORDER BY ROUTINE_NAME;

-- B) Migración 105 (debe ser 5: 2 tablas + 3 parámetros)
SELECT 'Migración 105 (debe ser 5)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('os_firma_responsable', 'os_constancia'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 IN ('FIRMA_ACEPTACION_TACITA_HORAS', 'FIRMA_SIMILITUD_MAXIMA_PCT', 'CONSTANCIA_ENVIO_CORREO')) AS valor;

-- C) Validaciones: solo responden un mensaje de regla de negocio, NO escriben nada
CALL SP_ObtenerFirmasMovil(0, 0);                                                   -- "Servicio no encontrado."
CALL SP_GuardarFirmaResponsableMovil(0, 0, 'x', 'x', NULL, NULL, NULL, NULL, NULL);  -- "El responsable no es válido."
CALL SP_GuardarConstanciaMovil(0, 0, 'otra', NULL, NULL, NULL, NULL);               -- "La acción de la constancia no es válida."
CALL SP_RegistrarCierreConstanciaMovil(0, 0, NULL, 'otro', NULL, NULL);             -- "El estado del envío no es válido."
CALL SP_ObtenerArchivoConstanciaMovil(0, 0, 'otro');                                -- "El archivo pedido no es válido."

-- D) Una OS real y su técnico: lista de informes, constancia y resumen (solo lectura). Si no hay informes generados, los informes salen INCOMPLETOS.
SET @os  = (SELECT id_os FROM orden_servicio WHERE eliminado_en IS NULL AND estado <> 'anulada' AND id_tecnico_principal IS NOT NULL ORDER BY id_os DESC LIMIT 1);
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
SELECT @os AS id_os, @tec AS tecnico;
CALL SP_ObtenerFirmasMovil(@tec, @os);          -- 1 mensaje · 2 cabecera · 3 informes · 4 responsables
CALL SP_ObtenerConstanciaMovil(@tec, @os);      -- 1 mensaje · 2 cabecera · 3 equipos · 4 faltan firmar
CALL SP_ResumenFirmasOsMovil(@tec, @os);
