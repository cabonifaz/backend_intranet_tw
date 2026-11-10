-- Aplicar en la base (Correlativos de Metrología HU-14 técnico + HU-34 Jefe de Metrología de la app móvil). Incluye la migración 103. Sin datos de prueba.
-- Ejecutar completo con Alt+X. NO subir al repositorio. Después REINICIAR la API.
-- ORDEN: aplica antes _aplicar_jefatura_menu_movil.sql (HU-28) y _aplicar_panel_campo_movil.sql (HU-29 / HU-30: SP_ResolverJefaturaMovil) y DESPUÉS este script.
--   No vuelvas a ejecutar esos scripts después de este: dejarían SP_ObtenerNotificacionesMovil sin los tipos de correlativo.
-- Requiere (ya existentes): la migración 102_centro_notificaciones (notificacion.prioridad / archivado), SP_ContextoEquipoMovil (HU-10), SP_ResolverJefaturaMovil (HU-29 / HU-30),
--   informe_tecnico con los ensayos de la HU-10 (migración 100) y la tabla ticket_metrologia (migración 01).
-- Qué hace: crea correlativo_metrologia y correlativo_secuencia, agrega columnas a ticket_metrologia e informe_tecnico, el catálogo TIPO_CERTIFICADO_MET y el parámetro
--   CORRELATIVO_RESERVA_DIARIA; crea 11 procedimientos y actualiza SP_ObtenerTrabajoEquipoMovil (etapa 5 real) y SP_ObtenerNotificacionesMovil (tipos de correlativo).

-- ############################################################
-- 0) Requisitos
-- ############################################################
DROP PROCEDURE IF EXISTS tmp_hu14_requisitos;
DELIMITER $$
CREATE PROCEDURE tmp_hu14_requisitos()
BEGIN
    IF (SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME IN ('prioridad', 'archivado', 'tipo_notificacion')) < 3 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes la migración 102_centro_notificaciones.sql (HU-90).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ResolverJefaturaMovil') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes _aplicar_panel_campo_movil.sql (HU-29 / HU-30): SP_ResolverJefaturaMovil.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ContextoEquipoMovil') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes _aplicar_ensayos_movil.sql (HU-10): SP_ContextoEquipoMovil.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'ensayos_finalizado_en') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes la migración 100_ensayos_calibracion_movil.sql (HU-10).';
    END IF;
END$$
DELIMITER ;
CALL tmp_hu14_requisitos();
DROP PROCEDURE IF EXISTS tmp_hu14_requisitos;

-- ############################################################
-- 1) Migración 103
-- ############################################################
-- ============================================================
-- Migración 103 — Correlativos de Metrología para la app móvil (App Mobile HU-14 técnico / HU-34 Jefe de Metrología)
--   El técnico pide un correlativo de certificación desde "Correlativo y certificado" (ticket TK-MET-#####), el Jefe de Metrología lo asigna
--   (CC-####-AAAA) y el técnico lo usa como N° de certificado del informe técnico. Cada técnico de Metrología tiene además una reserva diaria
--   de correlativos para trabajar sin conexión.
--   1. ticket_metrologia (ya existía, nada la llenaba): + id_equipo, id_tipo_certificado, id_correlativo, usado_en; numero único; índice del ticket abierto.
--   2. correlativo_metrologia: cada correlativo emitido (asignado a un ticket · reservado a un técnico · usado de la reserva). (anio, numero) y codigo únicos.
--   3. correlativo_secuencia: último número emitido por año (UNA sola secuencia para tickets y reservas). Arranca en el mayor CC-####-AAAA que ya
--      exista en certificados o tickets del año (orden_metrologia.numero_certificado / ticket_metrologia.correlativo_asignado); si no hay ninguno, en 0.
--   4. informe_tecnico.numero_certificado: el N° de certificado / constancia que forma parte del informe técnico.
--   5. Catálogo TIPO_CERTIFICADO_MET (tipos de certificado de la solicitud) y parámetro CORRELATIVO_RESERVA_DIARIA (2 por técnico).
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. ticket_metrologia ───────────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'id_equipo'),
    'ALTER TABLE ticket_metrologia ADD COLUMN id_equipo BIGINT NULL AFTER id_om', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'id_tipo_certificado'),
    'ALTER TABLE ticket_metrologia ADD COLUMN id_tipo_certificado INT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'id_correlativo'),
    'ALTER TABLE ticket_metrologia ADD COLUMN id_correlativo BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'usado_en'),
    'ALTER TABLE ticket_metrologia ADD COLUMN usado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND INDEX_NAME = 'ux_ticket_met_numero'),
    'ALTER TABLE ticket_metrologia ADD UNIQUE KEY ux_ticket_met_numero (numero)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND INDEX_NAME = 'ix_ticket_met_equipo'),
    'ALTER TABLE ticket_metrologia ADD KEY ix_ticket_met_equipo (id_os, id_equipo, estado)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. correlativo_metrologia ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS correlativo_metrologia (
    id_correlativo  BIGINT       NOT NULL AUTO_INCREMENT,
    anio            SMALLINT     NOT NULL,
    numero          INT          NOT NULL,
    codigo          VARCHAR(20)  NOT NULL,
    -- asignado = dado por Metrología a un ticket · reservado = reserva diaria libre de un técnico · usado = reservado que el técnico ya usó (por confirmar)
    estado          ENUM('asignado','reservado','usado') NOT NULL,
    id_ticket_met   BIGINT       NULL,
    id_tecnico      BIGINT       NULL,
    fecha_reserva   DATETIME     NULL,
    id_os           BIGINT       NULL,
    id_equipo       BIGINT       NULL,
    usado_en        DATETIME     NULL,
    -- AUDITORÍA
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT       NULL,
    modificado_en   DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT       NULL,
    eliminado_en    DATETIME     NULL,
    eliminado_por   BIGINT       NULL,
    PRIMARY KEY (id_correlativo),
    UNIQUE KEY ux_correlativo_anio_numero (anio, numero),
    UNIQUE KEY ux_correlativo_codigo (codigo),
    KEY ix_correlativo_estado (estado, id_tecnico)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. correlativo_secuencia ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS correlativo_secuencia (
    anio            SMALLINT     NOT NULL,
    ultimo          INT          NOT NULL DEFAULT 0,
    modificado_en   DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (anio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @anio := YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
INSERT INTO correlativo_secuencia (anio, ultimo)
SELECT @anio, (SELECT IFNULL(MAX(CAST(SUBSTRING(x.cod, 4, 4) AS UNSIGNED)), 0)
               FROM (SELECT om.numero_certificado AS cod FROM orden_metrologia om
                     WHERE om.numero_certificado REGEXP '^CC-[0-9]{4}-[0-9]{4}$' AND RIGHT(om.numero_certificado, 4) = CAST(@anio AS CHAR)
                     UNION ALL
                     SELECT t.correlativo_asignado FROM ticket_metrologia t
                     WHERE t.correlativo_asignado REGEXP '^CC-[0-9]{4}-[0-9]{4}$' AND RIGHT(t.correlativo_asignado, 4) = CAST(@anio AS CHAR)) x)
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM correlativo_secuencia s WHERE s.anio = @anio);

-- ── 4. informe_tecnico.numero_certificado ──────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'numero_certificado'),
    'ALTER TABLE informe_tecnico ADD COLUMN numero_certificado VARCHAR(50) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 5. Catálogo de tipos de certificado y parámetro de la reserva diaria ───────────────────
