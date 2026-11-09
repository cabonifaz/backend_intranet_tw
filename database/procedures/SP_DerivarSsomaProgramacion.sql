-- HU-36 (Sprint 5) "Derivar al área SSOMA" desde el bloque de validación SSOMA de la ficha "Programar Servicio".
-- Avisa (notificación en la plataforma) a los usuarios activos del área SSOMA qué técnicos no cumplen los requisitos del
-- cliente / zona de la orden y qué les falta, para que lo regularicen. No cambia la orden ni la programación.
-- Acceso: prog_gestionar (módulo operaciones).
--   p_fecha: fecha del servicio con la que se evalúan los vencimientos (vacío = fecha de la orden o hoy).
--   p_ids_tecnicos: JSON [ids] de 1 a 10 técnicos evaluados en la ficha.
--   p_comentario: nota opcional para SSOMA (hasta 500 caracteres).
-- Reglas (cada falla devuelve tipo 1 y no guarda nada):
--   · la orden existe y está emitida, programada o reprogramada
--   · los técnicos existen, están activos y son de servicio técnico o metrología
--   · al menos un técnico tiene algo pendiente (bloqueado, por vencer, sin documento o sin verificar)
--   · hay al menos un usuario activo del área SSOMA
--   · la misma persona no derivó la misma orden en los últimos 10 minutos (evita avisos repetidos; se vuelve a revisar con
--     la orden bloqueada, así dos clics simultáneos no envían dos avisos)
-- La evaluación es la de SP_EvaluarSsomaProgramacion (la misma que el buscador y la creación).
-- Resultados: 1 mensaje, 2 resumen (notificados, técnicos con pendientes), 3 pendientes derivados (técnico y requisito).
DROP PROCEDURE IF EXISTS SP_DerivarSsomaProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_DerivarSsomaProgramacion(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_fecha        DATE,
    IN p_ids_tecnicos JSON,
    IN p_comentario   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha       DATE;
    DECLARE v_n           INT DEFAULT 0;
    DECLARE v_con_pend    INT DEFAULT 0;
    DECLARE v_notificados INT DEFAULT 0;
    DECLARE v_detalle     TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_remitente   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloqueada   BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_pend;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para programar servicios.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.numero, os.estado, os.tipo, c.razon_social, IFNULL(p_fecha, IFNULL(os.fecha_ejecucion, CURDATE()))
    INTO   v_numero, v_estado, v_tipo, v_cliente, v_fecha
    FROM   orden_servicio os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de servicio no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('emitida', 'programada', 'reprogramada') THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('La orden ', v_numero, ' está ', v_estado, ': solo se deriva una orden por programar o programada.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_ids_tecnicos IS NULL OR JSON_TYPE(p_ids_tecnicos) <> 'ARRAY' THEN
        SELECT 1 AS IdTipoMensaje, 'Indica los técnicos a revisar como una lista de identificadores.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM auditoria_evento a
               WHERE a.entidad_tipo = 'orden_servicio' AND a.id_entidad = p_id_os AND a.accion = 'derivar_ssoma'
                 AND a.id_usuario = p_id_usuario AND a.registrado_en >= NOW() - INTERVAL 10 MINUTE) THEN
        SELECT 1 AS IdTipoMensaje, 'Ya derivaste esta orden a SSOMA hace menos de 10 minutos. Espera su respuesta antes de volver a enviarla.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_obs = NULLIF(TRIM(IFNULL(p_comentario, '')), '');

    DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_drv_pend;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_drv_tec (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT IGNORE INTO tmp_drv_tec (id_usuario)
    SELECT jt.id FROM JSON_TABLE(p_ids_tecnicos, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
    WHERE jt.id IS NOT NULL AND jt.id > 0;

    SELECT COUNT(*) INTO v_n FROM tmp_drv_tec;
    IF v_n = 0 OR v_n > 10 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
        SELECT 1 AS IdTipoMensaje, 'Indica de 1 a 10 técnicos a revisar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_n
    FROM tmp_drv_tec t
    WHERE NOT EXISTS (SELECT 1 FROM usuario u
                      WHERE u.id_usuario = t.id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
                        AND u.area IN ('servicio_tecnico', 'metrologia')
                        AND (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%')));
    IF v_n > 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
        SELECT 1 AS IdTipoMensaje, 'Uno o más técnicos no están activos o no pertenecen a Servicio Técnico o Metrología.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Evaluación SSOMA (la misma del buscador y de la creación)
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_drv_tec;
    CALL SP_EvaluarSsomaProgramacion(p_id_os, v_fecha);

    -- Pendientes a derivar: requisitos que no están conformes + bloqueos por otra orden
    CREATE TEMPORARY TABLE tmp_drv_pend AS
    SELECT d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico, d.requisito, d.situacion,
           d.fecha_vencimiento, d.requerido
    FROM tmp_ssoma_det d
    JOIN usuario u ON u.id_usuario = d.id_usuario
    WHERE d.situacion IN ('bloqueado', 'por_vencer', 'sin_documento', 'sin_verificar')
      AND (d.requerido = 1 OR d.situacion IN ('bloqueado', 'por_vencer'));

    INSERT INTO tmp_drv_pend (id_usuario, tecnico, requisito, situacion, fecha_vencimiento, requerido)
    SELECT r.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), 'Bloqueo SSOMA en otra orden activa', 'bloqueado', NULL, 0
    FROM tmp_ssoma_res r
    JOIN usuario u ON u.id_usuario = r.id_usuario
    WHERE r.bloqueado_en_otra_os = 1;

    SELECT COUNT(DISTINCT id_usuario) INTO v_con_pend FROM tmp_drv_pend;
    IF v_con_pend = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_pend;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Los técnicos indicados no tienen pendientes SSOMA para esta orden: no hace falta derivar.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM usuario s
                   WHERE s.area = 'ssoma' AND s.estado = 'activo' AND s.eliminado_en IS NULL AND s.id_usuario <> p_id_usuario) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_pend;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'No hay usuarios activos en el área SSOMA para recibir la derivación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT LEFT(GROUP_CONCAT(CONCAT(tecnico, ': ', requisito, ' (',
                                    CASE situacion WHEN 'bloqueado' THEN 'no conforme'
                                                   WHEN 'por_vencer' THEN CONCAT('vence ', DATE_FORMAT(fecha_vencimiento, '%d/%m/%Y'))
                                                   WHEN 'sin_documento' THEN 'sin documento'
                                                   ELSE 'sin verificar' END, ')')
                             ORDER BY tecnico, requisito SEPARATOR '; '), 1500)
    INTO v_detalle
    FROM tmp_drv_pend;

    SET v_remitente = (SELECT TRIM(CONCAT(nombre, ' ', apellido)) FROM usuario WHERE id_usuario = p_id_usuario);

    START TRANSACTION;

    -- Concurrencia: primero se bloquea la orden y recién después se vuelve a revisar el aviso repetido, así dos clics
    -- simultáneos no envían dos derivaciones (la foto de datos de la transacción se toma después del bloqueo).
    SELECT id_os INTO v_bloqueada FROM orden_servicio WHERE id_os = p_id_os FOR UPDATE;

    IF EXISTS (SELECT 1 FROM auditoria_evento a
               WHERE a.entidad_tipo = 'orden_servicio' AND a.id_entidad = p_id_os AND a.accion = 'derivar_ssoma'
                 AND a.id_usuario = p_id_usuario AND a.registrado_en >= NOW() - INTERVAL 10 MINUTE) THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_drv_pend;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Ya derivaste esta orden a SSOMA hace menos de 10 minutos. Espera su respuesta antes de volver a enviarla.' AS Mensaje;
        LEAVE proc;
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT s.id_usuario, 5,
           LEFT(CONCAT('Revisión SSOMA para programar ', v_numero), 150),
           CONCAT(IFNULL(v_remitente, 'Operaciones'), ' necesita habilitar técnicos para la ', v_tipo, ' ', v_numero,
                  IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)), ' (servicio del ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), '). ',
                  'Pendientes: ', v_detalle, '.',
                  IF(v_obs IS NULL, '', CONCAT(' Nota: ', v_obs))),
           'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM usuario s
    WHERE s.area = 'ssoma' AND s.estado = 'activo' AND s.eliminado_en IS NULL AND s.id_usuario <> p_id_usuario;
    SET v_notificados = ROW_COUNT();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'derivar_ssoma', v_estado, v_estado,
            CONCAT(v_tipo, ' ', v_numero, ' derivada a SSOMA: ', v_detalle),
            p_id_usuario, NOW(),
            JSON_OBJECT('notificados', v_notificados, 'tecnicos', v_con_pend, 'fecha', DATE_FORMAT(v_fecha, '%Y-%m-%d')));

    COMMIT;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje,
           CONCAT('Se derivó a SSOMA (', v_notificados, IF(v_notificados = 1, ' persona', ' personas'), ') la revisión de ',
                  v_con_pend, IF(v_con_pend = 1, ' técnico.', ' técnicos.')) AS Mensaje;

    -- 2. Resumen
    SELECT v_notificados AS notificados, v_con_pend AS tecnicos_con_pendientes;

    -- 3. Pendientes derivados
    SELECT id_usuario, tecnico, requisito, situacion, fecha_vencimiento
    FROM tmp_drv_pend
    ORDER BY tecnico, requisito;

    DROP TEMPORARY TABLE IF EXISTS tmp_drv_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_drv_pend;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;
