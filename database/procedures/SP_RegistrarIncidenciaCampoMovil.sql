-- ============================================================
-- SP_RegistrarIncidenciaCampoMovil  (App Mobile HU-32 — "Registrar incidencia" y "Escalar" · escritura)
-- El jefe registra una incidencia de un servicio de su área (imprevisto en ruta o en planta): tipo, severidad, impacto, descripción y foto (solo cámara).
--   - Se guarda en incidencia_operativa, la misma tabla que lee la bandeja de Seguimiento Operativo: una incidencia con impacto "detiene" o de nivel crítico
--     deja el servicio "con incidente" y genera la alerta crítica. Queda a nombre del técnico de la OS (id_usuario) y del jefe (creado_por).
--   - Tipo: catálogo TIPO_INCIDENCIA_OPERATIVA (1 a 6). Severidad: NIVEL_ALERTA (1 Bajo · 2 Medio · 3 Alto · 4 Crítico). Impacto: retrasa | detiene.
--   - p_escalar = 1: la incidencia queda "escalada" (escalada_en) y se avisa a los administradores y al Jefe de Operaciones.
--   - La OS debe estar en el alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil). p_evidencia = ruta de la foto ya guardada por el back.
-- Resultados: 1 mensaje; 2 (id_incidencia, estado, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarIncidenciaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarIncidenciaCampoMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_id_tipo     INT,
    IN p_id_nivel    INT,
    IN p_impacto     VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion VARCHAR(1100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_evidencia   VARCHAR(500)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_escalar     TINYINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_impacto   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desc      VARCHAR(1100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec       BIGINT DEFAULT NULL;
    DECLARE v_tipo_txt  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nivel_txt VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id        BIGINT;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_impacto = LOWER(TRIM(IFNULL(p_impacto, '')));
    SET v_desc    = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT t.String1 INTO v_tipo_txt FROM tabla_maestra t
    WHERE  t.Descripcion = 'TIPO_INCIDENCIA_OPERATIVA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_tipo AND t.eliminado_en IS NULL LIMIT 1;
    IF v_tipo_txt IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de incidencia.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT t.String1 INTO v_nivel_txt FROM tabla_maestra t
    WHERE  t.Descripcion = 'NIVEL_ALERTA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_nivel AND t.eliminado_en IS NULL LIMIT 1;
    IF v_nivel_txt IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona la severidad.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_impacto NOT IN ('retrasa', 'detiene') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el impacto en el servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_desc IS NULL OR CHAR_LENGTH(v_desc) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe la descripción de la incidencia (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_desc) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 1000 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.numero, os.id_tecnico_principal INTO v_num_os, v_tec FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    SET v_estado = IF(IFNULL(p_escalar, 0) = 1, 'escalada', 'abierta');

    START TRANSACTION;

    INSERT INTO incidencia_operativa (id_os, id_usuario, id_tipo, descripcion, id_nivel_alerta, estado, impacto, fecha_registro, creado_por, evidencia_url, escalada_en)
    VALUES (p_id_os, IFNULL(v_tec, p_id_usuario), p_id_tipo, v_desc, p_id_nivel, v_estado, v_impacto, NOW(), p_id_usuario,
            NULLIF(TRIM(IFNULL(p_evidencia, '')), ''), IF(v_estado = 'escalada', NOW(), NULL));
    SET v_id = LAST_INSERT_ID();

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    IF v_estado = 'escalada' THEN
        SET v_texto = LEFT(CONCAT(v_nom_jefe, ' escaló una incidencia en ', v_num_os, ': ', v_tipo_txt, ' · severidad ', v_nivel_txt, ' · ',
                                  IF(v_impacto = 'detiene', 'detiene el servicio', 'retrasa el servicio'), '. ', v_desc), 500);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, CONCAT('Incidencia escalada: ', LEFT(v_tipo_txt, 60)), v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND  (u.rol_sistema IN ('administrador', 'admin') OR u.cargo = 'jefe_operaciones');
        SET v_notif = ROW_COUNT();
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, IF(v_estado = 'escalada', 'incidencia_escalada', 'incidencia_registrada'), NULL, v_estado,
            LEFT(CONCAT(v_nom_jefe, ' registró una incidencia en ', v_num_os, ': ', v_tipo_txt, ' · ', v_nivel_txt, ' · ', v_impacto, ' · ', v_desc), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_incidencia', v_id, 'id_tipo', p_id_tipo, 'id_nivel', p_id_nivel, 'impacto', v_impacto));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_estado = 'escalada', 'Incidencia registrada y escalada.', 'Incidencia registrada.') AS Mensaje;
    SELECT v_id AS id_incidencia, v_estado AS estado, v_notif AS notificados;
END$$

DELIMITER ;
