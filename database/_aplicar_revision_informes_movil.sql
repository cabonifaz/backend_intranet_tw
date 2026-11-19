-- HU-33 · Revisión de informes técnicos desde la app (Jefe de Área): migración 121 + procedimientos. IDEMPOTENTE. Requiere antes _aplicar_aprobaciones_area_rol_movil.sql (SP_ResolverAprobadorMovil) y las migraciones 93, 101 y 113.
-- Ejecutar con Alt+X (Execute script) y responder "No" a las variables.

-- ============================================================
-- Migración 121 — Revisión de informes técnicos desde la app (HU-33, Jefe de Área)
--   Tabla informe_correccion: la solicitud de corrección que el jefe le hace al técnico al OBSERVAR un informe (motivo, secciones afectadas, qué debe corregir y plazo).
--   Un informe tiene como máximo UNA corrección pendiente (lo asegura SP_ObservarInformeMovil con el informe bloqueado). Al observar, el informe pasa a estado 'observado'
--   (ya existe en el ENUM informe_tecnico.estado desde la migración 93) y el técnico recibe una notificación (y el push de la app).
--     motivo ....... evidencia_insuficiente | datos_incorrectos | ensayos_inconsistentes | firma_faltante | otro (catálogo fijo: SP_ArmarCatalogoRevisionInformeMovil)
--     secciones .... códigos separados por coma: registro_fotografico, cabecera, ensayos, firmas
--     plazo_en ..... fecha y hora límite (hora de Lima, igual que notificacion.fecha_creacion y el resto de los SP de la app)
--     estado ....... pendiente | atendida | cancelada (la atiende el técnico; esa pantalla es de otra HU)
--   Soft delete + auditoría. Sin FK ni UNIQUE (la regla de "una pendiente" la valida el SP). No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS informe_correccion (
    id_correccion  BIGINT        NOT NULL AUTO_INCREMENT,
    id_informe     BIGINT        NOT NULL,
    id_jefe        BIGINT        NOT NULL,
    motivo         VARCHAR(30)   NOT NULL,
    secciones      VARCHAR(200)  NOT NULL,
    instruccion    VARCHAR(1000) NOT NULL,
    plazo_en       DATETIME      NOT NULL,
    estado         ENUM('pendiente','atendida','cancelada') NOT NULL DEFAULT 'pendiente',
    atendida_en    DATETIME      NULL,
    -- AUDITORÍA
    creado_en      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT        NULL,
    modificado_en  DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por BIGINT        NULL,
    eliminado_en   DATETIME      NULL,
    eliminado_por  BIGINT        NULL,
    PRIMARY KEY (id_correccion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_correccion' AND INDEX_NAME = 'ix_informe_correccion_informe'),
    'ALTER TABLE informe_correccion ADD KEY ix_informe_correccion_informe (id_informe, estado, eliminado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 121 (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_correccion') AS valor;

-- Revisión Técnica (Sprint 5, HU-56 a HU-59): cálculo compartido de los informes de servicio técnico.
-- Llena tmp_rt_base (una fila por informe; el que llama hace DROP TEMPORARY TABLE tmp_rt_base al terminar).
--   p_id_informe NULL = todos (bandeja). Solo informes ya enviados por el técnico (no borradores).
--   Alcance: gerencia / TI ven todo; el resto, los informes de los técnicos de su área ("informes de mis técnicos").
--   App móvil (HU-33): SP_FijarAlcanceInformesMovil fija @tw_inf_usuario / @tw_inf_ver_todo / @tw_inf_area con la regla ÁREA + ROL de la app (Gerencia, Operaciones, Administración,
--   TI, SSOMA, Calidad y Comercial con cualquier rol, y Administradores, ven todo; el Supervisor de Servicio Técnico / Metrología, solo su área). Esas variables SOLO se respetan si
--   @tw_inf_usuario es el usuario que consulta: la intranet no las fija y conserva su regla de siempre.
-- grupo_estado (bandeja y tarjetas):
--   pendiente_revision       enviado o en revisión, sin observaciones o con la precotización ya registrada
--   pendiente_precotizacion  enviado o en revisión, con observaciones y sin precotización (no se puede marcar revisado)
--   revisado_sin_precot      revisado sin precotización
--   revisado_con_precot      revisado con precotización (generó oportunidad comercial)
-- SLA: horas desde que llegó a la bandeja (fecha_envio_revision) contra RT_SLA_REVISION_HORAS (48 h por defecto).
DROP PROCEDURE IF EXISTS SP_ArmarBaseInformes;

DELIMITER $$

CREATE PROCEDURE SP_ArmarBaseInformes(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
BEGIN
    DECLARE v_area     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ver_todo TINYINT DEFAULT 0;
    DECLARE v_sla      INT DEFAULT 48;

    SELECT area INTO v_area FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo' LIMIT 1;
    SET v_ver_todo = IF(IFNULL(v_area, '') IN ('gerencia', 'ti'), 1, 0);
    -- Alcance de la app móvil (regla ÁREA + ROL); sin área y sin "ver todo" no hay filas
    IF @tw_inf_usuario IS NOT NULL AND @tw_inf_usuario = p_id_usuario THEN
        SET v_ver_todo = IF(IFNULL(@tw_inf_ver_todo, 0) = 1, 1, 0);
        SET v_area     = @tw_inf_area;
    END IF;

    SELECT CAST(IFNULL(MAX(Num2), 48) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'RT_SLA_REVISION_HORAS';

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    CREATE TEMPORARY TABLE tmp_rt_base (PRIMARY KEY (id_informe)) AS
    SELECT it.id_informe,
           it.numero                                                   AS numero_informe,
           it.version,
           it.estado,
           it.url_pdf,
           it.diagnostico_principal                                    AS diagnostico,
           it.id_os,
           os.numero                                                   AS numero_os,
           os.tipo                                                     AS tipo_os,
           it.id_equipo,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), NULLIF(TRIM(CONCAT_WS(' ', ec.marca, ec.modelo)), ''), ec.codigo_tw) AS equipo,
           ec.codigo_tw                                                AS codigo_tw,
           ec.num_serie                                                AS numero_serie,
           ec.marca, ec.modelo,
           COALESCE(cl.String1, ec.clasificacion)                      AS tipo_equipo,
           os.id_cliente,
           c.razon_social,
           c.ruc,
           os.id_sede,
           sc.nombre                                                   AS sede,
           os.id_tipo_servicio,
           ts.String1                                                  AS tipo_servicio,
           it.id_tecnico,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido))                   AS tecnico,
           ut.area                                                     AS area_tecnico,
           COALESCE(os.fecha_ejecucion, DATE(it.fecha_creacion))       AS fecha_ejecucion,
           TIME_FORMAT(COALESCE(os.hora_llegada_real, os.hora_inicio), '%H:%i')  AS hora_inicio,
           TIME_FORMAT(COALESCE(os.hora_fin_real, os.hora_fin_estimada), '%H:%i') AS hora_fin,
           IF(COALESCE(os.hora_llegada_real, os.hora_inicio) IS NULL OR COALESCE(os.hora_fin_real, os.hora_fin_estimada) IS NULL, NULL,
              GREATEST(TIMESTAMPDIFF(MINUTE, COALESCE(os.hora_llegada_real, os.hora_inicio),
                                             COALESCE(os.hora_fin_real, os.hora_fin_estimada)), 0)) AS duracion_min,
           COALESCE(os.id_propuesta, e.id_propuesta)                   AS id_propuesta,
           pr.numero                                                   AS numero_propuesta,
           pr.version                                                  AS version_propuesta,
           rq.id_requerimiento,
           rq.numero                                                   AS numero_rq,
           rq.id_responsable                                           AS id_responsable_rq,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), co.nombres) AS contacto,
           it.fecha_envio_revision,
           it.fecha_inicio_revision,
           it.fecha_revision,
           it.nota_revision,
           it.id_revisor,
           TRIM(CONCAT(ur.nombre, ' ', ur.apellido))                   AS revisor,
           v_sla                                                       AS sla_horas,
           TIMESTAMPDIFF(HOUR, COALESCE(it.fecha_envio_revision, it.fecha_creacion),
                         IF(it.estado IN ('revisado', 'aprobado'), IFNULL(it.fecha_revision, NOW()), NOW())) AS horas_espera,
           (SELECT COUNT(*) FROM informe_observacion o WHERE o.id_informe = it.id_informe AND o.eliminado_en IS NULL)    AS n_observaciones,
           (SELECT COUNT(*) FROM informe_recomendacion r WHERE r.id_informe = it.id_informe AND r.eliminado_en IS NULL)  AS n_recomendaciones,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_fotos,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1 AND f.validacion_ia <> 'rechazada'
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_fotos_validas,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1 AND f.override_aprobado = 1
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_forzadas,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1 AND f.override_aprobado = 1
              AND f.revision_jefe IS NULL
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_forzadas_sin_revision,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL)      AS n_ensayos,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL
              AND en.resultado IS NULL)                                                                                  AS n_ensayos_sin_resultado,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL
              AND en.resultado = 'no_conforme')                                                                          AS n_ensayos_no_conformes,
           (SELECT COUNT(*) FROM informe_procedimiento ip WHERE ip.id_informe = it.id_informe AND ip.eliminado_en IS NULL) AS n_pasos,
           (SELECT COUNT(*) FROM informe_procedimiento ip WHERE ip.id_informe = it.id_informe AND ip.eliminado_en IS NULL
              AND ip.realizado = 1)                                                                                       AS n_pasos_realizados,
           pc.id_precotizacion,
           pc.numero                                                   AS numero_precot,
           pc.estado                                                   AS estado_precot,
           pc.fecha_envio                                              AS fecha_precot,
           pc.id_creador                                               AS id_autor_precot,
           TRIM(CONCAT(up.nombre, ' ', up.apellido))                   AS autor_precot,
           (SELECT COUNT(*) FROM precotizacion_item pi WHERE pi.id_precotizacion = pc.id_precotizacion AND pi.eliminado_en IS NULL) AS n_items_precot,
           pd.id_propuesta                                             AS id_propuesta_derivada,
           pd.numero                                                   AS numero_propuesta_derivada,
           pd.version                                                  AS version_propuesta_derivada,
           pd.estado                                                   AS estado_propuesta_derivada
    FROM informe_tecnico it
    LEFT JOIN orden_servicio os      ON os.id_os = it.id_os
    LEFT JOIN expediente_digital e   ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial pr ON pr.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento rq       ON rq.id_requerimiento = COALESCE(os.id_requerimiento, pr.id_requerimiento, e.id_requerimiento)
    LEFT JOIN cliente c              ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc        ON sc.id_sede = os.id_sede
    LEFT JOIN contacto_cliente co    ON co.id_contacto = os.id_contacto
    LEFT JOIN equipo_cliente ec      ON ec.id_equipo = it.id_equipo
    LEFT JOIN suministros su         ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra cl       ON cl.IdMaestro = 71 AND cl.IdEmpresa = 1 AND cl.String2 = ec.clasificacion
    LEFT JOIN tabla_maestra ts       ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario ut             ON ut.id_usuario = it.id_tecnico
    LEFT JOIN usuario ur             ON ur.id_usuario = it.id_revisor
    LEFT JOIN precotizacion pc       ON pc.id_precotizacion = (SELECT MAX(p2.id_precotizacion) FROM precotizacion p2
                                                               WHERE p2.id_informe = it.id_informe AND p2.eliminado_en IS NULL)
    LEFT JOIN usuario up             ON up.id_usuario = pc.id_creador
    LEFT JOIN propuesta_comercial pd ON pd.id_propuesta = pc.id_propuesta_generada
    WHERE it.eliminado_en IS NULL
      AND it.estado <> 'borrador'
      AND (p_id_informe IS NULL OR it.id_informe = p_id_informe)
      -- solo la última versión del informe de cada OS + equipo
      AND NOT EXISTS (SELECT 1 FROM informe_tecnico i2
                      WHERE i2.eliminado_en IS NULL AND i2.id_os <=> it.id_os AND i2.id_equipo <=> it.id_equipo
                        AND i2.estado <> 'borrador' AND i2.id_os IS NOT NULL
                        AND (i2.version > it.version OR (i2.version = it.version AND i2.id_informe > it.id_informe)))
      AND (v_ver_todo = 1 OR (v_area IS NOT NULL AND ut.area = v_area));

    ALTER TABLE tmp_rt_base
        ADD COLUMN grupo_estado VARCHAR(30) NULL,
        ADD COLUMN sla_vencido  TINYINT     NOT NULL DEFAULT 0;

    UPDATE tmp_rt_base SET
        grupo_estado = CASE
            WHEN estado IN ('revisado', 'aprobado') AND id_precotizacion IS NOT NULL THEN 'revisado_con_precot'
            WHEN estado IN ('revisado', 'aprobado')                                  THEN 'revisado_sin_precot'
            WHEN n_observaciones > 0 AND IFNULL(n_items_precot, 0) = 0               THEN 'pendiente_precotizacion'
            ELSE 'pendiente_revision' END,
        sla_vencido = IF(estado NOT IN ('revisado', 'aprobado') AND horas_espera > sla_horas, 1, 0);
