-- Aplicar en la base (Ensayo con lecturas fuera de EMP y encargado notificado: App Mobile HU-10 / HU-16). Incluye la migración 107. Sin datos de prueba.
-- Ejecutar completo con Alt+X. NO subir al repositorio. Después REINICIAR la API.
-- Requiere (ya existentes): la migración 100 (ensayos), el script de la HU-15 / HU-16 (SP_ArmarEtapasEquipoMovil) y la tabla notificacion.
-- No vuelvas a ejecutar _aplicar_ensayos_movil.sql ni _aplicar_informe_equipo_movil.sql después de este: dejarían SP_GuardarEnsayosMovil y SP_ArmarEtapasEquipoMovil con su versión anterior.
-- Qué hace: agrega informe_tecnico.error_critico_notificado_en (migración 107), actualiza SP_GuardarEnsayosMovil y SP_ArmarEtapasEquipoMovil.

-- ############################################################
-- 0) Requisitos
-- ############################################################
DROP PROCEDURE IF EXISTS tmp_hu16b_requisitos;
DELIMITER $$
CREATE PROCEDURE tmp_hu16b_requisitos()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ArmarEtapasEquipoMovil') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes _aplicar_informe_equipo_movil.sql (HU-15 / HU-16): SP_ArmarEtapasEquipoMovil.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_motivo') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes la migración 100_ensayos_calibracion_movil.sql (HU-10).';
    END IF;
END$$
DELIMITER ;
CALL tmp_hu16b_requisitos();
DROP PROCEDURE IF EXISTS tmp_hu16b_requisitos;

-- ############################################################
-- 1) Migración 107
-- ############################################################
-- ============================================================
-- Migración 107 — Ensayo con lecturas fuera de EMP y encargado notificado (App Mobile HU-10 / HU-16)
--   informe_tecnico.error_critico_notificado_en: cuándo se avisó al encargado del área (o a los administradores) del ensayo guardado con error crítico
--   ("Guardar de todas formas", SP_GuardarEnsayosMovil). NULL = nadie fue notificado. Con la notificación hecha, el ensayo ya no bloquea el cierre del equipo
--   (SP_ArmarEtapasEquipoMovil: etapa "notificado"): el informe se puede generar y queda registrado como resultado fuera de EMP.
--   Los informes que ya estaban guardados con error crítico toman la fecha de su notificación "Ensayo con error crítico" (la de la OS). No borra datos. IDEMPOTENTE.
-- ============================================================
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_notificado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_notificado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE informe_tecnico it
SET    it.error_critico_notificado_en = (SELECT MAX(n.fecha_creacion) FROM notificacion n
                                         WHERE n.titulo = 'Ensayo con error crítico' AND n.entidad_tipo = 'orden_servicio' AND n.id_entidad = it.id_os AND n.eliminado_en IS NULL)
WHERE  it.error_critico_motivo IS NOT NULL AND it.error_critico_notificado_en IS NULL AND it.eliminado_en IS NULL;

