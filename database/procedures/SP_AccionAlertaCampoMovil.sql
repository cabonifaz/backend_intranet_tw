-- ============================================================
-- SP_AccionAlertaCampoMovil  (App Mobile HU-32 — decisiones del jefe ante un pedido de apoyo · escritura)
-- p_accion:
--   llamar  : deja constancia de la llamada al técnico (auditoria_evento) y devuelve su teléfono (la llamada la hace el teléfono).
--   repetir : "Pedir repetir ensayo": avisa al técnico (notificación) para que repita el ensayo del equipo.
--   ajuste  : "Indicar ajuste y nueva calibración": avisa al técnico para que ajuste el equipo y calibre de nuevo.
--   p_mensaje (opcional, hasta 300 caracteres): indicación del jefe que se agrega al aviso.
-- Mismo acceso que SP_ObtenerAlertaCampoMovil (aviso propio de "Ensayo con error crítico" y OS del alcance del jefe).
-- Resultados: 1 mensaje · 2 técnico (nombre, telefono).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AccionAlertaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_AccionAlertaCampoMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT,
    IN p_accion          VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_mensaje         VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_accion    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_msg       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_titulo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tec       BIGINT;
    DECLARE v_id_os     BIGINT;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_tec   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_tec   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_accion = LOWER(TRIM(IFNULL(p_accion, '')));
    IF v_accion NOT IN ('llamar', 'repetir', 'ajuste') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_msg = NULLIF(TRIM(IFNULL(p_mensaje, '')), '');
    IF CHAR_LENGTH(IFNULL(v_msg, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'La indicación puede tener hasta 300 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT n.titulo, n.creado_por, n.id_entidad INTO v_titulo, v_tec, v_id_os
    FROM   notificacion n
    WHERE  n.id_notificacion = p_id_notificacion AND n.id_usuario_destino = p_id_usuario AND n.entidad_tipo = 'orden_servicio'
      AND  n.titulo LIKE 'Ensayo con error cr%'
    LIMIT 1;
    IF v_titulo IS NULL OR v_tec IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La alerta no existe o no es tuya.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarAlcanceJefaturaMovil(v_area, v_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = v_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio de esta alerta no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.numero INTO v_num_os FROM orden_servicio os WHERE os.id_os = v_id_os;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULLIF(TRIM(u.telefono), '') INTO v_nom_tec, v_tel_tec
    FROM   usuario u WHERE u.id_usuario = v_tec;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    IF v_accion = 'llamar' THEN
        IF v_tel_tec IS NULL THEN
            SELECT 1 AS IdTipoMensaje, CONCAT(v_nom_tec, ' no tiene un teléfono registrado.') AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    START TRANSACTION;

    IF v_accion IN ('repetir', 'ajuste') THEN
        SET v_texto = LEFT(CONCAT(v_nom_jefe, IF(v_accion = 'repetir', ' te pide repetir el ensayo', ' indica ajustar el equipo y volver a calibrar'),
                                  ' (', v_num_os, ').', IF(v_msg IS NULL, '', CONCAT(' ', v_msg))), 500);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_tec, 5, IF(v_accion = 'repetir', 'Repite el ensayo', 'Ajuste y nueva calibración'), v_texto, 'orden_servicio', v_id_os, NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', v_id_os, CONCAT('alerta_campo_', v_accion), NULL, NULL,
            LEFT(CONCAT(v_nom_jefe, CASE v_accion WHEN 'llamar' THEN ' llamó a ' WHEN 'repetir' THEN ' pidió repetir el ensayo a ' ELSE ' indicó ajuste y nueva calibración a ' END,
                        v_nom_tec, ' en ', v_num_os, IF(v_msg IS NULL, '', CONCAT(': ', v_msg))), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_notificacion', p_id_notificacion, 'id_tecnico', v_tec));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE v_accion WHEN 'llamar' THEN 'Llamada registrada.'
                         WHEN 'repetir' THEN CONCAT('Se avisó a ', v_nom_tec, ' que repita el ensayo.')
                         ELSE CONCAT('Se avisó a ', v_nom_tec, ' que ajuste el equipo y calibre de nuevo.') END AS Mensaje;
    SELECT v_nom_tec AS nombre, v_tel_tec AS telefono;
END$$

DELIMITER ;
