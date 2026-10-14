-- HU-33 Datos del modal "Reasignar responsable".
-- Acción expediente_reasignar y ser del área responsable de la etapa (o Gerencia / TI). Solo en etapas que avanzan
-- desde el expediente (Programación en adelante): en las
-- etapas comerciales el responsable es el del RQ, la propuesta o el VB y se cambia en su módulo.
-- Resultados: 1 mensaje · 2 datos (responsable actual, área, etapa, SLA restante, vencimiento y nota de impacto)
--   · 3 motivos (MOTIVO_REASIGNACION_EXPEDIENTE, tal cual)
DROP PROCEDURE IF EXISTS SP_PrepararReasignacionExpediente;

DELIMITER $$

CREATE PROCEDURE SP_PrepararReasignacionExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_etapa  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_manual TINYINT DEFAULT 0;
    DECLARE v_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area   VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_u VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar el responsable del expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*), MAX(etapa), MAX(etapa_manual), MAX(etapa_nombre), MAX(area)
      INTO v_existe, v_etapa, v_manual, v_nombre, v_area FROM tmp_exp;
    SELECT area INTO v_area_u FROM usuario WHERE id_usuario = p_id_usuario;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_manual = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('En la etapa ', v_nombre, ' el responsable es el ',
                      CASE v_etapa WHEN 'requerimiento' THEN 'del requerimiento' WHEN 'visto_bueno' THEN 'aprobador del visto bueno'
                                   ELSE 'de la propuesta' END,
                      ' y se cambia desde su módulo. La reasignación aplica desde Programación.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(v_area_u, '') <> IFNULL(v_area, '') AND IFNULL(v_area_u, '') NOT IN ('gerencia', 'ti') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'Solo los jefes del área responsable de la etapa (o Gerencia / TI) pueden reasignar el expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_expediente, x.numero, x.etapa, x.etapa_nombre,
           x.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable, u.cargo AS cargo_responsable,
           x.area, a.String1 AS area_nombre,
           x.sla_horas, x.fecha_limite, x.sla_estado, x.sla_minutos_restantes,
           'Esta acción quedará registrada en la bitácora de auditoría. Se notificará inmediatamente al nuevo responsable vía correo y notificación en la intranet.' AS nota_impacto
    FROM tmp_exp x
    LEFT JOIN usuario u       ON u.id_usuario = x.id_responsable
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = x.area;

    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra WHERE IdMaestro = 100 AND IdEmpresa = 1 ORDER BY Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