-- ############################################################
-- SP_GuardarEnsayosMovil
-- ############################################################
-- ============================================================
-- SP_GuardarEnsayosMovil  (App Mobile HU-10 — Ensayos y Calibración · escritura)
-- Guarda las lecturas de pesaje y excentricidad del equipo. La app envía SOLO la carga (L) y la indicación (I); aquí se calcula el error (E = I − L),
-- el EMP (SP_EmpEnsayoMovil) y la conformidad (|E| ≤ EMP): nunca se confía en lo que la app mostró.
--   - Acceso (SP_ContextoEnsayoMovil): OS del técnico, llegada registrada (Hard Stop), equipo EN EJECUCIÓN y variables ambientales guardadas (HU-09).
--   - p_json = {"pesaje":[{"carga":10000,"indicacion":10005}], "excentricidad":[{"carga":26000,"lecturas":[26000,26004,null,…]}]}. Se puede guardar
--     incompleto (borrador); cada guardado REEMPLAZA las lecturas del técnico de ese informe.
--   - Excentricidad: posiciones por forma del plato (rectangular y circular 5, triangular 4); la lectura 1 es el centro.
--   - Error crítico = una lectura fuera del EMP. Se puede guardar igual (borrador); para FINALIZAR hay que corregirlo o aceptarlo con un motivo (3 a 300
--     caracteres, "Guardar de todas formas"): el motivo se guarda, el ensayo queda marcado con error en el informe y se avisa al encargado del área.
--   - p_finalizar = 1 exige pesaje y excentricidad completos (todas las posiciones de cada carga) y marca la etapa como finalizada; guardar de nuevo
--     sin finalizar la reabre ("Editar lecturas").
--   - Crea el informe técnico en borrador (informe_tecnico, número provisional BRR-…) si todavía no existe; lo definitivo lo asigna la generación del informe.
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 (id_informe, criticos, finalizado, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarEnsayosMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarEnsayosMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_forma        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_json         LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_finalizar    TINYINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_forma    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_ant VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pos_req  INT;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_i        INT DEFAULT 0;
    DECLARE v_fila     BIGINT;
    DECLARE v_carga    DECIMAL(14,4);
    DECLARE v_emp      DECIMAL(14,4);
    DECLARE v_n_pes    INT DEFAULT 0;
    DECLARE v_n_ecc    INT DEFAULT 0;
    DECLARE v_incompl  INT DEFAULT 0;
    DECLARE v_invalid  INT DEFAULT 0;
    DECLARE v_criticos INT DEFAULT 0;
    DECLARE v_err_max  DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    TINYINT DEFAULT 0;
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_forma = LOWER(TRIM(IFNULL(p_forma, 'rectangular')));
    IF v_forma NOT IN ('rectangular', 'circular', 'triangular') THEN
        SELECT 1 AS IdTipoMensaje, 'La forma del plato no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_pos_req = IF(v_forma = 'triangular', 4, 5);
    IF p_json IS NULL OR NOT JSON_VALID(p_json) OR CHAR_LENGTH(p_json) > 30000 THEN
        SELECT 1 AS IdTipoMensaje, 'Las lecturas enviadas no son válidas.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NOT NULL AND (CHAR_LENGTH(v_motivo) < 3 OR CHAR_LENGTH(v_motivo) > 300) THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo debe tener entre 3 y 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar los ensayos.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar ensayos.'));
    END IF;
    IF v_msg IS NULL AND (v_clase IS NULL OR v_e IS NULL OR v_e <= 0) THEN
        SET v_msg = 'El equipo no tiene clase de exactitud o división e registradas: complétalas en la ficha del equipo para evaluar el ensayo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- ── Lecturas que llegan ─────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
    CREATE TEMPORARY TABLE tmp_ens_filas (
        id INT NOT NULL AUTO_INCREMENT, tipo VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, grupo INT NULL, pos INT NULL,
        carga DECIMAL(14,4) NULL, ind DECIMAL(14,4) NULL, emp DECIMAL(14,4) NULL, err DECIMAL(14,4) NULL, res VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id));

    INSERT INTO tmp_ens_filas (tipo, grupo, pos, carga, ind)
    SELECT 'pesaje', NULL, jt.n, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.pesaje[*]' COLUMNS (
               n FOR ORDINALITY,
               carga DECIMAL(14,4) PATH '$.carga'      NULL ON EMPTY NULL ON ERROR,
               ind   DECIMAL(14,4) PATH '$.indicacion' NULL ON EMPTY NULL ON ERROR)) jt;

    INSERT INTO tmp_ens_filas (tipo, grupo, pos, carga, ind)
    SELECT 'excentricidad', jt.g, jt.pos, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.excentricidad[*]' COLUMNS (
               g FOR ORDINALITY,
               carga DECIMAL(14,4) PATH '$.carga' NULL ON EMPTY NULL ON ERROR,
               NESTED PATH '$.lecturas[*]' COLUMNS (
                   pos FOR ORDINALITY,
                   ind DECIMAL(14,4) PATH '$' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.pos IS NOT NULL;

    SELECT COUNT(*) INTO v_n FROM tmp_ens_filas;
    SELECT COUNT(*) INTO v_n_pes FROM tmp_ens_filas WHERE tipo = 'pesaje';
    SELECT COUNT(DISTINCT grupo) INTO v_n_ecc FROM tmp_ens_filas WHERE tipo = 'excentricidad';

    -- Límites: cantidad de filas, cargas e indicaciones razonables y posiciones según la forma del plato
    SELECT COUNT(*) INTO v_invalid
    FROM   tmp_ens_filas
    WHERE  carga IS NULL OR carga <= 0 OR carga > 100000000 OR (ind IS NOT NULL AND (ind < 0 OR ind > 100000000))
        OR (tipo = 'pesaje' AND pos > 12) OR (tipo = 'excentricidad' AND (grupo > 10 OR pos > v_pos_req));
    IF v_n = 0 OR v_n_pes > 12 OR v_n_ecc > 10 OR v_invalid > 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
        SELECT 1 AS IdTipoMensaje,
               IF(v_n = 0, 'No hay lecturas para guardar.',
                  'Revisa las lecturas: cada carga debe ser mayor que 0, las indicaciones no pueden ser negativas y no se aceptan más de 12 cargas de pesaje, 10 de excentricidad ni posiciones fuera del plato.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── EMP, error y conformidad: aquí, una sola vez ───────────────────────────────────────────
    WHILE v_i < v_n DO
        SELECT id, carga INTO v_fila, v_carga FROM tmp_ens_filas ORDER BY id LIMIT 1 OFFSET v_i;
        CALL SP_EmpEnsayoMovil(v_clase, v_e, v_carga, v_emp);
        UPDATE tmp_ens_filas SET emp = v_emp WHERE id = v_fila;
        SET v_i = v_i + 1;
    END WHILE;
    UPDATE tmp_ens_filas
    SET    err = IF(ind IS NULL, NULL, ind - carga),
           res = IF(ind IS NULL OR emp IS NULL, NULL, IF(ABS(ind - carga) <= emp, 'conforme', 'no_conforme'));

    SELECT COUNT(*) INTO v_criticos FROM tmp_ens_filas WHERE res = 'no_conforme';
    SELECT MAX(ABS(err)) INTO v_err_max FROM tmp_ens_filas WHERE tipo = 'pesaje';

    -- Completitud (para finalizar): todo con indicación y cada carga de excentricidad con todas sus posiciones
    SELECT COUNT(*) INTO v_incompl FROM tmp_ens_filas WHERE ind IS NULL;
    IF v_n_pes = 0 OR v_n_ecc = 0 THEN SET v_incompl = v_incompl + 1; END IF;
    SELECT COUNT(*) INTO v_invalid
    FROM  (SELECT grupo, COUNT(*) AS c FROM tmp_ens_filas WHERE tipo = 'excentricidad' GROUP BY grupo HAVING COUNT(*) <> v_pos_req) x;
    SET v_incompl = v_incompl + v_invalid;

    IF p_finalizar = 1 THEN
        IF v_incompl > 0 THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
            SELECT 1 AS IdTipoMensaje, 'Completa todas las lecturas de pesaje y de excentricidad (todas las posiciones de cada carga) antes de finalizar el ensayo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_criticos > 0 AND v_motivo IS NULL THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
            SELECT 1 AS IdTipoMensaje, 'Hay un error crítico: corrige la lectura, repite el ensayo o usa "Guardar de todas formas" con un motivo.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_final = 1;
    END IF;

    -- ── Informe técnico (borrador) ───────────────────────────────────────────────────────────
    SELECT it.id_informe, it.error_critico_motivo INTO v_informe, v_motivo_ant
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;
    IF v_informe IS NULL THEN
        INSERT INTO informe_tecnico (numero, id_os, id_equipo, id_tecnico, estado, version, fecha_creacion, creado_por)
        VALUES (CONCAT('BRR-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, 'borrador', 1, NOW(), p_id_usuario);
        SET v_informe = LAST_INSERT_ID();
        UPDATE informe_tecnico SET numero = CONCAT('BRR-', LPAD(v_informe, 8, '0')) WHERE id_informe = v_informe;
    END IF;

    UPDATE informe_ensayo
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  id_informe = v_informe AND tipo IN ('pesaje', 'excentricidad') AND origen = 'tecnico' AND eliminado_en IS NULL;

    INSERT INTO informe_ensayo (id_informe, tipo, orden, punto, carga, lectura, error, tolerancia, resultado, origen, creado_por, grupo, critico)
    SELECT v_informe, t.tipo, t.pos, IF(t.tipo = 'pesaje', CONCAT('Carga ', t.pos), CONCAT('Pos. ', t.pos)), t.carga, t.ind, t.err, t.emp, t.res,
           'tecnico', p_id_usuario, t.grupo, IF(t.res = 'no_conforme', 1, 0)
    FROM   tmp_ens_filas t
    ORDER BY t.id;

    UPDATE informe_tecnico
    SET    forma_plato = v_forma,
           error_critico_motivo = IF(v_criticos > 0, v_motivo, NULL),
           error_critico_notificado_en = IF(v_criticos > 0, error_critico_notificado_en, NULL),
           ensayos_finalizado_en = IF(v_final = 1, UTC_TIMESTAMP(), NULL),
           resultado_global = IF(v_criticos > 0, 'fuera', 'dentro'),
           error_maximo = v_err_max,
           modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- ── Error crítico aceptado: aviso al encargado del área (y, si no hay, a los administradores) ──────────
    IF v_criticos > 0 AND v_motivo IS NOT NULL AND (v_motivo_ant IS NULL OR v_motivo_ant <> v_motivo) THEN
        CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
        SET v_texto = LEFT(CONCAT(v_nombre_tec, ' guardó el ensayo de ', v_nombre, ' (', v_num_os, ') con ', v_criticos,
                                  IF(v_criticos = 1, ' lectura fuera', ' lecturas fuera'), ' del EMP. Motivo: ', v_motivo), 500);
        IF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            VALUES (v_id_enc, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario);
            SET v_notif = 1;
        ELSE
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.rol_sistema IN ('administrador', 'admin');
            SET v_notif = ROW_COUNT();
        END IF;
        -- Quedó constancia de que se avisó (o de que no había a quién avisar): con el aviso hecho, el ensayo ya no bloquea el cierre del equipo (HU-16)
        UPDATE informe_tecnico SET error_critico_notificado_en = IF(v_notif > 0, NOW(), NULL) WHERE id_informe = v_informe;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, IF(v_final = 1, 'finalizar_ensayos', 'guardar_ensayos'), NULL, IF(v_final = 1, 'finalizado', 'borrador'),
            LEFT(CONCAT(IF(v_final = 1, 'Ensayos finalizados', 'Ensayos guardados'), ' en ', v_num_os, ': ', v_n_pes, ' cargas de pesaje, ', v_n_ecc, ' de excentricidad, ',
                        v_criticos, ' fuera del EMP', IF(v_criticos > 0 AND v_motivo IS NOT NULL, CONCAT('. Motivo: ', v_motivo), '')), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_informe', v_informe, 'criticos', v_criticos, 'clase', v_clase, 'e', v_e));

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;

    SELECT 2 AS IdTipoMensaje,
           IF(v_final = 1, 'Ensayo finalizado.', IF(v_criticos > 0 AND v_motivo IS NOT NULL, 'Ensayo guardado con error crítico: se avisó al encargado.', 'Ensayo guardado.')) AS Mensaje;
    SELECT v_informe AS id_informe, v_criticos AS criticos, v_final AS finalizado, v_notif AS notificados;
END$$

DELIMITER ;

-- ############################################################
-- SP_ArmarEtapasEquipoMovil
-- ############################################################
-- ============================================================
-- SP_ArmarEtapasEquipoMovil  (App Mobile HU-08 / HU-15 / HU-16 — apoyo, NO es un endpoint)
-- Las 5 etapas del trabajo en un equipo y sus PENDIENTES, UNA sola vez. Las leen SP_ObtenerTrabajoEquipoMovil (pantalla "Trabajo en el equipo"),
-- SP_ValidarCierreEquipoMovil (Hard Stop de "Finalizar trabajo en equipo") y SP_GenerarInformeEquipoMovil (generar el informe técnico): así el botón, el
-- modal de pendientes y la generación nunca discrepan. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov, tmp_pend_eq.
--   tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible):
--     estado: conforme | en_curso | pendiente | bloqueado | no_conforme (Ensayos finalizados CON error crítico: bloquea el cierre).
--     1 variables   conforme con las variables ambientales guardadas (HU-09).
--     2 fotos       conforme con las 9 evidencias completas: aprobadas por la IA, forzadas o sin validar (SP_ResumenEvidenciasMovil, HU-11 / HU-12).
--     3 ensayos     bloqueado sin variables; conforme al finalizar sin error crítico; si se finalizó con error crítico: NOTIFICADO (el encargado ya fue avisado,
--                   informe_tecnico.error_critico_notificado_en: cuenta como resuelto y deja generar el informe, que queda registrado fuera de EMP) o NO CONFORME
--                   (nadie fue notificado: bloquea el cierre) (HU-10).
--     4 cabecera    "Cabecera del informe" (HU-15): conforme con la cabecera guardada y sin pendientes (recomendaciones o "sin recomendaciones", fallas o
--                   "sin fallas", Detalle Serv. guardado, Diagnóstico final completo y cada falla con su prueba).
--     5 correlativo conforme con el certificado guardado en el informe (HU-14); bloqueado hasta finalizar los ensayos.
--   tmp_pend_eq (id, orden, codigo, texto): una fila por pendiente con el texto para el técnico ("Falta la foto Final", "Error crítico en 20,000 kg (+34 kg ·
--     EMP ±20 kg)", "Falta completar el Diagnóstico final", "Esperando el correlativo de Metrología (TK-MET-00241)"…). Una etapa conforme no tiene pendientes.
--   p_conformes = etapas conformes de 5.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarEtapasEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarEtapasEquipoMovil(
    IN  p_id_os     BIGINT,
    IN  p_id_equipo BIGINT,
    OUT p_conformes INT
)
BEGIN
    DECLARE v_vars       TINYINT DEFAULT 0;
    DECLARE v_det_vars   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe    BIGINT DEFAULT NULL;
    DECLARE v_n_ensayos  INT DEFAULT 0;
    DECLARE v_ens_final  DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert       VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cab_guard  DATETIME DEFAULT NULL;
    DECLARE v_tiene_det  TINYINT DEFAULT 0;
    DECLARE v_sev        VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_est_fin    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sin_rec    TINYINT DEFAULT 0;
    DECLARE v_sin_fal    TINYINT DEFAULT 0;
    DECLARE v_n_rec      INT DEFAULT 0;
    DECLARE v_n_fal      INT DEFAULT 0;
    DECLARE v_clase      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap        DECIMAL(14,4);
    DECLARE v_d          DECIMAL(14,4);
    DECLARE v_e          DECIMAL(14,4);
    DECLARE v_ev_total   INT DEFAULT 9;
    DECLARE v_ev_compl   INT DEFAULT 0;
    DECLARE v_ev_forz    INT DEFAULT 0;
    DECLARE v_ev_rech    INT DEFAULT 0;
    DECLARE v_ev_oblig   INT DEFAULT 0;
    DECLARE v_tk_estado  VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_num     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_corr    VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_crit_carga DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_ens_notif  DATETIME DEFAULT NULL;
    DECLARE v_pend_cab   INT DEFAULT 0;
    DECLARE v_prim_cab   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE s1 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s2 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s3 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s4 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s5 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    CREATE TEMPORARY TABLE tmp_etapas_mov (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        disponible TINYINT DEFAULT 0, PRIMARY KEY (orden));
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    CREATE TEMPORARY TABLE tmp_pend_eq (
        id INT NOT NULL AUTO_INCREMENT, orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        texto VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (id));

    CALL SP_EspecEquipoMovil(p_id_equipo, v_clase, v_unidad, v_cap, v_d, v_e);

    -- ── 1. Variables ambientales (HU-09) ───────────────────────────────────────────────────────
    SELECT COUNT(*) INTO v_vars FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL;
    IF v_vars > 0 THEN
        SELECT CONCAT('T° ', TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.temperatura_c AS CHAR))), ' °C · h ',
                      TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.humedad_pct AS CHAR))), ' % · Procedencia ', IFNULL(va.procedencia, 'N.I'))
        INTO   v_det_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL
        ORDER BY va.id_variable DESC LIMIT 1;
    ELSE
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (1, 'variables', 'Faltan las variables ambientales (temperatura y humedad)');
    END IF;

    -- ── 2. Registro fotográfico (HU-11): una pendiente por evidencia que falta ─────────────────
    CALL SP_ResumenEvidenciasMovil(p_id_os, p_id_equipo, v_ev_total, v_ev_compl, v_ev_forz, v_ev_rech, v_ev_oblig);
    INSERT INTO tmp_pend_eq (orden, codigo, texto)
    SELECT 2, 'fotos',
           CASE WHEN c.rechazada = 1 THEN CONCAT('La toma de ', c.nombre, ' fue rechazada: repítela o acéptala con un motivo')
                WHEN c.codigo = 'qr' THEN 'Falta la foto del QR'
                WHEN c.codigo = 'placa' THEN 'Falta la foto de la placa'
                WHEN c.codigo = 'informe' THEN 'Falta la foto del informe a mano'
                WHEN c.medio = 'video' THEN CONCAT('Falta el video de ', LOWER(c.nombre))
                ELSE CONCAT('Falta la foto ', c.nombre) END
    FROM   tmp_cat_evid c
    WHERE  c.completa = 0
    ORDER BY c.orden;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;

    -- ── Informe técnico del equipo (lo crea la primera captura de ensayos o de la cabecera) ───
    SELECT it.id_informe, it.ensayos_finalizado_en, it.error_critico_motivo, it.numero_certificado, it.cabecera_guardada_en, IF(it.detalle_servicio IS NULL, 0, 1),
           it.severidad_general, it.estado_equipo_final, it.sin_recomendaciones, it.sin_fallas, it.error_critico_notificado_en
    INTO   v_informe, v_ens_final, v_ens_motivo, v_cert, v_cab_guard, v_tiene_det, v_sev, v_est_fin, v_sin_rec, v_sin_fal, v_ens_notif
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = p_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_informe IS NOT NULL THEN
        SELECT COUNT(*) INTO v_n_ensayos FROM informe_ensayo ie WHERE ie.id_informe = v_informe AND ie.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n_rec FROM informe_recomendacion r WHERE r.id_informe = v_informe AND r.origen = 'tecnico' AND r.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n_fal FROM informe_observacion o WHERE o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL;
    END IF;

    -- ── 3. Ensayos y Calibración (HU-10) ───────────────────────────────────────────────────────
    IF v_vars = 0 THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'Se habilita al guardar las variables ambientales');
    ELSEIF v_ens_final IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'Falta finalizar los ensayos y la calibración');
    ELSEIF v_ens_motivo IS NOT NULL THEN
        -- Finalizado CON error crítico: si el encargado YA FUE NOTIFICADO (error_critico_notificado_en) no bloquea el cierre (etapa "notificado");
        -- si nadie fue notificado, una pendiente por cada lectura fuera del EMP (carga, error con signo y EMP)
        SELECT MIN(en.carga) INTO v_crit_carga FROM informe_ensayo en WHERE en.id_informe = v_informe AND en.eliminado_en IS NULL AND en.critico = 1;
        IF v_ens_notif IS NULL THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto)
            SELECT 3, 'ensayos',
                   LEFT(CONCAT('Error crítico en ', FORMAT(en.carga, 0), ' ', v_unidad, ' (', IF(en.error >= 0, '+', ''),
                               TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ROUND(en.error, 4) AS CHAR))), ' ', v_unidad, ' · EMP ±',
                               IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ROUND(en.tolerancia, 4) AS CHAR))), '?'), ' ', v_unidad, ')'), 250)
            FROM   informe_ensayo en
            WHERE  en.id_informe = v_informe AND en.eliminado_en IS NULL AND en.critico = 1
            ORDER BY en.tipo, en.grupo, en.orden;
            IF NOT EXISTS (SELECT 1 FROM tmp_pend_eq WHERE orden = 3) THEN
                INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'El ensayo se guardó con un error crítico y no se avisó al encargado: guárdalo de nuevo con un motivo');
            END IF;
        END IF;
    END IF;

    -- ── 4. Cabecera del informe (HU-15) ────────────────────────────────────────────────────────
    IF v_cab_guard IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar la cabecera del informe (Datos, Detalle Serv. y Observación y pruebas)');
    ELSE
        IF v_tiene_det = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar el Detalle del servicio');
        END IF;
        IF v_n_rec = 0 AND v_sin_rec = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Faltan las recomendaciones inmediatas (o indicar que no hay)');
        END IF;
        IF v_n_fal = 0 AND v_sin_fal = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Faltan las fallas del equipo (o indicar que no hay)');
        END IF;
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        SELECT 4, 'cabecera', LEFT(CONCAT('La falla ', o.codigo, ' no tiene una prueba que la justifique'), 250)
        FROM   informe_observacion o
        WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL
          AND  NOT EXISTS (SELECT 1 FROM informe_observacion_prueba p WHERE p.id_observacion = o.id_observacion AND p.eliminado_en IS NULL)
        ORDER BY o.orden;
        IF v_sev IS NULL OR v_est_fin IS NULL THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar el Diagnóstico final');
        END IF;
    END IF;
    SELECT COUNT(*) INTO v_pend_cab FROM tmp_pend_eq WHERE orden = 4;
    SELECT texto INTO v_prim_cab FROM tmp_pend_eq WHERE orden = 4 ORDER BY id LIMIT 1;

    -- ── 5. Correlativo y certificado (HU-14) ───────────────────────────────────────────────────
    SELECT t.estado, t.numero, t.correlativo_asignado INTO v_tk_estado, v_tk_num, v_tk_corr
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = p_id_equipo AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;
    IF v_cert IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        VALUES (5, 'correlativo',
                CASE WHEN v_ens_final IS NULL THEN 'Se habilita al finalizar los ensayos y la calibración'
                     WHEN v_tk_estado = 'asignado' THEN CONCAT('Falta usar el correlativo asignado (', IFNULL(v_tk_corr, ''), ')')
                     WHEN v_tk_estado = 'solicitado' THEN CONCAT('Esperando el correlativo de Metrología (', v_tk_num, ')')
                     ELSE 'Falta solicitar el correlativo de Metrología' END);
    END IF;

    -- ── Estados y detalle de las 5 etapas ──────────────────────────────────────────────────────
    SET s1 = IF(v_vars > 0, 'conforme', 'pendiente');
    SET s2 = IF(v_ev_compl >= v_ev_total, 'conforme', IF(v_ev_compl > 0 OR v_ev_rech > 0, 'en_curso', 'pendiente'));
    SET s3 = IF(v_vars = 0, 'bloqueado', IF(v_ens_final IS NOT NULL, IF(v_ens_motivo IS NULL, 'conforme', IF(v_ens_notif IS NULL, 'no_conforme', 'notificado')), IF(v_n_ensayos > 0, 'en_curso', 'pendiente')));
    SET s4 = IF(v_cab_guard IS NOT NULL AND v_pend_cab = 0, 'conforme', IF(v_cab_guard IS NOT NULL, 'en_curso', 'pendiente'));
    SET s5 = IF(v_cert IS NOT NULL, 'conforme', IF(v_ens_final IS NULL, 'bloqueado', IF(v_tk_estado IS NOT NULL, 'en_curso', 'pendiente')));

    INSERT INTO tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible) VALUES
        (1, 'variables', 'Variables ambientales', s1, IF(v_vars > 0, v_det_vars, 'Temperatura, humedad y procedencia'), 1),
        (2, 'fotos', 'Registro fotográfico', s2,
            CONCAT(v_ev_compl, ' de ', v_ev_total, ' · incluye foto del informe a mano', IF(v_ev_forz > 0, CONCAT(' · ', v_ev_forz, IF(v_ev_forz = 1, ' forzada', ' forzadas')), '')), 1),
        (3, 'ensayos', 'Ensayos y Calibración', s3,
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales',
               IF(v_ens_final IS NOT NULL,
                  IF(v_ens_motivo IS NULL, 'Pesaje y excentricidad conformes',
                     IF(v_ens_notif IS NULL,
                        CONCAT('Pesaje guardado con error crítico', IF(v_crit_carga IS NULL, '', CONCAT(' (', FORMAT(v_crit_carga, 0), ' ', v_unidad, ')'))),
                        CONCAT('Lectura fuera de EMP', IF(v_crit_carga IS NULL, '', CONCAT(' en ', FORMAT(v_crit_carga, 0), ' ', v_unidad)), ' · encargado notificado'))),
                  IF(v_n_ensayos > 0, CONCAT(v_n_ensayos, ' lecturas guardadas · falta finalizar'), 'Verificación de pesaje tras el ajuste'))), 1),
        (4, 'cabecera', 'Cabecera del informe', s4,
            IF(s4 = 'conforme', 'Cabecera completa', IF(s4 = 'en_curso', v_prim_cab, 'Datos · Detalle Serv. · Observación y pruebas')), 1),
        (5, 'correlativo', 'Correlativo y certificado', s5,
            IF(v_cert IS NOT NULL, CONCAT('Certificado ', v_cert),
               IF(v_ens_final IS NULL, 'Se habilita al finalizar los ensayos',
                  IF(v_tk_estado = 'asignado', CONCAT(v_tk_num, ' asignado · listo para usar'),
                     IF(v_tk_estado = 'solicitado', CONCAT(v_tk_num, ' · esperando a Metrología'), 'Correlativo de Metrología → N° de certificado')))), 1);

    -- "notificado" (ensayo con lecturas fuera de EMP y el encargado ya avisado) cuenta como resuelto: no bloquea el cierre
    SELECT COUNT(*) INTO p_conformes FROM tmp_etapas_mov WHERE estado IN ('conforme', 'notificado');
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 2)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_GuardarEnsayosMovil', 'SP_ArmarEtapasEquipoMovil') ORDER BY ROUTINE_NAME;

-- B) La columna nueva (debe ser 1)
SELECT 'Migración 107 (debe ser 1)' AS verificacion, COUNT(*) AS valor FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_notificado_en';

-- C) Informes guardados con error crítico y si el encargado fue notificado (NULL = nadie fue notificado: sigue bloqueando el cierre)
SELECT id_informe, id_os, id_equipo, error_critico_motivo, error_critico_notificado_en FROM informe_tecnico WHERE error_critico_motivo IS NOT NULL AND eliminado_en IS NULL;

-- D) El equipo 20 de la OS-000005 (solo lectura): 1 mensaje · 2 resumen · 3 etapas (ensayos debe salir "notificado" si C trae fecha) · 4 pendientes
SET @os  = 8;
SET @oe  = 20;
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
CALL SP_ValidarCierreEquipoMovil(@tec, @os, @oe);
