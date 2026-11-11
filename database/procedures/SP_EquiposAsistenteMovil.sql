-- ============================================================
-- SP_EquiposAsistenteMovil  (App Mobile HU-19 — "Cambiar" el equipo del contexto · lectura)
-- Los equipos (objetivos, SP_ArmarObjetivosMovil) de las OS asignadas al técnico que siguen activas (no finalizadas, anuladas ni reprogramadas), con cuántos
-- documentos oficiales consultables tiene cada uno (SP_ArmarDocumentosAsistenteMovil, solo los disponibles). El equipo en ejecución va primero, luego los pausados,
-- por iniciar, observados y completados. Máx. 15 OS y 50 equipos.
-- Resultados: 1 mensaje · 2 equipos (id_os, numero_os, id_os_equipo, nombre, numero, marca, modelo, codigo_cliente, estado, en_trabajo, fuentes_disponibles).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EquiposAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_EquiposAsistenteMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_i         INT DEFAULT 1;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_os        BIGINT;
    DECLARE v_num       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_oe        BIGINT;
    DECLARE v_sum       BIGINT;
    DECLARE v_cuenta    INT;
    DECLARE v_estado_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida    DATETIME;
    DECLARE v_llegada   DATETIME;
    DECLARE v_hab       TINYINT;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_asist;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq_asist;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_asist;
    CREATE TEMPORARY TABLE tmp_os_asist (
        n INT NOT NULL AUTO_INCREMENT, id_os BIGINT NOT NULL, numero_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (n));
    INSERT INTO tmp_os_asist (id_os, numero_os)
    SELECT os.id_os, os.numero
    FROM   orden_servicio os
    WHERE  os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada', 'reprogramada')
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ORDER BY os.id_os DESC LIMIT 15;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_asist;
    CREATE TEMPORARY TABLE tmp_eq_asist (
        n INT NOT NULL AUTO_INCREMENT, id_os BIGINT NOT NULL, numero_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_os_equipo BIGINT NOT NULL,
        id_suministro BIGINT NULL, nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, numero INT,
        marca VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, modelo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        prioridad INT NOT NULL DEFAULT 4, fuentes INT NOT NULL DEFAULT 0, PRIMARY KEY (n));

    -- Los objetivos de cada OS salen de SP_ArmarObjetivosMovil (una sola regla de qué es un equipo del servicio)
    SELECT COUNT(*) INTO v_n FROM tmp_os_asist;
    SET v_i = 1;
    WHILE v_i <= v_n DO
        SELECT o.id_os, o.numero_os INTO v_os, v_num FROM tmp_os_asist o WHERE o.n = v_i;
        CALL SP_ArmarObjetivosMovil(v_os, v_estado_os, v_salida, v_llegada, v_hab, v_motivo);
        INSERT INTO tmp_eq_asist (id_os, numero_os, id_os_equipo, id_suministro, nombre, numero, marca, modelo, codigo_cliente, estado, prioridad)
        SELECT v_os, v_num, t.id_os_equipo, ec.id_suministro, t.nombre, t.numero, t.marca, t.modelo, t.codigo_cliente, t.estado,
               CASE t.estado WHEN 'en_ejecucion' THEN 0 WHEN 'pausado' THEN 1 WHEN 'por_iniciar' THEN 2 WHEN 'observado' THEN 3 ELSE 4 END
        FROM   tmp_obj_mov t
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = t.id_equipo;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SET v_i = v_i + 1;
    END WHILE;

    -- Documentos oficiales disponibles de cada equipo (se calculan para los primeros 200)
    DELETE e FROM tmp_eq_asist e WHERE e.n > 200;
    SELECT COUNT(*) INTO v_n FROM tmp_eq_asist;
    SET v_i = 1;
    WHILE v_i <= v_n DO
        SELECT e.id_os, e.id_os_equipo, e.id_suministro INTO v_os, v_oe, v_sum FROM tmp_eq_asist e WHERE e.n = v_i;
        CALL SP_ArmarDocumentosAsistenteMovil(v_os, v_oe, v_sum);
        SELECT COUNT(*) INTO v_cuenta FROM tmp_doc_asist d WHERE d.disponible = 1;
        UPDATE tmp_eq_asist SET fuentes = v_cuenta WHERE n = v_i;
        SET v_i = v_i + 1;
    END WHILE;
    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT e.id_os, e.numero_os, e.id_os_equipo, e.nombre, e.numero, e.marca, e.modelo, e.codigo_cliente, e.estado,
           IF(e.estado = 'en_ejecucion', 1, 0) AS en_trabajo, e.fuentes AS fuentes_disponibles
    FROM   tmp_eq_asist e
    ORDER BY e.prioridad, e.id_os DESC, e.numero, e.id_os_equipo
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_asist;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_asist;
END$$

DELIMITER ;