SET @id_cat := COALESCE((SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_CERTIFICADO_MET'),
                        (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_cat, 'TIPO_CERTIFICADO_MET', v.n, v.nombre, v.codigo
FROM (SELECT 1 AS n, 'Calibración con pesas' AS nombre, 'calibracion_pesas' AS codigo
      UNION ALL SELECT 2, 'Certificado de calibración', 'certificado_calibracion'
      UNION ALL SELECT 3, 'Constancia de verificación',  'constancia_verificacion') v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'TIPO_CERTIFICADO_MET' AND t.IdEmpresa = 1 AND t.Num1 = v.n);

SET @id_param  := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @num_param := (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', @num_param, 2,
       'Correlativos reservados por técnico de Metrología cada día (para trabajar sin conexión)', 'CORRELATIVO_RESERVA_DIARIA'
FROM DUAL
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'CORRELATIVO_RESERVA_DIARIA');

-- ############################################################
-- 2) SP_SiguienteCorrelativoMovil
-- ############################################################
-- ============================================================
-- SP_SiguienteCorrelativoMovil  (App Mobile HU-14 / HU-34 — apoyo, NO es un endpoint)
-- El siguiente correlativo de certificación CC-####-AAAA disponible, de la ÚNICA secuencia (correlativo_secuencia) que usan los tickets y las reservas.
-- Año = el de Lima (UTC-5). Salta los números ya emitidos (correlativo_metrologia). Quien consume lo hace dentro de su transacción.
--   p_consumir = 0 → solo sugiere (no escribe, no bloquea).
--   p_consumir = 1 → bloquea la fila del año (FOR UPDATE), deja la secuencia en ese número y devuelve el código; quien llama lo inserta en correlativo_metrologia
--                    antes del COMMIT. Con el año agotado (9999) devuelve NULL.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SiguienteCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_SiguienteCorrelativoMovil(
    IN  p_consumir TINYINT,
    OUT p_numero   INT,
    OUT p_codigo   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_anio     SMALLINT
)
BEGIN
    DECLARE v_ultimo INT DEFAULT 0;

    SET p_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    IF p_consumir = 1 THEN
        INSERT IGNORE INTO correlativo_secuencia (anio, ultimo) VALUES (p_anio, 0);
        SELECT s.ultimo INTO v_ultimo FROM correlativo_secuencia s WHERE s.anio = p_anio FOR UPDATE;
    ELSE
        SELECT IFNULL(MAX(s.ultimo), 0) INTO v_ultimo FROM correlativo_secuencia s WHERE s.anio = p_anio;
    END IF;

    SET p_numero = v_ultimo + 1;
    WHILE p_numero <= 9999 AND EXISTS (SELECT 1 FROM correlativo_metrologia c WHERE c.anio = p_anio AND c.numero = p_numero) DO
        SET p_numero = p_numero + 1;
    END WHILE;

    IF p_numero > 9999 THEN
        SET p_numero = NULL;
        SET p_codigo = NULL;
    ELSE
        SET p_codigo = CONCAT('CC-', LPAD(p_numero, 4, '0'), '-', p_anio);
        IF p_consumir = 1 THEN
            UPDATE correlativo_secuencia SET ultimo = p_numero WHERE anio = p_anio;
        END IF;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 3) SP_ArmarJefesMetrologiaMovil
-- ############################################################
-- ============================================================
-- SP_ArmarJefesMetrologiaMovil  (App Mobile HU-14 / HU-34 — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_jm_jefes` (id_usuario) a quienes atienden los correlativos: los usuarios activos cuyo menú de Jefatura es del área de Metrología
-- (la MISMA regla de SP_ResolverJefaturaMovil: cargo "Jefe de …" con área Metrología, o supervisor / administrador con área Metrología). A ellos les llega
-- el aviso de una solicitud nueva. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarJefesMetrologiaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarJefesMetrologiaMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes;
    CREATE TEMPORARY TABLE tmp_jm_jefes (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));

    INSERT INTO tmp_jm_jefes (id_usuario)
    SELECT u.id_usuario
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
      AND  IF(u.cargo LIKE 'jefe\_%',
              COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
              IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> '', u.area, NULL)) = 'metrologia';
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_ArmarTecnicosMetrologiaMovil
-- ############################################################
-- ============================================================
-- SP_ArmarTecnicosMetrologiaMovil  (App Mobile HU-34 — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_tm_tec` (id_usuario, nombre) a los técnicos de Metrología que reciben la reserva diaria de correlativos: usuarios activos del
-- área Metrología sin jefaturas ni asistentes (la MISMA regla de técnico que el contador "Mi Equipo" del menú de Jefatura, SP_ObtenerMenuJefaturaMovil).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarTecnicosMetrologiaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarTecnicosMetrologiaMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
    CREATE TEMPORARY TABLE tmp_tm_tec (
        id_usuario BIGINT NOT NULL,
        nombre     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id_usuario));

    INSERT INTO tmp_tm_tec (id_usuario, nombre)
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
    FROM   usuario u
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'metrologia'
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'));
END$$

DELIMITER ;

-- ############################################################
-- 5) SP_ContextoCorrelativoMovil
-- ############################################################
-- ============================================================
-- SP_ContextoCorrelativoMovil  (App Mobile HU-14 — apoyo, NO es un endpoint)
-- Valida y arma, UNA sola vez, el contexto del técnico para pedir / usar el correlativo de un equipo: la OS es suya, Hard Stop de llegada y equipo iniciado
-- (SP_ContextoEquipoMovil), los datos del equipo y el estado de su informe técnico. Deja UNA fila en la tabla temporal `tmp_cc_ctx` (quien la llame debe
-- terminar con DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx). `mensaje` trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL).
--   tipo_orden: según la RQ, servicio técnico → OS, metrología → OM (igual que SP_ObtenerTrabajoEquipoMovil).
--   ens_final: cuándo se finalizaron los ensayos (HU-10). resultado: Conforme / No conforme (resultado_global que deja HU-10) o NULL.
--   tecnico_metrologia: el técnico recibe la reserva diaria de correlativos (SP_ArmarTecnicosMetrologiaMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoCorrelativoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_est_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_area     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_rq       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_global   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert     VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_critico  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_serie    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_clase    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_alcance  VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_es_tec   TINYINT DEFAULT 0;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);

    IF v_msg IS NULL THEN
        SELECT asr.area_usuario, rq.numero INTO v_area, v_rq
        FROM   orden_servicio os
        JOIN   expediente_digital ed  ON ed.id_expediente = os.id_expediente
        JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq asr ON asr.id_area_rq = rq.id_area
        WHERE  os.id_os = p_id_os LIMIT 1;

        SELECT it.id_informe, it.ensayos_finalizado_en, it.resultado_global, it.numero_certificado, it.error_critico_motivo
        INTO   v_informe, v_final, v_global, v_cert, v_critico
        FROM   informe_tecnico it
        WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
        ORDER BY it.id_informe DESC LIMIT 1;

        SELECT ec.num_serie, ec.codigo_cliente, ec.codigo_tw, ec.clase_exactitud, ec.alcance_maximo
        INTO   v_serie, v_cod_cli, v_cod_tw, v_clase, v_alcance
        FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq LIMIT 1;

        CALL SP_ArmarTecnicosMetrologiaMovil();
        SELECT COUNT(*) INTO v_es_tec FROM tmp_tm_tec WHERE id_usuario = p_id_usuario;
        DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
    CREATE TEMPORARY TABLE tmp_cc_ctx (
        mensaje VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        id_os BIGINT, id_os_equipo BIGINT, id_equipo BIGINT, numero_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre_equipo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, numero INT, estado_equipo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        habilitado TINYINT, tipo_orden VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_informe BIGINT NULL, ens_final DATETIME NULL, resultado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        numero_certificado VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        num_serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_tw VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, clase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        capacidad VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, tecnico_metrologia TINYINT);

    INSERT INTO tmp_cc_ctx
    VALUES (v_msg, p_id_os, p_id_os_equipo, v_id_eq, v_num_os, v_nombre, v_numero, v_est_eq, v_hab, IF(v_area = 'metrologia', 'OM', 'OS'), v_rq,
            v_informe, v_final,
            IF(v_final IS NULL, NULL, IF(v_global = 'fuera' OR v_critico IS NOT NULL, 'No conforme', 'Conforme')),
            v_cert, v_serie, v_cod_cli, v_cod_tw, v_clase, v_alcance, v_es_tec);
END$$

DELIMITER ;

