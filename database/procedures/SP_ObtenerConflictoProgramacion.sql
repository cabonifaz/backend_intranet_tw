-- HU-39 (Sprint 5) Modal "Resolver Conflicto de Programación": servicio actual vs servicio en conflicto, solapamiento, impacto
-- operativo, opciones de resolución y recursos sugeridos para reasignar. Acceso: prog_bandeja. Solo lectura.
--   p_tipo: baja | ssoma_vencido | solapamiento | extension_duracion (el de la alerta)
--   p_id_tecnico: el técnico del conflicto · p_id_os_a: la orden desde la que se abre ("servicio actual")
--   p_id_os_b: la otra orden del cruce (obligatoria en solapamiento y extension_duracion; se ignora en baja y ssoma_vencido)
-- El conflicto se vuelve a detectar al abrir el modal: si ya se resolvió o cambió, devuelve un mensaje (no hay datos viejos).
-- Opciones (selección única): reasignar (mantiene confirmado, no cambia el cronograma), reprogramar cada servicio (vuelve a
--   Pendiente confirmación cliente; ejecuta la HU-38 según el rol) y cancelar la programación (HU-38, siempre disponible).
-- Recursos sugeridos: técnicos de la plantilla libres en la franja de cada servicio y con SSOMA conforme para esa orden;
--   score = 100 - utilización de la semana del servicio (a menos carga, mayor puntaje).
-- Resultados: 1 mensaje, 2 conflicto, 3 servicios, 4 opciones, 5 recursos sugeridos.
DROP PROCEDURE IF EXISTS SP_ObtenerConflictoProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConflictoProgramacion(
    IN p_id_usuario  BIGINT,
    IN p_tipo        VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico  BIGINT,
    IN p_id_os_a     BIGINT,
    IN p_id_os_b     BIGINT
)
proc: BEGIN
    DECLARE v_gestiona  TINYINT DEFAULT 0;
    DECLARE v_aprueba   TINYINT DEFAULT 0;
    DECLARE v_tipo      VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave     VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_otro      BIGINT DEFAULT NULL;
    DECLARE v_n_serv    INT DEFAULT 0;
    DECLARE v_i         INT DEFAULT 1;
    DECLARE v_n_resolubles INT DEFAULT 0;
    DECLARE v_os        BIGINT;
    DECLARE v_fecha     DATE;
    DECLARE v_ini       TIME;
    DECLARE v_fin       TIME;
    DECLARE v_semana_i  DATE;
    DECLARE v_param     DECIMAL(18,6);
    DECLARE v_jornada   DECIMAL(5,1) DEFAULT 8;
    DECLARE v_capacidad DECIMAL(5,1) DEFAULT 48;
    DECLARE v_minutos   INT DEFAULT 0;
    DECLARE v_impacto   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los conflictos de la programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('baja', 'ssoma_vencido', 'solapamiento', 'extension_duracion') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de conflicto no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_tipo IN ('solapamiento', 'extension_duracion') THEN
        IF IFNULL(p_id_os_b, 0) <= 0 OR p_id_os_b = p_id_os_a THEN
            SELECT 1 AS IdTipoMensaje, 'Indica las dos órdenes que se cruzan.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_otro  = p_id_os_b;
        SET v_clave = CONCAT(v_tipo, ':', p_id_tecnico, ':', LEAST(p_id_os_a, p_id_os_b), ':', GREATEST(p_id_os_a, p_id_os_b));
    ELSE
        SET v_clave = CONCAT(v_tipo, ':', p_id_tecnico);
    END IF;

    SET v_gestiona = FN_PermisoAccion(p_id_usuario, 'prog_gestionar');
    SET v_aprueba  = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');

    CALL SP_ArmarConflictosProgramacion();

    IF NOT EXISTS (SELECT 1 FROM tmp_cf WHERE clave = v_clave) THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'El conflicto ya no existe o cambió: actualiza la lista de alertas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tmp_cf_serv WHERE clave = v_clave AND id_os = p_id_os_a) THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'La orden indicada no forma parte de este conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Servicios del modal: actual (la orden desde la que se abrió) y, si es un cruce, el servicio en conflicto
    CREATE TEMPORARY TABLE tmp_cf_sv (
        idx INT NOT NULL, etiqueta VARCHAR(12) NOT NULL, id_os BIGINT NOT NULL, id_programacion BIGINT NULL, numero VARCHAR(20) NULL,
        tipo_os VARCHAR(5) NULL, razon_social VARCHAR(250) NULL, tipo_servicio VARCHAR(200) NULL, estado_prog VARCHAR(25) NULL,
        fecha DATE NULL, hora_inicio TIME NULL, hora_fin TIME NULL, horas DECIMAL(8,2) NULL, PRIMARY KEY (idx)
    );
    INSERT INTO tmp_cf_sv (idx, etiqueta, id_os, id_programacion, numero, tipo_os, razon_social, tipo_servicio, estado_prog, fecha, hora_inicio, hora_fin, horas)
    SELECT IF(a.id_os = p_id_os_a, 1, 2), IF(a.id_os = p_id_os_a, 'actual', 'conflicto'), a.id_os, a.id_programacion, a.numero, a.tipo_os,
           a.razon_social, a.tipo_servicio, a.estado_prog, a.fecha, a.hora_inicio, a.hora_fin, a.horas
    FROM tmp_cf_asig a
    WHERE a.id_usuario = p_id_tecnico
      AND (a.id_os = p_id_os_a OR (v_otro IS NOT NULL AND a.id_os = v_otro));
    SELECT COUNT(*), IFNULL(SUM(id_programacion IS NOT NULL), 0) INTO v_n_serv, v_n_resolubles FROM tmp_cf_sv;
    IF v_otro IS NOT NULL AND v_n_serv < 2 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cf_sv;
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'El conflicto ya no existe o cambió: actualiza la lista de alertas.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Impacto operativo
    SELECT IFNULL(TIME_TO_SEC(TIMEDIFF(solape_fin, solape_ini)) DIV 60, 0) INTO v_minutos FROM tmp_cf WHERE clave = v_clave;
    SET v_impacto = CASE v_tipo
        WHEN 'baja' THEN 'El técnico no está disponible: sus servicios no podrán ejecutarse hasta reasignarlos o reprogramarlos.'
        WHEN 'ssoma_vencido' THEN 'Sin habilitación SSOMA vigente el técnico no puede ejecutar el servicio: la ejecución queda bloqueada hasta reasignar o reprogramar.'
        ELSE CONCAT('El técnico no puede atender ambos frentes simultáneamente. Se proyecta un retraso en cadena de +',
                    v_minutos DIV 60, 'h ', LPAD(v_minutos MOD 60, 2, '0'), 'min si no se desvincula de inmediato.')
    END;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Conflicto
    SELECT c.clave, c.tipo, c.severidad, c.titulo, c.detalle, c.id_usuario AS id_tecnico, c.tecnico,
           COALESCE(cg.String1, u.cargo) AS cargo, so.String1 AS sede_operativa, c.fecha,
           TIME_FORMAT(c.solape_ini, '%H:%i') AS solape_inicio, TIME_FORMAT(c.solape_fin, '%H:%i') AS solape_fin,
           IF(c.solape_ini IS NULL, NULL, TIME_TO_SEC(TIMEDIFF(c.solape_fin, c.solape_ini)) DIV 60) AS solape_minutos,
           v_impacto AS impacto_operativo, c.id_motivo AS id_motivo_sugerido, c.motivo_sugerido,
           IF(v_aprueba = 1, 'directa', IF(v_gestiona = 1, 'solicitud', 'solo_lectura')) AS modo,
           v_gestiona AS puede_resolver
    FROM tmp_cf c
    JOIN usuario u ON u.id_usuario = c.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tabla_maestra so ON so.IdMaestro = 69 AND so.IdEmpresa = 1 AND so.String2 = u.sede_operativa
    WHERE c.clave = v_clave;

    -- 3. Servicios
    SELECT idx AS orden, etiqueta, id_os, id_programacion, numero AS numero_os, tipo_os AS tipo, razon_social, tipo_servicio,
           estado_prog AS estado_programacion,
           IF(estado_prog = 'confirmada', 'Confirmado', IF(estado_prog = 'pendiente_confirmacion', 'Pendiente confirmación cliente', NULL)) AS estado_label,
           fecha, TIME_FORMAT(hora_inicio, '%H:%i') AS hora_inicio, TIME_FORMAT(hora_fin, '%H:%i') AS hora_fin, horas,
           IF(id_programacion IS NULL, 0, 1) AS resoluble
    FROM tmp_cf_sv ORDER BY idx;

    -- 4. Opciones de resolución (varias sentencias: MySQL no reabre una temporal en la misma consulta)
    CREATE TEMPORARY TABLE tmp_cf_op (
        ord INT NOT NULL, codigo VARCHAR(12) NOT NULL, titulo VARCHAR(300) NULL, descripcion VARCHAR(400) NULL,
        afecta_id_os BIGINT NULL, afecta_id_programacion BIGINT NULL, mantiene_confirmado TINYINT NOT NULL DEFAULT 0,
        vuelve_pendiente_cliente TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (ord)
    );
    INSERT INTO tmp_cf_op (ord, codigo, titulo, descripcion, mantiene_confirmado)
    VALUES (1, 'reasignar',
            IF(v_n_serv > 1, CONCAT('Reasignar técnico a uno de los ', v_n_serv, ' servicios'), 'Reasignar técnico del servicio'),
            'Buscar otro especialista habilitado con homologación SSOMA al día. No modifica el cronograma: el cliente final no percibe alteración.', 1);
    INSERT INTO tmp_cf_op (ord, codigo, titulo, descripcion, afecta_id_os, afecta_id_programacion, vuelve_pendiente_cliente)
    SELECT 2 + idx, 'reprogramar', CONCAT('Reprogramar ', numero, ' (', IFNULL(razon_social, ''), ') a otra ventana'),
           IF(etiqueta = 'actual', 'Mover fecha u hora de esta orden. La cita vuelve al estado de Pendiente Confirmación Cliente.',
                                   'Ajustar franja horaria del servicio coincidente. Retorna a Pendiente Confirmación Cliente.'),
           id_os, id_programacion, 1
    FROM tmp_cf_sv;
    INSERT INTO tmp_cf_op (ord, codigo, titulo, descripcion, afecta_id_os, afecta_id_programacion)
    SELECT 10 + idx, 'cancelar', CONCAT('Cancelar la programación de ', numero),
           'Cancelación directa con motivo tipificado, sin aprobación. La orden sigue emitida y vuelve a Pendientes.',
           id_os, id_programacion
    FROM tmp_cf_sv;

    SELECT x.codigo, x.titulo, x.descripcion, x.afecta_id_os, x.afecta_id_programacion, x.mantiene_confirmado,
           x.vuelve_pendiente_cliente,
           IF(v_gestiona = 1 AND IF(x.codigo = 'reasignar', v_n_resolubles > 0, x.afecta_id_programacion IS NOT NULL), 1, 0) AS disponible,
           CASE WHEN v_gestiona = 0 THEN 'Tu rol no puede gestionar programaciones.'
                WHEN x.codigo = 'reasignar' AND v_n_resolubles = 0 THEN 'Ninguna de las órdenes tiene una programación vigente (se programaron fuera del módulo).'
                WHEN x.codigo <> 'reasignar' AND x.afecta_id_programacion IS NULL THEN 'La orden no tiene una programación vigente (se programó fuera del módulo).'
                ELSE NULL END AS motivo_no_disponible
    FROM tmp_cf_op x
    ORDER BY x.ord;

    -- 5. Recursos sugeridos para la reasignación inmediata (por servicio)
    CALL SP_LeerParametroProgramacion('HORAS_JORNADA', 8, v_param);
    SET v_jornada   = IF(v_param BETWEEN 1 AND 24, v_param, 8);
    CALL SP_LeerParametroProgramacion('DIAS_LABORABLES_SEMANA', 6, v_param);
    SET v_capacidad = v_jornada * IF(v_param BETWEEN 1 AND 7, ROUND(v_param), 6);

    CREATE TEMPORARY TABLE tmp_cf_cand (
        para_id_os BIGINT NOT NULL, para_numero VARCHAR(20) NULL, id_usuario BIGINT NOT NULL, nombre VARCHAR(250) NULL, cargo VARCHAR(150) NULL,
        tipo_recurso VARCHAR(10) NULL, sede_operativa VARCHAR(100) NULL, ssoma_estado VARCHAR(20) NULL,
        horas_semana DECIMAL(8,2) NULL, utilizacion_pct INT NULL, score INT NULL, PRIMARY KEY (para_id_os, id_usuario)
    );

    WHILE v_i <= v_n_serv DO
        SELECT id_os, fecha, IFNULL(hora_inicio, '00:00:00'), IFNULL(hora_fin, '23:59:59')
          INTO v_os, v_fecha, v_ini, v_fin
        FROM tmp_cf_sv WHERE idx = v_i;
        SET v_semana_i = DATE_SUB(v_fecha, INTERVAL WEEKDAY(v_fecha) DAY);

        DROP TEMPORARY TABLE IF EXISTS tmp_cf_pre;
        CREATE TEMPORARY TABLE tmp_cf_pre (id_usuario BIGINT NOT NULL, horas_semana DECIMAL(8,2) NOT NULL DEFAULT 0, PRIMARY KEY (id_usuario));
        INSERT INTO tmp_cf_pre (id_usuario)
        SELECT u.id_usuario
        FROM usuario u
        WHERE u.eliminado_en IS NULL AND u.estado = 'activo'
          AND u.area IN ('servicio_tecnico', 'metrologia')
          AND (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
          AND u.id_usuario <> p_id_tecnico
          AND NOT EXISTS (SELECT 1 FROM tmp_cf_asig x
                          WHERE x.id_usuario = u.id_usuario AND x.fecha = v_fecha
                            AND x.hora_inicio IS NOT NULL AND x.hora_fin IS NOT NULL
                            AND x.hora_inicio < v_fin AND v_ini < x.hora_fin);

        UPDATE tmp_cf_pre pr
        SET pr.horas_semana = IFNULL((SELECT SUM(w.horas) FROM tmp_cf_asig w
                                      WHERE w.id_usuario = pr.id_usuario
                                        AND w.fecha BETWEEN v_semana_i AND DATE_ADD(v_semana_i, INTERVAL 6 DAY)), 0);

        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_cf_pre;
        CALL SP_EvaluarSsomaProgramacion(v_os, v_fecha);

        INSERT INTO tmp_cf_cand (para_id_os, para_numero, id_usuario, nombre, cargo, tipo_recurso, sede_operativa, ssoma_estado,
                                 horas_semana, utilizacion_pct, score)
        SELECT v_os, (SELECT numero FROM tmp_cf_sv WHERE idx = v_i), u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)),
               COALESCE(cg.String1, u.cargo),
               IF(u.area = 'metrologia' OR IFNULL(u.cargo, '') LIKE 'metrologo%', 'metrologo', 'tecnico'),
               so.String1, r.estado,
               pr.horas_semana,
               LEAST(100, ROUND(pr.horas_semana / v_capacidad * 100)),
               GREATEST(0, 100 - LEAST(100, ROUND(pr.horas_semana / v_capacidad * 100)))
        FROM tmp_ssoma_res r
        JOIN tmp_cf_pre pr ON pr.id_usuario = r.id_usuario
        JOIN usuario u ON u.id_usuario = r.id_usuario
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
        LEFT JOIN tabla_maestra so ON so.IdMaestro = 69 AND so.IdEmpresa = 1 AND so.String2 = u.sede_operativa
        WHERE r.estado NOT IN ('bloqueado', 'pendiente')
        ORDER BY pr.horas_semana, u.nombre, u.id_usuario
        LIMIT 5;

        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SET v_i = v_i + 1;
    END WHILE;

    SELECT para_id_os, para_numero, id_usuario AS id_tecnico, nombre, cargo, tipo_recurso, sede_operativa, ssoma_estado,
           horas_semana, utilizacion_pct, score
    FROM tmp_cf_cand
    ORDER BY para_id_os, score DESC, nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_cf_pre;
    CALL SP_LimpiarConflictosProgramacion();
END$$

DELIMITER ;
