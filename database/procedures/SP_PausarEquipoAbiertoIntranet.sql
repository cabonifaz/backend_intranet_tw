-- ============================================================
-- SP_PausarEquipoAbiertoIntranet  (HU-55 — pausar el OTRO equipo que el técnico dejó en ejecución · escritura)
-- Un técnico solo puede tener un equipo en ejecución a la vez (SP_CambiarEstadoEquipoMovil). Si SP_IniciarRegistroIntranet responde que el técnico ya tiene otro equipo abierto,
-- quien registra lo pausa con este SP (en la OS que sea) y vuelve a iniciar el registro. p_id_os / p_id_os_equipo son el servicio y el equipo que se quiere registrar: de la OS sale el
-- técnico; el equipo a pausar es el OTRO en proceso y sin pausa de ese técnico (p_id_os_equipo se excluye).
-- Es una COPIA de la rama «pausar» de SP_CambiarEstadoEquipoMovil (que no se llama: su resultado se mezclaría con el de este SP y exige la llegada del otro servicio): cierra el
-- tramo de tiempo (acumulado_seg += ahora − reanudado_utc), deja pausado = 1 con el motivo, registra el evento de campo PAUSA a nombre del técnico (creado_por = quien registra) y la
-- auditoría. La pausa NO requiere aprobación. Motivo obligatorio (3 a 200 caracteres); en la pausa se guarda «Pausado desde la intranet por <quien registra>: <motivo>».
-- Acción seg_registrar_informe (FN_PermisoAccion).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: id_os, id_os_equipo, nombre (el equipo pausado).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_PausarEquipoAbiertoIntranet;

DELIMITER $$

CREATE PROCEDURE SP_PausarEquipoAbiertoIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_motivo         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_p  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico   BIGINT       DEFAULT NULL;
    DECLARE v_otro_id   BIGINT       DEFAULT NULL;
    DECLARE v_otro_os   BIGINT       DEFAULT NULL;
    DECLARE v_otro_num  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_otro_nom  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_en_proc   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pausado   TINYINT      DEFAULT 0;
    DECLARE v_ahora     DATETIME;
    DECLARE v_tipo_evt  INT          DEFAULT NULL;
    DECLARE v_nom_reg   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo de la pausa (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_motivo, '')) > 200 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 200 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.id_tecnico_principal INTO v_tecnico FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_tecnico IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o sin técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    -- El otro equipo abierto del técnico (la misma condición que la regla "un solo equipo a la vez")
    SELECT x.id, x.id_os, o2.numero, CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')')
    INTO   v_otro_id, v_otro_os, v_otro_num, v_otro_nom
    FROM   os_equipo x
    JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
    JOIN   orden_servicio o2 ON o2.id_os = x.id_os
    WHERE  x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
      AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
    LIMIT 1;
    IF v_otro_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay otro equipo en ejecución.' AS Mensaje; LEAVE proc;
    END IF;

    -- Se bloquea la fila y se vuelve a leer (otro envío pudo pausarlo entre tanto)
    SELECT oe.estado_ejecucion, oe.pausado INTO v_en_proc, v_pausado FROM os_equipo oe WHERE oe.id = v_otro_id FOR UPDATE;
    IF v_en_proc <> 'en_proceso' OR v_pausado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay otro equipo en ejecución.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_reg FROM usuario u WHERE u.id_usuario = p_id_registrador LIMIT 1;
    SET v_motivo_p = LEFT(CONCAT('Pausado desde la intranet por ', IFNULL(v_nom_reg, ''), ': ', v_motivo), 300);

    UPDATE os_equipo
    SET    acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_ahora))),
           reanudado_utc = NULL, pausado = 1, motivo_pausa = v_motivo_p, pausa_requiere_aprobacion = 0, modificado_por = p_id_registrador
    WHERE  id = v_otro_id;

    SELECT m.Num1 INTO v_tipo_evt FROM tabla_maestra m
    WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'PAUSA' AND m.eliminado_en IS NULL LIMIT 1;
    IF v_tipo_evt IS NOT NULL THEN
        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (v_otro_os, v_tecnico, v_tipo_evt, v_ahora, 1, LEFT(CONCAT('Pausa en ', v_otro_nom, '. Motivo: ', v_motivo_p), 1000), p_id_registrador);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', v_otro_id, 'pausar_equipo', 'en ejecución', 'pausado', LEFT(CONCAT('Pausa: ', v_motivo_p), 300), p_id_registrador, NOW(),
            JSON_OBJECT('id_os', v_otro_os, 'accion', 'pausar', 'via', 'intranet', 'idTecnico', v_tecnico, 'idRegistrador', p_id_registrador));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Equipo pausado.' AS Mensaje;
    SELECT v_otro_os AS id_os, v_otro_id AS id_os_equipo, v_otro_nom AS nombre;
END$$

DELIMITER ;