-- ############################################################
-- 6) SP_ObtenerSolicitudCorrelativoMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerSolicitudCorrelativoMovil  (App Mobile HU-14 — "Solicitud de correlativo" y modal "Correlativo y certificado" · solo lectura)
-- Todo lo que necesita el técnico para pedir o usar el correlativo de UN equipo de su OS. El contexto (OS suya, Hard Stop, equipo iniciado) lo valida
-- SP_ContextoCorrelativoMovil, una sola vez. No escribe nada (la reserva diaria se genera con SP_GenerarReservaCorrelativosMovil).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 tipos de certificado · 4 correlativo asignado listo para usar (0 o 1 fila) · 5 reserva libre del técnico.
--   Cabecera: orden, equipo, serie, código, COD TW, clase y capacidad (equipo_cliente), tipo_orden (OS · Servicio técnico / OM · Metrología según la RQ),
--     puede_solicitar (en ejecución, ensayos finalizados, sin ticket abierto y sin certificado) y motivo_bloqueo con el texto cuando no se puede,
--     ticket_abierto_* (el ticket solicitado o asignado de este equipo), numero_certificado (el ya guardado en el informe), tecnico_metrologia (recibe reserva).
--   Correlativo asignado: el ticket de este equipo en estado asignado que aún no se usó (asignado por quién y cuándo, hora de Lima).
--   Reserva libre: los correlativos reservados al técnico que todavía no usó.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerSolicitudCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSolicitudCorrelativoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_final     DATETIME DEFAULT NULL;
    DECLARE v_cert      VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_id     BIGINT DEFAULT NULL;
    DECLARE v_tk_num    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_puede     TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ContextoCorrelativoMovil(p_id_usuario, p_id_os, p_id_os_equipo);
    SELECT c.mensaje, c.id_equipo, c.estado_equipo, c.habilitado, c.ens_final, c.numero_certificado
    INTO   v_msg, v_id_eq, v_estado, v_hab, v_final, v_cert
    FROM   tmp_cc_ctx c LIMIT 1;
    IF v_msg IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT t.id_ticket_met, t.numero, t.estado INTO v_tk_id, v_tk_num, v_tk_estado
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_eq AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;

    IF v_cert IS NOT NULL THEN
        SET v_motivo = CONCAT('Este equipo ya tiene el certificado ', v_cert, '.');
    ELSEIF v_hab = 0 OR v_estado <> 'en_ejecucion' THEN
        SET v_motivo = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para solicitar el correlativo.',
                          IF(v_estado = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso.'));
    ELSEIF v_final IS NULL THEN
        SET v_motivo = 'Primero finaliza los ensayos y la calibración del equipo.';
    ELSEIF v_tk_id IS NOT NULL THEN
        SET v_motivo = CONCAT('Ya hay un ticket abierto para este equipo (', v_tk_num, ').');
    END IF;
    SET v_puede = IF(v_motivo IS NULL, 1, 0);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 Cabecera
    SELECT c.id_os, c.numero_os, c.id_os_equipo, c.nombre_equipo AS equipo, c.numero, c.num_serie, c.codigo_cliente, c.codigo_tw, c.clase, c.capacidad,
           c.tipo_orden, c.numero_rq, c.resultado,
           v_puede AS puede_solicitar, v_motivo AS motivo_bloqueo,
           v_tk_id AS ticket_abierto_id, v_tk_num AS ticket_abierto_numero, v_tk_estado AS ticket_abierto_estado,
           c.numero_certificado, c.tecnico_metrologia
    FROM   tmp_cc_ctx c;

    -- 3 Tipos de certificado
    SELECT m.Num1 AS id_tipo, m.String1 AS nombre
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'TIPO_CERTIFICADO_MET' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    -- 4 Correlativo asignado y todavía sin usar
    SELECT t.id_ticket_met AS id_ticket, t.numero AS ticket, t.correlativo_asignado AS correlativo,
           CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00') AS asignado_en,
           TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))) AS asignado_por
    FROM   ticket_metrologia t
    LEFT JOIN usuario j ON j.id_usuario = t.id_metrologo_asignado
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_eq AND t.estado = 'asignado' AND t.eliminado_en IS NULL
      AND  t.id_tecnico_solicitante = p_id_usuario
    ORDER BY t.id_ticket_met DESC LIMIT 1;

    -- 5 Reserva libre del técnico
    SELECT c.codigo AS correlativo
    FROM   correlativo_metrologia c
    WHERE  c.id_tecnico = p_id_usuario AND c.estado = 'reservado' AND c.eliminado_en IS NULL
    ORDER BY c.anio, c.numero;

    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_SolicitarCorrelativoMovil
