-- Propuestas — Importación de equipos desde Excel con IA (Sprint 4). Confirmación (todo o nada).
-- p_filas_json: [{ "fila": 5, "accion": "vincular", "idEquipo": 41 },
--                { "fila": 6, "accion": "crear", "numSerie": "BAL-01", "marca": "...", "modelo": "...",
--                  "clasificacion": "equipo", "idSuministro": 12, "idSede": 3, "codigoCliente": "TAG-9",
--                  "ubicacion": "Laboratorio", "alcanceMaximo": "220 g" }]
--   vincular: el equipo debe ser del cliente.
--   crear:    registra el equipo en el inventario del cliente (estado activo, código EQ-TW-AAAA-NNNN). El suministro del
--             catálogo es obligatorio (ficha técnica del equipo); marca y modelo se toman de él si no se envían.
--             Si el cliente ya tiene un equipo con la misma serie, marca y modelo, se reutiliza (no se duplica).
--             Si la serie está registrada en OTRO cliente, se rechaza.
-- Primero valida todas las filas; si alguna falla no se guarda nada.
-- Devuelve: resumen (vinculados, creados, reutilizados) y los equipos en el orden recibido.
DROP PROCEDURE IF EXISTS SP_ImportarEquiposPropuesta;
DELIMITER $$
CREATE PROCEDURE SP_ImportarEquiposPropuesta(
    IN p_id_cliente  BIGINT,
    IN p_filas_json  LONGTEXT,
    IN p_id_usuario  BIGINT
)
proc: BEGIN
    DECLARE v_usuario_login VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_errores       TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_errores     INT DEFAULT 0;
    DECLARE v_i             INT;
    DECLARE v_max           INT;
    DECLARE v_anio          CHAR(4);
    DECLARE v_correlativo   INT;
    DECLARE v_codigo_tw     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_serie     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo        VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clasificacion VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_suministro BIGINT;
    DECLARE v_id_sede       BIGINT;
    DECLARE v_codigo_cli    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ubicacion     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_alcance       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id            BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_importacion_equipos;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_filas_json IS NULL OR JSON_VALID(p_filas_json) = 0 OR JSON_LENGTH(p_filas_json) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione al menos un equipo para importar.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_importacion_equipos;
    CREATE TEMPORARY TABLE tmp_importacion_equipos (
        orden          INT          NOT NULL,
        fila           INT          NULL,
        accion         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        id_equipo      BIGINT       NULL,
        num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        serie_norm     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        clasificacion  VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        id_suministro  BIGINT       NULL,
        id_sede        BIGINT       NULL,
        codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        ubicacion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        alcance        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resultado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        error          VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (orden)
    ) ENGINE = MEMORY;

    INSERT INTO tmp_importacion_equipos
        (orden, fila, accion, id_equipo, num_serie, serie_norm, marca, modelo, clasificacion, id_suministro,
         id_sede, codigo_cliente, ubicacion, alcance)
    SELECT jt.orden,
           jt.fila,
           LOWER(TRIM(IFNULL(jt.accion, ''))),
           NULLIF(jt.id_equipo, 0),
           NULLIF(TRIM(jt.num_serie), ''),
           REGEXP_REPLACE(UPPER(IFNULL(jt.num_serie, '')), '[^A-Z0-9]', ''),
           NULLIF(TRIM(jt.marca), ''),
           NULLIF(TRIM(jt.modelo), ''),
           LOWER(NULLIF(TRIM(jt.clasificacion), '')),
           NULLIF(jt.id_suministro, 0),
           NULLIF(jt.id_sede, 0),
           NULLIF(TRIM(jt.codigo_cliente), ''),
           NULLIF(TRIM(jt.ubicacion), ''),
           NULLIF(TRIM(jt.alcance), '')
    FROM JSON_TABLE(p_filas_json, '$[*]' COLUMNS (
            orden          FOR ORDINALITY,
            fila           INT          PATH '$.fila',
            accion         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.accion',
            id_equipo      BIGINT       PATH '$.idEquipo',
            num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.numSerie',
            marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.marca',
            modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.modelo',
            clasificacion  VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.clasificacion',
            id_suministro  BIGINT       PATH '$.idSuministro',
            id_sede        BIGINT       PATH '$.idSede',
            codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.codigoCliente',
            ubicacion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.ubicacion',
            alcance        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.alcanceMaximo'
         )) jt;

    -- ── Validaciones ─────────────────────────────────────────────────────
    UPDATE tmp_importacion_equipos
       SET error = 'La acción debe ser vincular o crear.'
     WHERE accion NOT IN ('vincular', 'crear');

    -- vincular: el equipo es del cliente
    UPDATE tmp_importacion_equipos t
       SET t.error = 'El equipo no existe o no pertenece al cliente.'
     WHERE t.accion = 'vincular' AND t.error IS NULL
       AND NOT EXISTS (SELECT 1 FROM equipo_cliente ec
                       WHERE ec.id_equipo = t.id_equipo AND ec.id_cliente = p_id_cliente AND ec.SoftDelete = 0);

    UPDATE tmp_importacion_equipos
       SET resultado = 'vinculado'
     WHERE accion = 'vincular' AND error IS NULL;

    -- crear: datos obligatorios
    UPDATE tmp_importacion_equipos
       SET error = 'El número de serie es obligatorio.'
     WHERE accion = 'crear' AND error IS NULL AND (num_serie IS NULL OR serie_norm = '');

    UPDATE tmp_importacion_equipos t
       SET t.error = 'La sede no pertenece al cliente.'
     WHERE t.accion = 'crear' AND t.error IS NULL
       AND NOT EXISTS (SELECT 1 FROM sede_cliente s
                       WHERE s.id_sede = t.id_sede AND s.id_cliente = p_id_cliente AND s.SoftDelete = 0);

    UPDATE tmp_importacion_equipos t
       SET t.error = 'La clasificación debe ser Equipo, Instrumento o Pesa.'
     WHERE t.accion = 'crear' AND t.error IS NULL
       AND NOT EXISTS (SELECT 1 FROM tabla_maestra tm
                       WHERE tm.IdMaestro = 71 AND tm.IdEmpresa = 1
                         AND tm.String2 = t.clasificacion AND tm.String2 <> 'servicio');

    -- Un equipo del cliente no se registra sin su ficha técnica (suministro del catálogo)
    UPDATE tmp_importacion_equipos
       SET error = 'Elija el suministro del catálogo para registrar el equipo.'
     WHERE accion = 'crear' AND error IS NULL AND id_suministro IS NULL;

    UPDATE tmp_importacion_equipos t
       SET t.error = 'El suministro elegido no existe o no está activo.'
     WHERE t.accion = 'crear' AND t.error IS NULL AND t.id_suministro IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM suministros su
                       WHERE su.id_suministro = t.id_suministro AND su.eliminado_en IS NULL
                         AND su.estado = 'activo' AND su.clase IN ('equipo', 'instrumento', 'pesa'));

    -- Marca y modelo del suministro cuando no se envían (igual que SP_GuardarEquipoCliente).
    UPDATE tmp_importacion_equipos t
      JOIN suministros su ON su.id_suministro = t.id_suministro
       SET t.marca  = COALESCE(t.marca,  NULLIF(TRIM(su.marca), ''),  'Genérico'),
           t.modelo = COALESCE(t.modelo, NULLIF(TRIM(su.modelo), ''), 'Genérico')
     WHERE t.accion = 'crear' AND t.error IS NULL;

    UPDATE tmp_importacion_equipos
       SET error = 'Indique la marca y el modelo, o elija el suministro del catálogo.'
     WHERE accion = 'crear' AND error IS NULL AND (marca IS NULL OR modelo IS NULL);

    -- La serie ya es de otro cliente: no se duplica.
    UPDATE tmp_importacion_equipos t
       SET t.error = (SELECT CONCAT('La serie ', t.num_serie, ' está registrada como equipo de ',
                                    IFNULL(c.razon_social, 'otro cliente'), ' (', ec.codigo_tw, ').')
                      FROM equipo_cliente ec
                      LEFT JOIN cliente c ON c.id_cliente = ec.id_cliente
                      WHERE REGEXP_REPLACE(UPPER(ec.num_serie), '[^A-Z0-9]', '') = t.serie_norm
                        AND ec.id_cliente <> p_id_cliente AND ec.SoftDelete = 0
                      ORDER BY ec.id_equipo LIMIT 1)
     WHERE t.accion = 'crear' AND t.error IS NULL
       AND EXISTS (SELECT 1 FROM equipo_cliente ec
                   WHERE REGEXP_REPLACE(UPPER(ec.num_serie), '[^A-Z0-9]', '') = t.serie_norm
                     AND ec.id_cliente <> p_id_cliente AND ec.SoftDelete = 0);

    SELECT COUNT(*),
           GROUP_CONCAT(CONCAT(IF(fila IS NULL, '', CONCAT('Fila ', fila, ': ')), error) ORDER BY orden SEPARATOR ' ')
      INTO v_n_errores, v_errores
      FROM tmp_importacion_equipos
     WHERE error IS NOT NULL;

    IF v_n_errores > 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_importacion_equipos;
        SELECT 1 AS IdTipoMensaje,
               LEFT(CONCAT(IF(v_n_errores = 1, 'No se importó: ', CONCAT('No se importó (', v_n_errores, ' filas con error): ')),
                           v_errores), 1000) AS Mensaje;
        LEAVE proc;
    END IF;

    -- El cliente ya tiene el equipo (misma serie, marca y modelo): se reutiliza.
    UPDATE tmp_importacion_equipos t
       SET t.id_equipo = (SELECT ec.id_equipo FROM equipo_cliente ec
                          WHERE ec.id_cliente = p_id_cliente AND ec.SoftDelete = 0
                            AND REGEXP_REPLACE(UPPER(ec.num_serie), '[^A-Z0-9]', '') = t.serie_norm
                            AND ec.marca = t.marca AND ec.modelo = t.modelo
                          ORDER BY ec.id_equipo LIMIT 1)
     WHERE t.accion = 'crear';

    UPDATE tmp_importacion_equipos
       SET resultado = 'reutilizado'
     WHERE accion = 'crear' AND id_equipo IS NOT NULL;

    SELECT correo INTO v_usuario_login FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    -- ── Registro de los equipos nuevos ───────────────────────────────────
    START TRANSACTION;

    SET v_anio = DATE_FORMAT(NOW(), '%Y');
    SELECT IFNULL(MAX(orden), 0) INTO v_max FROM tmp_importacion_equipos;
    SET v_i = 1;

    WHILE v_i <= v_max DO
        SET v_num_serie = NULL;
        SELECT num_serie, marca, modelo, clasificacion, id_suministro, id_sede, codigo_cliente, ubicacion, alcance
          INTO v_num_serie, v_marca, v_modelo, v_clasificacion, v_id_suministro, v_id_sede, v_codigo_cli, v_ubicacion, v_alcance
          FROM tmp_importacion_equipos
         WHERE orden = v_i AND accion = 'crear' AND id_equipo IS NULL;

        IF v_num_serie IS NOT NULL THEN
            SELECT IFNULL(MAX(CAST(SUBSTRING_INDEX(codigo_tw, '-', -1) AS UNSIGNED)), 0) + 1
              INTO v_correlativo
              FROM equipo_cliente
             WHERE codigo_tw LIKE CONCAT('EQ-TW-', v_anio, '-%');
            SET v_codigo_tw = CONCAT('EQ-TW-', v_anio, '-', LPAD(v_correlativo, 4, '0'));

            INSERT INTO equipo_cliente (
                codigo_tw, num_serie, id_cliente, id_sede, codigo_cliente,
                clasificacion, marca, modelo,
                ubicacion_especifica, es_pre_revisado, bloqueado_para_servicios,
                id_suministro, division_verif_igual,
                alcance_maximo, valor_nominal, observaciones,
                estado_operativo, es_activo, estado,
                usuario_registro, SoftDelete, UsuCre, FchCre
            ) VALUES (
                v_codigo_tw, v_num_serie, p_id_cliente, v_id_sede, v_codigo_cli,
                v_clasificacion, v_marca, v_modelo,
                v_ubicacion, 0, 0,
                v_id_suministro, 1,
                IF(v_clasificacion = 'pesa', NULL, v_alcance),
                IF(v_clasificacion = 'pesa', v_alcance, NULL),
                'Registrado desde la importación de equipos de una propuesta.',
                NULL, 1, 'activo',
                v_usuario_login, 0, v_usuario_login, NOW()
            );
            SET v_id = LAST_INSERT_ID();

            UPDATE tmp_importacion_equipos
               SET id_equipo = v_id, resultado = 'creado'
             WHERE orden = v_i;
        END IF;

        SET v_i = v_i + 1;
    END WHILE;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Equipos importados: ', COUNT(*), '.') AS Mensaje
      FROM tmp_importacion_equipos;

    SELECT SUM(resultado = 'vinculado')   AS vinculados,
           SUM(resultado = 'creado')      AS creados,
           SUM(resultado = 'reutilizado') AS reutilizados
      FROM tmp_importacion_equipos;

    SELECT t.fila,
           ec.id_equipo,
           ec.codigo_tw,
           ec.num_serie,
           ec.marca,
           ec.modelo,
           ec.clasificacion,
           COALESCE(tm_cl.String1, ec.clasificacion) AS clasificacion_label,
           su.tipo                                   AS suministro_tipo,
           su.subtipo                                AS suministro_subtipo,
           ec.id_sede,
           s.nombre                                  AS sede_nombre,
           ec.codigo_cliente,
           ec.ubicacion_especifica,
           t.resultado
    FROM   tmp_importacion_equipos t
    JOIN   equipo_cliente ec ON ec.id_equipo = t.id_equipo
    LEFT   JOIN sede_cliente s  ON s.id_sede = ec.id_sede
    LEFT   JOIN suministros  su ON su.id_suministro = ec.id_suministro
    LEFT   JOIN tabla_maestra tm_cl
             ON tm_cl.IdMaestro = 71 AND tm_cl.IdEmpresa = 1 AND tm_cl.String2 = ec.clasificacion
    ORDER  BY t.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_importacion_equipos;
END$$
DELIMITER ;
