-- HU-33 Confirmar la reasignación del responsable comercial (Jefe Comercial / Administrador, acción expediente_reasignar).
-- Solo desde un expediente en etapa comercial (RQ, Propuesta, VB, Seguimiento, OC u OS) y no cerrado. Tres modos:
--   entidad  (Opción A) solo la entidad elegida (p_entidad_tipo + p_id_entidad)
--   cascada  (Opción B) la entidad raíz + todo lo que viene de ella en el árbol (RQ → propuestas → OC/OS; propuesta →
--            sus OC y OS), menos las claves de p_excluidos (JSON ["oc-12","os-3"]); la raíz no se puede excluir
--   global   (Opción C) todas las entidades activas del comercial p_id_responsable_actual en TODOS los expedientes
-- Entidades reasignables: RQ, propuesta (última versión), OC y OS ACTIVAS (las finalizadas conservan su responsable).
-- El seguimiento se arrastra: su próxima acción pendiente pasa al nuevo responsable de la propuesta.
-- Validaciones: nuevo responsable activo del área Comercial; motivo de MOTIVO_REASIGNACION_EXPEDIENTE; comentario de 20
--   a 1000 caracteres; gestión del SLA 'mantener' (sigue el vencimiento) o 'reiniciar' (la etapa actual de cada
--   expediente afectado cuenta su SLA desde ahora). Se omiten las entidades que ya son del nuevo responsable.
-- Registra: cabecera y detalle (expediente_reasignacion), el cambio en el timeline de cada entidad (auditoría de la
--   propuesta, OC y OS; historial del RQ), el evento consolidado en cada expediente afectado y las notificaciones en la
--   intranet al nuevo responsable (lista de lo que ahora es suyo) y a los anteriores (informativa). El correo lo envía
--   la aplicación con los datos de los resultados 2 y 4.
-- Resultados: 1 mensaje · 2 resumen · 3 entidades reasignadas · 4 responsables anteriores (para el correo informativo)
DROP PROCEDURE IF EXISTS SP_ReasignarResponsableExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ReasignarResponsableExpediente(
    IN p_id_usuario            BIGINT,
    IN p_id_expediente         BIGINT,
    IN p_modo                  VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_entidad_tipo          VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_entidad            BIGINT,
    IN p_excluidos             TEXT          CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_responsable_actual BIGINT,
    IN p_id_nuevo              BIGINT,
    IN p_id_motivo             INT,
    IN p_comentario            VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_gestion_sla           VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_modo        VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_gestion     VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comentario  VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_etapa       VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comercial   TINYINT DEFAULT 0;
    DECLARE v_resp_exp    BIGINT;
    DECLARE v_raiz_clave  VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_raiz_codigo VARCHAR(80)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_raiz_resp   BIGINT;
    DECLARE v_anterior    BIGINT;
    DECLARE v_nuevo       VARCHAR(220)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_correo      VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nuevo  VARCHAR(60)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo      VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ejecutor    VARCHAR(220)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total       INT DEFAULT 0;
    DECLARE v_expedientes INT DEFAULT 0;
    DECLARE v_id_reas     BIGINT;
    DECLARE v_alcance     VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_lista       TEXT          CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_reas_sel;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent;
        DROP TEMPORARY TABLE IF EXISTS tmp_cartera;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET SESSION group_concat_max_len = 1000000;
    SET v_modo       = LOWER(TRIM(IFNULL(p_modo, '')));
    SET v_gestion    = LOWER(TRIM(IFNULL(p_gestion_sla, '')));
    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SET v_tipo       = LOWER(TRIM(IFNULL(p_entidad_tipo, '')));

    -- ── Validaciones de entrada ─────────────────────────────────────────────
    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar responsables.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_modo NOT IN ('entidad', 'cascada', 'global') THEN
        SELECT 1 AS IdTipoMensaje, 'Elija el tipo de reasignación: entidad, cascada o global.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_modo IN ('entidad', 'cascada')
       AND (v_tipo NOT IN ('requerimiento', 'propuesta', 'orden_compra', 'orden_servicio') OR IFNULL(p_id_entidad, 0) <= 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione la entidad a reasignar (RQ, propuesta, OC u OS).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_excluidos, '')), '') IS NOT NULL AND JSON_VALID(p_excluidos) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La lista de entidades excluidas no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido), correo, area INTO v_nuevo, v_correo, v_area_nuevo
    FROM usuario WHERE id_usuario = p_id_nuevo AND estado = 'activo' AND eliminado_en IS NULL;
    IF v_nuevo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione un nuevo responsable activo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(v_area_nuevo, '') <> 'comercial' THEN
        SELECT 1 AS IdTipoMensaje, 'El nuevo responsable debe ser del área Comercial.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_motivo FROM tabla_maestra
    WHERE IdMaestro = 100 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL;
    IF v_motivo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo de la reasignación.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_comentario IS NULL OR CHAR_LENGTH(v_comentario) < 20 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario es obligatorio (mínimo 20 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_gestion NOT IN ('mantener', 'reiniciar') THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la gestión del SLA: mantener o reiniciar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Expediente de origen (etapa comercial) ──────────────────────────────
    CALL SP_CalcularExpedientes(p_id_usuario, NULL);
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
    SELECT COUNT(*), MAX(etapa), MAX(etapa_comercial), MAX(id_responsable)
      INTO v_existe, v_etapa, v_comercial, v_resp_exp
    FROM tmp_exp WHERE id_expediente = p_id_expediente;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' OR v_comercial = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje,
               'La reasignación solo está disponible en las etapas comerciales (RQ, Propuesta, VB, Seguimiento, OC u OS).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Entidades seleccionadas ─────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_reas_sel;
    CREATE TEMPORARY TABLE tmp_reas_sel (
        id_expediente  BIGINT,
        entidad_tipo   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_entidad     BIGINT,
        codigo         VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_anterior    BIGINT,
        PRIMARY KEY (entidad_tipo, id_entidad)
    );

    IF v_modo IN ('entidad', 'cascada') THEN
        CALL SP_CargarEntidadesExpediente(p_id_expediente);

        SELECT clave, IF(entidad_tipo = 'propuesta', CONCAT(codigo, ' v', version), codigo), id_responsable
          INTO v_raiz_clave, v_raiz_codigo, v_raiz_resp
        FROM tmp_exp_ent
        WHERE entidad_tipo = v_tipo AND id_entidad = p_id_entidad AND activa = 1;

        IF v_raiz_clave IS NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent;
            DROP TEMPORARY TABLE IF EXISTS tmp_reas_sel;
            DROP TEMPORARY TABLE IF EXISTS tmp_exp;
            SELECT 1 AS IdTipoMensaje,
                   'La entidad no pertenece al expediente o ya está finalizada (las finalizadas conservan su responsable).' AS Mensaje;
            LEAVE proc;
        END IF;

        -- Raíz y, en cascada, sus descendientes activos (RQ → todo; propuesta → sus OC y OS)
        INSERT INTO tmp_reas_sel
        SELECT p_id_expediente, e.entidad_tipo, e.id_entidad,
               IF(e.entidad_tipo = 'propuesta', CONCAT(e.codigo, ' v', e.version), e.codigo), e.id_responsable
        FROM tmp_exp_ent e
        WHERE e.activa = 1 AND e.entidad_tipo IN ('requerimiento', 'propuesta', 'orden_compra', 'orden_servicio')
          AND (e.clave = v_raiz_clave
               OR (v_modo = 'cascada' AND v_tipo = 'requerimiento')
               OR (v_modo = 'cascada' AND v_tipo = 'propuesta' AND e.clave_padre = v_raiz_clave));

        -- Personalización: entidades desmarcadas (la raíz siempre queda)
        IF NULLIF(TRIM(IFNULL(p_excluidos, '')), '') IS NOT NULL AND v_modo = 'cascada' THEN
            DELETE s FROM tmp_reas_sel s
            JOIN JSON_TABLE(p_excluidos, '$[*]' COLUMNS (clave VARCHAR(40) PATH '$')) j
              ON j.clave = CONCAT(CASE s.entidad_tipo WHEN 'requerimiento' THEN 'rq-' WHEN 'propuesta' THEN 'prop-'
                                                       WHEN 'orden_compra' THEN 'oc-' ELSE 'os-' END, s.id_entidad)
            WHERE j.clave <> v_raiz_clave;
        END IF;

        SET v_anterior = v_raiz_resp;
        SET v_alcance  = CONCAT(IF(v_modo = 'cascada', 'Cascada desde ', ''),
                                CASE v_tipo WHEN 'propuesta' THEN 'Propuesta ' WHEN 'orden_compra' THEN 'OC ' ELSE '' END,
                                v_raiz_codigo);
        DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent;
    ELSE
        SET v_anterior = IFNULL(NULLIF(p_id_responsable_actual, 0), v_resp_exp);
        IF v_anterior IS NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_reas_sel;
            DROP TEMPORARY TABLE IF EXISTS tmp_exp;
            SELECT 1 AS IdTipoMensaje, 'Seleccione el comercial cuya cartera se reasignará.' AS Mensaje;
            LEAVE proc;
        END IF;
        CALL SP_CargarCarteraComercial(v_anterior);
        INSERT IGNORE INTO tmp_reas_sel
        SELECT id_expediente, entidad_tipo, id_entidad, codigo, v_anterior FROM tmp_cartera;
        DROP TEMPORARY TABLE IF EXISTS tmp_cartera;
        SET v_alcance = 'Cartera completa';
    END IF;

    -- Las que ya son del nuevo responsable no cambian
    DELETE FROM tmp_reas_sel WHERE id_anterior <=> p_id_nuevo;

    SELECT COUNT(*), COUNT(DISTINCT id_expediente) INTO v_total, v_expedientes FROM tmp_reas_sel;
    IF v_total = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_reas_sel;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje,
               'No hay entidades activas para reasignar (o ya son del nuevo responsable). Seleccione al menos una.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_modo = 'global' THEN
        SET v_alcance = CONCAT('Cartera completa (', v_total, ' entidades en ', v_expedientes, ' expedientes)');
    ELSEIF v_modo = 'cascada' THEN
        SET v_alcance = CONCAT(v_alcance, ' (', v_total, ' entidades)');
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_ejecutor FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    -- 1. Las OC y OS que heredaban el responsable de su propuesta quedan con el actual (así no se mueven sin elegirlas)
    UPDATE orden_compra oc
    SET oc.id_responsable = (SELECT COALESCE(p.id_responsable, p.id_creador) FROM oc_propuesta op
                             JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
                             WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL ORDER BY op.id LIMIT 1),
        oc.modificado_en = oc.modificado_en
    WHERE oc.id_responsable IS NULL AND oc.eliminado_en IS NULL
      AND oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                       JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
                       JOIN expediente_digital e ON e.id_requerimiento = p.id_requerimiento
                       WHERE op.eliminado_en IS NULL AND e.id_expediente IN (SELECT id_expediente FROM tmp_reas_sel));

    UPDATE orden_servicio os
    JOIN expediente_digital e ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = e.id_propuesta
    SET os.id_responsable_comercial = COALESCE(p.id_responsable, p.id_creador), os.modificado_en = os.modificado_en
    WHERE os.id_responsable_comercial IS NULL AND os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada')
      AND os.id_expediente IN (SELECT id_expediente FROM tmp_reas_sel);

    -- 2. Cambio de responsable en cada entidad
    UPDATE requerimiento r JOIN tmp_reas_sel s ON s.entidad_tipo = 'requerimiento' AND s.id_entidad = r.id_requerimiento
    SET r.id_responsable = p_id_nuevo, r.modificado_por = p_id_usuario, r.modificado_en = r.modificado_en;

    UPDATE propuesta_comercial p JOIN tmp_reas_sel s ON s.entidad_tipo = 'propuesta' AND s.id_entidad = p.id_propuesta
    SET p.id_responsable = p_id_nuevo, p.modificado_por = p_id_usuario, p.modificado_en = p.modificado_en;

    UPDATE orden_compra oc JOIN tmp_reas_sel s ON s.entidad_tipo = 'orden_compra' AND s.id_entidad = oc.id_oc
    SET oc.id_responsable = p_id_nuevo, oc.modificado_por = p_id_usuario, oc.modificado_en = oc.modificado_en;

    UPDATE orden_servicio os JOIN tmp_reas_sel s ON s.entidad_tipo = 'orden_servicio' AND s.id_entidad = os.id_os
    SET os.id_responsable_comercial = p_id_nuevo, os.modificado_por = p_id_usuario, os.modificado_en = os.modificado_en;

    -- El seguimiento se arrastra: la próxima acción pendiente de la propuesta pasa al nuevo responsable
    UPDATE seguimiento_comercial sc
    JOIN tmp_reas_sel s ON s.entidad_tipo = 'propuesta' AND s.id_entidad = sc.id_propuesta
    SET sc.id_responsable = p_id_nuevo, sc.modificado_por = p_id_usuario
    WHERE sc.eliminado_en IS NULL AND sc.estado = 'activo'
      AND sc.id_seguimiento = (SELECT x.id_seguimiento FROM (SELECT id_seguimiento, id_propuesta FROM seguimiento_comercial
                                                             WHERE eliminado_en IS NULL) x
                               WHERE x.id_propuesta = sc.id_propuesta ORDER BY x.id_seguimiento DESC LIMIT 1);

    -- 3. SLA: "Reiniciar" cuenta desde ahora la etapa actual de cada expediente afectado que esté en etapa comercial
    --    (no cambia el SLA de las etapas operativas)
    IF v_gestion = 'reiniciar' THEN
        UPDATE expediente_digital e
        JOIN tmp_exp x ON x.id_expediente = e.id_expediente
        SET e.sla_reinicio = NOW(), e.sla_reinicio_etapa = x.etapa, e.modificado_por = p_id_usuario
        WHERE e.id_expediente IN (SELECT id_expediente FROM tmp_reas_sel) AND x.etapa <> 'cerrado' AND x.etapa_comercial = 1;
    END IF;

    -- 4. Registro de la reasignación (cabecera y detalle)
    INSERT INTO expediente_reasignacion (modo, id_expediente, entidad_tipo, id_entidad, codigo_entidad, id_responsable_anterior,
                                         id_responsable_nuevo, id_motivo, comentario, gestion_sla, total_entidades,
                                         total_expedientes, registrado_en, registrado_por, UsuCre, FchCre)
    VALUES (v_modo, p_id_expediente, IF(v_modo = 'global', NULL, v_tipo), IF(v_modo = 'global', NULL, p_id_entidad),
            IF(v_modo = 'global', NULL, v_raiz_codigo), v_anterior, p_id_nuevo, p_id_motivo, v_comentario, v_gestion,
            v_total, v_expedientes, NOW(), p_id_usuario, CAST(p_id_usuario AS CHAR), NOW());
    SET v_id_reas = LAST_INSERT_ID();

    INSERT INTO expediente_reasignacion_detalle (id_reasignacion, id_expediente, entidad_tipo, id_entidad, codigo_entidad,
                                                 id_responsable_anterior, id_responsable_nuevo, etapa, sla_limite_anterior,
                                                 sla_limite_nuevo, UsuCre, FchCre)
    SELECT v_id_reas, s.id_expediente, s.entidad_tipo, s.id_entidad, s.codigo, s.id_anterior, p_id_nuevo, x.etapa, x.fecha_limite,
           IF(v_gestion = 'reiniciar' AND x.sla_horas IS NOT NULL AND x.etapa_comercial = 1, NOW() + INTERVAL x.sla_horas HOUR, x.fecha_limite),
           CAST(p_id_usuario AS CHAR), NOW()
    FROM tmp_reas_sel s
    LEFT JOIN tmp_exp x ON x.id_expediente = s.id_expediente;

    -- 5. Timeline de cada entidad
    INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
    SELECT s.id_entidad, 'reasignacion', 'Responsable reasignado', 'swap_horiz',
           LEFT(CONCAT('Responsable: ', IFNULL(CONCAT(ua.nombre, ' ', ua.apellido), 'sin asignar'), ' → ', v_nuevo,
                       '. Motivo: ', v_motivo, '. ', v_comentario), 2000),
           v_ejecutor, NOW(), NOW(), p_id_usuario
    FROM tmp_reas_sel s LEFT JOIN usuario ua ON ua.id_usuario = s.id_anterior
    WHERE s.entidad_tipo = 'requerimiento';

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                  registrado_en, metadata)
    SELECT s.entidad_tipo, s.id_entidad, 'reasignar_responsable',
           LEFT(IFNULL(CONCAT(ua.nombre, ' ', ua.apellido), 'sin asignar'), 80), LEFT(v_nuevo, 80),
           LEFT(CONCAT('Responsable: ', IFNULL(CONCAT(ua.nombre, ' ', ua.apellido), 'sin asignar'), ' → ', v_nuevo,
                       '. Motivo: ', v_motivo, '. ', v_comentario), 2000),
           p_id_usuario, NOW(),
           JSON_OBJECT('id_reasignacion', v_id_reas, 'modo', v_modo, 'id_anterior', s.id_anterior, 'id_nuevo', p_id_nuevo,
                       'id_motivo', p_id_motivo, 'gestion_sla', v_gestion)
    FROM tmp_reas_sel s LEFT JOIN usuario ua ON ua.id_usuario = s.id_anterior
    WHERE s.entidad_tipo IN ('propuesta', 'orden_compra', 'orden_servicio');

    -- 6. Evento consolidado en cada expediente afectado
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                  registrado_en, metadata)
    SELECT 'expediente', k.id_expediente, 'reasignar_responsable',
           LEFT(IFNULL(CONCAT(ua.nombre, ' ', ua.apellido), 'varios'), 80), LEFT(v_nuevo, 80),
           LEFT(CONCAT(v_alcance, ': ', k.codigos, ' → ', v_nuevo, '. Motivo: ', v_motivo, '. ', v_comentario,
                       IF(v_gestion = 'reiniciar', ' SLA reiniciado.', ' SLA se mantiene.')), 2000),
           p_id_usuario, NOW(),
           JSON_OBJECT('id_reasignacion', v_id_reas, 'modo', v_modo, 'etapa', x.etapa, 'entidades', k.cantidad,
                       'id_anterior', v_anterior, 'id_nuevo', p_id_nuevo, 'id_motivo', p_id_motivo, 'gestion_sla', v_gestion)
    FROM (SELECT id_expediente, COUNT(*) AS cantidad, GROUP_CONCAT(codigo ORDER BY entidad_tipo, id_entidad SEPARATOR ', ') AS codigos
          FROM tmp_reas_sel GROUP BY id_expediente) k
    LEFT JOIN tmp_exp x ON x.id_expediente = k.id_expediente
    LEFT JOIN usuario ua ON ua.id_usuario = v_anterior;

    -- 7. Notificaciones en la intranet
    SELECT GROUP_CONCAT(CONCAT(e.numero, ': ', s.codigo) ORDER BY e.id_expediente, s.entidad_tipo SEPARATOR ', ')
      INTO v_lista
    FROM tmp_reas_sel s JOIN expediente_digital e ON e.id_expediente = s.id_expediente;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_nuevo, 5,
            LEFT(CONCAT('Te reasignaron ', v_total, IF(v_total = 1, ' entidad', ' entidades'),
                        IF(v_expedientes > 1, CONCAT(' en ', v_expedientes, ' expedientes'), '')), 150),
            LEFT(CONCAT(v_ejecutor, ' te asignó como responsable (', v_alcance, '): ', v_lista, '. Motivo: ', v_motivo, '.'), 2000),
            'expediente', p_id_expediente, NOW(), p_id_usuario);

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT a.id_anterior, 5, 'Cambio de responsable',
           LEFT(CONCAT(v_ejecutor, ' reasignó a ', v_nuevo, ': ', a.codigos, '. Motivo: ', v_motivo, '.'), 2000),
           'expediente', p_id_expediente, NOW(), p_id_usuario
    FROM (SELECT id_anterior, GROUP_CONCAT(codigo ORDER BY entidad_tipo, id_entidad SEPARATOR ', ') AS codigos
          FROM tmp_reas_sel WHERE id_anterior IS NOT NULL GROUP BY id_anterior) a
    JOIN usuario u ON u.id_usuario = a.id_anterior AND u.estado = 'activo' AND u.eliminado_en IS NULL
    WHERE a.id_anterior <> p_id_usuario;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Reasignación confirmada: ', v_total, IF(v_total = 1, ' entidad', ' entidades'),
                  IF(v_expedientes > 1, CONCAT(' en ', v_expedientes, ' expedientes'), ''), ' ahora a cargo de ', v_nuevo, '.') AS Mensaje;

    -- 2. Resumen
    SELECT v_id_reas AS id_reasignacion, v_modo AS modo, v_alcance AS alcance, v_total AS total_entidades,
           v_expedientes AS total_expedientes, p_id_expediente AS id_expediente,
           (SELECT numero FROM expediente_digital WHERE id_expediente = p_id_expediente) AS numero_expediente,
           p_id_nuevo AS id_responsable, v_nuevo AS responsable, v_correo AS correo_responsable,
           v_motivo AS motivo, v_comentario AS comentario, v_gestion AS gestion_sla, v_ejecutor AS reasignado_por;

    -- 3. Entidades reasignadas
    SELECT s.id_expediente, e.numero AS numero_expediente, c.razon_social AS cliente, s.entidad_tipo, s.id_entidad, s.codigo,
           s.id_anterior, CONCAT(ua.nombre, ' ', ua.apellido) AS responsable_anterior
    FROM tmp_reas_sel s
    JOIN expediente_digital e ON e.id_expediente = s.id_expediente
    LEFT JOIN cliente c ON c.id_cliente = e.id_cliente
    LEFT JOIN usuario ua ON ua.id_usuario = s.id_anterior
    ORDER BY e.id_expediente, FIELD(s.entidad_tipo, 'requerimiento', 'propuesta', 'orden_compra', 'orden_servicio'), s.id_entidad;

    -- 4. Responsables anteriores (correo informativo)
    SELECT u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.correo, a.cantidad, a.codigos
    FROM (SELECT id_anterior, COUNT(*) AS cantidad, GROUP_CONCAT(codigo ORDER BY entidad_tipo, id_entidad SEPARATOR ', ') AS codigos
          FROM tmp_reas_sel WHERE id_anterior IS NOT NULL GROUP BY id_anterior) a
    JOIN usuario u ON u.id_usuario = a.id_anterior AND u.estado = 'activo' AND u.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_reas_sel;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
