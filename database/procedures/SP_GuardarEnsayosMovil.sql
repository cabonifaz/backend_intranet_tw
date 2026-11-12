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
