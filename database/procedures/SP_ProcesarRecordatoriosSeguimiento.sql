-- Observaciones 2026-10-15 — Notificación anticipada de las acciones de seguimiento comercial.
-- Lo ejecuta el worker de la API (RecordatoriosSeguimientoWorker) cada minuto. No valida permisos
-- porque es un proceso del sistema.
-- Pasos:
--   1. Cancela los recordatorios pendientes que ya no aplican: la propuesta se eliminó o dejó de estar
--      enviada al cliente, el seguimiento ya se cerró (aceptación o rechazo), la propuesta ya tiene orden
--      de compra o el destinatario no está activo.
--   2. Omite los que llevan más de 1 hora de atraso respecto a la acción (el worker estuvo detenido).
--   3. Toma un lote de recordatorios vencidos (fecha_notificar <= NOW()), crea la notificación en la
--      plataforma (canal 5) para el responsable de la acción y los marca como enviados.
-- p_limite: máximo de recordatorios por ejecución (NULL o menor a 1 = 200, tope 1000).
-- Resultados: 1 mensaje, 2 enviados, omitidos y cancelados.
DROP PROCEDURE IF EXISTS SP_ProcesarRecordatoriosSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ProcesarRecordatoriosSeguimiento(
    IN p_limite INT
)
proc: BEGIN
    DECLARE v_limite      INT;
    DECLARE v_lote        VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cancelados  INT DEFAULT 0;
    DECLARE v_omitidos    INT DEFAULT 0;
    DECLARE v_enviados    INT DEFAULT 0;
    DECLARE v_fin         TINYINT DEFAULT 0;
    DECLARE v_id_rec      BIGINT;
    DECLARE v_destino     BIGINT;
    DECLARE v_id_prop     BIGINT;
    DECLARE v_titulo      VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cuerpo      TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE c_lote CURSOR FOR
        SELECT r.id_recordatorio, r.id_usuario_destino, r.id_propuesta,
               LEFT(CONCAT(IF(r.fecha_accion <= NOW(), 'Acción pendiente: ', 'Recordatorio: '),
                           IFNULL(ta.String1, 'Acción de seguimiento'), ' - ', p.numero), 150),
               CONCAT('"', IFNULL(ta.String1, 'Acción de seguimiento'), '" de la propuesta ', p.numero,
                      IFNULL(CONCAT(' (', c.razon_social, ')'), ''),
                      IF(r.fecha_accion <= NOW(), ' debía realizarse ', ' está programada '),
                      'para las ', DATE_FORMAT(r.fecha_accion, '%H:%i'),
                      ' del ', DATE_FORMAT(r.fecha_accion, '%d/%m/%Y'),
                      IF(r.fecha_accion <= NOW(), '.',
                         CONCAT(' (en ', GREATEST(TIMESTAMPDIFF(MINUTE, NOW(), r.fecha_accion), 1), ' min).')))
        FROM seguimiento_recordatorio r
        JOIN propuesta_comercial p ON p.id_propuesta = r.id_propuesta
        LEFT JOIN cliente c        ON c.id_cliente   = p.id_cliente
        LEFT JOIN tabla_maestra ta ON ta.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND ta.IdEmpresa = 1
                                  AND ta.Num1 = r.id_tipo_accion
        WHERE r.lote = v_lote AND r.estado = 'pendiente'
        ORDER BY r.fecha_notificar, r.id_recordatorio;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_limite = IF(IFNULL(p_limite, 0) < 1, 200, LEAST(p_limite, 1000));
    SET v_lote   = UUID();

    START TRANSACTION;

    -- 1. Recordatorios que ya no aplican
    UPDATE seguimiento_recordatorio r
    JOIN propuesta_comercial p ON p.id_propuesta = r.id_propuesta
    LEFT JOIN usuario u        ON u.id_usuario   = r.id_usuario_destino
    SET r.estado = 'cancelado', r.fecha_procesado = NOW()
    WHERE r.estado = 'pendiente' AND r.eliminado_en IS NULL
      AND (p.eliminado_en IS NOT NULL
           OR p.estado <> 'enviado'
           OR u.id_usuario IS NULL OR u.eliminado_en IS NOT NULL OR u.estado <> 'activo'
           OR EXISTS (SELECT 1 FROM seguimiento_comercial s
                      WHERE s.id_propuesta = r.id_propuesta AND s.eliminado_en IS NULL
                        AND s.estado <> 'activo')
           OR EXISTS (SELECT 1 FROM orden_compra oc
                      WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                        AND (oc.id_propuesta = r.id_propuesta
                             OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                             WHERE op.id_propuesta = r.id_propuesta AND op.eliminado_en IS NULL))));
    SET v_cancelados = ROW_COUNT();

    -- 2. Muy atrasados (más de 1 hora después de la acción)
    UPDATE seguimiento_recordatorio
    SET estado = 'omitido', fecha_procesado = NOW()
    WHERE estado = 'pendiente' AND eliminado_en IS NULL
      AND fecha_accion < NOW() - INTERVAL 1 HOUR;
    SET v_omitidos = ROW_COUNT();

    -- 3. Lote de recordatorios vencidos
    UPDATE seguimiento_recordatorio
    SET lote = v_lote
    WHERE estado = 'pendiente' AND eliminado_en IS NULL AND lote IS NULL
      AND fecha_notificar <= NOW()
    ORDER BY fecha_notificar, id_recordatorio
    LIMIT v_limite;

    OPEN c_lote;
    lectura: LOOP
        FETCH c_lote INTO v_id_rec, v_destino, v_id_prop, v_titulo, v_cuerpo;
        IF v_fin = 1 THEN
            LEAVE lectura;
        END IF;

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_destino, 5, v_titulo, v_cuerpo, 'propuesta', v_id_prop, NOW(), NULL);

        UPDATE seguimiento_recordatorio
        SET estado = 'enviado', fecha_procesado = NOW(), id_notificacion = LAST_INSERT_ID()
        WHERE id_recordatorio = v_id_rec;

        SET v_enviados = v_enviados + 1;
    END LOOP;
    CLOSE c_lote;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Recordatorios procesados.' AS Mensaje;
    SELECT v_enviados AS enviados, v_omitidos AS omitidos, v_cancelados AS cancelados;
END$$

DELIMITER ;
