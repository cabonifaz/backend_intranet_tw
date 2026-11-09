-- HU-45 (Sprint 5) Tarjetas de la pestaña "Rendición de Gastos" de una programación. Devuelve UN resultado (1 fila). Solo lectura.
--   Total solicitado = todo lo que presentaron los técnicos · aprobado / observado / pendiente / rechazado por estado del gasto.
--   Saldo vs. monto asignado = (solicitado − rechazado) − asignado: positivo = a favor del técnico, negativo = a devolver, 0 = cuadrado.
--   p_gestiona = 1 si el usuario puede operar (Jefe): habilita "Cerrar rendición". El cierre exige que no queden gastos pendientes
--   ni observados (cada uno debe quedar aprobado o rechazado).
DROP PROCEDURE IF EXISTS SP_ResumenRendicionProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ResumenRendicionProgramacion(
    IN p_id_programacion BIGINT,
    IN p_gestiona        TINYINT
)
BEGIN
    DECLARE v_id_os     BIGINT;
    DECLARE v_estado    VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vigente   TINYINT DEFAULT 0;
    DECLARE v_cerrada   TINYINT DEFAULT 0;
    DECLARE v_asignado  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_deposit   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sol       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_apr       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_obs       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_pen       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rec       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_n_gastos  INT DEFAULT 0;
    DECLARE v_n_comp    INT DEFAULT 0;
    DECLARE v_n_apr     INT DEFAULT 0;
    DECLARE v_n_rev     INT DEFAULT 0;
    DECLARE v_saldo     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_por_dep   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_puede     TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_adv       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SELECT id_os, estado INTO v_id_os, v_estado FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    SET v_vigente = IF(v_estado IS NOT NULL AND v_estado <> 'cancelada', 1, 0);
    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_cerrada FROM programacion_rendicion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0)
      INTO v_asignado, v_deposit
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1));

    SELECT IFNULL(SUM(g.monto), 0),
           IFNULL(SUM(IF(g.estado = 'aprobado',  g.monto, 0)), 0), IFNULL(SUM(IF(g.estado = 'observado', g.monto, 0)), 0),
           IFNULL(SUM(IF(g.estado = 'pendiente', g.monto, 0)), 0), IFNULL(SUM(IF(g.estado = 'rechazado', g.monto, 0)), 0),
           COUNT(*), IFNULL(SUM(g.url_comprobante IS NOT NULL AND g.url_comprobante <> ''), 0),
           IFNULL(SUM(g.estado = 'aprobado'), 0), IFNULL(SUM(g.estado IN ('pendiente', 'observado')), 0)
      INTO v_sol, v_apr, v_obs, v_pen, v_rec, v_n_gastos, v_n_comp, v_n_apr, v_n_rev
    FROM gasto_viatico g
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os AND v_vigente = 1));

    SET v_saldo   = (v_sol - v_rec) - v_asignado;
    SET v_por_dep = v_asignado - v_deposit;

    IF v_cerrada = 1 THEN
        SET v_motivo = 'La rendición ya está cerrada.';
    ELSEIF v_estado IS NULL OR v_estado <> 'confirmada' THEN
        SET v_motivo = 'La programación debe estar confirmada por el cliente (Programado).';
    ELSEIF IFNULL(p_gestiona, 0) = 0 THEN
        SET v_motivo = 'Solo el Jefe de Operaciones cierra la rendición.';
    ELSEIF v_asignado = 0 AND v_n_gastos = 0 THEN
        SET v_motivo = 'No hay viáticos ni gastos que rendir.';
    ELSEIF v_n_rev > 0 THEN
        SET v_motivo = CONCAT('Quedan ', v_n_rev, IF(v_n_rev = 1, ' gasto', ' gastos'), ' por resolver (pendientes u observados): apruébalos o recházalos para cerrar.');
    ELSE
        SET v_puede = 1;
        IF v_por_dep > 0 THEN
            SET v_adv = CONCAT('Aún hay S/ ', FORMAT(v_por_dep, 2), ' de viáticos pendientes de depósito por Contabilidad.');
        END IF;
    END IF;

    SELECT p_id_programacion AS id_programacion, v_asignado AS total_asignado, v_deposit AS total_depositado, v_por_dep AS total_pendiente_deposito,
           v_sol AS total_solicitado, v_n_gastos AS n_gastos, v_n_comp AS n_comprobantes,
           v_apr AS total_aprobado, v_n_apr AS n_aprobados, v_obs AS total_observado, v_pen AS total_pendiente, v_rec AS total_rechazado,
           v_saldo AS saldo_vs_asignado,
           CASE WHEN v_saldo > 0 THEN 'a_favor_tecnico' WHEN v_saldo < 0 THEN 'a_devolver' ELSE 'cuadrado' END AS tipo_saldo,
           v_n_rev AS pendientes_revision, v_cerrada AS cerrada, v_puede AS puede_cerrar, v_motivo AS motivo_no_cerrar, v_adv AS advertencia_cierre;
END$$

DELIMITER ;
