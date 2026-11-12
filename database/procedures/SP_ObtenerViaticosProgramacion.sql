-- HU-45 (Sprint 5) Modal "Gestión de Viáticos" de una programación: pestaña 1 Asignación de Viáticos y pestaña 2 Rendición de Gastos.
-- Acceso: prog_bandeja (solo lectura: también es la referencia de la pestaña Programación del detalle de la OS y del Expediente Digital).
-- Operar (guardar, revisar gastos, cerrar) lo hace solo el Jefe (prog_aprobar_reprogramacion) y con la programación CONFIRMADA (Programado).
--   Un viático asignado en estado 'aprobado' es DEPOSITADO (lo marca Contabilidad fuera de este módulo); cualquier otro = pendiente de depósito.
-- Resultados: 1 mensaje, 2 cabecera, 3 técnicos (subtotal, rendido y saldo), 4 conceptos del catálogo, 5 líneas de la asignación,
--   6 totales de la asignación, 7 gastos rendidos, 8 tarjetas de la rendición, 9 cierre (0 o 1 fila).
DROP PROCEDURE IF EXISTS SP_ObtenerViaticosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticosProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT
)
proc: BEGIN
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_codigo    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado    VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vigente   TINYINT DEFAULT 0;
    DECLARE v_cerrada   TINYINT DEFAULT 0;
    DECLARE v_jefe      TINYINT DEFAULT 0;
    DECLARE v_gestiona  TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_version   VARCHAR(80);
    DECLARE v_pend_not  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_n_pend_not INT DEFAULT 0;
    DECLARE v_en_campo  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los viáticos de la programación.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os, codigo, estado INTO v_id_os, v_codigo, v_estado
    FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_vigente = IF(v_estado <> 'cancelada', 1, 0);
    -- El servicio ya salió a campo: la asignación queda congelada (los gastos se siguen revisando)
    SELECT IF(estado IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada'), 1, 0) INTO v_en_campo
    FROM orden_servicio WHERE id_os = v_id_os;
    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_cerrada FROM programacion_rendicion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    SET v_jefe     = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');
    SET v_gestiona = IF(v_jefe = 1 AND v_estado = 'confirmada' AND v_cerrada = 0, 1, 0);
    SET v_motivo = CASE WHEN v_jefe = 0 THEN 'Solo el Jefe de Operaciones gestiona los viáticos.'
                        WHEN v_estado = 'cancelada' THEN 'La programación está cancelada.'
                        WHEN v_estado <> 'confirmada' THEN 'La programación aún no está confirmada por el cliente.'
                        WHEN v_cerrada = 1 THEN 'La rendición ya fue cerrada: los viáticos y gastos quedan solo de lectura.'
                        ELSE NULL END;

    CALL SP_VersionViaticosProgramacion(p_id_programacion, v_id_os, v_vigente, v_version);

    SELECT IFNULL(SUM(g.monto), 0), COUNT(*) INTO v_pend_not, v_n_pend_not
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT p.id_programacion, p.codigo, p.estado,
           CASE p.estado WHEN 'confirmada' THEN 'Programado' WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente' ELSE 'Cancelada' END AS estado_label,
           os.id_os, os.numero AS numero_os, os.tipo, c.razon_social, p.fecha_ejecucion,
           TIME_FORMAT(p.hora_inicio, '%H:%i') AS hora_inicio, TIME_FORMAT(p.hora_fin_estimada, '%H:%i') AS hora_fin,
           p.id_tecnico_principal, TRIM(CONCAT(tp.nombre, ' ', tp.apellido)) AS tecnico_principal, COALESCE(cg.String1, tp.cargo) AS cargo_principal,
           v_gestiona AS puede_gestionar, v_motivo AS motivo_no_gestionar, v_cerrada AS rendicion_cerrada,
           v_version AS version, 'S/' AS moneda,
           IF(v_gestiona = 1 AND v_en_campo = 0, 1, 0) AS puede_editar_asignacion,
           IF(v_en_campo = 1, 'La asignación ya no se puede editar: el servicio salió a campo.', NULL) AS motivo_no_editar_asignacion
    FROM programacion p
    JOIN orden_servicio os ON os.id_os = p.id_os
    LEFT JOIN cliente c    ON c.id_cliente = os.id_cliente
    LEFT JOIN usuario tp   ON tp.id_usuario = p.id_tecnico_principal
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = tp.cargo
    WHERE p.id_programacion = p_id_programacion;

    -- 3. Técnicos: el personal de la programación y quienes ya tienen viáticos o gastos (aunque hoy no estén asignados)
    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre, COALESCE(cg.String1, u.cargo) AS cargo,
           IFNULL(pt.rol, 'apoyo') AS rol, IF(pt.id_usuario IS NULL, 0, 1) AS vigente,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = u.id_usuario
                     AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1))), 0) AS subtotal_asignado,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g WHERE g.tipo = 'gasto_solicitado' AND g.estado = 'aprobado' AND g.eliminado_en IS NULL AND g.id_usuario = u.id_usuario
                     AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1))), 0) AS rendido_aprobado
    FROM usuario u
    LEFT JOIN programacion_tecnico pt ON pt.id_programacion = p_id_programacion AND pt.id_usuario = u.id_usuario AND pt.eliminado_en IS NULL
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    WHERE u.eliminado_en IS NULL
      AND (pt.id_usuario IS NOT NULL
           OR EXISTS (SELECT 1 FROM gasto_viatico g WHERE g.eliminado_en IS NULL AND g.id_usuario = u.id_usuario
                        AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1))))
    ORDER BY IF(pt.rol = 'principal', 0, 1), u.nombre, u.id_usuario;

    -- 4. Conceptos del catálogo
    SELECT t.Num1 AS id_concepto, t.String1 AS nombre, t.String2 AS categoria, IF(t.String3 LIKE 'PERS\_%', 1, 0) AS personalizado
    FROM tabla_maestra t
    WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL
    ORDER BY IF(t.String2 = 'viatico', 0, 1), t.Num1;

    -- 5. Líneas de la asignación
    SELECT g.id_gasto, g.id_usuario AS id_tecnico, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico, IFNULL(pt.rol, 'apoyo') AS rol,
           g.id_concepto, IFNULL(cg.String1, 'Concepto') AS concepto, g.monto,
           IF(g.estado IN ('aprobado', 'rendido'), 'depositado', 'pendiente') AS estado_deposito,
           g.fecha_deposito, IF(g.notificado_en IS NULL, 0, 1) AS notificado,
           IF(v_gestiona = 1 AND v_en_campo = 0 AND g.estado NOT IN ('aprobado', 'rendido'), 1, 0) AS editable
    FROM gasto_viatico g
    JOIN usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN programacion_tecnico pt ON pt.id_programacion = p_id_programacion AND pt.id_usuario = g.id_usuario AND pt.eliminado_en IS NULL
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1))
    ORDER BY IF(pt.rol = 'principal', 0, 1), u.nombre, g.id_gasto;

    -- 6. Totales de la asignación
    SELECT IFNULL(SUM(g.monto), 0) AS total_asignado,
           IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0) AS total_depositado,
           IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), 0, g.monto)), 0) AS total_pendiente,
           v_pend_not AS pendiente_por_notificar, v_n_pend_not AS lineas_por_notificar
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1));

    -- 7. Gastos rendidos por los técnicos
    SELECT g.id_gasto, COALESCE(g.fecha_gasto, g.fecha_solicitud) AS fecha, g.id_usuario AS id_tecnico, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico,
           g.id_concepto,
           IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, CONCAT('Otro: ', g.concepto_texto), IFNULL(cg.String1, 'Concepto')) AS concepto,
           g.descripcion, g.monto,
           IF(g.url_comprobante IS NULL OR g.url_comprobante = '', 0, 1) AS tiene_comprobante,
           g.estado, g.comentario_revision,
           IF(v_gestiona = 1 AND g.estado IN ('pendiente', 'observado'), 1, 0) AS puede_aprobar,
           IF(v_gestiona = 1 AND g.estado = 'pendiente', 1, 0) AS puede_observar,
           IF(v_gestiona = 1 AND g.estado IN ('pendiente', 'observado'), 1, 0) AS puede_rechazar
    FROM gasto_viatico g
    JOIN usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1))
    ORDER BY COALESCE(g.fecha_gasto, g.fecha_solicitud), g.id_gasto;

    -- 8. Tarjetas de la rendición
    CALL SP_ResumenRendicionProgramacion(p_id_programacion, v_jefe);

    -- 9. Cierre
    SELECT r.cerrado_en, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS cerrado_por, r.total_asignado, r.total_aprobado, r.saldo, r.tipo_saldo
    FROM programacion_rendicion r LEFT JOIN usuario u ON u.id_usuario = r.cerrado_por
    WHERE r.id_programacion = p_id_programacion AND r.eliminado_en IS NULL
    ORDER BY r.id_rendicion DESC LIMIT 1;
END$$

DELIMITER ;
