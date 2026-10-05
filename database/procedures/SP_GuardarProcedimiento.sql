-- HU-87 — Crear (p_id_procedimiento = 0) o editar un procedimiento
--   * Código único entre procedimientos activos.
--   * Al editar (si hubo cambios): copia la versión anterior al historial
--     y la versión sube automáticamente (o toma la indicada si es mayor).
--   * Auditoría con los campos modificados.
DROP PROCEDURE IF EXISTS SP_GuardarProcedimiento;

DELIMITER $$

CREATE PROCEDURE SP_GuardarProcedimiento(
    IN p_id_procedimiento       BIGINT,
    IN p_codigo                 VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_anio                   INT,
    IN p_version                INT,
    IN p_autor_norma            VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_norma_base             VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion            TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_formato_digital_iso TINYINT,
    IN p_url_pdf_aprobado       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_activo              TINYINT,
    IN p_guardar_como_borrador  TINYINT,
    IN p_id_usuario             BIGINT,
    IN p_pc_registro            VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id          BIGINT;
    DECLARE v_usu         VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_ant  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cambios     TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version_ant INT;
    DECLARE v_version_new INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones ─────────────────────────────────────────────────────
    IF p_id_procedimiento <> 0 AND NOT EXISTS (
        SELECT 1 FROM procedimiento_metrologico WHERE id_procedimiento = p_id_procedimiento AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Procedimiento no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = CASE
                       WHEN p_guardar_como_borrador = 1 THEN 'borrador'
                       WHEN IFNULL(p_es_activo, 1) = 1  THEN 'activo'
                       ELSE 'inactivo'
                   END;

    IF v_estado = 'activo' AND EXISTS (
        SELECT 1 FROM procedimiento_metrologico
        WHERE codigo = p_codigo
          AND estado = 'activo'
          AND SoftDelete = 0
          AND (p_id_procedimiento = 0 OR id_procedimiento <> p_id_procedimiento)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Ya existe un procedimiento activo con ese código.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    START TRANSACTION;

    IF p_id_procedimiento = 0 THEN
        -- ── Crear ────────────────────────────────────────────────────────
        INSERT INTO procedimiento_metrologico (
            codigo, anio, version, autor_norma, norma_base,
            descripcion, es_formato_digital_iso, url_pdf_aprobado,
            estado, total_ediciones, id_usuario_registro, pc_registro,
            SoftDelete, UsuCre, FchCre
        ) VALUES (
            p_codigo, p_anio, GREATEST(IFNULL(p_version, 1), 1), p_autor_norma, p_norma_base,
            p_descripcion, IFNULL(p_es_formato_digital_iso, 0),
            NULLIF(p_url_pdf_aprobado, ''),
            v_estado, 0, p_id_usuario, p_pc_registro,
            0, v_usu, NOW()
        );
        SET v_id = LAST_INSERT_ID();

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('procedimiento', v_id, 'creacion', NULL, v_estado,
                CONCAT('Procedimiento ', p_codigo, ' (', p_anio, ') creado, versión ', GREATEST(IFNULL(p_version, 1), 1), '.'),
                p_id_usuario, NOW());

        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Procedimiento registrado correctamente.' AS Mensaje;
        SELECT v_id AS id_procedimiento;
        LEAVE proc;
    END IF;

    -- ── Editar: detectar cambios ─────────────────────────────────────────
    SELECT version, estado,
           CONCAT_WS(', ',
               IF(NOT (codigo                 <=> p_codigo),                          'Código', NULL),
               IF(NOT (anio                   <=> p_anio),                            'Año', NULL),
               IF(NOT (autor_norma            <=> p_autor_norma),                     'Autor/organismo', NULL),
               IF(NOT (norma_base             <=> p_norma_base),                      'Norma base', NULL),
               IF(NOT (descripcion            <=> p_descripcion),                     'Descripción', NULL),
               IF(NOT (es_formato_digital_iso <=> IFNULL(p_es_formato_digital_iso, 0)), 'Formato digital', NULL),
               IF(NOT (url_pdf_aprobado       <=> NULLIF(p_url_pdf_aprobado, '')),    'PDF aprobado', NULL),
               IF(NOT (estado                 <=> v_estado),                          'Estado', NULL),
               IF(IFNULL(p_version, version) > version,                               'Versión', NULL)
           )
      INTO v_version_ant, v_estado_ant, v_cambios
    FROM procedimiento_metrologico WHERE id_procedimiento = p_id_procedimiento;

    IF v_cambios IS NULL OR v_cambios = '' THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, 'No se detectaron cambios; la versión se mantiene.' AS Mensaje;
        SELECT p_id_procedimiento AS id_procedimiento;
        LEAVE proc;
    END IF;

    SET v_version_new = GREATEST(IFNULL(p_version, 0), v_version_ant + 1);

    -- Guardar la versión anterior en el historial
    INSERT INTO procedimiento_metrologico_version (id_procedimiento, version, datos, UsuCre, FchCre)
    SELECT id_procedimiento, version,
           JSON_OBJECT(
               'codigo',              codigo,
               'anio',                anio,
               'version',             version,
               'autorNorma',          autor_norma,
               'normaBase',           norma_base,
               'descripcion',         descripcion,
               'esFormatoDigitalIso', es_formato_digital_iso,
               'urlPdfAprobado',      url_pdf_aprobado,
               'estado',              estado
           ),
           v_usu, NOW()
    FROM procedimiento_metrologico WHERE id_procedimiento = p_id_procedimiento;

    UPDATE procedimiento_metrologico SET
        codigo                 = p_codigo,
        anio                   = p_anio,
        version                = v_version_new,
        autor_norma            = p_autor_norma,
        norma_base             = p_norma_base,
        descripcion            = p_descripcion,
        es_formato_digital_iso = IFNULL(p_es_formato_digital_iso, 0),
        url_pdf_aprobado       = NULLIF(p_url_pdf_aprobado, ''),
        estado                 = v_estado,
        total_ediciones        = total_ediciones + 1,
        UsuMod                 = v_usu,
        FchMod                 = NOW()
    WHERE id_procedimiento = p_id_procedimiento;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('procedimiento', p_id_procedimiento, 'edicion', v_estado_ant, v_estado,
            CONCAT('Procedimiento ', p_codigo, ' editado: v', v_version_ant, ' → v', v_version_new,
                   '. Campos modificados: ', v_cambios, '.'),
            p_id_usuario, NOW(),
            JSON_OBJECT('version_anterior', v_version_ant, 'version_nueva', v_version_new,
                        'campos_modificados', v_cambios, 'pc', p_pc_registro));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Procedimiento actualizado correctamente (versión ', v_version_new, ').') AS Mensaje;
    SELECT p_id_procedimiento AS id_procedimiento;
END$$

DELIMITER ;