-- ############################################################
-- ============================================================
-- SP_SolicitarCorrelativoMovil  (App Mobile HU-14 — "Solicitar correlativo")
-- El técnico pide a Metrología el correlativo de certificación de UN equipo de su OS. Crea el ticket TK-MET-##### (ticket_metrologia, estado solicitado).
--   Reglas (el contexto lo valida SP_ContextoCorrelativoMovil, una sola vez): la OS es suya, Hard Stop de llegada, equipo EN EJECUCIÓN, ensayos finalizados
--   (HU-10), el equipo aún sin certificado y sin otro ticket abierto (solicitado o asignado). Observación opcional de hasta 300 caracteres.
--   Se serializa por equipo bloqueando su informe técnico; luego el ticket. Avisos (notificacion, canal 5): al técnico "Solicitud de correlativo enviada" y a los
--   jefes de Metrología (SP_ArmarJefesMetrologiaMovil) "Solicitud de correlativo". Auditoría: auditoria_evento (entidad ticket_metrologia).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_ticket, numero, estado, solicitado_en (hora de Lima), notificados.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarCorrelativoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_tipo      INT,
    IN p_observacion  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_cert     VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_eq   VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_obs      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dup_num  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ticket   BIGINT DEFAULT NULL;
    DECLARE v_numero   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora    DATETIME;
    DECLARE v_jefes    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no válido.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT m.String1 INTO v_tipo
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'TIPO_CERTIFICADO_MET' AND m.IdEmpresa = 1 AND m.Num1 = p_id_tipo AND m.eliminado_en IS NULL LIMIT 1;
    IF IFNULL(p_id_tipo, 0) <= 0 OR v_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el tipo de certificado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_obs = NULLIF(TRIM(IFNULL(p_observacion, '')), '');
    IF CHAR_LENGTH(v_obs) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'La observación puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoCorrelativoMovil(p_id_usuario, p_id_os, p_id_os_equipo);
    SELECT c.mensaje, c.id_equipo, c.estado_equipo, c.habilitado, c.numero_os, c.id_informe, c.ens_final, c.numero_certificado, COALESCE(c.codigo_cliente, c.codigo_tw)
    INTO   v_msg, v_id_eq, v_estado, v_hab, v_num_os, v_informe, v_final, v_cert, v_cod_eq
    FROM   tmp_cc_ctx c LIMIT 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;

    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para solicitar el correlativo.',
                       IF(v_estado = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso.'));
    ELSEIF v_msg IS NULL AND (v_informe IS NULL OR v_final IS NULL) THEN
        SET v_msg = 'Primero finaliza los ensayos y la calibración del equipo.';
    ELSEIF v_msg IS NULL AND v_cert IS NOT NULL THEN
        SET v_msg = CONCAT('Este equipo ya tiene el certificado ', v_cert, '.');
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Se serializa por equipo (su informe técnico) para no crear dos tickets a la vez
    SELECT it.id_informe INTO v_informe FROM informe_tecnico it WHERE it.id_informe = v_informe FOR UPDATE;
    SELECT t.numero INTO v_dup_num
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_eq AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1 FOR UPDATE;
    IF v_dup_num IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('Ya hay un ticket abierto para este equipo (', v_dup_num, ').') AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    INSERT INTO ticket_metrologia (numero, id_os, id_equipo, id_tecnico_solicitante, id_tipo_certificado, estado, notas, fecha_solicitud, creado_por)
    VALUES (CONCAT('TMP-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, p_id_tipo, 'solicitado', v_obs, v_ahora, p_id_usuario);
    SET v_ticket = LAST_INSERT_ID();
    SET v_numero = CONCAT('TK-MET-', LPAD(v_ticket, 5, '0'));
    UPDATE ticket_metrologia SET numero = v_numero WHERE id_ticket_met = v_ticket;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('ticket_metrologia', v_ticket, 'solicitar_correlativo', NULL, 'solicitado',
            LEFT(CONCAT(v_nombre, ' solicitó el correlativo del equipo ', IFNULL(v_cod_eq, ''), ' (', v_num_os, '). Tipo: ', v_tipo, '.'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('ticket', v_numero, 'id_os', p_id_os, 'id_equipo', v_id_eq, 'id_tipo_certificado', p_id_tipo, 'observacion', v_obs));

    -- Avisos: a los jefes de Metrología y la confirmación al técnico
    CALL SP_ArmarJefesMetrologiaMovil();
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT j.id_usuario, 5, 'Solicitud de correlativo',
           LEFT(CONCAT(v_nombre, ' solicita un correlativo · ', v_numero, ' · ', v_num_os, ' · ', IFNULL(v_cod_eq, ''), ' · ', v_tipo), 500),
           'ticket_metrologia', v_ticket, NOW(), p_id_usuario
    FROM   tmp_jm_jefes j WHERE j.id_usuario <> p_id_usuario;
    SET v_jefes = ROW_COUNT();
    DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de correlativo enviada',
            CONCAT(v_numero, IF(v_jefes > 0, ' · avisado al supervisor de Metrología', ' · en espera de Metrología')),
            'ticket_metrologia', v_ticket, NOW(), p_id_usuario);

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Solicitud enviada · ticket ', v_numero, ' creado.') AS Mensaje;
    SELECT v_ticket AS id_ticket, v_numero AS numero, 'solicitado' AS estado, CONVERT_TZ(v_ahora, '+00:00', '-05:00') AS solicitado_en, v_jefes AS notificados;
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_ObtenerTicketsCorrelativoMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerTicketsCorrelativoMovil  (App Mobile HU-14 — "Mis tickets" · solo lectura)
-- Los tickets de correlativo que pidió el técnico que inició sesión (el id sale del token), del más reciente al más antiguo (máx. 50).
--   p_filtro: todos (por defecto) · pendientes (solicitados) · asignados (asignados y ya usados).   p_id_os: solo los de esa OS (NULL / 0 = todos).
--   estado del ticket: solicitado → "Pendiente" · asignado → "Asignado" · despachado → asignado y ya usado en el certificado (usado = 1).
--   Línea de tiempo: solicitado_en (hora de Lima) y asignado_en / asignado_por cuando Metrología lo asignó.
--   id_os_equipo = el objetivo (os_equipo) de ese equipo en la OS, para abrir "Correlativo y certificado".  puede_usar = asignado, sin usar y el informe del equipo aún
--   sin certificado.
-- Resultados: 1 mensaje · 2 tickets.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTicketsCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTicketsCorrelativoMovil(
    IN p_id_usuario BIGINT,
    IN p_filtro     VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_filtro VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_filtro = IFNULL(NULLIF(TRIM(p_filtro), ''), 'todos');
    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_filtro NOT IN ('todos', 'pendientes', 'asignados') THEN
        SELECT 1 AS IdTipoMensaje, 'El filtro de tickets no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.id_ticket_met AS id_ticket, t.numero AS numero, t.estado AS estado, IF(t.estado = 'despachado', 1, 0) AS usado,
           t.id_os AS id_os, os.numero AS numero_os, oe.id AS id_os_equipo,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion) AS equipo, COALESCE(ec.codigo_cliente, ec.codigo_tw) AS codigo_equipo, ec.num_serie AS num_serie,
           t.id_tipo_certificado AS id_tipo, tc.String1 AS tipo_certificado, t.notas AS observacion,
           CONVERT_TZ(t.fecha_solicitud, '+00:00', '-05:00') AS solicitado_en,
           TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))) AS solicitante,
           t.correlativo_asignado AS correlativo,
           CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00') AS asignado_en,
           TRIM(CONCAT(IFNULL(uj.nombre, ''), ' ', IFNULL(uj.apellido, ''))) AS asignado_por,
           IF(t.estado = 'asignado'
              AND (SELECT it.numero_certificado FROM informe_tecnico it
                   WHERE it.id_os = t.id_os AND it.id_equipo = t.id_equipo AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1) IS NULL, 1, 0) AS puede_usar
    FROM   ticket_metrologia t
    JOIN   orden_servicio os ON os.id_os = t.id_os
    LEFT JOIN os_equipo oe ON oe.id_os = t.id_os AND oe.id_equipo = t.id_equipo AND oe.eliminado_en IS NULL
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = t.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc ON tc.Descripcion = 'TIPO_CERTIFICADO_MET' AND tc.IdEmpresa = 1 AND tc.Num1 = t.id_tipo_certificado
    LEFT JOIN usuario ut ON ut.id_usuario = t.id_tecnico_solicitante
    LEFT JOIN usuario uj ON uj.id_usuario = t.id_metrologo_asignado
    WHERE  t.id_tecnico_solicitante = p_id_usuario AND t.eliminado_en IS NULL AND t.estado <> 'cancelado'
      AND  (IFNULL(p_id_os, 0) <= 0 OR t.id_os = p_id_os)
      AND  (v_filtro = 'todos'
            OR (v_filtro = 'pendientes' AND t.estado = 'solicitado')
            OR (v_filtro = 'asignados'  AND t.estado IN ('asignado', 'despachado')))
    ORDER BY t.fecha_solicitud DESC, t.id_ticket_met DESC
    LIMIT 50;
END$$

DELIMITER ;

-- ############################################################
-- 9) SP_GuardarCertificadoMovil
-- ############################################################
-- ============================================================
-- SP_GuardarCertificadoMovil  (App Mobile HU-14 — "Correlativo y certificado" → Guardar; marca el correlativo como USADO)
-- Guarda el N° de certificado / constancia del equipo en su informe técnico (informe_tecnico.numero_certificado) y marca el correlativo como usado.
-- Solo se acepta un CORRELATIVO emitido para este técnico (formato CC-####-AAAA):
--   · el que Metrología le ASIGNÓ en un ticket de este equipo (ticket asignado → pasa a despachado = usado, con su hora), o
--   · uno de SU reserva diaria libre (reservado → usado, "por confirmar" por Metrología).
--   Cualquier otro (inexistente, de otro técnico, de otro equipo, ya usado) se rechaza. Idempotente: guardar de nuevo el mismo certificado responde éxito; un equipo
--   que ya tiene otro certificado no se reemplaza.
--   Contexto (OS suya, Hard Stop, equipo en ejecución, ensayos finalizados) por SP_ContextoCorrelativoMovil. Se bloquea el informe y luego el correlativo.
--   Con esto la etapa 5 "Correlativo y certificado" del trabajo en el equipo (SP_ObtenerTrabajoEquipoMovil) pasa a conforme. Auditoría: auditoria_evento.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) numero_certificado, origen (ticket · reserva), ticket.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarCertificadoMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarCertificadoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_certificado  VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_cert_ant VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert     VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_corr     BIGINT DEFAULT NULL;
    DECLARE v_c_estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_c_ticket BIGINT DEFAULT NULL;
    DECLARE v_c_tec    BIGINT DEFAULT NULL;
    DECLARE v_t_equipo BIGINT DEFAULT NULL;
    DECLARE v_t_tec    BIGINT DEFAULT NULL;
    DECLARE v_t_estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_num    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_origen   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora    DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_cert = UPPER(TRIM(IFNULL(p_certificado, '')));
    IF v_cert = '' OR v_cert NOT REGEXP '^CC-[0-9]{4}-[0-9]{4}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El certificado debe ser el correlativo que asignó Metrología, con el formato CC-0000-2026.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoCorrelativoMovil(p_id_usuario, p_id_os, p_id_os_equipo);
    SELECT c.mensaje, c.id_equipo, c.estado_equipo, c.habilitado, c.numero_os, c.id_informe, c.ens_final
    INTO   v_msg, v_id_eq, v_estado, v_hab, v_num_os, v_informe, v_final
    FROM   tmp_cc_ctx c LIMIT 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;

    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para guardar el certificado.',
                       IF(v_estado = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso.'));
    ELSEIF v_msg IS NULL AND (v_informe IS NULL OR v_final IS NULL) THEN
        SET v_msg = 'Primero finaliza los ensayos y la calibración del equipo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT it.numero_certificado INTO v_cert_ant FROM informe_tecnico it WHERE it.id_informe = v_informe FOR UPDATE;
    IF v_cert_ant IS NOT NULL THEN
        ROLLBACK;
        IF v_cert_ant = v_cert THEN
            SELECT 2 AS IdTipoMensaje, 'El certificado ya estaba guardado.' AS Mensaje;
            SELECT v_cert AS numero_certificado, NULL AS origen, NULL AS ticket;
        ELSE
            SELECT 1 AS IdTipoMensaje, CONCAT('Este equipo ya tiene el certificado ', v_cert_ant, '.') AS Mensaje;
        END IF;
        LEAVE proc;
    END IF;

    SELECT c.id_correlativo, c.estado, c.id_ticket_met, c.id_tecnico INTO v_corr, v_c_estado, v_c_ticket, v_c_tec
    FROM   correlativo_metrologia c WHERE c.codigo = v_cert AND c.eliminado_en IS NULL FOR UPDATE;
    IF v_corr IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese correlativo no existe. Usa el que te asignó Metrología o uno de tu reserva.' AS Mensaje; LEAVE proc;
    END IF;

    IF v_c_estado = 'asignado' AND v_c_ticket IS NOT NULL THEN
        SELECT t.id_equipo, t.id_tecnico_solicitante, t.estado, t.numero INTO v_t_equipo, v_t_tec, v_t_estado, v_t_num
        FROM   ticket_metrologia t WHERE t.id_ticket_met = v_c_ticket FOR UPDATE;
        IF v_t_tec <> p_id_usuario OR v_t_equipo <> v_id_eq THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese correlativo se asignó a otro técnico o a otro equipo.' AS Mensaje; LEAVE proc;
        ELSEIF v_t_estado <> 'asignado' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese correlativo ya se usó.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_origen = 'ticket';
    ELSEIF v_c_estado = 'reservado' THEN
        IF v_c_tec <> p_id_usuario THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese correlativo está reservado a otro técnico.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_origen = 'reserva';
    ELSE
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese correlativo ya se usó.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    IF v_origen = 'ticket' THEN
        UPDATE ticket_metrologia SET estado = 'despachado', usado_en = v_ahora, modificado_por = p_id_usuario WHERE id_ticket_met = v_c_ticket;
        UPDATE correlativo_metrologia SET id_os = p_id_os, id_equipo = v_id_eq, usado_en = v_ahora, modificado_por = p_id_usuario WHERE id_correlativo = v_corr;
    ELSE
        UPDATE correlativo_metrologia SET estado = 'usado', id_os = p_id_os, id_equipo = v_id_eq, usado_en = v_ahora, modificado_por = p_id_usuario WHERE id_correlativo = v_corr;
    END IF;
    UPDATE informe_tecnico SET numero_certificado = v_cert, modificado_por = p_id_usuario WHERE id_informe = v_informe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'guardar_certificado', NULL, v_cert,
            LEFT(CONCAT('Certificado ', v_cert, ' vinculado al equipo de ', v_num_os, IF(v_origen = 'ticket', CONCAT(' (ticket ', v_t_num, ')'), ' (reserva del técnico, por confirmar)')), 900),
            p_id_usuario, NOW(), JSON_OBJECT('certificado', v_cert, 'origen', v_origen, 'id_correlativo', v_corr, 'id_ticket_met', v_c_ticket));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Certificado guardado: forma parte del informe técnico.' AS Mensaje;
    SELECT v_cert AS numero_certificado, v_origen AS origen, v_t_num AS ticket;
END$$

DELIMITER ;

