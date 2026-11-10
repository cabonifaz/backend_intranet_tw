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
