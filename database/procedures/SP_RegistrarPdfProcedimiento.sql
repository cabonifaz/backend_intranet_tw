-- Carga del PDF aprobado de Procedimientos (HU-87)
--   Registra el archivo ya guardado en el almacenamiento.
--   Vuelve a validar el permiso (FN_PermisoAccion, acción procedimiento_pdf_cargar).
--   El archivo anterior no se borra del almacenamiento (trazabilidad),
--   su ruta queda en la auditoría.
--   No sube la versión del procedimiento: el PDF es el documento aprobado
--   de la versión vigente.
DROP PROCEDURE IF EXISTS SP_RegistrarPdfProcedimiento;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarPdfProcedimiento(
    IN p_id_procedimiento BIGINT,
    IN p_ruta             VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_original  VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_bytes     BIGINT,
    IN p_hash_sha256      CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario       BIGINT,
    IN p_pc_registro      VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_ruta_ant      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_ant    VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_correo        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_usu    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT estado, codigo, version, url_pdf_aprobado, pdf_nombre_original
      INTO v_estado, v_codigo, v_version, v_ruta_ant, v_nombre_ant
    FROM procedimiento_metrologico
    WHERE id_procedimiento = p_id_procedimiento AND SoftDelete = 0;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Procedimiento no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado = 'inactivo' THEN
        SELECT 1 AS IdTipoMensaje, 'El procedimiento está inactivo. Actívelo antes de cargar el PDF.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo, CONCAT(nombre, ' ', apellido)
      INTO v_correo, v_nombre_usu
    FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo';

    IF FN_PermisoAccion(p_id_usuario, 'procedimiento_pdf_cargar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para cargar el PDF aprobado. Solo el área de Calidad o un administrador.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF TRIM(IFNULL(p_ruta, '')) = '' OR IFNULL(p_tamano_bytes, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El archivo PDF no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    UPDATE procedimiento_metrologico SET
        url_pdf_aprobado    = p_ruta,
        pdf_nombre_original = p_nombre_original,
        pdf_tamano_bytes    = p_tamano_bytes,
        pdf_hash_sha256     = p_hash_sha256,
        pdf_subido_en       = NOW(),
        pdf_subido_por      = p_id_usuario,
        UsuMod              = v_correo,
        FchMod              = NOW()
    WHERE id_procedimiento = p_id_procedimiento;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('procedimiento', p_id_procedimiento,
            IF(v_ruta_ant IS NULL, 'carga_pdf', 'reemplazo_pdf'),
            v_estado, v_estado,
            CONCAT(IF(v_ruta_ant IS NULL, 'PDF aprobado cargado', 'PDF aprobado reemplazado'),
                   ' en ', v_codigo, ' v', v_version, ': ', p_nombre_original, '.'),
            p_id_usuario, NOW(),
            JSON_OBJECT('ruta',            p_ruta,
                        'nombre',          p_nombre_original,
                        'tamano_bytes',    p_tamano_bytes,
                        'sha256',          p_hash_sha256,
                        'ruta_anterior',   v_ruta_ant,
                        'nombre_anterior', v_nombre_ant,
                        'pc',              p_pc_registro));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_ruta_ant IS NULL, 'PDF aprobado cargado correctamente.', 'PDF aprobado reemplazado correctamente.') AS Mensaje;

    SELECT p_nombre_original AS pdf_nombre_original,
           p_tamano_bytes    AS pdf_tamano_bytes,
           NOW()             AS pdf_subido_en,
           v_nombre_usu      AS pdf_subido_por;
END$$

DELIMITER ;
