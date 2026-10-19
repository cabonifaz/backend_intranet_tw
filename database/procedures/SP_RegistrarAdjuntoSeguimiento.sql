-- HU-19 Documentos adjuntos (opcionales) de un seguimiento.
-- p_solo_validar = 1: valida antes de guardar el archivo en disco (no inserta).
-- Reglas: el seguimiento existe, es de una propuesta del área del usuario (o todas con
-- propuesta_seguimiento_todas), el usuario tiene propuesta_seguimiento_registrar y el seguimiento
-- tiene como máximo 5 adjuntos.
-- Resultados: 1 mensaje, 2 id_adjunto (solo al guardar).
DROP PROCEDURE IF EXISTS SP_RegistrarAdjuntoSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarAdjuntoSeguimiento(
    IN p_id_usuario      BIGINT,
    IN p_id_seguimiento  BIGINT,
    IN p_nombre_archivo  VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta            VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_contenido  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_bytes    BIGINT,
    IN p_solo_validar    TINYINT
)
proc: BEGIN
    DECLARE v_area_usuario VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_resp    VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe       INT DEFAULT 0;
    DECLARE v_cantidad     INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar seguimientos.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(u.area) INTO v_existe, v_area_resp
    FROM seguimiento_comercial s
    JOIN propuesta_comercial p ON p.id_propuesta = s.id_propuesta
    JOIN usuario u ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE s.id_seguimiento = p_id_seguimiento AND s.eliminado_en IS NULL;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El seguimiento no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT area INTO v_area_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas') = 0
       AND IFNULL(v_area_usuario, '') <> IFNULL(v_area_resp, '-') THEN
        SELECT 1 AS IdTipoMensaje, 'El seguimiento no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_cantidad FROM seguimiento_adjunto
    WHERE id_seguimiento = p_id_seguimiento AND eliminado_en IS NULL;
    IF v_cantidad >= 5 THEN
        SELECT 1 AS IdTipoMensaje, 'El seguimiento ya tiene el máximo de 5 adjuntos.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;

    INSERT INTO seguimiento_adjunto (id_seguimiento, nombre_archivo, ruta, tipo_contenido, tamano_bytes, creado_por)
    VALUES (p_id_seguimiento, p_nombre_archivo, p_ruta, p_tipo_contenido, p_tamano_bytes, p_id_usuario);

    SELECT 2 AS IdTipoMensaje, 'Adjunto registrado.' AS Mensaje;
    SELECT LAST_INSERT_ID() AS id_adjunto;
END$$

DELIMITER ;