-- ############################################################
-- 10) SP_ObtenerCorrelativosJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerCorrelativosJefaturaMovil  (App Mobile HU-34 — "Correlativos · Solicitudes de los técnicos" del Jefe de Metrología · solo lectura)
-- Solo para el área de Metrología (la misma regla del menú de Jefatura: SP_ResolverJefaturaMovil); los demás reciben un mensaje.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 tickets · 4 reserva por técnico.
--   KPIs: pendientes = tickets solicitados · asignados_hoy = tickets asignados (o ya usados) HOY (hora de Lima) · reservados = correlativos de la reserva diaria
--         aún libres · siguiente_sugerido = el siguiente CC-####-AAAA de la secuencia única (SP_SiguienteCorrelativoMovil, sin consumirlo) · reserva_diaria = cuántos
--         recibe cada técnico (parámetro CORRELATIVO_RESERVA_DIARIA).
--   Tickets: primero los pendientes (los más recientes arriba) y luego los asignados hoy. Equipo = código del cliente (o COD TW) y capacidad; tipo de certificado;
--         patrón = patron_ensayo del informe técnico (HU-10 aún no lo llena: queda vacío); resultado = Conforme / No conforme de los ensayos (HU-10);
--         minutos = antigüedad de la solicitud; correlativo / asignado_en / asignado_por cuando ya se asignó (hora de Lima).
--   Reserva: por cada técnico de Metrología (SP_ArmarTecnicosMetrologiaMovil) con correlativos reservados o usados por confirmar: libres, codigos_libres
--         ("CC-1721-2026 · CC-1722-2026"), usados y usados_texto ("CC-1718-2026 usado · por confirmar").
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCorrelativosJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCorrelativosJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_hoy         DATE;
    DECLARE v_num         INT;
    DECLARE v_cod         VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_anio        SMALLINT;
    DECLARE v_reserva     INT DEFAULT 2;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_area <> 'metrologia' THEN
        SELECT 1 AS IdTipoMensaje, 'Correlativos se habilita solo para el área de Metrología.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    CALL SP_SiguienteCorrelativoMovil(0, v_num, v_cod, v_anio);
    SELECT IFNULL(MAX(m.Num2), 2) INTO v_reserva
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CORRELATIVO_RESERVA_DIARIA' AND m.eliminado_en IS NULL;
    IF v_reserva < 0 OR v_reserva > 10 THEN SET v_reserva = 2; END IF;
    CALL SP_ArmarTecnicosMetrologiaMovil();

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 KPIs
    SELECT (SELECT COUNT(*) FROM ticket_metrologia t WHERE t.eliminado_en IS NULL AND t.estado = 'solicitado')                                   AS pendientes,
           (SELECT COUNT(*) FROM ticket_metrologia t
            WHERE  t.eliminado_en IS NULL AND t.estado IN ('asignado', 'despachado')
              AND  DATE(CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00')) = v_hoy)                                                             AS asignados_hoy,
           (SELECT COUNT(*) FROM correlativo_metrologia c WHERE c.eliminado_en IS NULL AND c.estado = 'reservado')                             AS reservados,
           v_cod                                                                                                                                 AS siguiente_sugerido,
           v_reserva                                                                                                                             AS reserva_diaria;

    -- 3 Tickets: pendientes y asignados hoy
    SELECT t.id_ticket_met AS id_ticket, t.numero AS numero, t.estado AS estado,
           TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))) AS tecnico,
           os.numero AS numero_os,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion) AS equipo,
           COALESCE(ec.codigo_cliente, ec.codigo_tw) AS codigo_equipo, ec.alcance_maximo AS capacidad,
           tc.String1 AS tipo_certificado, t.notas AS observacion,
           (SELECT NULLIF(TRIM(it.patron_ensayo), '') FROM informe_tecnico it
            WHERE it.id_os = t.id_os AND it.id_equipo = t.id_equipo AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1) AS patron,
           (SELECT IF(it.ensayos_finalizado_en IS NULL, NULL, IF(it.resultado_global = 'fuera' OR it.error_critico_motivo IS NOT NULL, 'No conforme', 'Conforme'))
            FROM informe_tecnico it
            WHERE it.id_os = t.id_os AND it.id_equipo = t.id_equipo AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1) AS resultado,
           CONVERT_TZ(t.fecha_solicitud, '+00:00', '-05:00') AS solicitado_en,
           GREATEST(0, TIMESTAMPDIFF(MINUTE, t.fecha_solicitud, UTC_TIMESTAMP())) AS minutos,
           t.correlativo_asignado AS correlativo,
           CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00') AS asignado_en,
           TRIM(CONCAT(IFNULL(uj.nombre, ''), ' ', IFNULL(uj.apellido, ''))) AS asignado_por
    FROM   ticket_metrologia t
    JOIN   orden_servicio os ON os.id_os = t.id_os
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = t.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc ON tc.Descripcion = 'TIPO_CERTIFICADO_MET' AND tc.IdEmpresa = 1 AND tc.Num1 = t.id_tipo_certificado
    LEFT JOIN usuario ut ON ut.id_usuario = t.id_tecnico_solicitante
    LEFT JOIN usuario uj ON uj.id_usuario = t.id_metrologo_asignado
    WHERE  t.eliminado_en IS NULL
      AND  (t.estado = 'solicitado'
            OR (t.estado IN ('asignado', 'despachado') AND DATE(CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00')) = v_hoy))
    ORDER BY IF(t.estado = 'solicitado', 0, 1), t.fecha_solicitud DESC, t.id_ticket_met DESC
    LIMIT 60;

    -- 4 Reserva por técnico
    SELECT x.id_usuario AS id_usuario, x.nombre AS tecnico,
           SUM(x.estado = 'reservado') AS libres,
           IFNULL(GROUP_CONCAT(IF(x.estado = 'reservado', x.codigo, NULL) ORDER BY x.anio, x.numero SEPARATOR ' · '), '') AS codigos_libres,
           SUM(x.estado = 'usado') AS usados,
           IFNULL(GROUP_CONCAT(IF(x.estado = 'usado', CONCAT(x.codigo, ' usado · por confirmar'), NULL) ORDER BY x.anio, x.numero SEPARATOR ' · '), '') AS usados_texto
    FROM  (SELECT tt.id_usuario, tt.nombre, c.estado, c.codigo, c.anio, c.numero
           FROM   tmp_tm_tec tt
           JOIN   correlativo_metrologia c ON c.id_tecnico = tt.id_usuario AND c.estado IN ('reservado', 'usado') AND c.eliminado_en IS NULL
                                                    AND (c.estado = 'reservado' OR c.usado_en >= UTC_TIMESTAMP() - INTERVAL 7 DAY)) x
    GROUP BY x.id_usuario, x.nombre
    ORDER BY x.nombre
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
END$$

DELIMITER ;

-- ############################################################
-- 11) SP_AsignarCorrelativoMovil
-- ############################################################
-- ============================================================
-- SP_AsignarCorrelativoMovil  (App Mobile HU-34 — "Asignar correlativo" del Jefe de Metrología)
-- El Jefe de Metrología (o supervisor / administrador del área: SP_ResolverJefaturaMovil = metrologia) asigna el correlativo CC-####-AAAA a un ticket solicitado.
--   p_correlativo NULL / vacío → el siguiente de la secuencia única (SP_SiguienteCorrelativoMovil, consumido dentro de la transacción).
--   p_correlativo dado (editable en la pantalla) → debe ser CC-####-AAAA del AÑO ACTUAL (Lima), de 0001 a 9999 y no estar ya emitido (asignado, reservado o usado);
--     si es mayor que el último emitido, la secuencia salta a ese número (los intermedios quedan sin emitir).
--   Orden de bloqueos: ticket → fila del año de la secuencia → correlativo (índices únicos como red de seguridad ante cualquier carrera).
--   Avisa al técnico ("Correlativo asignado · TK… · BAL-… · Metrología asignó el correlativo CC-…") y deja auditoría (auditoria_evento, ticket_metrologia).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_ticket, numero, estado, correlativo, asignado_en (hora de Lima), asignado_por, tecnico,
--   siguiente_sugerido (el que sigue ahora).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AsignarCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_AsignarCorrelativoMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_ticket   BIGINT,
    IN p_correlativo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_cod_in      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_tk   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_corr_ant    VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_os       BIGINT DEFAULT NULL;
    DECLARE v_id_eq       BIGINT DEFAULT NULL;
    DECLARE v_tecnico     BIGINT DEFAULT NULL;
    DECLARE v_anio        SMALLINT;
    DECLARE v_anio_in     INT;
    DECLARE v_num_in      INT;
    DECLARE v_num         INT DEFAULT NULL;
    DECLARE v_cod         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ultimo      INT DEFAULT 0;
    DECLARE v_id_corr     BIGINT;
    DECLARE v_cod_eq      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nombre_jf   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nombre_tec  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora       DATETIME;
    DECLARE v_sig_num     INT;
    DECLARE v_sig_cod     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig_anio    SMALLINT;

    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese correlativo acaba de ser emitido: vuelve a abrir la pantalla y toma el siguiente.' AS Mensaje;
    END;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_ticket, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Ticket no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL OR v_area <> 'metrologia' THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el área de Metrología puede asignar correlativos.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_cod_in = NULLIF(UPPER(TRIM(IFNULL(p_correlativo, ''))), '');
    IF v_cod_in IS NOT NULL THEN
        IF v_cod_in NOT REGEXP '^CC-[0-9]{4}-[0-9]{4}$' THEN
            SELECT 1 AS IdTipoMensaje, 'El correlativo debe tener el formato CC-0000-2026.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_anio_in = CAST(RIGHT(v_cod_in, 4) AS UNSIGNED);
        SET v_num_in  = CAST(SUBSTRING(v_cod_in, 4, 4) AS UNSIGNED);
        IF v_anio_in <> YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR) THEN
            SELECT 1 AS IdTipoMensaje, CONCAT('El correlativo debe ser del año ', YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR), '.') AS Mensaje; LEAVE proc;
        END IF;
        IF v_num_in < 1 THEN
            SELECT 1 AS IdTipoMensaje, 'El número del correlativo debe ser desde 0001.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    START TRANSACTION;

    SELECT t.estado, t.numero, t.correlativo_asignado, t.id_os, t.id_equipo, t.id_tecnico_solicitante
    INTO   v_estado, v_numero_tk, v_corr_ant, v_id_os, v_id_eq, v_tecnico
    FROM   ticket_metrologia t
    WHERE  t.id_ticket_met = p_id_ticket AND t.eliminado_en IS NULL
    FOR UPDATE;
    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ticket no encontrado.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado IN ('asignado', 'despachado') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_numero_tk, ' ya tiene el correlativo ', IFNULL(v_corr_ant, ''), '.') AS Mensaje; LEAVE proc;
    ELSEIF v_estado <> 'solicitado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_numero_tk, ' fue cancelado.') AS Mensaje; LEAVE proc;
    END IF;

    IF v_cod_in IS NULL THEN
        CALL SP_SiguienteCorrelativoMovil(1, v_num, v_cod, v_anio);
        IF v_cod IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Se agotaron los correlativos del año.' AS Mensaje; LEAVE proc;
        END IF;
    ELSE
        SET v_anio = v_anio_in, v_num = v_num_in, v_cod = v_cod_in;
        INSERT IGNORE INTO correlativo_secuencia (anio, ultimo) VALUES (v_anio, 0);
        SELECT s.ultimo INTO v_ultimo FROM correlativo_secuencia s WHERE s.anio = v_anio FOR UPDATE;
        IF EXISTS (SELECT 1 FROM correlativo_metrologia c WHERE c.anio = v_anio AND c.numero = v_num) THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, CONCAT('El correlativo ', v_cod, ' ya está asignado, reservado o usado.') AS Mensaje; LEAVE proc;
        END IF;
        IF v_num > v_ultimo THEN
            UPDATE correlativo_secuencia SET ultimo = v_num WHERE anio = v_anio;
        END IF;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    INSERT INTO correlativo_metrologia (anio, numero, codigo, estado, id_ticket_met, id_tecnico, id_os, id_equipo, creado_por)
    VALUES (v_anio, v_num, v_cod, 'asignado', p_id_ticket, v_tecnico, v_id_os, v_id_eq, p_id_usuario);
    SET v_id_corr = LAST_INSERT_ID();

    UPDATE ticket_metrologia
    SET    estado = 'asignado', correlativo_asignado = v_cod, id_correlativo = v_id_corr, id_metrologo_asignado = p_id_usuario,
           fecha_asignacion = v_ahora, modificado_por = p_id_usuario
    WHERE  id_ticket_met = p_id_ticket;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_jf  FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = v_tecnico LIMIT 1;
    SELECT COALESCE(ec.codigo_cliente, ec.codigo_tw) INTO v_cod_eq FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq LIMIT 1;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_tecnico, 5, 'Correlativo asignado',
            LEFT(CONCAT(v_numero_tk, ' · ', IFNULL(v_cod_eq, ''), ' · Metrología asignó el correlativo ', v_cod, '.'), 500),
            'ticket_metrologia', p_id_ticket, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('ticket_metrologia', p_id_ticket, 'asignar_correlativo', 'solicitado', 'asignado',
            LEFT(CONCAT(v_nombre_jf, ' asignó el correlativo ', v_cod, ' al ticket ', v_numero_tk, ' de ', IFNULL(v_nombre_tec, ''), '.'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('ticket', v_numero_tk, 'correlativo', v_cod, 'id_correlativo', v_id_corr, 'sugerido', v_cod_in IS NULL, 'id_tecnico', v_tecnico));

    COMMIT;

    CALL SP_SiguienteCorrelativoMovil(0, v_sig_num, v_sig_cod, v_sig_anio);
    SELECT 2 AS IdTipoMensaje, CONCAT('Correlativo asignado · ', IFNULL(v_nombre_tec, 'el técnico'), ' ya puede usarlo en su certificado') AS Mensaje;
    SELECT p_id_ticket AS id_ticket, v_numero_tk AS numero, 'asignado' AS estado, v_cod AS correlativo, CONVERT_TZ(v_ahora, '+00:00', '-05:00') AS asignado_en,
           v_nombre_jf AS asignado_por, v_nombre_tec AS tecnico, v_sig_cod AS siguiente_sugerido;
END$$

DELIMITER ;

-- ############################################################
-- 12) SP_GenerarReservaCorrelativosMovil
-- ############################################################
-- ============================================================
-- SP_GenerarReservaCorrelativosMovil  (App Mobile HU-34 — reserva diaria de correlativos para trabajar sin conexión)
-- Cada técnico de Metrología (SP_ArmarTecnicosMetrologiaMovil) recibe, al iniciar el día, correlativos reservados de la MISMA secuencia que usan los tickets,
-- hasta completar el parámetro CORRELATIVO_RESERVA_DIARIA (2 por defecto, de 0 a 10) de libres. Idempotente por día: el técnico que ya recibió reserva HOY (hora de
-- Lima) no recibe más; los reservados sin usar siguen siendo suyos (no se pierden números, la numeración no deja huecos).
--   p_modo = todos  → lo dispara el Jefe de Metrología (SP_ResolverJefaturaMovil = metrologia) al abrir "Correlativos": a todos los técnicos de Metrología.
--   p_modo = propia → lo dispara el técnico de Metrología para sí mismo (al abrir "Correlativo y certificado"); si no es técnico de Metrología, no hace nada.
--   Se bloquea primero la fila del año de la secuencia (serializa la reserva con las asignaciones) y se insertan los correlativos como estado reservado.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) generados (correlativos nuevos), tecnicos (técnicos que recibieron).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarReservaCorrelativosMovil;

