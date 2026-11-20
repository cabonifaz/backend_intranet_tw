-- HU-23 Recepción de instrumentos (OM) en el taller (Técnico de Metrología, app móvil). Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- Requiere antes los procedimientos de la app que ya existen: SP_NormalizarQrMovil (HU-11), SP_ArmarAprobadoresOsMovil y FN_PermisoAccion. No crea datos: solo 3 tablas vacías y 13 procedimientos.
-- La OM es una orden_servicio de tipo OM; sus instrumentos son sus os_equipo. Una OM puede tener varias recepciones (la parcial se completa después: la OM queda abierta hasta recibir lo que falta).
-- Tablas nuevas (IF NOT EXISTS): om_recepcion · om_recepcion_equipo · om_recepcion_foto.
-- Procedimientos nuevos (13): apoyo SP_ArmarOmTecnicoMovil (acceso a la OM), SP_ArmarInstrumentosRecepcionOmMovil (qué es un instrumento recibido), SP_CatalogoAccesoriosRecepcionOmMovil (accesorios);
--   lectura SP_ObtenerRecepcionesOmMovil (lista), SP_ObtenerRecepcionOmMovil (detalle), SP_ObtenerFotosRecepcionOmMovil, SP_ObtenerArchivoFotoRecepcionOmMovil, SP_BuscarInstrumentoQrRecepcionOmMovil,
--   SP_ObtenerConstanciaRecepcionOmMovil; escritura SP_RegistrarFotoRecepcionOmMovil, SP_QuitarFotoRecepcionOmMovil, SP_RegistrarRecepcionOmMovil, SP_GuardarConstanciaRecepcionOmMovil.

