-- HU-88 — Crear (p_id_equipo = 0) o editar un equipo del cliente.
--   * Código automático EQ-TW-YYYY-XXXX (único por año).
--   * Bloquea duplicados de (num_serie, marca, modelo) activos.
--   * En edición, serie/marca/modelo quedan inmutables (regla del front).
--   * Marca pre-revisión con usuario + fecha cuando se activa el flag.
DROP PROCEDURE IF EXISTS SP_GuardarEquipoCliente;

DELIMITER $$

CREATE PROCEDURE SP_GuardarEquipoCliente(
    IN p_id_equipo               BIGINT,
    IN p_num_serie               VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente              BIGINT,
    IN p_id_sede                 BIGINT,
    IN p_codigo_cliente          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_clasificacion           VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_marca                   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modelo                  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ubicacion_especifica    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_pre_revisado         TINYINT,
    IN p_bloqueado_servicios     TINYINT,
    IN p_id_suministro           BIGINT,
    IN p_division_minima         VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_division_verif          VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_division_verif_igual    TINYINT,
    IN p_clase_exactitud         VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_alcance_maximo          VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_escala_graduacion       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_puntos_calibracion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rango_operativo_real    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_observaciones           TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado_operativo        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_activo               TINYINT,
    IN p_guardar_como_borrador   TINYINT,
    IN p_id_usuario              BIGINT
)
proc: BEGIN
    DECLARE v_id             BIGINT;
    DECLARE v_codigo_tw      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_anio           CHAR(4);
    DECLARE v_correlativo    INT;
    DECLARE v_usuario_login  VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pre_rev_antes  TINYINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones mínimas ────────────────────────────────────────────────
    IF p_num_serie IS NULL OR TRIM(p_num_serie) = '' THEN
        SELECT 1 AS IdTipoMensaje, 'El número de serie es obligatorio.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_cliente IS NULL OR p_id_cliente = 0 OR p_id_sede IS NULL OR p_id_sede = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente y sede son obligatorios.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = 81 AND IdEmpresa = 1 AND String2 = p_clasificacion
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'La clasificación seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_equipo <> 0 AND NOT EXISTS (
        SELECT 1 FROM equipo_cliente WHERE id_equipo = p_id_equipo AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Equipo no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = CASE
                       WHEN p_guardar_como_borrador = 1 THEN 'borrador'
                       WHEN IFNULL(p_es_activo, 1) = 1  THEN 'activo'
                       ELSE 'inactivo'
                   END;

    -- Duplicado (serie + marca + modelo) activo
    IF v_estado <> 'borrador' AND EXISTS (
        SELECT 1 FROM equipo_cliente
        WHERE num_serie = p_num_serie
          AND marca     = p_marca
          AND modelo    = p_modelo
          AND SoftDelete = 0
          AND (p_id_equipo = 0 OR id_equipo <> p_id_equipo)
    ) THEN
        SELECT 1 AS IdTipoMensaje,
               'Ya existe un equipo con la misma combinación serie + marca + modelo.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usuario_login FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    START TRANSACTION;

    IF p_id_equipo = 0 THEN
        -- ── Crear ─────────────────────────────────────────────────────────────
        SET v_anio = DATE_FORMAT(NOW(), '%Y');
        SELECT IFNULL(MAX(CAST(SUBSTRING_INDEX(codigo_tw, '-', -1) AS UNSIGNED)), 0) + 1
          INTO v_correlativo
          FROM equipo_cliente
         WHERE codigo_tw LIKE CONCAT('EQ-TW-', v_anio, '-%');
        SET v_codigo_tw = CONCAT('EQ-TW-', v_anio, '-', LPAD(v_correlativo, 4, '0'));

        INSERT INTO equipo_cliente (
            codigo_tw, num_serie, id_cliente, id_sede, codigo_cliente,
            clasificacion, marca, modelo,
            ubicacion_especifica, es_pre_revisado, usuario_pre_revisor, fecha_pre_revision,
            bloqueado_para_servicios,
            id_suministro, division_minima, division_verif, division_verif_igual,
            clase_exactitud, alcance_maximo, escala_graduacion, puntos_calibracion,
            rango_operativo_real, observaciones,
            estado_operativo, es_activo, estado,
            usuario_registro, pc_registro,
            SoftDelete, UsuCre, FchCre
        ) VALUES (
            v_codigo_tw, TRIM(p_num_serie), p_id_cliente, p_id_sede, NULLIF(TRIM(p_codigo_cliente), ''),
            p_clasificacion, TRIM(p_marca), TRIM(p_modelo),
            NULLIF(p_ubicacion_especifica, ''),
            IFNULL(p_es_pre_revisado, 0),
            IF(IFNULL(p_es_pre_revisado, 0) = 1, v_usuario_login, NULL),
            IF(IFNULL(p_es_pre_revisado, 0) = 1, NOW(), NULL),
            IFNULL(p_bloqueado_servicios, 0),
            IF(p_id_suministro = 0, NULL, p_id_suministro),
            NULLIF(p_division_minima, ''),
            NULLIF(p_division_verif, ''),
            IFNULL(p_division_verif_igual, 1),
            NULLIF(p_clase_exactitud, ''),
            NULLIF(p_alcance_maximo, ''),
            NULLIF(p_escala_graduacion, ''),
            NULLIF(p_puntos_calibracion, ''),
            NULLIF(p_rango_operativo_real, ''),
            NULLIF(p_observaciones, ''),
            IFNULL(p_estado_operativo, 'oficina_tw'),
            IF(v_estado = 'activo', 1, 0),
            v_estado,
            v_usuario_login,
            NULL,
            0, v_usuario_login, NOW()
        );
        SET v_id = LAST_INSERT_ID();
    ELSE
        -- ── Editar — serie/marca/modelo quedan inmutables ────────────────────
        SELECT es_pre_revisado INTO v_pre_rev_antes
          FROM equipo_cliente WHERE id_equipo = p_id_equipo;

        UPDATE equipo_cliente SET
            id_cliente               = p_id_cliente,
            id_sede                  = p_id_sede,
            codigo_cliente           = NULLIF(TRIM(p_codigo_cliente), ''),
            clasificacion            = p_clasificacion,
            ubicacion_especifica     = NULLIF(p_ubicacion_especifica, ''),
            es_pre_revisado          = IFNULL(p_es_pre_revisado, 0),
            usuario_pre_revisor      = CASE
                                           WHEN IFNULL(p_es_pre_revisado, 0) = 1 AND IFNULL(v_pre_rev_antes, 0) = 0
                                                THEN v_usuario_login
                                           WHEN IFNULL(p_es_pre_revisado, 0) = 0
                                                THEN NULL
                                           ELSE usuario_pre_revisor
                                       END,
            fecha_pre_revision       = CASE
                                           WHEN IFNULL(p_es_pre_revisado, 0) = 1 AND IFNULL(v_pre_rev_antes, 0) = 0
                                                THEN NOW()
                                           WHEN IFNULL(p_es_pre_revisado, 0) = 0
                                                THEN NULL
                                           ELSE fecha_pre_revision
                                       END,
            bloqueado_para_servicios = IFNULL(p_bloqueado_servicios, 0),
            id_suministro            = IF(p_id_suministro = 0, NULL, p_id_suministro),
            division_minima          = NULLIF(p_division_minima, ''),
            division_verif           = NULLIF(p_division_verif, ''),
            division_verif_igual     = IFNULL(p_division_verif_igual, 1),
            clase_exactitud          = NULLIF(p_clase_exactitud, ''),
            alcance_maximo           = NULLIF(p_alcance_maximo, ''),
            escala_graduacion        = NULLIF(p_escala_graduacion, ''),
            puntos_calibracion       = NULLIF(p_puntos_calibracion, ''),
            rango_operativo_real     = NULLIF(p_rango_operativo_real, ''),
            observaciones            = NULLIF(p_observaciones, ''),
            estado_operativo         = IFNULL(p_estado_operativo, estado_operativo),
            es_activo                = IF(v_estado = 'activo', 1, 0),
            estado                   = v_estado,
            UsuMod                   = v_usuario_login,
            FchMod                   = NOW()
        WHERE id_equipo = p_id_equipo;

        SET v_id = p_id_equipo;
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_equipo = 0, 'Equipo registrado correctamente.', 'Equipo actualizado correctamente.') AS Mensaje;
    SELECT v_id AS id_equipo;
END$$

DELIMITER ;