DELIMITER $$

CREATE PROCEDURE SP_GenerarReservaCorrelativosMovil(
    IN p_id_usuario BIGINT,
    IN p_modo       VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_n_diaria    INT DEFAULT 2;
    DECLARE v_hoy         DATE;
    DECLARE v_anio        SMALLINT;
    DECLARE v_total       INT DEFAULT 0;
    DECLARE v_i           INT DEFAULT 0;
    DECLARE v_tec         BIGINT;
    DECLARE v_libres      INT;
    DECLARE v_hoy_n       INT;
    DECLARE v_falta       INT;
    DECLARE v_num         INT;
    DECLARE v_cod         VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_anio_s      SMALLINT;
    DECLARE v_generados   INT DEFAULT 0;
    DECLARE v_recibieron  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_rs_obj;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_modo, '') NOT IN ('todos', 'propia') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de reserva no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_modo = 'todos' THEN
        CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
        IF v_area IS NULL OR v_area <> 'metrologia' THEN
            SELECT 1 AS IdTipoMensaje, 'Solo el área de Metrología puede generar la reserva de correlativos.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    SELECT IFNULL(MAX(m.Num2), 2) INTO v_n_diaria
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CORRELATIVO_RESERVA_DIARIA' AND m.eliminado_en IS NULL;
    IF v_n_diaria < 0 OR v_n_diaria > 10 THEN SET v_n_diaria = 2; END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    SET v_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    -- A quiénes: todos los técnicos de Metrología, o solo el que lo pide (si lo es)
    CALL SP_ArmarTecnicosMetrologiaMovil();
    DROP TEMPORARY TABLE IF EXISTS tmp_rs_obj;
    CREATE TEMPORARY TABLE tmp_rs_obj (n INT NOT NULL AUTO_INCREMENT, id_usuario BIGINT NOT NULL, PRIMARY KEY (n));
    INSERT INTO tmp_rs_obj (id_usuario)
    SELECT t.id_usuario FROM tmp_tm_tec t WHERE (p_modo = 'todos' OR t.id_usuario = p_id_usuario) ORDER BY t.id_usuario;
    DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
    SELECT COUNT(*) INTO v_total FROM tmp_rs_obj;

    START TRANSACTION;
    -- Se serializa con las asignaciones: primero la fila del año de la secuencia
    INSERT IGNORE INTO correlativo_secuencia (anio, ultimo) VALUES (v_anio, 0);
    SELECT s.ultimo INTO v_num FROM correlativo_secuencia s WHERE s.anio = v_anio FOR UPDATE;

    WHILE v_i < v_total DO
        SELECT o.id_usuario INTO v_tec FROM tmp_rs_obj o ORDER BY o.n LIMIT 1 OFFSET v_i;
        SELECT COUNT(*) INTO v_libres FROM correlativo_metrologia c WHERE c.id_tecnico = v_tec AND c.estado = 'reservado' AND c.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_hoy_n
        FROM   correlativo_metrologia c
        WHERE  c.id_tecnico = v_tec AND c.fecha_reserva IS NOT NULL AND c.eliminado_en IS NULL
          AND  DATE(CONVERT_TZ(c.fecha_reserva, '+00:00', '-05:00')) = v_hoy;
        SET v_falta = IF(v_hoy_n > 0, 0, v_n_diaria - v_libres);
        IF v_falta > 0 THEN
            SET v_recibieron = v_recibieron + 1;
            WHILE v_falta > 0 DO
                CALL SP_SiguienteCorrelativoMovil(1, v_num, v_cod, v_anio_s);
                IF v_cod IS NULL THEN
                    SET v_falta = 0;
                ELSE
                    INSERT INTO correlativo_metrologia (anio, numero, codigo, estado, id_tecnico, fecha_reserva, creado_por)
                    VALUES (v_anio_s, v_num, v_cod, 'reservado', v_tec, UTC_TIMESTAMP(), p_id_usuario);
                    SET v_generados = v_generados + 1;
                    SET v_falta = v_falta - 1;
                END IF;
            END WHILE;
        END IF;
        SET v_i = v_i + 1;
    END WHILE;

    IF v_generados > 0 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('correlativo_metrologia', v_anio, 'reserva_diaria', NULL, 'reservado',
                CONCAT('Reserva diaria de correlativos: ', v_generados, ' para ', v_recibieron, IF(v_recibieron = 1, ' técnico.', ' técnicos.')),
                p_id_usuario, NOW(), JSON_OBJECT('modo', p_modo, 'generados', v_generados, 'tecnicos', v_recibieron));
    END IF;
    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_rs_obj;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_generados AS generados, v_recibieron AS tecnicos;
