-- HU-85 — Crear (p_id_texto_base = 0) o editar un texto base
--   En edición guarda la versión anterior en texto_base_version y sube la versión.
--   Registra creación/edición en auditoria_evento.
DROP PROCEDURE IF EXISTS SP_GuardarTextoBase;

DELIMITER $$

CREATE PROCEDURE SP_GuardarTextoBase(
    IN p_id_texto_base                BIGINT,
    IN p_codigo_corto                 VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_categoria               VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre                       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_texto_clausula               TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_seccion_dossier              VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_orden_aparicion              INT,
    IN p_nivel_sangria                VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_predeterminado            TINYINT,
    IN p_es_negrita_por_defecto       TINYINT,
    IN p_activo                       TINYINT,
    IN p_aplica_todos_servicios       TINYINT,
    IN p_aplica_calibracion_lab       TINYINT,
    IN p_aplica_calibracion_planta    TINYINT,
    IN p_aplica_mantenimiento         TINYINT,
    IN p_aplica_venta_suministros     TINYINT,
    IN p_visible_gestores_comerciales TINYINT,
    IN p_visible_tecnicos_metrologos  TINYINT,
    IN p_visible_supervisores         TINYINT,
    IN p_guardar_como_borrador        TINYINT,
    IN p_id_usuario                   BIGINT
)
proc: BEGIN
    DECLARE v_id         BIGINT;
    DECLARE v_usu        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_ant VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version    INT;

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
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = 70 AND IdEmpresa = 1 AND String2 = p_tipo_categoria
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'La categoría seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (
        SELECT 1 FROM texto_base
        WHERE codigo_corto = p_codigo_corto
          AND SoftDelete = 0
          AND estado <> 'inactivo'
          AND (p_id_texto_base = 0 OR id_texto_base <> p_id_texto_base)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Ya existe otro texto base con ese código corto.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_texto_base <> 0 AND NOT EXISTS (
        SELECT 1 FROM texto_base WHERE id_texto_base = p_id_texto_base AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Texto base no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = CASE
                       WHEN p_guardar_como_borrador = 1 THEN 'borrador'
                       WHEN IFNULL(p_activo, 1) = 1     THEN 'activo'
                       ELSE 'inactivo'
                   END;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    START TRANSACTION;

    IF p_id_texto_base = 0 THEN
        -- ── Crear ────────────────────────────────────────────────────────
        INSERT INTO texto_base (
            codigo_corto, tipo_categoria, nombre, texto_clausula, seccion_dossier,
            orden_aparicion, nivel_sangria, es_predeterminado, es_negrita_por_defecto,
            aplica_todos_servicios, aplica_calibracion_lab, aplica_calibracion_planta,
            aplica_mantenimiento, aplica_venta_suministros,
            visible_gestores_comerciales, visible_tecnicos_metrologos, visible_supervisores,
            version, estado, id_usuario_creador, SoftDelete, UsuCre, FchCre
        ) VALUES (
            p_codigo_corto, p_tipo_categoria, p_nombre, p_texto_clausula, p_seccion_dossier,
            IFNULL(p_orden_aparicion, 1), IFNULL(p_nivel_sangria, 'estandar'),
            IFNULL(p_es_predeterminado, 0), IFNULL(p_es_negrita_por_defecto, 0),
            IFNULL(p_aplica_todos_servicios, 0), IFNULL(p_aplica_calibracion_lab, 0), IFNULL(p_aplica_calibracion_planta, 0),
            IFNULL(p_aplica_mantenimiento, 0), IFNULL(p_aplica_venta_suministros, 0),
            IFNULL(p_visible_gestores_comerciales, 1), IFNULL(p_visible_tecnicos_metrologos, 1), IFNULL(p_visible_supervisores, 1),
            1, v_estado, p_id_usuario, 0, v_usu, NOW()
        );
        SET v_id = LAST_INSERT_ID();

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('texto_base', v_id, 'creacion', NULL, v_estado,
                CONCAT('Texto base ', p_codigo_corto, ' creado (v1).'), p_id_usuario, NOW());
    ELSE
        -- ── Editar: guardar la versión anterior ──────────────────────────
        SELECT version, estado INTO v_version, v_estado_ant
        FROM texto_base WHERE id_texto_base = p_id_texto_base;

        INSERT INTO texto_base_version (id_texto_base, version, datos, UsuCre, FchCre)
        SELECT id_texto_base, version,
               JSON_OBJECT(
                   'codigoCorto',                codigo_corto,
                   'tipoCategoria',              tipo_categoria,
                   'nombre',                     nombre,
                   'textoClausula',              texto_clausula,
                   'seccionDossier',             seccion_dossier,
                   'ordenAparicion',             orden_aparicion,
                   'nivelSangria',               nivel_sangria,
                   'esPredeterminado',           es_predeterminado,
                   'esNegritaPorDefecto',        es_negrita_por_defecto,
                   'aplicaTodosServicios',       aplica_todos_servicios,
                   'aplicaCalibracionLab',       aplica_calibracion_lab,
                   'aplicaCalibracionPlanta',    aplica_calibracion_planta,
                   'aplicaMantenimiento',        aplica_mantenimiento,
                   'aplicaVentaSuministros',     aplica_venta_suministros,
                   'visibleGestoresComerciales', visible_gestores_comerciales,
                   'visibleTecnicosMetrologos',  visible_tecnicos_metrologos,
                   'visibleSupervisores',        visible_supervisores,
                   'estado',                     estado
               ),
               v_usu, NOW()
        FROM texto_base WHERE id_texto_base = p_id_texto_base;

        UPDATE texto_base SET
            codigo_corto                 = p_codigo_corto,
            tipo_categoria               = p_tipo_categoria,
            nombre                       = p_nombre,
            texto_clausula               = p_texto_clausula,
            seccion_dossier              = p_seccion_dossier,
            orden_aparicion              = IFNULL(p_orden_aparicion, 1),
            nivel_sangria                = IFNULL(p_nivel_sangria, 'estandar'),
            es_predeterminado            = IFNULL(p_es_predeterminado, 0),
            es_negrita_por_defecto       = IFNULL(p_es_negrita_por_defecto, 0),
            aplica_todos_servicios       = IFNULL(p_aplica_todos_servicios, 0),
            aplica_calibracion_lab       = IFNULL(p_aplica_calibracion_lab, 0),
            aplica_calibracion_planta    = IFNULL(p_aplica_calibracion_planta, 0),
            aplica_mantenimiento         = IFNULL(p_aplica_mantenimiento, 0),
            aplica_venta_suministros     = IFNULL(p_aplica_venta_suministros, 0),
            visible_gestores_comerciales = IFNULL(p_visible_gestores_comerciales, 1),
            visible_tecnicos_metrologos  = IFNULL(p_visible_tecnicos_metrologos, 1),
            visible_supervisores         = IFNULL(p_visible_supervisores, 1),
            version                      = version + 1,
            estado                       = v_estado,
            UsuMod                       = v_usu,
            FchMod                       = NOW()
        WHERE id_texto_base = p_id_texto_base;

        SET v_id = p_id_texto_base;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('texto_base', v_id, 'edicion', v_estado_ant, v_estado,
                CONCAT('Texto base ', p_codigo_corto, ' editado: v', v_version, ' → v', v_version + 1, '.'),
                p_id_usuario, NOW(),
                JSON_OBJECT('version_anterior', v_version, 'version_nueva', v_version + 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_texto_base = 0, 'Texto base registrado correctamente.', 'Texto base actualizado correctamente.') AS Mensaje;
    SELECT v_id AS id_texto_base;
END$$

DELIMITER ;
