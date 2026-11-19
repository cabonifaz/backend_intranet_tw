-- ============================================================
-- SP_ObtenerViaticoServicioEquipoMovil  (App Mobile HU-35 — detalle de los viáticos y gastos de UN servicio del equipo · lectura)
-- Por técnico: lo asignado por concepto (con su estado de depósito), lo rendido y lo que espera su decisión; y los gastos rendidos con su estado y la lectura de la IA del comprobante.
-- Acceso: prog_bandeja y el servicio dentro del alcance de la app (SP_ArmarAlcanceViaticosMovil). Un servicio fuera del alcance se responde como si no existiera.
-- Mismas definiciones que HU-45 (SP_ArmarViaticosOs). por_revisar = gastos en estado 'pendiente' (los que espera el jefe).
-- puede_asignar / motivo_no_asignar: las mismas condiciones con las que SP_GuardarViaticosProgramacion acepta o rechaza (prog_aprobar_reprogramacion, programación confirmada,
--   rendición abierta y servicio sin salir a campo); allí se vuelven a validar al guardar. version = huella de la asignación (SP_VersionViaticosProgramacion) que debe enviarse al asignar.
-- clave del concepto: movilidad | alimentacion | alojamiento (los conceptos fijos del catálogo CONCEPTO_GASTO) u otros (cualquier otro concepto).
-- Resultados: 1 mensaje · 2 cabecera · 3 técnicos · 4 líneas asignadas · 5 gastos rendidos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerViaticoServicioEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticoServicioEquipoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_sin       TINYINT DEFAULT 0;
    DECLARE v_prog      BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_pr VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cerrada   TINYINT DEFAULT 0;
    DECLARE v_jefe      TINYINT DEFAULT 0;
    DECLARE v_puede     TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_version   VARCHAR(80);
    DECLARE v_asignado  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_deposit   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rendido   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_revisar   DECIMAL(12,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los viáticos del equipo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, p_id_os, v_sin);
    IF v_sin = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tmp_vi_alc WHERE id_os = p_id_os) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no tiene programación o no pertenece a tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;

    SELECT MAX(p2.id_programacion) INTO v_prog
    FROM programacion p2 WHERE p2.id_os = p_id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL;

    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), os.estado
      INTO v_numero, v_cliente, v_estado_os
    FROM orden_servicio os LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    WHERE os.id_os = p_id_os;
    SELECT pr.estado INTO v_estado_pr FROM programacion pr WHERE pr.id_programacion = v_prog;
    SET v_cerrada = IF(EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL), 1, 0);
    SET v_jefe    = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');

    IF v_jefe = 0 THEN
        SET v_motivo = 'Solo el Jefe de Operaciones puede asignar viáticos y revisar gastos.';
    ELSEIF IFNULL(v_estado_os, '') IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada') THEN
        SET v_motivo = 'La asignación ya no se puede editar: el servicio salió a campo.';
    ELSEIF IFNULL(v_estado_pr, '') <> 'confirmada' THEN
        SET v_motivo = 'La programación aún no está confirmada por el cliente: los viáticos se asignan cuando está Programado.';
    ELSEIF v_cerrada = 1 THEN
        SET v_motivo = 'La rendición ya fue cerrada: los viáticos quedan solo de lectura.';
    END IF;
    SET v_puede = IF(v_motivo IS NULL, 1, 0);

    CALL SP_VersionViaticosProgramacion(v_prog, p_id_os, 1, v_version);

    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0)
      INTO v_asignado, v_deposit
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));
    SELECT IFNULL(SUM(IF(g.estado <> 'rechazado', g.monto, 0)), 0), IFNULL(SUM(IF(g.estado = 'pendiente', g.monto, 0)), 0)
      INTO v_rendido, v_revisar
    FROM gasto_viatico g
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 Cabecera
    SELECT p_id_os AS id_os, v_numero AS numero_os, v_cliente AS cliente, v_prog AS id_programacion, v_cerrada AS cerrada,
           v_puede AS puede_asignar, v_motivo AS motivo_no_asignar, v_version AS version,
           v_asignado AS asignado, v_deposit AS depositado, v_rendido AS rendido, v_revisar AS por_revisar;

    -- 3 Técnicos del servicio (el principal primero) con sus montos
    SELECT pt.id_usuario AS id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS nombre,
           IF(pt.rol = 'principal', 1, 0) AS principal,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS asignado,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario AND g.estado IN ('aprobado', 'rendido')
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS depositado,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario AND g.estado <> 'rechazado'
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS rendido,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario AND g.estado = 'pendiente'
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS por_revisar
    FROM   programacion_tecnico pt
    JOIN   usuario u ON u.id_usuario = pt.id_usuario
    WHERE  pt.id_programacion = v_prog AND pt.eliminado_en IS NULL
    ORDER BY IF(pt.rol = 'principal', 0, 1), u.nombre, pt.id_usuario;

    -- 4 Líneas asignadas por técnico y concepto
    SELECT g.id_gasto, g.id_usuario AS id_tecnico, IFNULL(cg.String1, 'Concepto') AS concepto,
           CASE UPPER(IFNULL(cg.String3, '')) WHEN 'MOVILIDAD' THEN 'movilidad' WHEN 'ALIMENTACION' THEN 'alimentacion'
                                              WHEN 'ALOJAMIENTO' THEN 'alojamiento' ELSE 'otros' END AS clave,
           g.monto, IF(g.estado IN ('aprobado', 'rendido'), 1, 0) AS depositado
    FROM   gasto_viatico g
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE  g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ORDER BY g.id_usuario, g.id_gasto;

    -- 5 Gastos rendidos (con el comprobante y la lectura de la IA)
    SELECT g.id_gasto, g.id_usuario AS id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS tecnico,
           IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, CONCAT('Otro: ', g.concepto_texto), IFNULL(cg.String1, 'Concepto')) AS concepto,
           g.monto, g.estado, DATE_FORMAT(COALESCE(g.fecha_gasto, g.fecha_solicitud), '%Y-%m-%d') AS fecha,
           IF(GREATEST((SELECT COUNT(*) FROM gasto_viatico_foto f WHERE f.id_gasto = g.id_gasto AND f.eliminado_en IS NULL),
                       IF(NULLIF(TRIM(IFNULL(g.url_comprobante, '')), '') IS NULL, 0, 1)) > 0, 1, 0) AS tiene_comprobante,
           g.monto_ia, g.coincide_ia
    FROM   gasto_viatico g
    JOIN   usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE  g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ORDER BY COALESCE(g.fecha_gasto, g.fecha_solicitud), g.id_gasto;
END$$

DELIMITER ;
