-- Detalle del Servicio Técnico: revisar y aprobar los gastos pendientes desde la pestaña Viáticos y Gastos. Ejecutar con Alt+X (No al aviso), redesplegar la API y recargar la intranet.
-- Ayuda interna (NO es un endpoint): de un informe técnico de la Revisión de Informes saca su orden de servicio, con las mismas reglas de acceso que el detalle del informe
-- (permiso rt_bandeja y el informe dentro del alcance del usuario, SP_ArmarBaseInformes). Si no se puede, devuelve el mensaje en p_msg y p_id_os queda NULL.
DROP PROCEDURE IF EXISTS SP_ResolverOsInformeViaticos;

DELIMITER $$

CREATE PROCEDURE SP_ResolverOsInformeViaticos(
    IN  p_id_usuario BIGINT,
    IN  p_id_informe BIGINT,
    OUT p_id_os      BIGINT,
    OUT p_msg        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SET p_id_os = NULL;
    SET p_msg = NULL;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SET p_msg = 'No tienes permiso para ver la revisión de informes técnicos.';
    ELSEIF IFNULL(p_id_informe, 0) <= 0 THEN
        SET p_msg = 'El informe no existe o no está en tu alcance.';
    ELSE
        CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
        SELECT COUNT(*), MAX(id_os) INTO v_existe, p_id_os FROM tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        IF v_existe = 0 THEN
            SET p_id_os = NULL;
            SET p_msg = 'El informe no existe o no está en tu alcance.';
        ELSEIF p_id_os IS NULL THEN
            SET p_msg = 'El informe no está vinculado a una orden de servicio.';
        END IF;
    END IF;
END$$

DELIMITER ;

-- Revisar (aprobar, observar o rechazar) un gasto rendido desde la pestaña Viáticos y Gastos del Detalle del Servicio Técnico (Revisión de Informes).
--   Resuelve informe → OS (SP_ResolverOsInformeViaticos: rt_bandeja y alcance del informe); comprueba que el gasto sea un gasto rendido de ESA OS (anti-IDOR) y llama a
--   SP_RevisarGastoProgramacion (HU-45), que es quien exige que revise solo el Jefe de Operaciones (prog_aprobar_reprogramacion), con la programación confirmada,
--   la rendición abierta y la acción con su comentario. Es la misma regla que la revisión del Seguimiento (SP_RevisarGastoServicioRuta).
-- Resultados: los de SP_RevisarGastoProgramacion (1 mensaje, 2 gasto resultante, 3 tarjetas de la rendición).
DROP PROCEDURE IF EXISTS SP_RevisarGastoInforme;

DELIMITER $$

CREATE PROCEDURE SP_RevisarGastoInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os BIGINT;
    DECLARE v_n     INT DEFAULT 0;
    DECLARE v_prog  BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverOsInformeViaticos(p_id_usuario, p_id_informe, v_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(g.id_programacion) INTO v_n, v_prog
    FROM gasto_viatico g
    JOIN orden_servicio os ON os.id_os = g.id_os AND os.eliminado_en IS NULL
    WHERE g.id_gasto = p_id_gasto AND g.id_os = v_id_os AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a la orden de servicio de este informe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_prog IS NULL THEN
        SELECT MAX(id_programacion) INTO v_prog
        FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    END IF;
    IF v_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene una programación activa.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_RevisarGastoProgramacion(p_id_usuario, v_prog, p_id_gasto, p_accion, p_comentario);
END$$

DELIMITER ;

-- Comprobante n (1 a 5) de un gasto rendido, para verlo desde la pestaña Viáticos y Gastos del Detalle del Servicio Técnico (Revisión de Informes).
--   Acceso: rt_bandeja y el informe en el alcance del usuario (SP_ResolverOsInformeViaticos). Anti-IDOR: el gasto debe ser un gasto rendido de la OS del informe.
--   n = orden de la foto en gasto_viatico_foto; un gasto antiguo sin fotos en esa tabla tiene solo n = 1 (url_comprobante). Solo devuelve la ruta; la API abre el archivo con autenticación.
-- Resultados: 1 mensaje · 2 ruta (1 fila).
DROP PROCEDURE IF EXISTS SP_ObtenerComprobanteGastoInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerComprobanteGastoInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_n          INT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os BIGINT;
    DECLARE v_n     INT DEFAULT 0;
    DECLARE v_url   VARCHAR(500);
    DECLARE v_ruta  VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverOsInformeViaticos(p_id_usuario, p_id_informe, v_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 OR IFNULL(p_n, 0) NOT BETWEEN 1 AND 5 THEN
        SELECT 1 AS IdTipoMensaje, 'El comprobante indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(g.url_comprobante) INTO v_n, v_url
    FROM gasto_viatico g
    WHERE g.id_gasto = p_id_gasto AND g.id_os = v_id_os AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a la orden de servicio de este informe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT url INTO v_ruta FROM gasto_viatico_foto WHERE id_gasto = p_id_gasto AND orden = p_n AND eliminado_en IS NULL ORDER BY id_foto DESC LIMIT 1;
    IF v_ruta IS NULL AND p_n = 1 AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto WHERE id_gasto = p_id_gasto AND eliminado_en IS NULL) THEN
        SET v_ruta = NULLIF(TRIM(IFNULL(v_url, '')), '');
    END IF;
    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no tiene ese comprobante.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;

-- HU-57 (Sprint 5) Viáticos de la OS de un informe técnico (Revisión de Informes): el resultado final de lo asignado y lo rendido. Solo lee; la revisión de los gastos
-- por revisar se hace con SP_RevisarGastoInforme. puede_revisar = el usuario es el Jefe de Operaciones (prog_aprobar_reprogramacion), la programación está confirmada y la
-- rendición sigue abierta (misma regla que el Seguimiento): habilita aprobar / observar / rechazar en cada gasto.
-- Acceso: rt_bandeja y el informe en el alcance del usuario (SP_ArmarBaseInformes), igual que el detalle del informe.
-- Resuelve informe → OS → programación (la última no cancelada) y devuelve lo mismo que la pestaña Viáticos del Seguimiento más el cierre de la rendición.
-- Resultados: 1 mensaje · 2 cabecera · 3 resumen · 4 líneas · 5 gastos (SP_ArmarViaticosOs) ·
--   6 cierre (1 fila): estado (abierta | cerrada | sin_programacion), asignado, aprobado, rechazado, saldo, tipo (devolucion | reembolso | cuadrado),
--     cerrado_por y cerrado_en (solo si está cerrada; si está abierta, los montos son los de ese momento).
DROP PROCEDURE IF EXISTS SP_ObtenerViaticosInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticosInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_id_os    BIGINT;
    DECLARE v_prog     BIGINT;
    DECLARE v_codigo   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado   VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_rend  BIGINT;
    DECLARE v_asignado DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sol      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_apr      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rec      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_saldo    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_revisa   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SELECT COUNT(*), MAX(id_os) INTO v_existe, v_id_os FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no está vinculado a una orden de servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(id_programacion) INTO v_prog
    FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    IF v_prog IS NOT NULL THEN
        SELECT codigo, estado INTO v_codigo, v_estado FROM programacion WHERE id_programacion = v_prog;
        SELECT MAX(id_rendicion) INTO v_id_rend FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL;
    END IF;

    SET v_revisa = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 AND v_estado = 'confirmada' AND v_id_rend IS NULL, 1, 0);

    -- Montos del momento (para la rendición abierta)
    SELECT IFNULL(SUM(g.monto), 0) INTO v_asignado
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = v_id_os));
    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado = 'aprobado', g.monto, 0)), 0), IFNULL(SUM(IF(g.estado = 'rechazado', g.monto, 0)), 0)
      INTO v_sol, v_apr, v_rec
    FROM gasto_viatico g
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = v_id_os));
    SET v_saldo = (v_sol - v_rec) - v_asignado;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT v_prog AS id_programacion, v_codigo AS codigo, v_estado AS estado,
           v_revisa AS puede_revisar, 0 AS puede_gestionar, IF(v_id_rend IS NULL, 0, 1) AS rendicion_cerrada, 'S/' AS moneda;

    CALL SP_ArmarViaticosOs(v_id_os, v_prog, v_revisa);

    IF v_id_rend IS NOT NULL THEN
        SELECT 'cerrada' AS estado, r.total_asignado AS asignado, r.total_aprobado AS aprobado, r.total_rechazado AS rechazado,
               r.saldo, r.tipo_saldo AS tipo,
               NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS cerrado_por, r.cerrado_en
        FROM programacion_rendicion r
        LEFT JOIN usuario u ON u.id_usuario = r.cerrado_por
        WHERE r.id_rendicion = v_id_rend;
    ELSE
        SELECT IF(v_prog IS NULL, 'sin_programacion', 'abierta') AS estado, v_asignado AS asignado, v_apr AS aprobado, v_rec AS rechazado,
               v_saldo AS saldo,
               CASE WHEN v_saldo > 0 THEN 'reembolso' WHEN v_saldo < 0 THEN 'devolucion' ELSE 'cuadrado' END AS tipo,
               CAST(NULL AS CHAR(210)) AS cerrado_por, CAST(NULL AS DATETIME) AS cerrado_en;
    END IF;
END$$

DELIMITER ;
