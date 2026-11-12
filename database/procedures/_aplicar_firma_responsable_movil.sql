-- Aplicar en la base (Firma de informes: «Quién atiende en planta» toma el contacto de la OS cuando el técnico no lo escribió. App Mobile HU-15 / HU-16 / HU-17). Sin migración y sin datos de prueba.
-- Ejecutar completo con Alt+X. NO subir al repositorio. Después REINICIAR la API.
-- Requiere (ya existentes): los scripts de la HU-15 / HU-16 y de la HU-17. No vuelvas a ejecutar _aplicar_informe_equipo_movil.sql ni _aplicar_firma_constancia_movil.sql después de este:
-- dejarían SP_GenerarInformeEquipoMovil y SP_ArmarFirmasOsMovil con su versión anterior.
-- Qué hace: actualiza SP_ArmarFirmasOsMovil (usa el contacto de la OS si el informe no tiene responsable) y SP_GenerarInformeEquipoMovil (lo deja guardado al generar).

-- ############################################################
-- SP_ArmarFirmasOsMovil
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
           IF(it.id_informe IS NOT NULL AND COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')) IS NOT NULL, 1, 0),
           CASE WHEN it.id_informe IS NULL THEN 'Falta finalizar el trabajo en el equipo (HU-16)'
                WHEN COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')) IS NULL THEN 'Falta «Quién atiende en planta» en la cabecera del informe'
                ELSE NULL END,
           -- «Quién atiende en planta»: lo guardado en la cabecera o, si el técnico no lo tocó, el contacto de la OS (lo mismo que muestra la pestaña Datos)
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')),
           IF(NULLIF(TRIM(it.responsable_nombre), '') IS NULL, NULLIF(TRIM(cc.cargo), ''), NULLIF(TRIM(it.responsable_cargo), '')),
           IF(NULLIF(TRIM(it.responsable_nombre), '') IS NULL, NULLIF(TRIM(cc.telefono_movil), ''), NULLIF(TRIM(it.responsable_telefono), '')),
           IF(it.id_informe IS NOT NULL AND COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')) IS NOT NULL,
              MD5(CONCAT(LOWER(TRIM(COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), cc.nombres))), '|',
                         LOWER(TRIM(IFNULL(IF(NULLIF(TRIM(it.responsable_nombre), '') IS NULL, cc.cargo, it.responsable_cargo), ''))))), NULL),
           it.generado_en
    FROM   os_equipo oe
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    JOIN   orden_servicio osr ON osr.id_os = oe.id_os
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
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
-- SP_GenerarInformeEquipoMovil
-- ############################################################
-- ============================================================
-- SP_GenerarInformeEquipoMovil  (App Mobile HU-16 — "Generar informe técnico" tras la Validación completa)
-- Con las 5 etapas conformes el técnico genera el informe técnico del equipo:
--   · el equipo pasa a COMPLETADO (os_equipo.estado_ejecucion = 'ejecutado'; se cierra su tramo de tiempo),
--   · el informe recibe su N° definitivo NNNN-AAAA de la secuencia propia (informe_secuencia, atómica; se copia también a informe_tecnico.numero, que era el borrador
--     BRR-########) y queda con generado_en / generado_por. Un informe generado es el que lista y firma la HU-17 (Firma de informes).
--   El informe NO cambia de estado (sigue 'borrador'): el envío a Revisión Técnica de la intranet corresponde al cierre del servicio (constancia, HU-17).
--   Reglas (una sola vez): el contexto lo valida SP_ContextoEquipoMovil (OS del técnico del token, Hard Stop de llegada, equipo iniciado); las 5 etapas
--   SP_ArmarEtapasEquipoMovil (la misma regla de SP_ValidarCierreEquipoMovil). Equipo EN EJECUCIÓN (no pausado). Idempotente: si el informe ya estaba generado
--   responde éxito con el mismo número (repetida = 1) sin tocar nada. Orden de bloqueos fijo: os_equipo → informe técnico → secuencia del año.
--   Auditoría: auditoria_evento (os_equipo y informe_tecnico).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_informe, numero_informe, estado_equipo, repetida.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarInformeEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_GenerarInformeEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_numero    INT DEFAULT NULL;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe        BIGINT DEFAULT NULL;
    DECLARE v_informe   BIGINT DEFAULT NULL;
    DECLARE v_gen       DATETIME DEFAULT NULL;
    DECLARE v_num_inf   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes INT DEFAULT 0;
    DECLARE v_anio      SMALLINT;
    DECLARE v_ultimo    INT DEFAULT 0;
    DECLARE v_n         INT;
    DECLARE v_cod       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora_utc DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Bloqueos en orden fijo: el equipo (objetivo) y luego su informe
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    SELECT it.id_informe, it.generado_en, it.numero_informe INTO v_informe, v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;

    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, 'El informe técnico ya estaba generado.' AS Mensaje;
        SELECT v_informe AS id_informe, v_num_inf AS numero_informe, 'completado' AS estado_equipo, 1 AS repetida;
        LEAVE proc;
    END IF;
    IF v_estado = 'pausado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo está pausado: reanúdalo para generar el informe.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado <> 'en_ejecucion' OR v_hab = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo debe estar en ejecución para generar el informe técnico.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop: las 5 etapas conformes (la misma regla que SP_ValidarCierreEquipoMovil)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_eq, v_conformes);
    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    IF v_informe IS NULL OR v_conformes < 5 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('No es posible finalizar el trabajo en el equipo: ', 5 - v_conformes, IF(5 - v_conformes = 1, ' etapa está incompleta o no conforme.', ' etapas están incompletas o no conformes.'),
                      ' Revisa los pendientes.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- N° del informe: la secuencia propia del año (se salta cualquier número ya usado)
    SET v_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    INSERT IGNORE INTO informe_secuencia (anio, ultimo) VALUES (v_anio, 0);
    SELECT s.ultimo INTO v_ultimo FROM informe_secuencia s WHERE s.anio = v_anio FOR UPDATE;
    SET v_n = v_ultimo + 1;
    SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    WHILE v_n <= 9999 AND EXISTS (SELECT 1 FROM informe_tecnico x WHERE x.numero_informe = v_cod OR x.numero = v_cod) DO
        SET v_n = v_n + 1;
        SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    END WHILE;
    IF v_n > 9999 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Se agotaron los números de informe del año.' AS Mensaje; LEAVE proc;
    END IF;
    UPDATE informe_secuencia SET ultimo = v_n WHERE anio = v_anio;

    SET v_ahora_utc = UTC_TIMESTAMP();
    UPDATE informe_tecnico
    SET    numero_informe = v_cod, numero = v_cod, generado_en = UTC_TIMESTAMP(), generado_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- «Quién atiende en planta»: si el técnico no lo escribió en la cabecera, el informe queda con el contacto de la OS (el mismo que muestra la pestaña Datos)
    -- para que se pueda firmar (HU-17). Lo ya escrito no se toca.
    UPDATE informe_tecnico it
    JOIN   orden_servicio osr ON osr.id_os = it.id_os
    JOIN   contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    SET    it.responsable_nombre   = cc.nombres,
           it.responsable_cargo    = LEFT(NULLIF(TRIM(cc.cargo), ''), 100),
           it.responsable_telefono = LEFT(NULLIF(TRIM(cc.telefono_movil), ''), 30)
    WHERE  it.id_informe = v_informe AND NULLIF(TRIM(it.responsable_nombre), '') IS NULL AND NULLIF(TRIM(cc.nombres), '') IS NOT NULL;

    -- El equipo queda COMPLETADO y se cierra su tramo de tiempo
    UPDATE os_equipo
    SET    estado_ejecucion = 'ejecutado', fecha_ejecucion = NOW(),
           acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_ahora_utc))),
           reanudado_utc = NULL, pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, modificado_por = p_id_usuario
    WHERE  id = p_id_os_equipo;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'finalizar_equipo', 'en ejecución', 'completado',
            LEFT(CONCAT('Trabajo finalizado en ', IFNULL(v_nombre, 'el equipo'), ' (', v_num_os, '). Informe técnico ', v_cod, '.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'numero_informe', v_cod));
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'generar_informe', 'borrador', v_cod,
            LEFT(CONCAT('Informe técnico ', v_cod, ' generado desde la app (HU-16) con las 5 etapas conformes.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', p_id_os_equipo, 'numero_informe', v_cod));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Informe técnico ', v_cod, ' generado.') AS Mensaje;
    SELECT v_informe AS id_informe, v_cod AS numero_informe, 'completado' AS estado_equipo, 0 AS repetida;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 2)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ArmarFirmasOsMovil', 'SP_GenerarInformeEquipoMovil') ORDER BY ROUTINE_NAME;

-- B) La OS-000005 (id 8) y su técnico: la lista de informes. El informe ya generado debe salir COMPLETO con su responsable (el contacto de la OS); los demás, INCOMPLETO
SET @os  = 8;
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
CALL SP_ObtenerFirmasMovil(@tec, @os);          -- 1 mensaje · 2 cabecera · 3 informes · 4 responsables
