-- HU-57 (Sprint 5) Viáticos de la OS de un informe técnico (Revisión de Informes): el resultado final de lo asignado y lo rendido. SIEMPRE SOLO LECTURA.
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
           0 AS puede_revisar, 0 AS puede_gestionar, IF(v_id_rend IS NULL, 0, 1) AS rendicion_cerrada, 'S/' AS moneda;

    CALL SP_ArmarViaticosOs(v_id_os, v_prog, 0);

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
