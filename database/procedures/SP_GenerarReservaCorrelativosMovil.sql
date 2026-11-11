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
