-- Observaciones 31/10 (RQ) — Adjuntos del requerimiento: foto, video, correo (.msg/.eml), PDF, Office, etc.
-- La API guarda el archivo en el almacenamiento y luego lo registra aquí (documento_adjunto, entidad 'requerimiento';
-- aparece en Documentos del expediente). p_solo_validar = 1: solo valida antes de guardar el archivo.
-- Reglas: acción rq_guardar, RQ no anulado ni cerrado, máximo 20 adjuntos por RQ.
-- Resultados: 1 mensaje, 2 id_documento (al registrar).
DROP PROCEDURE IF EXISTS SP_RegistrarAdjuntoRequerimiento;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarAdjuntoRequerimiento(
    IN p_id_usuario       BIGINT,
    IN p_id_requerimiento BIGINT,
    IN p_nombre_archivo   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta             VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_contenido   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_bytes     BIGINT,
    IN p_solo_validar     TINYINT
)
proc: BEGIN
    DECLARE v_estado  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total   INT DEFAULT 0;
    DECLARE v_id_doc  BIGINT;
    DECLARE v_usuario VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rq_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar requerimientos.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT estado INTO v_estado FROM requerimiento WHERE id_requerimiento = p_id_requerimiento AND SoftDelete = 0;
    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El requerimiento no existe.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado IN ('anulado', 'cerrado') THEN
        SELECT 1 AS IdTipoMensaje, 'No se pueden adjuntar documentos a un requerimiento anulado o cerrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_total FROM documento_adjunto
    WHERE entidad_tipo = 'requerimiento' AND id_entidad = p_id_requerimiento AND eliminado_en IS NULL;
    IF v_total >= 20 THEN
        SELECT 1 AS IdTipoMensaje, 'El requerimiento ya tiene el máximo de 20 adjuntos.' AS Mensaje; LEAVE proc;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo, version,
                                   id_visibilidad, metadatos, subido_por, fecha_carga, creado_en, creado_por)
    VALUES ('requerimiento', p_id_requerimiento,
            (SELECT MIN(Num1) FROM tabla_maestra WHERE IdMaestro = 96 AND IdEmpresa = 1 AND String2 = 'ADJUNTO_REQUERIMIENTO'),
            LEFT(p_nombre_archivo, 200), p_ruta, 1, 1,
            JSON_OBJECT('tipo_contenido', p_tipo_contenido, 'tamano_bytes', p_tamano_bytes),
            p_id_usuario, NOW(), NOW(), p_id_usuario);
    SET v_id_doc = LAST_INSERT_ID();

    INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
    VALUES (p_id_requerimiento, 'adjunto', 'Documento adjuntado', 'attach_file',
            CONCAT('Se adjuntó ', LEFT(p_nombre_archivo, 200), '.'), v_usuario, NOW(), NOW(), p_id_usuario);

    SELECT 2 AS IdTipoMensaje, 'Adjunto registrado.' AS Mensaje;
    SELECT v_id_doc AS id_documento;
END$$

DELIMITER ;
