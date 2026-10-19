-- HU-31 Adjuntar un documento interno al expediente.
-- Acción expediente_documento_adjuntar. Expediente no cerrado.
-- Obligatorios: tipo de documento (TIPO_DOCUMENTO_ADJUNTO con Num2 = 1), etapa asociada (ETAPA_EXPEDIENTE),
--   nombre (3 a 200), descripción (5 a 1000), visibilidad (VISIBILIDAD_DOCUMENTO: 1 interno o 2-4 un área) y el archivo.
-- Si ya existe un documento interno con el mismo tipo y nombre, el nuevo queda como la siguiente versión.
-- p_solo_validar = 1 valida sin guardar (antes de escribir el archivo).
-- Resultados: 1 mensaje · 2 documento creado
DROP PROCEDURE IF EXISTS SP_AdjuntarDocumentoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_AdjuntarDocumentoExpediente(
    IN p_id_usuario        BIGINT,
    IN p_id_expediente     BIGINT,
    IN p_id_tipo_documento INT,
    IN p_etapa             VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre            VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_visibilidad    INT,
    IN p_ruta              VARCHAR(500)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_archivo    VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano            BIGINT,
    IN p_tipo_contenido    VARCHAR(100)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_hash              CHAR(64)      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar      TINYINT
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre      VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_descripcion VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa_nom   VARCHAR(100)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version     INT DEFAULT 1;
    DECLARE v_id_doc      BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_nombre      = NULLIF(TRIM(IFNULL(p_nombre, '')), '');
    SET v_descripcion = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'expediente_documento_adjuntar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para adjuntar documentos al expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Etapa calculada (un RQ anulado o cerrado deja el expediente cerrado aunque no se haya guardado)
    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT MAX(etapa), MAX(numero) INTO v_estado, v_numero FROM tmp_exp;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
    IF v_numero IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'cerrado' THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado: no se pueden adjuntar documentos.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_tipo FROM tabla_maestra
    WHERE IdMaestro = 96 AND IdEmpresa = 1 AND Num1 = p_id_tipo_documento AND IFNULL(Num2, 0) = 1;
    IF v_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el tipo de documento.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_etapa_nom FROM tabla_maestra
    WHERE IdMaestro = 97 AND IdEmpresa = 1 AND String2 = TRIM(IFNULL(p_etapa, '')) AND String2 <> 'cerrado';
    IF v_etapa_nom IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione la etapa asociada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_nombre IS NULL OR CHAR_LENGTH(v_nombre) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el nombre del documento (mínimo 3 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_descripcion IS NULL OR CHAR_LENGTH(v_descripcion) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese la descripción del documento (mínimo 5 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_visibilidad, 0) NOT BETWEEN 1 AND 4
       OR NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 35 AND IdEmpresa = 1 AND Num1 = p_id_visibilidad) THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione la visibilidad: Interno o un área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Adjunte el archivo del documento.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT IFNULL(MAX(d.version), 0) + 1 INTO v_version
    FROM documento_adjunto d
    WHERE d.entidad_tipo = 'expediente' AND d.id_entidad = p_id_expediente AND d.eliminado_en IS NULL
      AND d.id_tipo_documento = p_id_tipo_documento
      AND JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.nombre_documento')) = v_nombre;

    START TRANSACTION;

    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo, version,
                                   id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
    VALUES ('expediente', p_id_expediente, p_id_tipo_documento, LEFT(IFNULL(p_nombre_archivo, v_nombre), 200), p_ruta, v_version,
            p_id_visibilidad,
            JSON_OBJECT('nombre_documento', v_nombre, 'descripcion', v_descripcion, 'etapa', TRIM(p_etapa),
                        'tamano_bytes', p_tamano, 'tipo_contenido', p_tipo_contenido, 'hash', p_hash),
            p_id_usuario, NOW(), p_id_usuario);
    SET v_id_doc = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('expediente', p_id_expediente, 'adjuntar_documento',
            CONCAT(v_tipo, ': ', v_nombre, IF(v_version > 1, CONCAT(' (versión ', v_version, ')'), ''), '. ', v_descripcion),
            p_id_usuario, NOW(),
            JSON_OBJECT('etapa', TRIM(p_etapa), 'id_documento', v_id_doc, 'id_tipo_documento', p_id_tipo_documento,
                        'version', v_version, 'id_visibilidad', p_id_visibilidad));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Documento adjuntado al expediente ', v_numero, '.') AS Mensaje;
    SELECT v_id_doc AS id_documento, CONCAT('doc-', v_id_doc) AS clave, v_version AS version, v_nombre AS nombre,
           v_tipo AS tipo, TRIM(p_etapa) AS etapa, v_etapa_nom AS etapa_nombre;
END$$

DELIMITER ;