END$$

DELIMITER ;

-- ============================================================
-- SP_FijarAlcanceInformesMovil  (App Mobile HU-33 — apoyo, NO es un endpoint)
-- Fija, para SP_ArmarBaseInformes, el alcance de informes de la app según la regla ÁREA + ROL (SP_ResolverAprobadorMovil, la misma de aprobaciones y alertas):
--   · Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y Administradores → informes de TODAS las áreas.
--   · Supervisor de Servicio Técnico / Metrología → solo los informes de los técnicos de su área.
--   · Usuario / Visor de Servicio Técnico / Metrología (o sin área) → p_tiene = 0 (no tiene Jefatura).
-- Lo hace con variables de sesión (@tw_inf_usuario, @tw_inf_ver_todo, @tw_inf_area): SP_ArmarBaseInformes las respeta SOLO si @tw_inf_usuario es el usuario que consulta, así la intranet
-- (que no las fija) sigue con su regla de siempre. Quien llame a este SP debe terminar con: SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_FijarAlcanceInformesMovil;

DELIMITER $$

CREATE PROCEDURE SP_FijarAlcanceInformesMovil(
    IN  p_id_usuario BIGINT,
    OUT p_tiene      TINYINT
)
BEGIN
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_gen  TINYINT DEFAULT 0;

    SET p_tiene = 0;
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area, v_gen);

    SET @tw_inf_usuario  = p_id_usuario;
    SET @tw_inf_ver_todo = IFNULL(v_gen, 0);
    SET @tw_inf_area     = IF(IFNULL(v_gen, 0) = 1, NULL, v_area);
    SET p_tiene          = IF(IFNULL(v_gen, 0) = 1 OR v_area IS NOT NULL, 1, 0);
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarCatalogoRevisionInformeMovil  (App Mobile HU-33 — apoyo, NO es un endpoint)
-- Catálogo FIJO del modal "Observar informe", una sola vez: lo devuelve el detalle del informe (SP_ObtenerInformeRevisionMovil) y lo usa SP_ObservarInformeMovil para validar.
-- Deja la tabla temporal tmp_cat_rev (tipo, codigo, nombre, orden, horas); quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev.
--   tipo 'motivo'  : evidencia_insuficiente · datos_incorrectos · ensayos_inconsistentes · firma_faltante · otro
--   tipo 'seccion' : registro_fotografico · cabecera · ensayos · firmas
--   tipo 'plazo'   : codigo h4 / h24 / h48 / h72, horas = 4 / 24 / 48 / 72
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarCatalogoRevisionInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarCatalogoRevisionInformeMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
    CREATE TEMPORARY TABLE tmp_cat_rev (
        tipo   VARCHAR(10) NOT NULL,
        codigo VARCHAR(30) NOT NULL,
        nombre VARCHAR(60) NOT NULL,
        orden  INT         NOT NULL,
        horas  INT         NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    INSERT INTO tmp_cat_rev (tipo, codigo, nombre, orden, horas) VALUES
        ('motivo',  'evidencia_insuficiente', 'Evidencia insuficiente',     1, NULL),
        ('motivo',  'datos_incorrectos',      'Datos incorrectos',          2, NULL),
        ('motivo',  'ensayos_inconsistentes', 'Ensayos inconsistentes',     3, NULL),
        ('motivo',  'firma_faltante',         'Firma faltante',             4, NULL),
        ('motivo',  'otro',                   'Otro (explicar abajo)',      5, NULL),
        ('seccion', 'registro_fotografico',   'Registro fotográfico',       1, NULL),
        ('seccion', 'cabecera',               'Cabecera',                   2, NULL),
        ('seccion', 'ensayos',                'Ensayos',                    3, NULL),
        ('seccion', 'firmas',                 'Firmas',                     4, NULL),
        ('plazo',   'h4',                     '4 horas',                    1, 4),
        ('plazo',   'h24',                    '24 horas',                   2, 24),
        ('plazo',   'h48',                    '48 horas (2 días)',          3, 48),
        ('plazo',   'h72',                    '72 horas (3 días)',          4, 72);
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerInformesRevisionMovil  (App Mobile HU-33 — "Informes por revisar" del Jefe de Área · solo lectura)
-- La misma bandeja de Revisión Técnica de la intranet (HU-56): SP_ArmarBaseInformes, permiso rt_bandeja, con el alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil).
--   p_grupo (pestaña): por_revisar (vacío = por_revisar) · en_correccion · aprobados.
--     por_revisar   informes enviados por el técnico y aún sin revisar (pendiente_revision y pendiente_precotizacion de la bandeja) que NO están observados.
--     en_correccion informes OBSERVADOS por el jefe (estado observado): esperan la corrección del técnico.
--     aprobados     informes revisados (revisado / aprobado): los 30 más recientes.
--   p_busqueda (hasta 80 caracteres): N° de informe, N° de OS, cliente, técnico, equipo, código TW o N° de serie.
--   KPIs (siempre sobre TODO el alcance, sin pestaña ni búsqueda): pendientes (= por_revisar) · observados (= en_correccion) · sin_evidencias (por_revisar sin fotos) ·
--     sla_vencido (por_revisar con más horas de espera que RT_SLA_REVISION_HORAS, 48 h por defecto).
--   Orden: por_revisar → SLA vencido primero y luego los más antiguos · en_correccion → plazo más próximo · aprobados → los más recientes.
--   firmado_cliente: la OS del informe ya tiene una firma de responsable (dispositivo o formato físico, no "ausente"); el detalle muestra el estado exacto del informe.
--   Fechas: texto ISO sin zona (yyyy-MM-ddTHH:mm:ss, hora de Lima), como el resto de la app.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 informes. Requiere las migraciones 93 y 121.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerInformesRevisionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerInformesRevisionMovil(
    IN p_id_usuario BIGINT,
    IN p_grupo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_grupo    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_patron   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tiene    TINYINT DEFAULT 0;
    DECLARE v_limite   INT DEFAULT 200;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_irm;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_grupo = LOWER(TRIM(IFNULL(p_grupo, '')));
    IF v_grupo = '' THEN SET v_grupo = 'por_revisar'; END IF;
    IF v_grupo NOT IN ('por_revisar', 'en_correccion', 'aprobados') THEN
        SELECT 1 AS IdTipoMensaje, 'El grupo de informes no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_busqueda = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');
    IF v_busqueda IS NOT NULL AND CHAR_LENGTH(v_busqueda) > 80 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda no puede superar los 80 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_busqueda IS NOT NULL THEN
        SET v_patron = CONCAT('%', REPLACE(REPLACE(REPLACE(v_busqueda, '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;
    IF v_grupo = 'aprobados' THEN SET v_limite = 30; END IF;

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_irm;
    CREATE TEMPORARY TABLE tmp_irm AS
    SELECT b.id_informe,
           b.numero_informe,
           b.numero_os,
           b.razon_social                                   AS cliente,
           b.equipo,
           b.codigo_tw,
           b.numero_serie,
           b.tecnico,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN 'aprobados'
                WHEN b.estado = 'observado'               THEN 'en_correccion'
                ELSE 'por_revisar' END                      AS pestana,
           b.n_fotos                                        AS evidencias,
           b.n_forzadas                                     AS forzadas,
           IF(EXISTS (SELECT 1 FROM os_firma_responsable f WHERE f.id_os = b.id_os AND f.modo IN ('dispositivo', 'fisico')), 1, 0) AS firmado_cliente,
           b.horas_espera,
           b.sla_vencido,
           c.plazo_en,
           b.fecha_revision
    FROM   tmp_rt_base b
    LEFT JOIN informe_correccion c ON c.id_informe = b.id_informe AND c.estado = 'pendiente' AND c.eliminado_en IS NULL;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 KPIs (todo el alcance)
    SELECT IFNULL(SUM(pestana = 'por_revisar'), 0)                                     AS pendientes,
           IFNULL(SUM(pestana = 'en_correccion'), 0)                                   AS observados,
           IFNULL(SUM(pestana = 'por_revisar' AND evidencias = 0), 0)                  AS sin_evidencias,
           IFNULL(SUM(pestana = 'por_revisar' AND sla_vencido = 1), 0)                 AS sla_vencido,
           DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%H:%i')                     AS actualizado,
           30                                                                          AS refresco_segundos
    FROM   tmp_irm;

    -- 3 Informes de la pestaña
    SELECT i.id_informe, i.numero_informe, i.numero_os, i.cliente, i.equipo, i.codigo_tw, i.tecnico,
           CASE i.pestana WHEN 'aprobados' THEN 'aprobado' ELSE i.pestana END            AS estado,
           i.evidencias, i.forzadas, i.firmado_cliente, i.horas_espera, i.sla_vencido,
           DATE_FORMAT(i.plazo_en, '%Y-%m-%dT%H:%i:%s')                                  AS plazo_en
    FROM   tmp_irm i
    WHERE  i.pestana = v_grupo
      AND  (v_patron IS NULL
            OR CONCAT_WS(' ', i.numero_informe, i.numero_os, i.cliente, i.tecnico, i.equipo, i.codigo_tw, i.numero_serie) LIKE v_patron)
    ORDER BY IF(v_grupo = 'por_revisar', i.sla_vencido, 0) DESC,
             IF(v_grupo = 'por_revisar', i.horas_espera, 0) DESC,
             IF(v_grupo = 'en_correccion', i.plazo_en, NULL) ASC,
             IF(v_grupo = 'aprobados', i.fecha_revision, NULL) DESC,
             i.id_informe DESC
    LIMIT v_limite;

    DROP TEMPORARY TABLE IF EXISTS tmp_irm;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerInformeRevisionMovil  (App Mobile HU-33 — "Revisar informe" del Jefe de Área · solo lectura)
-- Detalle de un informe para revisarlo desde la app: diagnóstico, VALIDACIONES, EVIDENCIAS (con las forzadas resaltadas y su motivo) y la corrección pedida si está observado.
-- Acceso: rt_bandeja + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil → SP_ArmarBaseInformes, la misma bandeja de la intranet).
-- Validaciones {codigo, titulo, detalle, estado ok | atencion | error, obligatoria}; salen de las MISMAS columnas de SP_ArmarBaseInformes que usan SP_PrepararRevisionInforme y
--   SP_RegistrarRevisionInforme (fotos, ensayos sin resultado, observaciones / precotización, pasos realizados): no hay otra regla. Las obligatorias en error bloquean "Aprobar y liberar":
--     datos (informativa) · ensayos (obligatoria) · evidencias (obligatoria: ≥ 1 foto y ninguna evidencia FORZADA sin revisar del jefe en Aprobaciones) · procedimiento (obligatoria) ·
--     precotizacion (obligatoria solo si hay observaciones) · firmas (informativa: el estado exacto de SP_ArmarFirmasOsMovil, HU-17; no bloquea).
--   puede_aprobar  = rt_revisar + informe sin revisar ni observado + sin corrección pendiente + ninguna obligatoria en error (SP_AprobarInformeMovil lo vuelve a validar).
--   puede_observar = rt_revisar + informe sin revisar + sin corrección pendiente. motivo_bloqueo = por qué no se puede aprobar (NULL si se puede).
--   estado: por_revisar | en_correccion | aprobado (la misma pestaña de la lista).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 validaciones · 4 evidencias · 5 corrección pendiente (0 o 1 fila) · 6 motivos · 7 secciones · 8 plazos. Fechas: ISO sin zona (hora de Lima).
-- Requiere las migraciones 93, 101, 113 y 121.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerInformeRevisionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerInformeRevisionMovil(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_tiene      TINYINT DEFAULT 0;
    DECLARE v_revisar    TINYINT DEFAULT 0;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_estado     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_os      BIGINT DEFAULT NULL;
    DECLARE v_datos_ok   TINYINT DEFAULT 0;
    DECLARE v_n_fotos    INT DEFAULT 0;
    DECLARE v_n_forz     INT DEFAULT 0;
    DECLARE v_n_forz_sr  INT DEFAULT 0;
    DECLARE v_n_ens      INT DEFAULT 0;
    DECLARE v_n_ens_sr   INT DEFAULT 0;
    DECLARE v_n_ens_nc   INT DEFAULT 0;
    DECLARE v_n_obs      INT DEFAULT 0;
    DECLARE v_n_items    INT DEFAULT 0;
    DECLARE v_n_pasos    INT DEFAULT 0;
    DECLARE v_n_pasos_r  INT DEFAULT 0;
    DECLARE v_corr       BIGINT DEFAULT NULL;
    DECLARE v_f_horas    INT;
    DECLARE v_f_vence    DATETIME;
    DECLARE v_f_seg      INT;
    DECLARE v_f_ninf     INT;
    DECLARE v_f_ncomp    INT;
    DECLARE v_f_nfirm    INT;
    DECLARE v_f_nresp    INT;
    DECLARE v_f_nok      INT;
    DECLARE v_f_listo    TINYINT;
    DECLARE v_firmado    TINYINT DEFAULT 0;
    DECLARE v_completo   TINYINT DEFAULT 0;
    DECLARE v_ausente    TINYINT DEFAULT 0;
    DECLARE v_resp       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo_inc VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_err_obl    INT DEFAULT 0;
    DECLARE v_primer_err VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aprobar    TINYINT DEFAULT 0;
    DECLARE v_observar   TINYINT DEFAULT 0;
    DECLARE v_bloqueo    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_irv;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_revisar = FN_PermisoAccion(p_id_usuario, 'rt_revisar');

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT b.estado, b.id_os,
           IF(NULLIF(TRIM(IFNULL(b.diagnostico, '')), '') IS NOT NULL AND b.equipo IS NOT NULL AND b.tecnico IS NOT NULL AND b.numero_os IS NOT NULL, 1, 0),
           b.n_fotos, b.n_forzadas, b.n_forzadas_sin_revision,
           b.n_ensayos, b.n_ensayos_sin_resultado, b.n_ensayos_no_conformes,
           b.n_observaciones, IFNULL(b.n_items_precot, 0), b.n_pasos, b.n_pasos_realizados
      INTO v_estado, v_id_os, v_datos_ok,
           v_n_fotos, v_n_forz, v_n_forz_sr,
           v_n_ens, v_n_ens_sr, v_n_ens_nc,
           v_n_obs, v_n_items, v_n_pasos, v_n_pasos_r
    FROM tmp_rt_base b LIMIT 1;

    SELECT MAX(c.id_correccion) INTO v_corr
    FROM   informe_correccion c WHERE c.id_informe = p_id_informe AND c.estado = 'pendiente' AND c.eliminado_en IS NULL;

    -- Firmas del informe (HU-17): el estado exacto lo arma SP_ArmarFirmasOsMovil, una sola vez
    CALL SP_ArmarFirmasOsMovil(v_id_os, v_f_horas, v_f_vence, v_f_seg, v_f_ninf, v_f_ncomp, v_f_nfirm, v_f_nresp, v_f_nok, v_f_listo);
    SELECT IFNULL(MAX(i.firmado), 0), IFNULL(MAX(i.completo), 0), MAX(i.resp_nombre), MAX(i.motivo)
      INTO v_firmado, v_completo, v_resp, v_motivo_inc
    FROM tmp_fm_inf i WHERE i.id_informe = p_id_informe;
    SELECT IFNULL(MAX(r.ausente), 0) INTO v_ausente
    FROM tmp_fm_resp r JOIN tmp_fm_inf i ON i.clave = r.clave WHERE i.id_informe = p_id_informe;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;

    CALL SP_ArmarCatalogoRevisionInformeMovil();

    -- Validaciones
    DROP TEMPORARY TABLE IF EXISTS tmp_irv;
    CREATE TEMPORARY TABLE tmp_irv (
        orden      INT,
        codigo     VARCHAR(20),
        titulo     VARCHAR(80),
        detalle    VARCHAR(300),
        estado     VARCHAR(10),
        obligatoria TINYINT
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    INSERT INTO tmp_irv VALUES
        (1, 'datos', 'Datos del informe',
         IF(v_datos_ok = 1, 'Completo', 'Falta el diagnóstico o algún dato de la cabecera'),
         IF(v_datos_ok = 1, 'ok', 'atencion'), 0),
        (2, 'ensayos', 'Ensayos',
         CASE WHEN v_n_ens = 0     THEN 'No aplica: el informe no registra ensayos'
              WHEN v_n_ens_sr > 0  THEN CONCAT(v_n_ens_sr, IF(v_n_ens_sr = 1, ' lectura sin resultado', ' lecturas sin resultado'))
              WHEN v_n_ens_nc > 0  THEN CONCAT(v_n_ens_nc, IF(v_n_ens_nc = 1, ' lectura no conforme registrada', ' lecturas no conformes registradas'))
              ELSE 'Conformes' END,
         CASE WHEN v_n_ens_sr > 0 THEN 'error' WHEN v_n_ens_nc > 0 THEN 'atencion' ELSE 'ok' END, 1),
        (3, 'evidencias', 'Evidencias',
         CASE WHEN v_n_fotos = 0    THEN 'Faltan las fotos del servicio'
              WHEN v_n_forz_sr > 0  THEN CONCAT(v_n_forz_sr, IF(v_n_forz_sr = 1, ' forzada sin revisar', ' forzadas sin revisar'), ': resuelve primero la evidencia forzada en Aprobaciones')
              WHEN v_n_forz > 0     THEN CONCAT(v_n_fotos, IF(v_n_fotos = 1, ' evidencia · ', ' evidencias · '), v_n_forz, IF(v_n_forz = 1, ' forzada ya revisada', ' forzadas ya revisadas'), ' en Aprobaciones')
              ELSE CONCAT(v_n_fotos, IF(v_n_fotos = 1, ' evidencia', ' evidencias')) END,
         CASE WHEN v_n_fotos = 0 OR v_n_forz_sr > 0 THEN 'error' WHEN v_n_forz > 0 THEN 'atencion' ELSE 'ok' END, 1),
        (4, 'procedimiento', 'Procedimiento ejecutado',
         IF(v_n_pasos = 0, 'El informe no registra el procedimiento ejecutado', CONCAT(v_n_pasos_r, ' / ', v_n_pasos, ' pasos completados')),
         IF(v_n_pasos_r > 0, 'ok', 'error'), 1),
        (5, 'precotizacion', 'Precotización',
         CASE WHEN v_n_obs = 0   THEN 'No aplica: el servicio no tiene observaciones'
              WHEN v_n_items = 0 THEN 'Falta registrar la precotización (el servicio tiene observaciones)'
              ELSE CONCAT(v_n_items, IF(v_n_items = 1, ' concepto enviado', ' conceptos enviados')) END,
         IF(v_n_obs > 0 AND v_n_items = 0, 'error', 'ok'), IF(v_n_obs > 0, 1, 0)),
        (6, 'firmas', 'Firmas',
         CASE WHEN v_firmado = 1  THEN CONCAT('Firmado por ', IFNULL(v_resp, 'el responsable'))
              WHEN v_ausente = 1  THEN 'Cliente ausente'
              WHEN v_completo = 0 THEN IFNULL(v_motivo_inc, 'Aún sin responsable en planta')
              ELSE 'Pendiente de la firma del cliente' END,
         IF(v_firmado = 1 OR v_ausente = 1, 'ok', 'atencion'), 0);

    SELECT COUNT(*) INTO v_err_obl FROM tmp_irv WHERE obligatoria = 1 AND estado = 'error';
    SELECT v.detalle INTO v_primer_err FROM tmp_irv v WHERE v.obligatoria = 1 AND v.estado = 'error' ORDER BY v.orden LIMIT 1;

    SET v_observar = IF(v_revisar = 1 AND v_estado NOT IN ('revisado', 'aprobado') AND v_corr IS NULL, 1, 0);
    SET v_aprobar  = IF(v_revisar = 1 AND v_estado IN ('pendiente_revision', 'en_revision') AND v_corr IS NULL AND v_err_obl = 0, 1, 0);
    SET v_bloqueo  = CASE WHEN v_aprobar = 1 THEN NULL
                          WHEN v_revisar = 0 THEN 'No tienes permiso para aprobar informes.'
                          WHEN v_estado IN ('revisado', 'aprobado') THEN 'El informe ya fue revisado.'
                          WHEN v_corr IS NOT NULL OR v_estado = 'observado' THEN 'El informe está en corrección: el técnico debe atenderla antes de aprobarlo.'
                          ELSE v_primer_err END;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 Cabecera
    SELECT b.id_informe, b.numero_informe, b.tipo_servicio, b.numero_os, b.razon_social AS cliente, b.sede, b.equipo, b.codigo_tw, b.numero_serie, b.tecnico,
           DATE_FORMAT(b.fecha_ejecucion, '%Y-%m-%d')                                       AS fecha_ejecucion,
           b.diagnostico,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN 'aprobado'
                WHEN b.estado = 'observado'               THEN 'en_correccion'
                ELSE 'por_revisar' END                                                      AS estado,
           b.sla_vencido, b.horas_espera,
           v_aprobar AS puede_aprobar, v_observar AS puede_observar, v_bloqueo AS motivo_bloqueo,
           b.revisor, DATE_FORMAT(b.fecha_revision, '%Y-%m-%dT%H:%i:%s')                    AS fecha_revision,
           b.nota_revision                                                                  AS nota
    FROM   tmp_rt_base b;

    -- 3 Validaciones
    SELECT v.codigo, v.titulo, v.detalle, v.estado, v.obligatoria FROM tmp_irv v ORDER BY v.orden;

    -- 4 Evidencias (las mismas del detalle de la intranet: sin lecturas del QR ni intentos descartados por retoma)
    SELECT f.id_evidencia,
           IF(f.es_video = 1, 'Video de encendido', IFNULL(tf.String1, 'Evidencia')) AS etiqueta,
           IF(f.override_aprobado = 1, 1, 0)                                         AS forzada,
           f.motivo_forzado                                                          AS motivo_forzada,
           f.es_video,
           f.validacion_ia
    FROM   evidencia_fotografica f
    JOIN   tmp_rt_base b ON b.id_informe = p_id_informe
    LEFT JOIN tabla_maestra tf ON tf.IdMaestro = 30 AND tf.IdEmpresa = 1 AND tf.Num1 = f.id_tipo_evidencia
    WHERE  f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7)
      AND  f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
      AND  (f.id_informe = p_id_informe
            OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    ORDER BY f.timestamp_captura, f.id_evidencia;

    -- 5 Corrección pendiente (si el informe está observado)
    SELECT c.id_correccion, c.motivo, IFNULL(m.nombre, c.motivo) AS motivo_nombre, c.secciones, c.instruccion,
           DATE_FORMAT(c.plazo_en, '%Y-%m-%dT%H:%i:%s')    AS plazo_en,
           c.estado,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS por,
           DATE_FORMAT(c.creado_en, '%Y-%m-%dT%H:%i:%s')   AS creada_en
    FROM   informe_correccion c
    LEFT JOIN usuario u     ON u.id_usuario = c.id_jefe
    LEFT JOIN tmp_cat_rev m ON m.tipo = 'motivo' AND m.codigo = c.motivo
    WHERE  c.id_correccion = v_corr;

    -- 6 7 8 Catálogos del modal "Observar informe"
    SELECT k.codigo, k.nombre FROM tmp_cat_rev k WHERE k.tipo = 'motivo'  ORDER BY k.orden;
    SELECT k.codigo, k.nombre FROM tmp_cat_rev k WHERE k.tipo = 'seccion' ORDER BY k.orden;
    SELECT k.horas, k.nombre AS texto FROM tmp_cat_rev k WHERE k.tipo = 'plazo' ORDER BY k.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_irv;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObservarInformeMovil  (App Mobile HU-33 — "Observar informe": pedir la corrección al técnico)
-- El Jefe de Área observa un informe sin revisar: indica el motivo, las secciones afectadas, qué debe corregir y el plazo. El técnico recibe la solicitud (notificación + push) y el
-- informe queda 'observado' (pestaña "En corrección").
-- Acceso: rt_revisar + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil → SP_ArmarBaseInformes).
-- Validaciones (catálogo fijo: SP_ArmarCatalogoRevisionInformeMovil):
--   p_motivo ......... evidencia_insuficiente | datos_incorrectos | ensayos_inconsistentes | firma_faltante | otro
--   p_secciones ...... códigos separados por coma, al menos una y sin repetir: registro_fotografico | cabecera | ensayos | firmas
--   p_instruccion .... "Qué debe corregir": de 10 a 1000 caracteres
--   p_plazo_horas .... 4 | 24 | 48 | 72 (desde ahora, hora de Lima)
--   El informe no puede estar revisado ni tener ya una corrección pendiente (informe bloqueado con FOR UPDATE: dos jefes a la vez, gana el primero).
-- Efectos (una transacción): informe_correccion pendiente · informe_tecnico.estado = 'observado' · evento 'observado' en el historial (auditoria_evento, categoría revisión, origen móvil)
--   · notificación al técnico "Informe observado: N°" (prioridad alta; el push sale solo).
-- Resultados: 1 mensaje · 2 (id_correccion, plazo_en ISO sin zona, notificados). Requiere la migración 121.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObservarInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObservarInformeMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_informe  BIGINT,
    IN p_motivo      VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_secciones   VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_instruccion VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_plazo_horas INT
)
proc: BEGIN
    DECLARE v_tiene      TINYINT DEFAULT 0;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_en_tx      TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_tecnico BIGINT DEFAULT NULL;
    DECLARE v_numero_inf VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_equipo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_nom VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_instr      VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_secc       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_secc_nom   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_resto      VARCHAR(260) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tok        VARCHAR(260) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_plazo_txt  VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_err        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_plazo      DATETIME;
    DECLARE v_id_corr    BIGINT DEFAULT NULL;
    DECLARE v_pend       INT DEFAULT 0;
    DECLARE v_notif      INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        IF v_en_tx = 1 THEN ROLLBACK; END IF;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_revisar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para observar informes.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Validación de la entrada contra el catálogo fijo ──────────────────────────────────────
    CALL SP_ArmarCatalogoRevisionInformeMovil();
    DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;
    CREATE TEMPORARY TABLE tmp_sec_obs (codigo VARCHAR(30) NOT NULL) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    SET v_motivo = LOWER(TRIM(IFNULL(p_motivo, '')));
    SET v_instr  = TRIM(IFNULL(p_instruccion, ''));
    SET v_secc   = LOWER(REPLACE(TRIM(IFNULL(p_secciones, '')), ' ', ''));

    IF NOT EXISTS (SELECT 1 FROM tmp_cat_rev c WHERE c.tipo = 'motivo' AND c.codigo = v_motivo) THEN
        SET v_err = 'Elige el motivo de la observación.';
    ELSEIF v_secc = '' OR CHAR_LENGTH(v_secc) > 200 THEN
        SET v_err = 'Elige al menos una sección afectada.';
    ELSEIF CHAR_LENGTH(v_instr) < 10 OR CHAR_LENGTH(v_instr) > 1000 THEN
        SET v_err = 'Indica qué debe corregir el técnico (de 10 a 1000 caracteres).';
    ELSEIF NOT EXISTS (SELECT 1 FROM tmp_cat_rev c WHERE c.tipo = 'plazo' AND c.horas = IFNULL(p_plazo_horas, 0)) THEN
        SET v_err = 'Elige un plazo válido (4, 24, 48 o 72 horas).';
    END IF;

    IF v_err IS NULL THEN
        SET v_resto = CONCAT(v_secc, ',');
        WHILE v_err IS NULL AND CHAR_LENGTH(v_resto) > 0 DO
            SET v_tok   = SUBSTRING_INDEX(v_resto, ',', 1);
            SET v_resto = SUBSTRING(v_resto, CHAR_LENGTH(v_tok) + 2);
            IF NOT EXISTS (SELECT 1 FROM tmp_cat_rev c WHERE c.tipo = 'seccion' AND c.codigo = v_tok) THEN
                SET v_err = 'Alguna de las secciones indicadas no es válida.';
            ELSEIF EXISTS (SELECT 1 FROM tmp_sec_obs s WHERE s.codigo = v_tok) THEN
                SET v_err = 'Hay secciones repetidas.';
            ELSE
                INSERT INTO tmp_sec_obs (codigo) VALUES (v_tok);
            END IF;
        END WHILE;
    END IF;

    IF v_err IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;
        SELECT 1 AS IdTipoMensaje, v_err AS Mensaje;
        LEAVE proc;
    END IF;

    -- Textos canónicos (en el orden del catálogo) para guardar y para el aviso al técnico
    SELECT GROUP_CONCAT(c.codigo ORDER BY c.orden SEPARATOR ','), GROUP_CONCAT(c.nombre ORDER BY c.orden SEPARATOR ', ')
      INTO v_secc, v_secc_nom
    FROM tmp_cat_rev c WHERE c.tipo = 'seccion' AND c.codigo IN (SELECT s.codigo FROM tmp_sec_obs s);
    SELECT c.nombre INTO v_motivo_nom FROM tmp_cat_rev c WHERE c.tipo = 'motivo' AND c.codigo = v_motivo LIMIT 1;
    SELECT c.nombre INTO v_plazo_txt  FROM tmp_cat_rev c WHERE c.tipo = 'plazo' AND c.horas = p_plazo_horas LIMIT 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
    DROP TEMPORARY TABLE IF EXISTS tmp_sec_obs;

    -- ── Alcance del jefe ─────────────────────────────────────────────────────────────────────
    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    SELECT COUNT(*), MAX(estado), MAX(id_tecnico), MAX(numero_informe), MAX(numero_os), MAX(equipo)
      INTO v_existe, v_estado, v_id_tecnico, v_numero_inf, v_numero_os, v_equipo
    FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado IN ('revisado', 'aprobado') THEN
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: no se puede observar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Transacción ──────────────────────────────────────────────────────────────────────────
    START TRANSACTION;
    SET v_en_tx = 1;

    SELECT estado INTO v_estado FROM informe_tecnico WHERE id_informe = p_id_informe AND eliminado_en IS NULL FOR UPDATE;
    IF v_estado IN ('revisado', 'aprobado') THEN
        ROLLBACK;
        SET v_en_tx = 0;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: no se puede observar.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_pend FROM informe_correccion WHERE id_informe = p_id_informe AND estado = 'pendiente' AND eliminado_en IS NULL;
    IF v_pend > 0 THEN
        ROLLBACK;
        SET v_en_tx = 0;
        SELECT 1 AS IdTipoMensaje, 'El informe ya tiene una corrección pendiente: espera a que el técnico la atienda.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_plazo = NOW() + INTERVAL p_plazo_horas HOUR;

    INSERT INTO informe_correccion (id_informe, id_jefe, motivo, secciones, instruccion, plazo_en, estado, creado_por)
    VALUES (p_id_informe, p_id_usuario, v_motivo, v_secc, v_instr, v_plazo, 'pendiente', p_id_usuario);
    SET v_id_corr = LAST_INSERT_ID();

    UPDATE informe_tecnico SET estado = 'observado', modificado_por = p_id_usuario WHERE id_informe = p_id_informe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', p_id_informe, 'observado', v_estado, 'observado',
            LEFT(CONCAT('Observó el informe (', v_motivo_nom, ') desde la app'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('categoria', 'revision', 'origen', 'movil', 'detalle', CONCAT('Secciones: ', v_secc_nom, ' · Plazo: ', v_plazo_txt), 'nota', v_instr,
                        'idCorreccion', v_id_corr));

    IF v_id_tecnico IS NOT NULL AND v_id_tecnico <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por, prioridad_origen)
        VALUES (v_id_tecnico, 5,
                LEFT(CONCAT('Informe observado: ', IFNULL(v_numero_inf, IFNULL(v_numero_os, ''))), 150),
                LEFT(CONCAT('Tu informe de ', IFNULL(v_equipo, 'el equipo'), IF(v_numero_os IS NULL, '', CONCAT(' (', v_numero_os, ')')), ' fue observado. Motivo: ', v_motivo_nom,
                            '. Secciones: ', v_secc_nom, '. Qué corregir: ', v_instr, '. Plazo: ', DATE_FORMAT(v_plazo, '%d/%m/%Y %H:%i'), ' (', v_plazo_txt, ').'), 3000),
                'informe_tecnico', p_id_informe, NOW(), p_id_usuario, 'alta');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;
    SET v_en_tx = 0;

    SELECT 2 AS IdTipoMensaje, 'Informe observado. El técnico recibió la solicitud de corrección.' AS Mensaje;
    SELECT v_id_corr AS id_correccion, DATE_FORMAT(v_plazo, '%Y-%m-%dT%H:%i:%s') AS plazo_en, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- SP_AprobarInformeMovil  (App Mobile HU-33 — "Aprobar y liberar" el informe, Jefe de Área)
-- Es la MISMA revisión de la intranet (HU-59): delega en SP_RegistrarRevisionInforme, que vuelve a validar el checklist obligatorio (fotos, ensayos con resultado, precotización si
-- hay observaciones y procedimiento ejecutado), deja el informe REVISADO (cerrado e inmutable), envía la precotización a Comercial, registra el historial y avisa al técnico y al
-- responsable de la RQ. Aquí solo se agrega lo propio de la app:
--   · Acceso: rt_revisar + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil, que SP_RegistrarRevisionInforme respeta al armar su base).
--   · No se aprueba un informe OBSERVADO o con una corrección pendiente (el técnico debe atenderla).
--   · No se aprueba con una evidencia FORZADA sin revisar: primero se resuelve en Aprobaciones (HU-12).
--   p_nota: nota interna del jefe (opcional, hasta 500 caracteres).
-- Resultados (los de SP_RegistrarRevisionInforme): 1 mensaje · 2 (id_informe, estado = revisado, fecha_revision, id_precotizacion, numero_precotizacion).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AprobarInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_AprobarInformeMovil(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_nota       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tiene    TINYINT DEFAULT 0;
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forz_sr  INT DEFAULT 0;
    DECLARE v_corr     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_revisar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar la revisión de informes.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SELECT COUNT(*), MAX(estado), IFNULL(MAX(n_forzadas_sin_revision), 0) INTO v_existe, v_estado, v_forz_sr FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_corr FROM informe_correccion WHERE id_informe = p_id_informe AND estado = 'pendiente' AND eliminado_en IS NULL;
    IF v_estado = 'observado' OR v_corr > 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'El informe está en corrección: el técnico debe atenderla antes de aprobarlo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_forz_sr > 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tiene una evidencia forzada sin revisar: resuélvela primero en Aprobaciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- La revisión de la intranet (valida el checklist, cierra el informe y avisa). Las variables del alcance siguen fijas: también arma su base con la regla de la app.
    CALL SP_RegistrarRevisionInforme(p_id_usuario, p_id_informe, p_nota);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerArchivoEvidenciaInformeMovil  (App Mobile HU-33 — ruta del archivo de una evidencia del informe, para verla en la app · lectura)
-- Acceso: rt_bandeja + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil → SP_ArmarBaseInformes). La evidencia debe ser del informe (id_informe) o, si no tiene
-- informe asignado, de la misma OS y equipo (la misma regla de SP_ObtenerInformeRevisionMovil y del detalle de la intranet). Las lecturas del QR no tienen archivo.
-- Resultados: 1 mensaje · 2 (ruta, ruta_cuadro = miniatura del video, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoEvidenciaInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoEvidenciaInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_informe   BIGINT,
    IN p_id_evidencia BIGINT
)
proc: BEGIN
    DECLARE v_tiene  TINYINT DEFAULT 0;
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM   evidencia_fotografica f
    JOIN   tmp_rt_base b ON b.id_informe = p_id_informe
    WHERE  f.id_evidencia = p_id_evidencia AND f.eliminado_en IS NULL AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
      AND  (f.id_informe = p_id_informe
            OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día para quien tiene el menú de Jefatura en la app. Es UN SOLO menú para todos los jefes de área:
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*: Servicio Técnico, Metrología, Operaciones…), o
--   · rol SUPERVISOR / ADMINISTRADOR con un área definida (cualquier área, incluida Servicio Técnico).
-- Los técnicos, metrólogos y usuarios comunes reciben un mensaje y la app les muestra el menú de campo.
-- El área del jefe sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (CARGO_USUARIO.String3): SP_ResolverJefaturaMovil.
-- El alcance de los servicios (área de la RQ) lo arma SP_ArmarAlcanceJefaturaMovil; el Panel de Campo y el Seguimiento del servicio (HU-29 / HU-30)
-- usan los mismos dos procedimientos de apoyo.
--   - Servicio Técnico y Metrología: se filtra por el área de la RQ de cada servicio (orden_servicio → expediente_digital →
--     requerimiento.id_area → area_servicio_rq.area_usuario = área del jefe).
--   - Otras áreas (Operaciones, TI, Gerencia, Comercial…): no tienen área en la RQ, así que ven el resumen de TODOS los servicios.
-- Resultados:
--   1. Mensaje
--   2. Una fila: area_codigo (el área del usuario), area_nombre, sede, y los contadores de HOY (fecha de Lima, UTC-5):
--        programados      : servicios programados para hoy (en cualquier estado activo)
--        en_ruta          : de esos, en ruta
--        en_ejecucion     : de esos, en ejecución o pausados (ya están en planta)
--        con_demora       : de esos, con una demora registrada hoy
--        aprobaciones_pendientes : solicitudes de salida que ESTE usuario puede resolver. Misma regla que
--                           SP_ObtenerAutorizacionesSalida / SP_ResolverAutorizacionSalida: encargado del área (Jefe de Servicio
--                           Técnico o Jefe de Metrología, o supervisor de Metrología) → las de su área y las que la RQ no ubica en
--                           un área; supervisión general (Jefe/Coordinador de Operaciones, supervisor de Operaciones, administrador)
--                           → todas; el resto → 0.
--      Contadores de las tarjetas (HU-28, actualización). NULL = sin dato para este usuario (no tiene el permiso, el área no aplica o
--      la fuente no está disponible): la app no pinta contador. Cada uno se calcula en su propio bloque: si una fuente falla (p. ej. falta
--      una migración) solo ese contador queda NULL y el menú sigue funcionando.
--        alertas_criticas     : notificaciones CRÍTICAS sin leer ni archivar de este usuario (notificacion.prioridad = 'critica', la
--                               clasificación del Centro de Notificaciones HU-90, migración 102_centro_notificaciones: error crítico de ensayo,
--                               servicio detenido, alertas críticas de Control de Campo). Es lo mismo que filtra "Críticas" en Notificaciones.
--        informes_por_revisar : informes de servicio técnico enviados por los técnicos y pendientes de revisión (grupos pendiente_revision y
--                               pendiente_precotizacion de SP_ArmarBaseInformes, el MISMO cálculo de la bandeja de Revisión Técnica). Solo con rt_bandeja.
--        certificados_pendientes : órdenes de metrología en estado pendiente_certificado. Solo área Metrología.
--        tickets_correlativo  : tickets de metrología solicitados (ticket_metrologia.estado = 'solicitado'), pendientes de asignar correlativo.
--                               Solo área Metrología.
--        mi_equipo_total / mi_equipo_en_labores : técnicos activos del área (misma regla de técnico que la bandeja de Programación: sin
--                               jefaturas ni asistentes) y, de ellos, los que HOY tienen una orden en ruta, en ejecución o pausada (como técnico
--                               principal o personal de apoyo). Solo Servicio Técnico y Metrología.
--        agenda_conflictos    : conflictos sobrevenidos de la Programación (HU-39, SP_ArmarConflictosProgramacion: el MISMO cálculo de la lista de
--                               conflictos). Solo con prog_bandeja; en Servicio Técnico y Metrología, los de técnicos de su área.
--        viaticos_por_revisar : gastos rendidos por los técnicos pendientes de revisión (gasto_viatico tipo gasto_solicitado, estado pendiente).
--                               Solo con prog_aprobar_reprogramacion (el Jefe de Operaciones, quien revisa los gastos: SP_RevisarGastoProgramacion).
--      Sin fuente todavía (no hay contador): Recepción en Taller (no existe el módulo ni tabla) y Panel de Campo usa en_ruta.
-- Solo lectura. No usa funciones almacenadas propias (solo el FN_PermisoAccion que ya existe).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerMenuJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMenuJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hoy  DATE;
    DECLARE v_aut_area    VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_alertas      INT DEFAULT NULL;
    DECLARE v_informes     INT DEFAULT NULL;
    DECLARE v_certificados INT DEFAULT NULL;
    DECLARE v_tickets      INT DEFAULT NULL;
    DECLARE v_eq_total     INT DEFAULT NULL;
    DECLARE v_eq_labores   INT DEFAULT NULL;
    DECLARE v_conflictos   INT DEFAULT NULL;
    DECLARE v_gastos       INT DEFAULT NULL;
    DECLARE v_prog         INT DEFAULT 0;
    DECLARE v_ruta         INT DEFAULT 0;
    DECLARE v_ejec         INT DEFAULT 0;
    DECLARE v_dem          INT DEFAULT 0;

    -- Quién es el jefe y de qué área: la regla vive en SP_ResolverJefaturaMovil (la comparten el Panel de Campo y el Seguimiento del servicio)
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);

    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    -- ── Contadores de las tarjetas: cada uno en su bloque; si la fuente falla queda NULL ─────────────────────────────────
    -- Alertas de Campo: críticas sin leer (la misma clasificación que el filtro "Críticas" de Notificaciones)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_alertas = NULL;
        SELECT COUNT(*) INTO v_alertas
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
          AND  n.archivado = 0 AND n.leido = 0 AND n.prioridad = 'critica';
    END;

    -- Informes pendientes de revisión: el cálculo compartido de la bandeja de Revisión Técnica
    BEGIN
        DECLARE v_tiene_inf TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            SET v_informes = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
            -- Con el alcance de la app (regla ÁREA + ROL) y sin los observados (esos esperan la corrección del técnico): los mismos de la pestaña "Por revisar" (HU-33)
            CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene_inf);
            IF v_tiene_inf = 1 THEN
                CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
                SELECT COUNT(*) INTO v_informes FROM tmp_rt_base
                WHERE grupo_estado IN ('pendiente_revision', 'pendiente_precotizacion') AND estado <> 'observado';
                DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            END IF;
            SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        END IF;
    END;

    -- Metrología: certificados pendientes y tickets de correlativo solicitados
    IF v_area = 'metrologia' THEN
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_certificados = NULL;
            SELECT COUNT(*) INTO v_certificados FROM orden_metrologia om WHERE om.eliminado_en IS NULL AND om.estado = 'pendiente_certificado';
        END;
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_tickets = NULL;
            SELECT COUNT(*) INTO v_tickets FROM ticket_metrologia t WHERE t.eliminado_en IS NULL AND t.estado = 'solicitado';
        END;
    END IF;

    -- Mi Equipo: técnicos del área y los que hoy están en labores (solo Servicio Técnico y Metrología)
    IF v_area IN ('servicio_tecnico', 'metrologia') THEN
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                SET v_eq_total = NULL;
                SET v_eq_labores = NULL;
            END;
            SELECT COUNT(*),
                   IFNULL(SUM(EXISTS (SELECT 1
                                      FROM   orden_servicio os
                                      WHERE  os.eliminado_en IS NULL AND os.fecha_ejecucion = v_hoy
                                        AND  os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
                                        AND  (os.id_tecnico_principal = u.id_usuario
                                              OR EXISTS (SELECT 1 FROM os_personal op
                                                         WHERE op.id_os = os.id_os AND op.id_usuario = u.id_usuario AND op.eliminado_en IS NULL)))), 0)
            INTO   v_eq_total, v_eq_labores
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = v_area
              AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'));
        END;
    END IF;

    -- Agenda del Área: conflictos sobrevenidos de la Programación (HU-39)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            CALL SP_LimpiarConflictosProgramacion();
            SET v_conflictos = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 1 THEN
            CALL SP_ArmarConflictosProgramacion();
            SELECT COUNT(*) INTO v_conflictos
            FROM   tmp_cf c
            WHERE  v_area NOT IN ('servicio_tecnico', 'metrologia')
                   OR EXISTS (SELECT 1 FROM usuario t WHERE t.id_usuario = c.id_usuario AND t.area = v_area);
            CALL SP_LimpiarConflictosProgramacion();
        END IF;
    END;

    -- Viáticos y Gastos: gastos rendidos por revisar (solo quien los revisa)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_gastos = NULL;
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 THEN
            SELECT COUNT(*) INTO v_gastos
            FROM   gasto_viatico g
            WHERE  g.eliminado_en IS NULL AND g.tipo = 'gasto_solicitado' AND g.estado = 'pendiente';
        END IF;
    END;

    -- Resumen del día: los servicios del alcance del jefe (SP_ArmarAlcanceJefaturaMovil: área de la RQ para ST/Metrología; las demás áreas ven todo)
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);
    SELECT COUNT(*),
           IFNULL(SUM(os.estado = 'en_ruta'), 0),
           IFNULL(SUM(os.estado IN ('en_ejecucion', 'pausada')), 0)
    INTO   v_prog, v_ruta, v_ejec
    FROM   orden_servicio os
    JOIN   tmp_jf_alc a ON a.id_os = os.id_os
    WHERE  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');
    SELECT COUNT(DISTINCT d.id_os) INTO v_dem
    FROM   demora_registro d
    JOIN   tmp_jf_alc a ON a.id_os = d.id_os
    JOIN   orden_servicio os ON os.id_os = d.id_os
    WHERE  d.eliminado_en IS NULL AND DATE(d.fecha_registro) = v_hoy
      AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT v_area                                                           AS area_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1) AS area_nombre,
           v_sede                                                           AS sede,
           v_prog                                                           AS programados,
           v_ruta                                                           AS en_ruta,
           v_ejec                                                           AS en_ejecucion,
           v_dem                                                            AS con_demora,
           (SELECT COUNT(*)
            FROM   autorizacion_salida_os a
            WHERE  a.eliminado_en IS NULL AND a.estado = 'pendiente'
              AND  (v_aut_general = 1
                    OR (v_aut_area IS NOT NULL AND (a.area_destino IS NULL OR a.area_destino = v_aut_area))))
           + (SELECT COUNT(*)
              FROM   llegada_forzada_os lf
              WHERE  lf.eliminado_en IS NULL AND lf.estado = 'pendiente'
                AND  (v_aut_general = 1
                      OR (v_aut_area IS NOT NULL AND (lf.area_destino IS NULL OR lf.area_destino = v_aut_area))))
           -- Evidencias forzadas y ensayos con error sin revisar (migración 113), por el área de la RQ
           + (SELECT COUNT(*)
              FROM   evidencia_fotografica f
              JOIN   orden_servicio os ON os.id_os = f.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
              LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
              LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
              LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
              WHERE  f.eliminado_en IS NULL AND f.override_aprobado = 1 AND f.vigente = 1 AND f.revision_jefe IS NULL
                AND  (v_aut_general = 1 OR (v_aut_area IS NOT NULL AND (asr.area_usuario IS NULL OR asr.area_usuario = v_aut_area))))
           + (SELECT COUNT(*)
              FROM   informe_tecnico it
              JOIN   orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
              LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
              LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
              LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
              WHERE  it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL AND it.error_critico_revision IS NULL
                AND  (v_aut_general = 1 OR (v_aut_area IS NOT NULL AND (asr.area_usuario IS NULL OR asr.area_usuario = v_aut_area))))
           -- Gastos pendientes: solo para quien los revisa (el mismo contador de la tarjeta Viáticos y Gastos)
           + IFNULL(v_gastos, 0)                                            AS aprobaciones_pendientes,
           v_alertas                                                        AS alertas_criticas,
           v_informes                                                       AS informes_por_revisar,
           v_certificados                                                   AS certificados_pendientes,
           v_tickets                                                        AS tickets_correlativo,
           v_eq_total                                                       AS mi_equipo_total,
           v_eq_labores                                                     AS mi_equipo_en_labores,
           v_conflictos                                                     AS agenda_conflictos,
           v_gastos                                                         AS viaticos_por_revisar;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerNotificacionesMovil  (App Mobile HU-02 / HU-04 — pestaña Notificaciones)
