-- ============================================================
-- SP_RegistrarRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — «Registrar recepción» · escritura)
-- El técnico de Metrología registra en UN solo paso la recepción de uno o varios instrumentos de una OM: trazabilidad de entrega, estado físico y observaciones de cada instrumento,
-- accesorios, fotos y la firma de quien entrega. Todo o nada (una transacción).
--   - Acceso: la OM debe ser del técnico y estar activa (SP_ArmarOmTecnicoMovil); el técnico que recibe sale del token. NO exige llegada GPS (el instrumento está en el taller).
--   - Trazabilidad: p_guia 3 a 40 caracteres · p_medio cliente_taller | courier | traslado_tw · p_entrego 3 a 120 · p_cargo opcional hasta 120. La fecha y hora es la del servidor.
--   - p_instrumentos (JSON): [{ "idOsEquipo": n, "estadoFisico": "conforme"|"observado", "observaciones": "10 a 500 caracteres", "accesorios": ["caja_original", …], "fotos": [idFoto, …] }]
--       · al menos 1 instrumento, sin repetidos, todos de la OM y todos pendientes de recibir (un instrumento se recibe UNA sola vez por OM);
--       · estado físico y observaciones obligatorios en cada uno (también si es conforme); accesorios del catálogo (SP_CatalogoAccesoriosRecepcionOmMovil);
--       · fotos: de 3 a 8 por instrumento, ya subidas (SP_RegistrarFotoRecepcionOmMovil), del mismo técnico, de ese instrumento y sin usar.
--   - Si tras esta recepción QUEDAN instrumentos sin recibir la recepción es PARCIAL: p_motivo obligatorio (10 a 300 caracteres) y se notifica a Programación (usuarios de Operaciones con el
--     permiso prog_bandeja; si no hay ninguno, a los jefes/administradores del área de la OM — SP_ArmarAprobadoresOsMovil). La OM queda abierta hasta recibir lo que falta.
--   - Estado de la recepción: parcial (quedan pendientes) · observado (alguno de los instrumentos recibidos está observado) · conforme.
--   - p_firma (JSON): { "trazos": [[[x,y],…],…] } de quien entrega (trazos normalizados 0 a 1, ≤ 30 000 caracteres), como la firma de la HU-17. El back ya validó su forma.
--   - Las demás fotos pendientes del técnico en esos instrumentos (no incluidas) se descartan.
--   - Deja el registro en auditoria_evento (entidad 'orden_servicio').
-- Resultados: 1 mensaje; 2 (id_recepcion, estado, parcial, instrumentos_recibidos, instrumentos_pendientes, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarRecepcionOmMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_guia          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_medio         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_entrego       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_cargo         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo        VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_instrumentos  JSON,
    IN p_firma         JSON
)
proc: BEGIN
    DECLARE v_guia      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_medio     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_entrego   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo    VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_n_dist    INT DEFAULT 0;
    DECLARE v_malos     INT DEFAULT 0;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_activa    TINYINT DEFAULT 0;
    DECLARE v_lock      BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total     INT DEFAULT 0;
    DECLARE v_previos   INT DEFAULT 0;
    DECLARE v_pend      INT DEFAULT 0;
    DECLARE v_obs       INT DEFAULT 0;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora     DATETIME;
    DECLARE v_id        BIGINT;
    DECLARE v_tecnico   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_faltan    TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_notif     INT DEFAULT 0;
    DECLARE v_msg       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_firma_txt MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nf        INT DEFAULT 0;
    DECLARE v_ok        INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_acc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_foto;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_acc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_dest;
        DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validación de la entrada ────────────────────────────────────────────
    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_guia    = NULLIF(TRIM(IFNULL(p_guia, '')), '');
    SET v_medio   = LOWER(TRIM(IFNULL(p_medio, '')));
    SET v_entrego = NULLIF(TRIM(IFNULL(p_entrego, '')), '');
    SET v_cargo   = NULLIF(TRIM(IFNULL(p_cargo, '')), '');
    SET v_motivo  = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_guia IS NULL OR CHAR_LENGTH(v_guia) < 3 OR CHAR_LENGTH(v_guia) > 40 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el N° de guía de remisión (de 3 a 40 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF v_medio NOT IN ('cliente_taller', 'courier', 'traslado_tw') THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el medio de entrega: Cliente en taller, Courier o Traslado TW.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_entrego IS NULL OR CHAR_LENGTH(v_entrego) < 3 OR CHAR_LENGTH(v_entrego) > 120 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el nombre de quien entrega (de 3 a 120 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(v_cargo, '')) > 120 THEN
        SELECT 1 AS IdTipoMensaje, 'La empresa o cargo de quien entrega puede tener hasta 120 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(v_motivo, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo de la recepción parcial puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_instrumentos IS NULL OR JSON_TYPE(p_instrumentos) <> 'ARRAY' OR JSON_LENGTH(p_instrumentos) < 1 OR JSON_LENGTH(p_instrumentos) > 50 THEN
        SELECT 1 AS IdTipoMensaje, 'Marca al menos un instrumento recibido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_firma_txt = CAST(p_firma AS CHAR);
    IF p_firma IS NULL OR JSON_TYPE(p_firma) <> 'OBJECT' OR CHAR_LENGTH(v_firma_txt) > 30000 OR IFNULL(JSON_TYPE(JSON_EXTRACT(p_firma, '$.trazos')), '') <> 'ARRAY' OR IFNULL(JSON_LENGTH(JSON_EXTRACT(p_firma, '$.trazos')), 0) < 1 THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la firma de quien entrega.' AS Mensaje; LEAVE proc;
    END IF;

    -- Los instrumentos que llegan, en tablas temporales (cada regla se valida en una sola consulta)
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_in;
    CREATE TEMPORARY TABLE tmp_rom_in (
        n INT NOT NULL, id_os_equipo BIGINT NULL,
        estado_fisico VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        observaciones VARCHAR(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        accesorios JSON NULL, PRIMARY KEY (n));
    INSERT INTO tmp_rom_in (n, id_os_equipo, estado_fisico, observaciones, accesorios)
    SELECT jt.n, jt.id_os_equipo, LOWER(TRIM(jt.estado_fisico)), TRIM(jt.observaciones), jt.accesorios
    FROM   JSON_TABLE(p_instrumentos, '$[*]' COLUMNS (
               n FOR ORDINALITY,
               id_os_equipo BIGINT PATH '$.idOsEquipo',
               estado_fisico VARCHAR(60) PATH '$.estadoFisico',
               observaciones VARCHAR(2000) PATH '$.observaciones',
               accesorios JSON PATH '$.accesorios')) jt;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_foto;
    CREATE TEMPORARY TABLE tmp_rom_in_foto (id_os_equipo BIGINT NULL, id_foto BIGINT NOT NULL);
    INSERT INTO tmp_rom_in_foto (id_os_equipo, id_foto)
    SELECT jt.id_os_equipo, jt.id_foto
    FROM   JSON_TABLE(p_instrumentos, '$[*]' COLUMNS (
               id_os_equipo BIGINT PATH '$.idOsEquipo',
               NESTED PATH '$.fotos[*]' COLUMNS (id_foto BIGINT PATH '$'))) jt
    WHERE  jt.id_foto IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_acc;
    CREATE TEMPORARY TABLE tmp_rom_in_acc (id_os_equipo BIGINT NULL, codigo VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL);
    INSERT INTO tmp_rom_in_acc (id_os_equipo, codigo)
    SELECT jt.id_os_equipo, LOWER(TRIM(jt.codigo))
    FROM   JSON_TABLE(p_instrumentos, '$[*]' COLUMNS (
               id_os_equipo BIGINT PATH '$.idOsEquipo',
               NESTED PATH '$.accesorios[*]' COLUMNS (codigo VARCHAR(100) PATH '$'))) jt
    WHERE  jt.codigo IS NOT NULL;

    -- Reglas de cada instrumento: el primer problema que se encuentra es el mensaje
    SELECT COUNT(*), COUNT(DISTINCT x.id_os_equipo) INTO v_n, v_n_dist FROM tmp_rom_in x;
    IF v_n <> v_n_dist OR EXISTS (SELECT 1 FROM tmp_rom_in x WHERE x.id_os_equipo IS NULL OR x.id_os_equipo <= 0) THEN
        SET v_msg = 'Los instrumentos de la recepción no son válidos o están repetidos.';
    END IF;
    IF v_msg IS NULL THEN
        SELECT COUNT(*) INTO v_malos FROM tmp_rom_in x WHERE x.estado_fisico IS NULL OR x.estado_fisico NOT IN ('conforme', 'observado');
        IF v_malos > 0 THEN SET v_msg = 'Elige el estado físico (Conforme u Observado) de cada instrumento.'; END IF;
    END IF;
    IF v_msg IS NULL THEN
        SELECT COUNT(*) INTO v_malos FROM tmp_rom_in x WHERE x.observaciones IS NULL OR CHAR_LENGTH(x.observaciones) < 10 OR CHAR_LENGTH(x.observaciones) > 500;
        IF v_malos > 0 THEN SET v_msg = 'Escribe las observaciones de cada instrumento (de 10 a 500 caracteres).'; END IF;
    END IF;
    IF v_msg IS NULL THEN
        CALL SP_CatalogoAccesoriosRecepcionOmMovil();
        SELECT COUNT(*) INTO v_malos FROM tmp_rom_in_acc a LEFT JOIN tmp_rom_acc c ON c.codigo = a.codigo WHERE c.codigo IS NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_acc;
        IF v_malos > 0 THEN SET v_msg = 'Hay un accesorio que no existe en la lista (Caja original, Adaptador de corriente, Protector de plato, Manual u Otro).'; END IF;
    END IF;
    IF v_msg IS NULL THEN
        SELECT COUNT(*) INTO v_malos
        FROM  (SELECT x.id_os_equipo, COUNT(f.id_foto) AS n, COUNT(DISTINCT f.id_foto) AS d
               FROM   tmp_rom_in x LEFT JOIN tmp_rom_in_foto f ON f.id_os_equipo = x.id_os_equipo
               GROUP BY x.id_os_equipo) z
        WHERE  z.n <> z.d OR z.n < 3 OR z.n > 8;
        IF v_malos > 0 THEN SET v_msg = 'Cada instrumento necesita de 3 a 8 fotos de recepción (solo cámara).'; END IF;
    END IF;
    IF v_msg IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_foto;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_acc;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;


    -- ── Transacción: la OM se bloquea (dos recepciones a la vez no reciben el mismo instrumento) ──
    START TRANSACTION;

    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os AND os.tipo = 'OM' AND os.eliminado_en IS NULL FOR UPDATE;
    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*), IFNULL(MAX(o.activa), 0), MAX(o.numero), MAX(o.cliente) INTO v_existe, v_activa, v_numero, v_cliente FROM tmp_rom_os o;
    IF v_lock IS NULL OR v_existe = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_activa = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, CONCAT('La ', v_numero, ' ya no está activa: no admite recepciones.') AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    SELECT COUNT(*), IFNULL(SUM(i.recibido), 0) INTO v_total, v_previos FROM tmp_rom_inst i;

    SELECT COUNT(*) INTO v_malos FROM tmp_rom_in x LEFT JOIN tmp_rom_inst i ON i.id_os_equipo = x.id_os_equipo WHERE i.id_os_equipo IS NULL;
    IF v_malos > 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 1 AS IdTipoMensaje, CONCAT('Un instrumento no pertenece a la ', v_numero, '.') AS Mensaje; LEAVE proc;
    END IF;
    SELECT CONCAT(CONCAT_WS(' ', i.nombre, i.marca, i.modelo), ' ya se recibió el ', DATE_FORMAT(CONVERT_TZ(i.recibido_utc, '+00:00', '-05:00'), '%d/%m a las %H:%i'),
                  '. No se puede recibir dos veces en la misma OM.')
    INTO   v_msg
    FROM   tmp_rom_in x JOIN tmp_rom_inst i ON i.id_os_equipo = x.id_os_equipo
    WHERE  i.recibido = 1
    ORDER BY x.n LIMIT 1;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Fotos: del mismo técnico, de ese instrumento y sin usar (se bloquean para que no se quiten a mitad del registro)
    SELECT COUNT(*) INTO v_ok
    FROM   om_recepcion_foto f
    JOIN   tmp_rom_in_foto x ON x.id_foto = f.id_foto AND x.id_os_equipo = f.id_os_equipo
    WHERE  f.id_usuario = p_id_usuario AND f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL
    FOR UPDATE;
    SELECT COUNT(*) INTO v_nf FROM tmp_rom_in_foto;
    IF v_ok <> v_nf THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 1 AS IdTipoMensaje, 'Alguna foto ya no está disponible (se quitó o ya se usó). Vuelve a tomar las fotos del instrumento.' AS Mensaje; LEAVE proc;
    END IF;

    -- Estado: parcial si quedan instrumentos sin recibir; si no, observado si alguno lo está; si no, conforme
    SET v_pend = v_total - v_previos - v_n;
    SELECT COUNT(*) INTO v_obs FROM tmp_rom_in x WHERE x.estado_fisico = 'observado';
    SET v_estado = IF(v_pend > 0, 'parcial', IF(v_obs > 0, 'observado', 'conforme'));
    IF v_estado = 'parcial' THEN
        IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 10 THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
            DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
            SELECT 1 AS IdTipoMensaje, CONCAT('Falta recibir ', v_pend, IF(v_pend = 1, ' instrumento', ' instrumentos'), ' de la ', v_numero,
                                              ': escribe el motivo de la recepción parcial (de 10 a 300 caracteres).') AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SET v_motivo = NULL;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    INSERT INTO om_recepcion (id_os, numero_guia, medio_entrega, entrego_nombre, entrego_cargo, id_usuario_recibio, recibido_utc, estado, motivo_parcial, firma_trazos, creado_por)
    VALUES (p_id_os, v_guia, v_medio, v_entrego, v_cargo, p_id_usuario, v_ahora, v_estado, v_motivo, p_firma, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    INSERT INTO om_recepcion_equipo (id_recepcion, id_os_equipo, estado_fisico, observaciones, accesorios)
    SELECT v_id, x.id_os_equipo, x.estado_fisico, x.observaciones, IFNULL(x.accesorios, JSON_ARRAY())
    FROM   tmp_rom_in x
    ORDER BY x.n;

    UPDATE om_recepcion_foto f
    JOIN   tmp_rom_in_foto x ON x.id_foto = f.id_foto
    JOIN   om_recepcion_equipo re ON re.id_recepcion = v_id AND re.id_os_equipo = x.id_os_equipo
    SET    f.id_recepcion_equipo = re.id_recepcion_equipo;

    -- Las fotos pendientes que no se incluyeron en esos instrumentos se descartan
    UPDATE om_recepcion_foto f
    SET    f.eliminado_en = NOW()
    WHERE  f.id_usuario = p_id_usuario AND f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL
      AND  f.id_os_equipo IN (SELECT x.id_os_equipo FROM tmp_rom_in x);

    -- Recepción parcial: aviso a Programación (la OM queda abierta hasta recibir lo que falta)
    IF v_estado = 'parcial' THEN
        SELECT NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') INTO v_tecnico FROM usuario u WHERE u.id_usuario = p_id_usuario;
        SELECT GROUP_CONCAT(CONCAT_WS(' ', i.nombre, i.marca, i.modelo) ORDER BY i.numero SEPARATOR ', ') INTO v_faltan
        FROM   tmp_rom_inst i
        WHERE  i.recibido = 0 AND i.id_os_equipo NOT IN (SELECT x.id_os_equipo FROM tmp_rom_in x);

        DROP TEMPORARY TABLE IF EXISTS tmp_rom_dest;
        CREATE TEMPORARY TABLE tmp_rom_dest (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT IGNORE INTO tmp_rom_dest (id_usuario)
        SELECT u.id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.area = 'operaciones'
          AND  FN_PermisoAccion(u.id_usuario, 'prog_bandeja') = 1;
        IF NOT EXISTS (SELECT 1 FROM tmp_rom_dest) THEN
            CALL SP_ArmarAprobadoresOsMovil(p_id_os);
            INSERT IGNORE INTO tmp_rom_dest (id_usuario) SELECT a.id_usuario FROM tmp_aprobadores a WHERE a.id_usuario <> p_id_usuario;
            DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
        END IF;

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT d.id_usuario, 5, CONCAT('Recepción parcial: ', v_numero),
               LEFT(CONCAT(IFNULL(v_tecnico, 'El técnico'), ' recibió ', v_n, IF(v_n = 1, ' instrumento' , ' instrumentos'), ' de la ', v_numero,
                           IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)), ' (guía ', v_guia, '). Faltan ', v_pend, IF(v_pend = 1, ' instrumento: ', ' instrumentos: '),
                           IFNULL(v_faltan, '—'), '. Motivo: ', v_motivo, '. La OM queda abierta hasta recibirlos.'), 3000),
               'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   tmp_rom_dest d;
        SET v_notif = ROW_COUNT();
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_dest;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'recepcion_om', NULL, v_estado,
            LEFT(CONCAT('Recepción de ', v_n, IF(v_n = 1, ' instrumento' , ' instrumentos'), ' de la ', v_numero, ' (guía ', v_guia, ', entregó ', v_entrego, '): ', v_estado,
                        IF(v_motivo IS NULL, '', CONCAT('. ', v_motivo))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_recepcion', v_id, 'guia', v_guia, 'medio', v_medio, 'instrumentos', v_n, 'pendientes', v_pend));

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_in;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_foto;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_in_acc;

    SELECT 2 AS IdTipoMensaje,
           IF(v_estado = 'parcial',
              CONCAT('Recepción parcial registrada: faltan ', v_pend, IF(v_pend = 1, ' instrumento' , ' instrumentos'), '. La ', v_numero, ' queda abierta.'),
              CONCAT('Recepción registrada: ', v_n, IF(v_n = 1, ' instrumento' , ' instrumentos'), ' de la ', v_numero, '.')) AS Mensaje;
    SELECT v_id AS id_recepcion, v_estado AS estado, IF(v_estado = 'parcial', 1, 0) AS parcial, v_n AS instrumentos_recibidos, v_pend AS instrumentos_pendientes, v_notif AS notificados;
END$$

DELIMITER ;