-- ============================================================
-- Migración 124 — Recepción de instrumentos de la OM en el taller desde la app móvil (App Mobile HU-23)
--   1. om_recepcion: una recepción registrada por el técnico de Metrología (guía, medio de entrega, quién entrega, quién recibe, firma de quien entrega como
--      TRAZOS normalizados —igual que HU-17—, estado conforme / observado / parcial, motivo si es parcial, PDF de la constancia y si se envió por correo).
--      Una OM puede tener varias recepciones (la parcial se completa después).
--   2. om_recepcion_equipo: cada instrumento recibido en esa recepción (estado físico, observaciones y accesorios). Un instrumento se recibe UNA sola vez en la
--      misma OM (lo controla SP_RegistrarRecepcionOmMovil).
--   3. om_recepcion_foto: fotos de recepción (solo cámara). Nacen sin recepción (id_recepcion_equipo NULL: «pendientes» del técnico) y quedan ligadas al registrar.
--   No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS om_recepcion (
    id_recepcion        BIGINT        NOT NULL AUTO_INCREMENT,
    id_os               BIGINT        NOT NULL,
    numero_guia         VARCHAR(40)   NOT NULL,
    medio_entrega       ENUM('cliente_taller','courier','traslado_tw') NOT NULL,
    entrego_nombre      VARCHAR(120)  NOT NULL,
    entrego_cargo       VARCHAR(120)  NULL,
    id_usuario_recibio  BIGINT        NOT NULL,
    recibido_utc        DATETIME      NOT NULL,
    estado              ENUM('conforme','observado','parcial') NOT NULL,
    motivo_parcial      VARCHAR(300)  NULL,
    firma_trazos        JSON          NULL,
    ruta_constancia     VARCHAR(500)  NULL,
    correo_enviado      TINYINT(1)    NOT NULL DEFAULT 0,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT        NULL,
    modificado_en       DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT        NULL,
    eliminado_en        DATETIME      NULL,
    eliminado_por       BIGINT        NULL,
    PRIMARY KEY (id_recepcion),
    KEY ix_om_recepcion_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS om_recepcion_equipo (
    id_recepcion_equipo BIGINT        NOT NULL AUTO_INCREMENT,
    id_recepcion        BIGINT        NOT NULL,
    id_os_equipo        BIGINT        NOT NULL,
    estado_fisico       ENUM('conforme','observado') NOT NULL,
    observaciones       VARCHAR(500)  NOT NULL,
    accesorios          JSON          NULL,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en        DATETIME      NULL,
    PRIMARY KEY (id_recepcion_equipo),
    KEY ix_om_recepcion_equipo_rec (id_recepcion),
    KEY ix_om_recepcion_equipo_oe (id_os_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS om_recepcion_foto (
    id_foto             BIGINT        NOT NULL AUTO_INCREMENT,
    id_os_equipo        BIGINT        NOT NULL,
    id_usuario          BIGINT        NOT NULL,
    id_recepcion_equipo BIGINT        NULL,
    orden               INT           NOT NULL,
    ruta                VARCHAR(500)  NOT NULL,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en        DATETIME      NULL,
    PRIMARY KEY (id_foto),
    KEY ix_om_recepcion_foto_oe (id_os_equipo),
    KEY ix_om_recepcion_foto_re (id_recepcion_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ============================================================
-- SP_ArmarOmTecnicoMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_rom_os` las OM (orden_servicio.tipo = 'OM', no eliminadas) a las que el técnico del token tiene acceso: es técnico principal o está en
-- os_personal (mismo criterio de HU-22). UNA sola vez: todos los SP de la recepción (lista, detalle, fotos, QR, registrar, constancia) piden el acceso aquí.
--   p_id_os = NULL → todas las OM del técnico; con un id → solo esa (vacía si no es suya o no es una OM: misma respuesta para «no existe» y «no es tuya»).
--   activa = 1 si el estado de la OM no es finalizada / anulada / reprogramada (solo las activas aceptan recepciones nuevas).
-- Columnas: id_os · numero · cliente · numero_rq · servicio · activa · id_cliente · id_contacto · id_expediente (para quien arma la constancia).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_rom_os. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarOmTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarOmTecnicoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    CREATE TEMPORARY TABLE tmp_rom_os (
        id_os BIGINT NOT NULL,
        numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        cliente VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        activa TINYINT NOT NULL DEFAULT 1,
        id_cliente BIGINT NULL,
        id_contacto BIGINT NULL,
        PRIMARY KEY (id_os));

    IF IFNULL(p_id_usuario, 0) > 0 THEN
        INSERT INTO tmp_rom_os (id_os, numero, cliente, numero_rq, servicio, activa, id_cliente, id_contacto)
        SELECT os.id_os, os.numero,
               LEFT(COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social), 200),
               (SELECT rq.numero FROM expediente_digital ed JOIN requerimiento rq ON rq.id_requerimiento = ed.id_requerimiento
                WHERE ed.id_expediente = os.id_expediente LIMIT 1),
               LEFT((SELECT tsv.String1 FROM tabla_maestra tsv
                     WHERE tsv.Descripcion = 'TIPO_SERVICIO' AND tsv.IdEmpresa = 1 AND tsv.Num1 = os.id_tipo_servicio
                     ORDER BY tsv.IdMaestro DESC LIMIT 1), 100),
               IF(os.estado IN ('finalizada', 'anulada', 'reprogramada'), 0, 1),
               os.id_cliente, os.id_contacto
        FROM   orden_servicio os
        LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
        WHERE  os.tipo = 'OM' AND os.eliminado_en IS NULL
          AND  (p_id_os IS NULL OR os.id_os = p_id_os)
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarInstrumentosRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — apoyo, NO es un endpoint)
-- Con las OM de `tmp_rom_os` (SP_ArmarOmTecnicoMovil) deja en la tabla temporal `tmp_rom_inst` los instrumentos de cada una (os_equipo no eliminados) y si ya fueron
-- RECIBIDOS: UNA sola regla de «instrumento recibido» = tiene una fila no eliminada en om_recepcion_equipo cuya recepción (om_recepcion) tampoco está eliminada.
-- Un instrumento se recibe una sola vez por OM; si hubiera más de una fila se toma la primera.
-- Columnas: id_os · id_os_equipo · id_equipo · numero (1..n dentro de la OM) · nombre · marca · modelo · serie · capacidad · codigo_cliente · codigo_tw ·
--   recibido (0/1) · id_recepcion · id_recepcion_equipo · estado_fisico · observaciones · accesorios (JSON) · fotos (n.º de fotos de la recepción) · recibido_utc.
-- El nombre sale igual que en los objetivos del servicio (suministro → clasificación → «Equipo»).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarInstrumentosRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarInstrumentosRecepcionOmMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    CREATE TEMPORARY TABLE tmp_rom_inst (
        id_os BIGINT NOT NULL,
        id_os_equipo BIGINT NOT NULL,
        id_equipo BIGINT NOT NULL,
        numero INT NOT NULL,
        nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        marca VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        modelo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        capacidad VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_tw VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        recibido TINYINT NOT NULL DEFAULT 0,
        id_recepcion BIGINT NULL,
        id_recepcion_equipo BIGINT NULL,
        estado_fisico VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        observaciones VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        accesorios JSON NULL,
        fotos INT NOT NULL DEFAULT 0,
        recibido_utc DATETIME NULL,
        PRIMARY KEY (id_os_equipo));

    INSERT INTO tmp_rom_inst (id_os, id_os_equipo, id_equipo, numero, nombre, marca, modelo, serie, capacidad, codigo_cliente, codigo_tw,
                              recibido, id_recepcion, id_recepcion_equipo, estado_fisico, observaciones, accesorios, fotos, recibido_utc)
    SELECT oe.id_os, oe.id, oe.id_equipo,
           ROW_NUMBER() OVER (PARTITION BY oe.id_os ORDER BY IFNULL(oe.orden, oe.id), oe.id),
           LEFT(REPLACE(COALESCE(NULLIF(TRIM(su.descripcion), ''), tc.String1, ec.clasificacion, 'Equipo'), '|', ' '), 150),
           ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), ''), NULLIF(TRIM(ec.alcance_maximo), ''), NULLIF(ec.codigo_cliente, ''), ec.codigo_tw,
           IF(re.id_recepcion_equipo IS NULL, 0, 1), re.id_recepcion, re.id_recepcion_equipo, re.estado_fisico, re.observaciones, re.accesorios,
           (SELECT COUNT(*) FROM om_recepcion_foto f WHERE f.id_recepcion_equipo = re.id_recepcion_equipo AND f.eliminado_en IS NULL),
           r.recibido_utc
    FROM   os_equipo oe
    JOIN   tmp_rom_os o ON o.id_os = oe.id_os
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    LEFT JOIN (SELECT x.id_os_equipo, MIN(x.id_recepcion_equipo) AS id_recepcion_equipo
               FROM   om_recepcion_equipo x
               JOIN   om_recepcion xr ON xr.id_recepcion = x.id_recepcion AND xr.eliminado_en IS NULL
               WHERE  x.eliminado_en IS NULL
               GROUP BY x.id_os_equipo) pr ON pr.id_os_equipo = oe.id
    LEFT JOIN om_recepcion_equipo re ON re.id_recepcion_equipo = pr.id_recepcion_equipo
    LEFT JOIN om_recepcion r ON r.id_recepcion = re.id_recepcion
    WHERE  oe.eliminado_en IS NULL;
END$$

DELIMITER ;

-- ============================================================
-- SP_CatalogoAccesoriosRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — apoyo, NO es un endpoint)
-- Catálogo FIJO de accesorios recibidos con un instrumento, UNA sola vez, en la tabla temporal `tmp_rom_acc` (codigo, nombre, orden). Lo usa SP_RegistrarRecepcionOmMovil para validar.
--   caja_original → «Caja original» · adaptador_corriente → «Adaptador de corriente» · protector_plato → «Protector de plato» · manual → «Manual» · otro → «Otro»
-- (La app y el PDF de la constancia muestran las mismas etiquetas: CatalogoRecepcionOm en el back y utilidades/recepcionOm en la app.)
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_rom_acc. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CatalogoAccesoriosRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_CatalogoAccesoriosRecepcionOmMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_acc;
    CREATE TEMPORARY TABLE tmp_rom_acc (
        codigo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        orden INT NOT NULL,
        PRIMARY KEY (codigo));
    INSERT INTO tmp_rom_acc (codigo, nombre, orden) VALUES
        ('caja_original',       'Caja original',          1),
        ('adaptador_corriente', 'Adaptador de corriente', 2),
        ('protector_plato',     'Protector de plato',     3),
        ('manual',              'Manual',                 4),
        ('otro',                'Otro',                   5);
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerRecepcionesOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — lista «Por recibir» y «Recibidos hoy» · lectura)
-- Las OM del técnico de Metrología (SP_ArmarOmTecnicoMovil: técnico principal u os_personal) con el avance de la recepción de sus instrumentos (SP_ArmarInstrumentosRecepcionOmMovil).
--   p_busqueda (opcional, hasta 80 caracteres): filtra por N° de OM, cliente o N° de guía de alguna de sus recepciones.
--   Por recibir  = OM activa con al menos un instrumento pendiente. estado: por_recibir (ninguno recibido) | parcial (ya recibió algunos). Primero las parciales, luego por id descendente.
--   Recibidos hoy = OM con una recepción registrada HOY (día de Lima) por cualquiera de sus técnicos; estado = el de la ÚLTIMA recepción de hoy (conforme | observado | parcial),
--                   hora y guía son los de esa recepción. Orden: hora descendente.
--   hora = HH:mm de Lima de la última recepción de la OM (null si no tiene); guia = su N° de guía; pendientes = nombres de los instrumentos sin recibir (hasta 5, separados por «|»).
--   Máximo 50 por lista.
-- Resultados: 1 mensaje · 2 Por recibir · 3 Recibidos hoy (mismas columnas). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRecepcionesOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRecepcionesOmMovil(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_b       VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_like    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ini_utc DATETIME;
    DECLARE v_fin_utc DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_res;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_b = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');
    IF CHAR_LENGTH(IFNULL(v_b, '')) > 80 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda puede tener hasta 80 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_b IS NOT NULL THEN
        SET v_like = CONCAT('%', REPLACE(REPLACE(REPLACE(v_b, '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;

    -- Hoy en Lima (UTC-5, sin horario de verano) expresado en UTC
    SET v_ini_utc = TIMESTAMP(DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'))) + INTERVAL 5 HOUR;
    SET v_fin_utc = v_ini_utc + INTERVAL 1 DAY;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, NULL);
    CALL SP_ArmarInstrumentosRecepcionOmMovil();

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_res;
    CREATE TEMPORARY TABLE tmp_rom_res (
        id_os BIGINT NOT NULL,
        numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        cliente VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        activa TINYINT NOT NULL,
        total INT NOT NULL DEFAULT 0,
        recibidos INT NOT NULL DEFAULT 0,
        pendientes TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        ult_utc DATETIME NULL, ult_guia VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        hoy_utc DATETIME NULL, hoy_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, hoy_guia VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id_os));

    INSERT INTO tmp_rom_res (id_os, numero, cliente, numero_rq, servicio, activa)
    SELECT o.id_os, o.numero, o.cliente, o.numero_rq, o.servicio, o.activa FROM tmp_rom_os o;

    -- Avance de la recepción por OM
    UPDATE tmp_rom_res r
    JOIN  (SELECT i.id_os, COUNT(*) AS total, SUM(i.recibido) AS recibidos FROM tmp_rom_inst i GROUP BY i.id_os) x ON x.id_os = r.id_os
    SET    r.total = x.total, r.recibidos = x.recibidos;

    UPDATE tmp_rom_res r
    JOIN  (SELECT i.id_os, SUBSTRING_INDEX(GROUP_CONCAT(CONCAT_WS(' ', i.nombre, i.marca, i.modelo) ORDER BY i.numero SEPARATOR '|'), '|', 5) AS nombres
           FROM   tmp_rom_inst i WHERE i.recibido = 0 GROUP BY i.id_os) x ON x.id_os = r.id_os
    SET    r.pendientes = x.nombres;

    -- Última recepción de cada OM, y la última de HOY
    UPDATE tmp_rom_res r
    JOIN  (SELECT q.id_os, q.recibido_utc, q.numero_guia
           FROM   om_recepcion q
           WHERE  q.eliminado_en IS NULL
             AND  q.id_recepcion = (SELECT MAX(y.id_recepcion) FROM om_recepcion y WHERE y.id_os = q.id_os AND y.eliminado_en IS NULL)) x ON x.id_os = r.id_os
    SET    r.ult_utc = x.recibido_utc, r.ult_guia = x.numero_guia;

    UPDATE tmp_rom_res r
    JOIN  (SELECT q.id_os, q.recibido_utc, q.estado, q.numero_guia
           FROM   om_recepcion q
           WHERE  q.eliminado_en IS NULL AND q.recibido_utc >= v_ini_utc AND q.recibido_utc < v_fin_utc
             AND  q.id_recepcion = (SELECT MAX(y.id_recepcion) FROM om_recepcion y
                                    WHERE y.id_os = q.id_os AND y.eliminado_en IS NULL AND y.recibido_utc >= v_ini_utc AND y.recibido_utc < v_fin_utc)) x ON x.id_os = r.id_os
    SET    r.hoy_utc = x.recibido_utc, r.hoy_estado = x.estado, r.hoy_guia = x.numero_guia;

    IF v_like IS NOT NULL THEN
        DELETE FROM tmp_rom_res
        WHERE  NOT (numero LIKE v_like OR IFNULL(cliente, '') LIKE v_like
                    OR EXISTS (SELECT 1 FROM om_recepcion g WHERE g.id_os = tmp_rom_res.id_os AND g.eliminado_en IS NULL AND g.numero_guia LIKE v_like));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Por recibir (parciales primero)
    SELECT r.id_os, r.numero, r.cliente, r.numero_rq, r.servicio, r.total AS total_instrumentos, r.recibidos,
           IF(r.recibidos = 0, 'por_recibir', 'parcial') AS estado,
           DATE_FORMAT(CONVERT_TZ(r.ult_utc, '+00:00', '-05:00'), '%H:%i') AS hora, r.ult_guia AS guia, r.pendientes
    FROM   tmp_rom_res r
    WHERE  r.activa = 1 AND r.recibidos < r.total
    ORDER BY (r.recibidos > 0) DESC, r.id_os DESC
    LIMIT 50;

    -- 3. Recibidos hoy
    SELECT r.id_os, r.numero, r.cliente, r.numero_rq, r.servicio, r.total AS total_instrumentos, r.recibidos,
           r.hoy_estado AS estado,
           DATE_FORMAT(CONVERT_TZ(r.hoy_utc, '+00:00', '-05:00'), '%H:%i') AS hora, r.hoy_guia AS guia, r.pendientes
    FROM   tmp_rom_res r
    WHERE  r.hoy_utc IS NOT NULL
    ORDER BY r.hoy_utc DESC, r.id_os DESC
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_res;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — detalle de una OM · lectura)
-- Resumen de la OM, sus instrumentos (recibidos o pendientes) y las recepciones ya registradas. La OM debe ser del técnico (SP_ArmarOmTecnicoMovil); misma respuesta si no existe o no es suya.
--   cabecera.estado: por_recibir (ningún instrumento recibido) · parcial (faltan instrumentos) · observado (todos recibidos y alguno con estado físico observado) · conforme.
--   cabecera.puede_recibir = la OM está activa (no finalizada / anulada / reprogramada) y quedan instrumentos pendientes.
--   Instrumentos: numero 1..n, estado_fisico / observaciones / fotos / recibido_en (hora de Lima 'yyyy-MM-dd HH:mm') solo si ya se recibió.
--   Recepciones: de la más reciente a la más antigua; recibio = nombre del técnico; instrumentos = cuántos se recibieron en esa recepción; tiene_constancia = ya hay PDF.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 instrumentos · 4 recepciones. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRecepcionOmMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_total   INT DEFAULT 0;
    DECLARE v_recib   INT DEFAULT 0;
    DECLARE v_obs     INT DEFAULT 0;
    DECLARE v_activa  TINYINT DEFAULT 0;
    DECLARE v_existe  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*), IFNULL(MAX(o.activa), 0) INTO v_existe, v_activa FROM tmp_rom_os o;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    SELECT COUNT(*), IFNULL(SUM(i.recibido), 0), IFNULL(SUM(i.recibido = 1 AND i.estado_fisico = 'observado'), 0) INTO v_total, v_recib, v_obs FROM tmp_rom_inst i;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT o.id_os, o.numero, o.cliente, o.numero_rq, o.servicio, v_total AS total_instrumentos, v_recib AS recibidos,
           IF(v_activa = 1 AND v_recib < v_total, 1, 0) AS puede_recibir,
           CASE WHEN v_recib = 0 THEN 'por_recibir' WHEN v_recib < v_total THEN 'parcial' WHEN v_obs > 0 THEN 'observado' ELSE 'conforme' END AS estado
    FROM   tmp_rom_os o;

    -- 3. Instrumentos
    SELECT i.id_os_equipo, i.numero, i.nombre, i.marca, i.modelo, i.serie, i.capacidad, i.codigo_cliente, i.codigo_tw,
           i.recibido, i.estado_fisico, i.observaciones, i.fotos,
           DATE_FORMAT(CONVERT_TZ(i.recibido_utc, '+00:00', '-05:00'), '%Y-%m-%d %H:%i') AS recibido_en
    FROM   tmp_rom_inst i
    ORDER BY i.numero;

    -- 4. Recepciones registradas
    SELECT r.id_recepcion, r.numero_guia AS guia, r.medio_entrega AS medio, r.entrego_nombre AS entrego, r.entrego_cargo AS entrego_cargo,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS recibio,
           DATE_FORMAT(CONVERT_TZ(r.recibido_utc, '+00:00', '-05:00'), '%Y-%m-%d %H:%i') AS fecha,
           r.estado, r.motivo_parcial,
           (SELECT COUNT(*) FROM om_recepcion_equipo e WHERE e.id_recepcion = r.id_recepcion AND e.eliminado_en IS NULL) AS instrumentos,
           IF(r.ruta_constancia IS NULL, 0, 1) AS tiene_constancia
    FROM   om_recepcion r
    LEFT JOIN usuario u ON u.id_usuario = r.id_usuario_recibio
    WHERE  r.id_os = p_id_os AND r.eliminado_en IS NULL
    ORDER BY r.id_recepcion DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarFotoRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — guarda una foto de recepción (solo cámara) · escritura)
-- El técnico sube una foto de un instrumento ANTES de registrar la recepción. Queda «pendiente» (id_recepcion_equipo NULL) y se liga al registrar la recepción.
--   - La OM debe ser del técnico y estar activa (SP_ArmarOmTecnicoMovil); el instrumento debe ser de esa OM y seguir pendiente de recibir (SP_ArmarInstrumentosRecepcionOmMovil).
--   - Máximo 8 fotos pendientes por instrumento y por técnico. Sin IA.
--   - p_ruta: ruta ya guardada por el back en el almacén (recepcion-om/{idOs}/{idOsEquipo}/….jpg).
-- Resultados: 1 mensaje; 2 (id_foto, orden = n.º de fotos pendientes del instrumento, 1..8).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarFotoRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarFotoRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_ruta         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_activa   TINYINT DEFAULT 0;
    DECLARE v_oe       BIGINT DEFAULT NULL;
    DECLARE v_recibido TINYINT DEFAULT 0;
    DECLARE v_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_id       BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Instrumento no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL OR CHAR_LENGTH(p_ruta) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la foto.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*), IFNULL(MAX(o.activa), 0) INTO v_existe, v_activa FROM tmp_rom_os o;
    IF v_existe = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_activa = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'La orden ya no está activa: no se pueden registrar fotos de recepción.' AS Mensaje; LEAVE proc;
    END IF;

    -- Se bloquea el instrumento: dos subidas a la vez no pasan del tope de 8
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    IF v_oe IS NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'El instrumento no pertenece a esta orden.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    SELECT i.recibido, CONCAT_WS(' ', i.nombre, i.marca, i.modelo) INTO v_recibido, v_nombre FROM tmp_rom_inst i WHERE i.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    IF v_recibido = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(IFNULL(v_nombre, 'El instrumento'), ' ya se recibió: no admite más fotos de recepción.') AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_n
    FROM   om_recepcion_foto f
    WHERE  f.id_os_equipo = p_id_os_equipo AND f.id_usuario = p_id_usuario AND f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL;
    IF v_n >= 8 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Un instrumento admite hasta 8 fotos de recepción. Quita alguna para tomar otra.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO om_recepcion_foto (id_os_equipo, id_usuario, orden, ruta) VALUES (p_id_os_equipo, p_id_usuario, v_n + 1, TRIM(p_ruta));
    SET v_id = LAST_INSERT_ID();

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto guardada.' AS Mensaje;
    SELECT v_id AS id_foto, v_n + 1 AS orden;
END$$

DELIMITER ;

-- ============================================================
-- SP_QuitarFotoRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — quita una foto de recepción aún NO registrada · escritura)
-- El técnico quita una de sus fotos pendientes de un instrumento (id_recepcion_equipo NULL): borrado lógico y las que quedan se renumeran 1..n. Una foto ya ligada a una
-- recepción registrada no se puede quitar. La OM debe ser del técnico (SP_ArmarOmTecnicoMovil).
-- Resultados: 1 mensaje; 2 (ruta = archivo de la foto, para que el back lo borre del almacén). Deja el archivo si el SP falla.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_QuitarFotoRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_QuitarFotoRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_foto      BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_foto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    IF v_existe = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.ruta INTO v_ruta
    FROM   om_recepcion_foto f
    JOIN   os_equipo oe ON oe.id = f.id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    WHERE  f.id_foto = p_id_foto AND f.id_os_equipo = p_id_os_equipo AND f.id_usuario = p_id_usuario
      AND  f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL
    FOR UPDATE;
    IF v_ruta IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La foto no existe o ya forma parte de una recepción registrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE om_recepcion_foto SET eliminado_en = NOW() WHERE id_foto = p_id_foto;

    -- Las que quedan se renumeran 1..n (el n.º de foto es siempre el de la lista)
    UPDATE om_recepcion_foto f
    JOIN  (SELECT x.id_foto, ROW_NUMBER() OVER (ORDER BY x.orden, x.id_foto) AS rn
           FROM   om_recepcion_foto x
           WHERE  x.id_os_equipo = p_id_os_equipo AND x.id_usuario = p_id_usuario AND x.id_recepcion_equipo IS NULL AND x.eliminado_en IS NULL) n ON n.id_foto = f.id_foto
    SET    f.orden = n.rn;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto quitada.' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerFotosRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — fotos pendientes de un instrumento · lectura)
-- Las fotos de recepción que el técnico del token ya subió para un instrumento y que aún NO están ligadas a una recepción registrada (para reanudar si cerró la pantalla a medias).
-- La OM debe ser del técnico (SP_ArmarOmTecnicoMovil) y el instrumento de esa OM.
-- Resultados: 1 mensaje · 2 (id_foto, orden) de la 1 a la 8. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFotosRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFotosRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Instrumento no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El instrumento no pertenece a esta orden.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT f.id_foto, f.orden
    FROM   om_recepcion_foto f
    WHERE  f.id_os_equipo = p_id_os_equipo AND f.id_usuario = p_id_usuario AND f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL
    ORDER BY f.orden, f.id_foto
    LIMIT 8;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerArchivoFotoRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — ruta del archivo de una foto de recepción · lectura)
-- Devuelve la ruta de una foto SOLO si la OM del instrumento es del técnico (SP_ArmarOmTecnicoMovil) y, además:
--   · la foto aún no está registrada y es del propio técnico, o
--   · la foto ya forma parte de una recepción registrada de esa OM (la puede ver cualquier técnico asignado a la OM).
-- Misma respuesta si no existe o no es suya.
-- Resultados: 1 mensaje; 2 (ruta). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoFotoRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoFotoRecepcionOmMovil(
    IN p_id_usuario BIGINT,
    IN p_id_foto    BIGINT
)
proc: BEGIN
    DECLARE v_os        BIGINT DEFAULT NULL;
    DECLARE v_ruta      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dueno     BIGINT DEFAULT NULL;
    DECLARE v_pendiente TINYINT DEFAULT 0;
    DECLARE v_existe    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_foto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_os, f.ruta, f.id_usuario, IF(f.id_recepcion_equipo IS NULL, 1, 0) INTO v_os, v_ruta, v_dueno, v_pendiente
    FROM   om_recepcion_foto f
    JOIN   os_equipo oe ON oe.id = f.id_os_equipo AND oe.eliminado_en IS NULL
    WHERE  f.id_foto = p_id_foto AND f.eliminado_en IS NULL;

    IF v_os IS NOT NULL THEN
        CALL SP_ArmarOmTecnicoMovil(p_id_usuario, v_os);
        SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    END IF;

    IF v_os IS NULL OR v_existe = 0 OR (v_pendiente = 1 AND v_dueno <> p_id_usuario) THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;

-- ============================================================
-- SP_BuscarInstrumentoQrRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — «Escanear etiqueta del instrumento» · lectura)
-- Resuelve el texto leído por la cámara (QR, N/S, código del cliente o COD TW) al instrumento de ESTA OM. Mismas reglas de coincidencia que la búsqueda por QR de la HU-07 / el
-- registro fotográfico: coincidencia exacta (sin distinguir mayúsculas) con N/S, código del cliente o COD TW; o un texto más largo (una URL) que contenga el COD TW o el código del
-- cliente (de 5 o más caracteres); o una etiqueta QR de TW (SP_NormalizarQrMovil) ya vinculada a un equipo de la OM (equipo_qr). NO exige llegada: el instrumento está en el taller.
--   La OM debe ser del técnico (SP_ArmarOmTecnicoMovil). Si hay varios que coinciden se prefiere el que aún está pendiente.
--   Si el instrumento ya se recibió responde la regla de negocio indicando cuándo.
-- Resultados: 1 mensaje; 2 (id_os_equipo, nombre). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_BuscarInstrumentoQrRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_BuscarInstrumentoQrRecepcionOmMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_texto      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_t        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe       BIGINT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(320) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_recibido TINYINT DEFAULT 0;
    DECLARE v_cuando   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_t = UPPER(TRIM(IFNULL(p_texto, '')));
    IF v_t = '' OR CHAR_LENGTH(v_t) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El código leído no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    CALL SP_NormalizarQrMovil(p_texto, v_clave);

    SELECT i.id_os_equipo, CONCAT_WS(' ', i.nombre, i.marca, i.modelo), i.recibido,
           DATE_FORMAT(CONVERT_TZ(i.recibido_utc, '+00:00', '-05:00'), '%d/%m a las %H:%i')
    INTO   v_oe, v_nombre, v_recibido, v_cuando
    FROM   tmp_rom_inst i
    WHERE  UPPER(IFNULL(i.serie, '')) = v_t OR UPPER(IFNULL(i.codigo_cliente, '')) = v_t OR UPPER(IFNULL(i.codigo_tw, '')) = v_t
        OR (CHAR_LENGTH(IFNULL(i.codigo_tw, '')) >= 5 AND LOCATE(UPPER(i.codigo_tw), v_t) > 0)
        OR (CHAR_LENGTH(IFNULL(i.codigo_cliente, '')) >= 5 AND LOCATE(UPPER(i.codigo_cliente), v_t) > 0)
        OR (v_clave IS NOT NULL AND i.id_equipo IN (SELECT q.id_equipo FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL))
    ORDER BY i.recibido, i.numero
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;

    IF v_oe IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El código leído no corresponde a ningún instrumento de esta orden.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_recibido = 1 THEN
        SELECT 1 AS IdTipoMensaje, CONCAT(v_nombre, ' ya se recibió el ', v_cuando, '.') AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_oe AS id_os_equipo, v_nombre AS nombre;
END$$

DELIMITER ;

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

-- ============================================================
-- SP_ObtenerConstanciaRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — datos de la constancia de recepción · lectura)
-- Todo lo que necesita el PDF de la constancia de UNA recepción registrada: la OM, el cliente y su contacto, la trazabilidad de entrega, los instrumentos recibidos en ESA recepción y los
-- que seguían pendientes cuando se registró. La OM de la recepción debe ser del técnico (SP_ArmarOmTecnicoMovil); misma respuesta si no existe o no es suya.
--   cabecera: id_recepcion · numero_om · cliente · direccion · contacto_nombre · contacto_correo · numero_rq · guia · medio · entrego · entrego_cargo · recibio · recibido_en (Lima 'yyyy-MM-dd HH:mm') ·
--             estado · motivo_parcial · firma_trazos (JSON) · ruta_constancia · correo_enviado · envio_activo (parámetro CONSTANCIA_ENVIO_CORREO = 1: el caso de uso envía la constancia al contacto).
--   instrumentos (de esta recepción): nombre · marca · modelo · serie · codigo · estado_fisico · observaciones · accesorios (JSON con los códigos) · fotos.
--   pendientes: instrumentos de la OM que aún no estaban recibidos al registrar esta recepción (nombre, marca, modelo, serie, codigo).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 instrumentos · 4 pendientes. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConstanciaRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConstanciaRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_recepcion BIGINT
)
proc: BEGIN
    DECLARE v_os     BIGINT DEFAULT NULL;
    DECLARE v_existe INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_recepcion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Constancia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT r.id_os INTO v_os FROM om_recepcion r WHERE r.id_recepcion = p_id_recepcion AND r.eliminado_en IS NULL;
    IF v_os IS NOT NULL THEN
        CALL SP_ArmarOmTecnicoMovil(p_id_usuario, v_os);
        SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    END IF;
    IF v_os IS NULL OR v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Constancia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT r.id_recepcion, o.numero AS numero_om, o.cliente, c.direccion_fiscal AS direccion,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.correo), '') AS contacto_correo, o.numero_rq,
           r.numero_guia AS guia, r.medio_entrega AS medio, r.entrego_nombre AS entrego, r.entrego_cargo,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS recibio,
           DATE_FORMAT(CONVERT_TZ(r.recibido_utc, '+00:00', '-05:00'), '%Y-%m-%d %H:%i') AS recibido_en,
           r.estado, r.motivo_parcial, CAST(r.firma_trazos AS CHAR) AS firma_trazos, r.ruta_constancia, r.correo_enviado,
           IF(IFNULL((SELECT MAX(m.Num2) FROM tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CONSTANCIA_ENVIO_CORREO' AND m.eliminado_en IS NULL), 0) = 1, 1, 0) AS envio_activo
    FROM   om_recepcion r
    JOIN   tmp_rom_os o ON o.id_os = r.id_os
    LEFT JOIN cliente c ON c.id_cliente = o.id_cliente
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = o.id_contacto AND cc.SoftDelete = 0
    LEFT JOIN usuario u ON u.id_usuario = r.id_usuario_recibio
    WHERE  r.id_recepcion = p_id_recepcion;

    -- 3. Instrumentos recibidos en esta recepción
    SELECT i.nombre, i.marca, i.modelo, i.serie, COALESCE(i.codigo_cliente, i.codigo_tw) AS codigo,
           i.estado_fisico, i.observaciones, CAST(i.accesorios AS CHAR) AS accesorios, i.fotos
    FROM   tmp_rom_inst i
    WHERE  i.id_recepcion = p_id_recepcion
    ORDER BY i.numero;

    -- 4. Pendientes al registrar esta recepción
    SELECT i.nombre, i.marca, i.modelo, i.serie, COALESCE(i.codigo_cliente, i.codigo_tw) AS codigo
    FROM   tmp_rom_inst i
    WHERE  i.id_recepcion IS NULL OR i.id_recepcion > p_id_recepcion
    ORDER BY i.numero;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
END$$

DELIMITER ;

-- ============================================================
-- SP_GuardarConstanciaRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — guarda la ruta del PDF de la constancia y si se envió por correo · escritura)
-- El back genera el PDF al registrar la recepción (o lo vuelve a generar si el archivo ya no está) y guarda aquí su ruta en el almacén y si se envió al contacto del cliente.
-- La OM de la recepción debe ser del técnico (SP_ArmarOmTecnicoMovil).
-- Resultados: 1 mensaje; 2 (ruta_anterior = el PDF que reemplaza, para que el back lo borre del almacén; NULL si no había).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarConstanciaRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarConstanciaRecepcionOmMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_recepcion   BIGINT,
    IN p_ruta           VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_correo_enviado TINYINT
)
proc: BEGIN
    DECLARE v_os       BIGINT DEFAULT NULL;
    DECLARE v_anterior VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_existe   INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_recepcion, 0) <= 0 OR NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL OR CHAR_LENGTH(p_ruta) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'Constancia no válida.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT r.id_os, r.ruta_constancia INTO v_os, v_anterior FROM om_recepcion r WHERE r.id_recepcion = p_id_recepcion AND r.eliminado_en IS NULL FOR UPDATE;
    IF v_os IS NOT NULL THEN
        CALL SP_ArmarOmTecnicoMovil(p_id_usuario, v_os);
        SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    END IF;
    IF v_os IS NULL OR v_existe = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Constancia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE om_recepcion
    SET    ruta_constancia = TRIM(p_ruta), correo_enviado = IF(IFNULL(p_correo_enviado, 0) = 1, 1, 0), modificado_por = p_id_usuario
    WHERE  id_recepcion = p_id_recepcion;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Constancia guardada.' AS Mensaje;
    SELECT IF(v_anterior = TRIM(p_ruta), NULL, v_anterior) AS ruta_anterior;
END$$

DELIMITER ;

-- ============================================================
-- VERIFICACIÓN (solo lectura: no crea datos)
-- ============================================================
SELECT 'Tablas de la recepción (deben ser 3)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('om_recepcion', 'om_recepcion_equipo', 'om_recepcion_foto')) AS valor
UNION ALL
SELECT 'Procedimientos de la recepción (deben ser 13)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE' AND ROUTINE_NAME IN ('SP_ArmarOmTecnicoMovil', 'SP_ArmarInstrumentosRecepcionOmMovil', 'SP_CatalogoAccesoriosRecepcionOmMovil', 'SP_ObtenerRecepcionesOmMovil', 'SP_ObtenerRecepcionOmMovil', 'SP_RegistrarFotoRecepcionOmMovil', 'SP_QuitarFotoRecepcionOmMovil', 'SP_ObtenerFotosRecepcionOmMovil', 'SP_ObtenerArchivoFotoRecepcionOmMovil', 'SP_BuscarInstrumentoQrRecepcionOmMovil', 'SP_RegistrarRecepcionOmMovil', 'SP_ObtenerConstanciaRecepcionOmMovil', 'SP_GuardarConstanciaRecepcionOmMovil'))
UNION ALL
SELECT 'Registrar usa el acceso y los instrumentos de apoyo (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_RegistrarRecepcionOmMovil'
          AND ROUTINE_DEFINITION LIKE '%SP_ArmarOmTecnicoMovil%' AND ROUTINE_DEFINITION LIKE '%SP_ArmarInstrumentosRecepcionOmMovil%')
UNION ALL
SELECT 'Requisitos previos: SP_NormalizarQrMovil, SP_ArmarAprobadoresOsMovil (deben ser 2)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE' AND ROUTINE_NAME IN ('SP_NormalizarQrMovil', 'SP_ArmarAprobadoresOsMovil'))
UNION ALL
SELECT 'Requisito previo: FN_PermisoAccion (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'FUNCTION' AND ROUTINE_NAME = 'FN_PermisoAccion');