-- Avisos del usuario que inició sesión (el id sale del token): las 60 más recientes, no eliminadas.
-- Son las mismas de la campana de la intranet (tabla notificacion), con el tipo ya clasificado para el ícono y la acción de la app.
--   tipo (según el título que dejan los demás SP):
--     autorizacion_aprobada   "Autorización de salida aprobada" (y el texto anterior "Visto bueno de salida: …")
--     autorizacion_rechazada  "Autorización de salida rechazada" (y "Salida no autorizada: …")
--     autorizacion_solicitud  "Autorización de salida · …" (le llega al jefe cuando un técnico pide su visto bueno)
--     solicitud_enviada       "Solicitud de autorización enviada" (confirmación para el técnico)
--     gasto_aprobado | gasto_observado | gasto_rechazado   gastos revisados por el Jefe de Operaciones
--     servicio                "Nueva programación: …" (se asignó un servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     ensayo_critico          "Ensayo con error crítico" (HU-10: le llega al encargado del área; el técnico pidió apoyo o aceptó guardar con una lectura fuera del EMP)
--     evidencia_forzada       "Evidencia forzada" (HU-12: una foto rechazada por la IA que el técnico aceptó con un motivo)
--     correlativo_solicitado  "Solicitud de correlativo enviada" (HU-14: confirmación al técnico) · correlativo_solicitud "Solicitud de correlativo" (HU-34: le llega al Jefe de
--                             Metrología) · correlativo_asignado "Correlativo asignado" (HU-14: Metrología asignó el correlativo; abre "Mis tickets"). entidad_tipo = ticket_metrologia.
--     equipo_nuevo            "Equipo nuevo por aprobar" (HU-07: equipo NEW registrado en campo)
--     servicio_detenido       "Servicio detenido: …" (Control de Campo)
--     informe_observado       "Informe observado: …" (HU-33: el jefe pidió una corrección; le llega al técnico, entidad_tipo = informe_tecnico) · informe_revisado "Informe revisado: …" (HU-59)
--     alerta_campo            otra alerta operativa del Control de Campo (tipo_notificacion = alerta_operativa)
--     general                 cualquier otro
--   critica / prioridad: la prioridad que ya clasifica el Centro de Notificaciones (HU-90, migración 102_centro_notificaciones: columna
--     notificacion.prioridad = critica | alta | normal). Es lo que filtra "Críticas" en la pestaña Notificaciones del jefe. No se repite la regla aquí.
--   Las archivadas en la intranet no se muestran.
--   pendientes_aprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
--   entidad_tipo / id_entidad: a qué abre la app ('orden_servicio' = el detalle del servicio).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_notificacion, x.tipo, x.titulo, x.cuerpo, x.entidad_tipo, x.id_entidad, x.leida, x.fecha_creacion,
           x.prioridad, IF(x.prioridad = 'critica', 1, 0) AS critica,
           CASE WHEN x.tipo = 'autorizacion_aprobada' AND x.entidad_tipo = 'orden_servicio'
                THEN (SELECT a.pendientes FROM autorizacion_salida_os a
                      WHERE  a.id_os = x.id_entidad AND a.eliminado_en IS NULL
                      ORDER BY a.id_autorizacion DESC LIMIT 1)
           END AS pendientes_aprobados
    FROM (
        SELECT n.id_notificacion,
               CASE WHEN n.titulo LIKE 'Autorización de salida aprobada%' OR n.titulo LIKE 'Visto bueno de salida%'     THEN 'autorizacion_aprobada'
                    WHEN n.titulo LIKE 'Autorización de salida rechazada%' OR n.titulo LIKE 'Salida no autorizada%'     THEN 'autorizacion_rechazada'
                    WHEN n.titulo LIKE 'Solicitud de autorización enviada%'                                             THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Solicitud de llegada forzada enviada%'                                          THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Llegada forzada aprobada%'                                                      THEN 'llegada_forzada_aprobada'
                    WHEN n.titulo LIKE 'Llegada forzada rechazada%'                                                     THEN 'llegada_forzada_rechazada'
                    WHEN n.titulo LIKE 'Llegada forzada%'                                                               THEN 'llegada_forzada_solicitud'
                    WHEN n.titulo LIKE 'Solicitud de correlativo enviada%'                                              THEN 'correlativo_solicitado'
                    WHEN n.titulo LIKE 'Solicitud de correlativo%'                                                      THEN 'correlativo_solicitud'
                    WHEN n.titulo LIKE 'Correlativo asignado%'                                                          THEN 'correlativo_asignado'
                    WHEN n.titulo LIKE 'Autorización de salida%'                                                        THEN 'autorizacion_solicitud'
                    WHEN n.titulo LIKE 'Gasto aprobado%'                                                                THEN 'gasto_aprobado'
                    WHEN n.titulo LIKE 'Gasto observado%'                                                               THEN 'gasto_observado'
                    WHEN n.titulo LIKE 'Gasto rechazado%'                                                               THEN 'gasto_rechazado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'                         THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    WHEN n.titulo LIKE 'Ensayo con error cr%'                                                           THEN 'ensayo_critico'
                    WHEN n.titulo LIKE 'Evidencia forzada%'                                                             THEN 'evidencia_forzada'
                    WHEN n.titulo LIKE 'Equipo nuevo por aprobar%'                                                      THEN 'equipo_nuevo'
                    WHEN n.titulo LIKE 'Servicio detenido:%'                                                            THEN 'servicio_detenido'
                    WHEN n.titulo LIKE 'Informe observado%'                                                             THEN 'informe_observado'
                    WHEN n.titulo LIKE 'Informe revisado%'                                                              THEN 'informe_revisado'
                    WHEN n.tipo_notificacion = 'alerta_operativa'                                                       THEN 'alerta_campo'
                    ELSE 'general' END AS tipo,
               n.titulo,
               n.cuerpo,
               n.entidad_tipo,
               n.id_entidad,
               n.leido                AS leida,
               n.fecha_creacion,
               n.prioridad
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL AND n.archivado = 0
        ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
        LIMIT 60
    ) x
    ORDER BY x.fecha_creacion DESC, x.id_notificacion DESC;
END$$

DELIMITER ;

-- ============================================================
-- VERIFICACIÓN (solo lectura, no crea datos)
-- ============================================================
SELECT 'Tabla informe_correccion (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_correccion') AS valor
UNION ALL
SELECT 'Procedimientos HU-33 (deben ser 8)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE'
          AND ROUTINE_NAME IN ('SP_FijarAlcanceInformesMovil', 'SP_ArmarCatalogoRevisionInformeMovil', 'SP_ObtenerInformesRevisionMovil', 'SP_ObtenerInformeRevisionMovil',
                               'SP_ObservarInformeMovil', 'SP_AprobarInformeMovil', 'SP_ObtenerArchivoEvidenciaInformeMovil', 'SP_ResolverAprobadorMovil'))
UNION ALL
SELECT 'SP_ArmarBaseInformes con el alcance de la app y las forzadas (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ArmarBaseInformes'
          AND ROUTINE_DEFINITION LIKE '%tw_inf_usuario%' AND ROUTINE_DEFINITION LIKE '%n_forzadas_sin_revision%')
UNION ALL
SELECT 'Columna evidencia_fotografica.revision_jefe (migración 113, debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'revision_jefe');
