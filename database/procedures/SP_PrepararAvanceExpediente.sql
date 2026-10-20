-- HU-34 Panel "Avanzar expediente": validaciones de la etapa y si se puede pasar a la siguiente.
-- Acción expediente_bandeja para ver el panel. Para avanzar (puede_avanzar = 1):
--   acción expediente_avanzar, etapa que avanza desde el expediente (Programación en adelante), requisitos críticos
--   cumplidos (sin bloqueos) y ser del área responsable de la etapa (o Gerencia / TI).
-- Resultados: 1 mensaje · 2 datos (etapa actual, estado, responsable, siguiente etapa y su área, puede_avanzar,
--   mensaje, primer bloqueo abierto para "Resolver bloqueo", fecha y usuario de la revisión) · 3 validaciones
DROP PROCEDURE IF EXISTS SP_PrepararAvanceExpediente;

DELIMITER $$

CREATE PROCEDURE SP_PrepararAvanceExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_etapa     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_orden     INT;
    DECLARE v_manual    TINYINT;
    DECLARE v_area      VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_usr  VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fallan    INT DEFAULT 0;
    DECLARE v_puede     TINYINT DEFAULT 0;
    DECLARE v_mensaje   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*), MAX(etapa), MAX(orden_etapa), MAX(etapa_manual), MAX(area)
      INTO v_existe, v_etapa, v_orden, v_manual, v_area
    FROM tmp_exp;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarAvanceExpediente();
    SELECT COUNT(*) INTO v_fallan FROM tmp_exp_check WHERE critico = 1 AND cumple = 0;
    SELECT area INTO v_area_usr FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT String2 INTO v_sig FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 AND Num1 = v_orden + 1;

    SET v_mensaje = CASE
        WHEN v_etapa = 'cerrado'      THEN 'El expediente está cerrado.'
        WHEN v_etapa IN ('requerimiento', 'propuesta', 'visto_bueno')
                                      THEN 'Esta etapa avanza sola con la gestión comercial (requerimiento, propuesta y visto bueno).'
        WHEN v_etapa = 'orden_compra' THEN 'Pasa a Programación cuando se valida la orden de compra (o se autogenera una OC provisional) en Órdenes de Compra.'
        WHEN v_fallan > 0             THEN 'NO ES POSIBLE AVANZAR: existen requisitos críticos pendientes que deben resolverse antes de cambiar de etapa.'
        WHEN FN_PermisoAccion(p_id_usuario, 'expediente_avanzar') = 0
                                      THEN 'Expediente listo para avanzar, pero no tienes permiso para avanzar expedientes.'
        WHEN IFNULL(v_area_usr, '') <> IFNULL(v_area, '') AND IFNULL(v_area_usr, '') NOT IN ('gerencia', 'ti')
                                      THEN 'Expediente listo para avanzar. Solo el área responsable de la etapa puede avanzarlo.'
        ELSE 'EXPEDIENTE LISTO PARA AVANZAR: todos los requisitos críticos están completos y validados por el sistema.'
    END;
    SET v_puede = IF(v_manual = 1 AND v_fallan = 0 AND FN_PermisoAccion(p_id_usuario, 'expediente_avanzar') = 1
                     AND (IFNULL(v_area_usr, '') = IFNULL(v_area, '') OR IFNULL(v_area_usr, '') IN ('gerencia', 'ti')), 1, 0);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_expediente, x.numero, x.etapa, x.etapa_nombre, x.estado,
           x.id_responsable, IFNULL(CONCAT(u.nombre, ' ', u.apellido), a.String1) AS responsable,
           x.area, a.String1 AS area_nombre,
           v_sig AS siguiente_etapa, s.String1 AS siguiente_etapa_nombre,
           s.String3 AS area_siguiente, sa.String1 AS area_siguiente_nombre,
           (v_manual = 1 AND v_fallan = 0) AS listo, v_puede AS puede_avanzar, v_mensaje AS mensaje,
           (SELECT b.id_bloqueador FROM expediente_bloqueador b
            WHERE b.id_expediente = x.id_expediente AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'bloqueo'
            ORDER BY b.critico DESC, b.id_bloqueador LIMIT 1)                       AS id_bloqueo_pendiente,
           NOW() AS fecha_revision, (SELECT CONCAT(nombre, ' ', apellido) FROM usuario WHERE id_usuario = p_id_usuario) AS revisado_por
    FROM tmp_exp x
    LEFT JOIN usuario u        ON u.id_usuario = x.id_responsable
    LEFT JOIN tabla_maestra a  ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = x.area
    LEFT JOIN tabla_maestra s  ON s.IdMaestro = 97 AND s.IdEmpresa = 1 AND s.String2 = v_sig
    LEFT JOIN tabla_maestra sa ON sa.IdMaestro = 79 AND sa.IdEmpresa = 1 AND sa.String2 = s.String3;

    SELECT orden, codigo, descripcion, cumple, critico, es_documento, detalle, accion_sugerida
    FROM tmp_exp_check ORDER BY orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
