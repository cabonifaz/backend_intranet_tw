-- HU-86 — Crear (p_id_suministro = 0) o editar un suministro
--   * Código automático SUM-0001 (único).
--   * No permite dos suministros ACTIVOS con la misma descripción.
--   * Clase 'servicio': sin marca/modelo; otras clases: sin procedimientos.
--   * Auditoría con los campos modificados.
DROP PROCEDURE IF EXISTS SP_GuardarSuministro;

DELIMITER $$

CREATE PROCEDURE SP_GuardarSuministro(
    IN p_id_suministro            BIGINT,
    IN p_clase                    VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo                     VARCHAR(60)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_subtipo                  VARCHAR(60)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_marca                    VARCHAR(80)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modelo                   VARCHAR(80)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion_auto         VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion_manual       TEXT          CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_alcance                  VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_unidad                   VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_cta_contable             VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_procedencia              VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_casillero                VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_activo                   TINYINT,
    IN p_usar_en_propuestas       TINYINT,
    IN p_codigo_unspsc            VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_precio_min_referencia    DECIMAL(12,2),
    IN p_precio_nivel_estandar    DECIMAL(12,2),
    IN p_precio_nivel_volumen     DECIMAL(12,2),
    IN p_precio_nivel_corporativo DECIMAL(12,2),
    IN p_aplica_comercial         TINYINT,
    IN p_aplica_servicio          TINYINT,
    IN p_aplica_metrologia        TINYINT,
    IN p_id_primer_procedimiento  VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_segundo_procedimiento VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_guardar_como_borrador    TINYINT,
    IN p_id_usuario               BIGINT
)
proc: BEGIN
    DECLARE v_id         BIGINT;
    DECLARE v_codigo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_ant VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cambios    TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_proc1      VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_proc2      VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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
    IF NOT EXISTS (
        SELECT 1 FROM tabla_maestra WHERE IdMaestro = 71 AND IdEmpresa = 1 AND String2 = p_clase
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'La clase seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_suministro <> 0 AND NOT EXISTS (
        SELECT 1 FROM suministros WHERE id_suministro = p_id_suministro AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Suministro no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = CASE
                       WHEN p_guardar_como_borrador = 1 THEN 'borrador'
                       WHEN IFNULL(p_activo, 1) = 1     THEN 'activo'
                       ELSE 'inactivo'
                   END;

    IF v_estado = 'activo' AND EXISTS (
        SELECT 1 FROM suministros
        WHERE descripcion = p_descripcion_auto
          AND estado = 'activo'
          AND eliminado_en IS NULL
          AND (p_id_suministro = 0 OR id_suministro <> p_id_suministro)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Ya existe un suministro activo con la misma descripción.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Regla de negocio por clase
    IF p_clase = 'servicio' THEN
        SET v_marca = NULL;  SET v_modelo = NULL;
        SET v_proc1 = NULLIF(p_id_primer_procedimiento, '');
        SET v_proc2 = NULLIF(p_id_segundo_procedimiento, '');
    ELSE
        SET v_marca = NULLIF(p_marca, '');  SET v_modelo = NULLIF(p_modelo, '');
        SET v_proc1 = NULL;  SET v_proc2 = NULL;
    END IF;

    START TRANSACTION;

    IF p_id_suministro = 0 THEN
        -- ── Crear ────────────────────────────────────────────────────────
        INSERT INTO suministros (
            codigo, descripcion, id_tipo_item, id_moneda, precio_referencia, unidad_medida, activo,
            clase, tipo, subtipo, marca, modelo, descripcion_manual, alcance, cta_contable,
            procedencia, casillero, usar_en_propuestas, codigo_unspsc,
            precio_nivel_estandar, precio_nivel_volumen, precio_nivel_corporativo,
            aplica_comercial, aplica_servicio, aplica_metrologia,
            id_primer_procedimiento, id_segundo_procedimiento,
            estado, total_ediciones, creado_en, creado_por
        ) VALUES (
            'SUM-TEMP', p_descripcion_auto,
            IF(p_clase = 'servicio', 2, 1),   -- TIPO_ITEM_CATALOGO: 1 Repuesto/pieza, 2 Servicio técnico
            2,                                -- Moneda USD (precios de referencia en dólares)
            p_precio_min_referencia, p_unidad, IF(v_estado = 'activo', 1, 0),
            p_clase, p_tipo, p_subtipo, v_marca, v_modelo, p_descripcion_manual, p_alcance, p_cta_contable,
            p_procedencia, p_casillero, IFNULL(p_usar_en_propuestas, 0), NULLIF(p_codigo_unspsc, ''),
            p_precio_nivel_estandar, p_precio_nivel_volumen, p_precio_nivel_corporativo,
            IFNULL(p_aplica_comercial, 0), IFNULL(p_aplica_servicio, 0), IFNULL(p_aplica_metrologia, 0),
            v_proc1, v_proc2,
            v_estado, 0, NOW(), p_id_usuario
        );
        SET v_id     = LAST_INSERT_ID();
        SET v_codigo = CONCAT('SUM-', LPAD(v_id, 4, '0'));
        UPDATE suministros SET codigo = v_codigo WHERE id_suministro = v_id;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('suministro', v_id, 'creacion', NULL, v_estado,
                CONCAT('Suministro ', v_codigo, ' creado: ', p_descripcion_auto), p_id_usuario, NOW());
    ELSE
        -- ── Editar: detectar campos modificados ──────────────────────────
        SELECT codigo, estado,
               CONCAT_WS(', ',
                   IF(NOT (clase                    <=> p_clase),                    'Clase', NULL),
                   IF(NOT (tipo                     <=> p_tipo),                     'Tipo', NULL),
                   IF(NOT (subtipo                  <=> p_subtipo),                  'Subtipo', NULL),
                   IF(NOT (marca                    <=> v_marca),                    'Marca', NULL),
                   IF(NOT (modelo                   <=> v_modelo),                   'Modelo', NULL),
                   IF(NOT (descripcion              <=> p_descripcion_auto),         'Descripción', NULL),
                   IF(NOT (descripcion_manual       <=> p_descripcion_manual),       'Descripción manual', NULL),
                   IF(NOT (alcance                  <=> p_alcance),                  'Alcance', NULL),
                   IF(NOT (unidad_medida            <=> p_unidad),                   'Unidad', NULL),
                   IF(NOT (cta_contable             <=> p_cta_contable),             'Cta. contable', NULL),
                   IF(NOT (procedencia              <=> p_procedencia),              'Procedencia', NULL),
                   IF(NOT (casillero                <=> p_casillero),                'Casillero', NULL),
                   IF(NOT (estado                   <=> v_estado),                   'Estado', NULL),
                   IF(NOT (usar_en_propuestas       <=> IFNULL(p_usar_en_propuestas, 0)), 'Uso en propuestas', NULL),
                   IF(NOT (codigo_unspsc            <=> NULLIF(p_codigo_unspsc, '')), 'UNSPSC', NULL),
                   IF(NOT (precio_referencia        <=> p_precio_min_referencia),    'Precio mínimo', NULL),
                   IF(NOT (precio_nivel_estandar    <=> p_precio_nivel_estandar),    'Precio nivel 1', NULL),
                   IF(NOT (precio_nivel_volumen     <=> p_precio_nivel_volumen),     'Precio nivel 2', NULL),
                   IF(NOT (precio_nivel_corporativo <=> p_precio_nivel_corporativo), 'Precio nivel 3', NULL),
                   IF(NOT (aplica_comercial         <=> IFNULL(p_aplica_comercial, 0)),  'Área comercial', NULL),
                   IF(NOT (aplica_servicio          <=> IFNULL(p_aplica_servicio, 0)),   'Área servicio', NULL),
                   IF(NOT (aplica_metrologia        <=> IFNULL(p_aplica_metrologia, 0)), 'Área metrología', NULL),
                   IF(NOT (id_primer_procedimiento  <=> v_proc1),                    'Procedimiento 1', NULL),
                   IF(NOT (id_segundo_procedimiento <=> v_proc2),                    'Procedimiento 2', NULL)
               )
          INTO v_codigo, v_estado_ant, v_cambios
        FROM suministros WHERE id_suministro = p_id_suministro;

        UPDATE suministros SET
            descripcion              = p_descripcion_auto,
            id_tipo_item             = IF(p_clase = 'servicio', 2, 1),
            precio_referencia        = p_precio_min_referencia,
            unidad_medida            = p_unidad,
            activo                   = IF(v_estado = 'activo', 1, 0),
            clase                    = p_clase,
            tipo                     = p_tipo,
            subtipo                  = p_subtipo,
            marca                    = v_marca,
            modelo                   = v_modelo,
            descripcion_manual       = p_descripcion_manual,
            alcance                  = p_alcance,
            cta_contable             = p_cta_contable,
            procedencia              = p_procedencia,
            casillero                = p_casillero,
            usar_en_propuestas       = IFNULL(p_usar_en_propuestas, 0),
            codigo_unspsc            = NULLIF(p_codigo_unspsc, ''),
            precio_nivel_estandar    = p_precio_nivel_estandar,
            precio_nivel_volumen     = p_precio_nivel_volumen,
            precio_nivel_corporativo = p_precio_nivel_corporativo,
            aplica_comercial         = IFNULL(p_aplica_comercial, 0),
            aplica_servicio          = IFNULL(p_aplica_servicio, 0),
            aplica_metrologia        = IFNULL(p_aplica_metrologia, 0),
            id_primer_procedimiento  = v_proc1,
            id_segundo_procedimiento = v_proc2,
            estado                   = v_estado,
            total_ediciones          = total_ediciones + 1,
            modificado_en            = NOW(),
            modificado_por           = p_id_usuario
        WHERE id_suministro = p_id_suministro;

        SET v_id = p_id_suministro;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('suministro', v_id, 'edicion', v_estado_ant, v_estado,
                CONCAT('Suministro ', v_codigo, ' editado. Campos modificados: ',
                       IF(v_cambios IS NULL OR v_cambios = '', 'ninguno', v_cambios), '.'),
                p_id_usuario, NOW(),
                JSON_OBJECT('campos_modificados', IFNULL(v_cambios, '')));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_suministro = 0, 'Suministro registrado correctamente.', 'Suministro actualizado correctamente.') AS Mensaje;
    SELECT v_id AS id_suministro;
END$$

DELIMITER ;
