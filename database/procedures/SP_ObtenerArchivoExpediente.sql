-- HU-31 Archivo de un documento del expediente para verlo o descargarlo.
-- Acción expediente_bandeja y que el usuario pueda ver el documento (misma regla del repositorio).
-- Cada descarga queda registrada en descarga_documento (trazabilidad ISO 9001).
-- Resultados: 1 mensaje · 2 ruta (o id_propuesta si es el PDF de una propuesta, que se genera), nombre y tipo
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_clave         VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_ruta    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_prop BIGINT;
    DECLARE v_existe  INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarDocumentosExpediente(p_id_usuario, p_id_expediente);
    SELECT COUNT(*), MAX(ruta), MAX(nombre_archivo), MAX(tipo_contenido), MAX(id_propuesta)
      INTO v_existe, v_ruta, v_nombre, v_tipo, v_id_prop
    FROM tmp_exp_doc WHERE clave = p_clave;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El documento no existe en este expediente o no tienes acceso a él.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ruta IS NULL AND v_id_prop IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El documento no tiene un archivo adjunto.' AS Mensaje;
        LEAVE proc;
    END IF;

    INSERT INTO descarga_documento (id_usuario, entidad_tipo, id_entidad, url_archivo, canal, registrado_en)
    VALUES (p_id_usuario, 'expediente', p_id_expediente, IFNULL(v_ruta, CONCAT('propuesta:', v_id_prop)), 'intranet', NOW());

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta, v_nombre AS nombre_archivo, v_tipo AS tipo_contenido, v_id_prop AS id_propuesta;
END$$

DELIMITER ;