END$$

DELIMITER ;

-- ############################################################
-- 13) SP_ObtenerTrabajoEquipoMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerTrabajoEquipoMovil  (App Mobile HU-08 — "Trabajo en el equipo": cabecera y las 5 etapas · lectura)
-- Pantalla a la que entra el técnico con "Trabajar en el equipo". El técnico sale del token; la OS debe ser suya.
--   - Hard Stop (HU-06): sin llegada registrada no se entrega nada. El equipo debe haberse iniciado (en ejecución, pausado o completado).
--   - Tipo de orden según la RQ: el área de la RQ (area_servicio_rq) define OS (servicio técnico) u OM (metrología).
--   - Servicio: sigla y nombre del tipo de intervención del equipo; si no tiene, el tipo de servicio de la OS.
--   - Etapas (siempre las 5, una sola vez aquí): variables (HU-09), fotos, ensayos, cabecera y correlativo.
--       estado: conforme | en_curso | pendiente | bloqueado.  "Ensayos y Calibración" queda BLOQUEADO hasta guardar las variables ambientales (HU-09).
--       disponible = 0 → la etapa aún no tiene pantalla en la app (la app avisa que se habilita más adelante).
--   - Avance = etapas conformes de 5. "Finalizar trabajo" se habilita cuando las 5 están conformes (puede_finalizar).
--   - puede_registrar = el equipo está EN EJECUCIÓN y el servicio en curso: solo así se guardan datos de las etapas.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 variables ambientales (0 o 1 fila) · 4 etapas (5 filas).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTrabajoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTrabajoEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
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
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_rq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n_fotos     INT DEFAULT 0;
    DECLARE v_n_ensayos   INT DEFAULT 0;
    DECLARE v_informe     BIGINT DEFAULT NULL;
    DECLARE v_vars        TINYINT DEFAULT 0;
    DECLARE v_det_vars    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sigla       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_int    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes   INT DEFAULT 0;
    DECLARE v_ev_total    INT DEFAULT 9;
    DECLARE v_ev_compl    INT DEFAULT 0;
    DECLARE v_ev_forz     INT DEFAULT 0;
    DECLARE v_ev_rech     INT DEFAULT 0;
    DECLARE v_ev_oblig    INT DEFAULT 0;
    DECLARE v_ens_final   DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert        VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_estado   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_num      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
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
    IF v_llegada_utc IS NULL THEN
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
    IF v_estado NOT IN ('en_ejecucion', 'pausado', 'completado') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el trabajo en este equipo desde los objetivos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Tipo de orden según la RQ: servicio técnico → OS, metrología → OM
    SELECT asr.area_usuario, rq.numero INTO v_area, v_numero_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed  ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq asr ON asr.id_area_rq = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;
    SET v_tipo_orden = IF(v_area = 'metrologia', 'OM', 'OS');

    -- Variables ambientales (HU-09)
    SELECT COUNT(*) INTO v_vars
    FROM   variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL;
    IF v_vars > 0 THEN
        SELECT CONCAT('T° ', TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.temperatura_c AS CHAR))), ' °C · h ',
                      TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.humedad_pct AS CHAR))), ' % · Procedencia ', IFNULL(va.procedencia, 'N.I'))
        INTO   v_det_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL
        ORDER BY va.id_variable DESC LIMIT 1;
    END IF;

    -- Registro fotográfico (HU-11): el avance lo calcula SP_ResumenEvidenciasMovil, una sola vez
    CALL SP_ResumenEvidenciasMovil(p_id_os, v_id_equipo, v_ev_total, v_ev_compl, v_ev_forz, v_ev_rech, v_ev_oblig);
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    SET v_n_fotos = v_ev_compl;

    SELECT it.id_informe, it.ensayos_finalizado_en, it.error_critico_motivo, it.numero_certificado INTO v_informe, v_ens_final, v_ens_motivo, v_cert
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_informe IS NOT NULL THEN
        SELECT COUNT(*) INTO v_n_ensayos FROM informe_ensayo ie WHERE ie.id_informe = v_informe AND ie.eliminado_en IS NULL;
    END IF;

    -- Correlativo y certificado (HU-14): el ticket abierto de este equipo en Metrología (solicitado o asignado)
    SELECT t.estado, t.numero INTO v_tk_estado, v_tk_num
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_equipo AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    CREATE TEMPORARY TABLE tmp_etapas_mov (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        disponible TINYINT DEFAULT 0, PRIMARY KEY (orden));

    INSERT INTO tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible) VALUES
        (1, 'variables', 'Variables ambientales', IF(v_vars > 0, 'conforme', 'pendiente'),
            IF(v_vars > 0, v_det_vars, 'Temperatura, humedad y procedencia'), 1),
        (2, 'fotos', 'Registro fotográfico', IF(v_ev_compl >= v_ev_total, 'conforme', IF(v_ev_compl > 0 OR v_ev_rech > 0, 'en_curso', 'pendiente')),
            CONCAT(v_ev_compl, ' de ', v_ev_total, ' · incluye foto del informe a mano',
                   IF(v_ev_forz > 0, CONCAT(' · ', v_ev_forz, IF(v_ev_forz = 1, ' forzada', ' forzadas')), '')), 1),
        (3, 'ensayos', 'Ensayos y Calibración',
            IF(v_vars = 0, 'bloqueado', IF(v_ens_final IS NOT NULL, 'conforme', IF(v_n_ensayos > 0, 'en_curso', 'pendiente'))),
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales',
               IF(v_ens_final IS NOT NULL, IF(v_ens_motivo IS NULL, 'Pesaje y excentricidad conformes', 'Finalizado con error crítico: se avisó al encargado'),
                  IF(v_n_ensayos > 0, CONCAT(v_n_ensayos, ' lecturas guardadas · falta finalizar'), 'Verificación de pesaje tras el ajuste'))), 1),
        (4, 'cabecera', 'Cabecera del informe', IF(v_informe IS NOT NULL, 'en_curso', 'pendiente'), 'Datos · Detalle Serv. · Observación y pruebas', 0),
        (5, 'correlativo', 'Correlativo y certificado',
            IF(v_cert IS NOT NULL, 'conforme', IF(v_ens_final IS NULL, 'bloqueado', IF(v_tk_estado IS NOT NULL, 'en_curso', 'pendiente'))),
            IF(v_cert IS NOT NULL, CONCAT('Certificado ', v_cert),
               IF(v_ens_final IS NULL, 'Se habilita al finalizar los ensayos',
                  IF(v_tk_estado = 'asignado', CONCAT(v_tk_num, ' asignado · listo para usar'),
                     IF(v_tk_estado = 'solicitado', CONCAT(v_tk_num, ' · esperando a Metrología'), 'Correlativo de Metrología → N° de certificado')))), 1);

    SELECT COUNT(*) INTO v_conformes FROM tmp_etapas_mov WHERE estado = 'conforme';

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
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ############################################################
-- 14) SP_ObtenerNotificacionesMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerNotificacionesMovil  (App Mobile HU-02 / HU-04 — pestaña Notificaciones)
-- Avisos del usuario que inició sesión (el id sale del token): las 60 más recientes, no eliminadas.
-- Son las mismas de la campana de la intranet (tabla notificacion), con el tipo ya clasificado para el ícono y la acción de la app.
--   tipo (según el título que dejan los demás SP):
--     autorizacion_aprobada   "Autorización de salida aprobada" (y el texto anterior "Visto bueno de salida: …")
--     autorizacion_rechazada  "Autorización de salida rechazada" (y "Salida no autorizada: …")
--     autorizacion_solicitud  "Autorización de salida · …" (le llega al jefe cuando un técnico pide su visto bueno)
--     solicitud_enviada       "Solicitud de autorización enviada" (confirmación para el técnico)
--     gasto_aprobado | gasto_observado | gasto_rechazado   gastos revisados por el Jefe de Operaciones
--     servicio                "Nueva programación: …" (se asignó un servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     ensayo_critico          "Ensayo con error crítico" (HU-10: le llega al encargado del área; el técnico pidió apoyo o aceptó guardar con una lectura fuera del EMP)
--     evidencia_forzada       "Evidencia forzada" (HU-12: una foto rechazada por la IA que el técnico aceptó con un motivo)
--     correlativo_solicitado  "Solicitud de correlativo enviada" (HU-14: confirmación al técnico) · correlativo_solicitud "Solicitud de correlativo" (HU-34: le llega al Jefe de
--                             Metrología) · correlativo_asignado "Correlativo asignado" (HU-14: Metrología asignó el correlativo; abre "Mis tickets"). entidad_tipo = ticket_metrologia.
--     equipo_nuevo            "Equipo nuevo por aprobar" (HU-07: equipo NEW registrado en campo)
--     servicio_detenido       "Servicio detenido: …" (Control de Campo)
--     alerta_campo            otra alerta operativa del Control de Campo (tipo_notificacion = alerta_operativa)
--     general                 cualquier otro
--   critica / prioridad: la prioridad que ya clasifica el Centro de Notificaciones (HU-90, migración 102_centro_notificaciones: columna
--     notificacion.prioridad = critica | alta | normal). Es lo que filtra "Críticas" en la pestaña Notificaciones del jefe. No se repite la regla aquí.
--   Las archivadas en la intranet no se muestran.
--   pendientes_aprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
--   entidad_tipo / id_entidad: a qué abre la app ('orden_servicio' = el detalle del servicio).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_notificacion, x.tipo, x.titulo, x.cuerpo, x.entidad_tipo, x.id_entidad, x.leida, x.fecha_creacion,
           x.prioridad, IF(x.prioridad = 'critica', 1, 0) AS critica,
           CASE WHEN x.tipo = 'autorizacion_aprobada' AND x.entidad_tipo = 'orden_servicio'
                THEN (SELECT a.pendientes FROM autorizacion_salida_os a
                      WHERE  a.id_os = x.id_entidad AND a.eliminado_en IS NULL
                      ORDER BY a.id_autorizacion DESC LIMIT 1)
           END AS pendientes_aprobados
    FROM (
        SELECT n.id_notificacion,
               CASE WHEN n.titulo LIKE 'Autorización de salida aprobada%' OR n.titulo LIKE 'Visto bueno de salida%'     THEN 'autorizacion_aprobada'
                    WHEN n.titulo LIKE 'Autorización de salida rechazada%' OR n.titulo LIKE 'Salida no autorizada%'     THEN 'autorizacion_rechazada'
                    WHEN n.titulo LIKE 'Solicitud de autorización enviada%'                                             THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Solicitud de correlativo enviada%'                                              THEN 'correlativo_solicitado'
                    WHEN n.titulo LIKE 'Solicitud de correlativo%'                                                      THEN 'correlativo_solicitud'
                    WHEN n.titulo LIKE 'Correlativo asignado%'                                                          THEN 'correlativo_asignado'
                    WHEN n.titulo LIKE 'Autorización de salida%'                                                        THEN 'autorizacion_solicitud'
                    WHEN n.titulo LIKE 'Gasto aprobado%'                                                                THEN 'gasto_aprobado'
                    WHEN n.titulo LIKE 'Gasto observado%'                                                               THEN 'gasto_observado'
                    WHEN n.titulo LIKE 'Gasto rechazado%'                                                               THEN 'gasto_rechazado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'                         THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    WHEN n.titulo LIKE 'Ensayo con error cr%'                                                           THEN 'ensayo_critico'
                    WHEN n.titulo LIKE 'Evidencia forzada%'                                                             THEN 'evidencia_forzada'
                    WHEN n.titulo LIKE 'Equipo nuevo por aprobar%'                                                      THEN 'equipo_nuevo'
                    WHEN n.titulo LIKE 'Servicio detenido:%'                                                            THEN 'servicio_detenido'
                    WHEN n.tipo_notificacion = 'alerta_operativa'                                                       THEN 'alerta_campo'
                    ELSE 'general' END AS tipo,
               n.titulo,
               n.cuerpo,
               n.entidad_tipo,
               n.id_entidad,
               n.leido                AS leida,
               n.fecha_creacion,
               n.prioridad
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL AND n.archivado = 0
        ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
        LIMIT 60
    ) x
    ORDER BY x.fecha_creacion DESC, x.id_notificacion DESC;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 13)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_SiguienteCorrelativoMovil', 'SP_ArmarJefesMetrologiaMovil', 'SP_ArmarTecnicosMetrologiaMovil', 'SP_ContextoCorrelativoMovil',
      'SP_ObtenerSolicitudCorrelativoMovil', 'SP_SolicitarCorrelativoMovil', 'SP_ObtenerTicketsCorrelativoMovil', 'SP_GuardarCertificadoMovil', 'SP_ObtenerCorrelativosJefaturaMovil',
      'SP_AsignarCorrelativoMovil', 'SP_GenerarReservaCorrelativosMovil', 'SP_ObtenerTrabajoEquipoMovil', 'SP_ObtenerNotificacionesMovil')
ORDER BY ROUTINE_NAME;

-- B) Migración 103 (debe ser 12: 2 tablas + 4 columnas del ticket + 1 del informe + 3 tipos de certificado + 1 parámetro + 1 fila de la secuencia del año)
SELECT 'Migración 103 (debe ser 12)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('correlativo_metrologia', 'correlativo_secuencia'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME IN ('id_equipo', 'id_tipo_certificado', 'id_correlativo', 'usado_en'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'numero_certificado')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'TIPO_CERTIFICADO_MET' AND IdEmpresa = 1)
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'CORRELATIVO_RESERVA_DIARIA')
     + (SELECT COUNT(*) FROM correlativo_secuencia WHERE anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR)) AS valor;

-- C) La secuencia del año y el correlativo que se sugeriría ahora (no se consume)
SELECT anio, ultimo FROM correlativo_secuencia ORDER BY anio DESC;
CALL SP_SiguienteCorrelativoMovil(0, @n, @c, @a);
SELECT @c AS siguiente_sugerido;

-- D) Tipos de certificado
SELECT Num1 AS id_tipo, String1 AS nombre FROM tabla_maestra WHERE Descripcion = 'TIPO_CERTIFICADO_MET' AND IdEmpresa = 1 ORDER BY Num1;

-- E) Un jefe de Metrología (si hay) y su pantalla: 1 mensaje · 2 KPIs · 3 tickets · 4 reserva. Sin jefe de Metrología sale "Tu cargo no tiene el menú de Jefatura."
SET @jefe = (SELECT u.id_usuario FROM usuario u
             WHERE u.estado = 'activo' AND u.eliminado_en IS NULL AND u.area = 'metrologia' AND (u.cargo LIKE 'jefe_%' OR u.rol_sistema IN ('supervisor', 'administrador'))
             ORDER BY u.id_usuario LIMIT 1);
SELECT @jefe AS jefe_metrologia;
CALL SP_ObtenerCorrelativosJefaturaMovil(@jefe);

-- F) Validaciones: solo responden un mensaje de regla de negocio, NO escriben nada
CALL SP_AsignarCorrelativoMovil(@jefe, 0, NULL);               -- "Ticket no encontrado." (o "Solo el área de Metrología…" si no hay jefe)
CALL SP_SolicitarCorrelativoMovil(0, 0, 0, 0, NULL);           -- "Servicio o equipo no válido."
CALL SP_GuardarCertificadoMovil(0, 0, 0, 'x');                 -- "Servicio o equipo no válido."
CALL SP_GuardarCertificadoMovil(1, 1, 1, 'x');                 -- "El certificado debe ser el correlativo que asignó Metrología…"
CALL SP_ObtenerTicketsCorrelativoMovil(1, 'otro', NULL);       -- "El filtro de tickets no es válido."
CALL SP_GenerarReservaCorrelativosMovil(0, 'otro');            -- "El tipo de reserva no es válido."
CALL SP_ObtenerSolicitudCorrelativoMovil(0, 0, 0);             -- "Servicio o equipo no válido."
