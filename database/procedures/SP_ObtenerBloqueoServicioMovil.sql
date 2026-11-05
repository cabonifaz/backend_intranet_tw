-- ============================================================
-- SP_ObtenerBloqueoServicioMovil  (App Mobile HU-03 / HU-04 — regla de bloqueo del servicio)
-- Ayuda interna: NO devuelve resultados. Dice si un servicio está BLOQUEADO para el técnico y por qué.
--   p_motivo (OUT): NULL si el servicio NO está bloqueado; si lo está, el motivo que se muestra en la tarjeta:
--     1. descripción del primer bloqueo sin resolver del expediente (clase 'bloqueo');
--     2. 'SSOMA bloqueado'  : el SSOMA del técnico en esta OS (o, si no figura en el personal, el peor del equipo);
--     3. 'Servicio bloqueado': la OS está en estado 'bloqueada'.
-- Es la misma regla de estado_general = 'BLOQUEADO' de SP_ObtenerServiciosProgramadosMovil (agenda). El detalle la usa para
-- no entregar datos de un servicio bloqueado hasta que se levante el motivo (HU-03, criterio 4).
-- Solo lee datos. Sin funciones almacenadas (exigen SUPER) ni tablas temporales.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerBloqueoServicioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBloqueoServicioMovil(
    IN  p_id_os      BIGINT,
    IN  p_id_usuario BIGINT,
    OUT p_motivo     VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ssoma     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloqueo   VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_motivo = NULL;

    SELECT os.estado INTO v_estado_os FROM orden_servicio os WHERE os.id_os = p_id_os;

    SET v_ssoma = COALESCE(
        (SELECT op.estado_ssoma FROM os_personal op
         WHERE  op.id_os = p_id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
        (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                     WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                     WHEN COUNT(*) > 0 THEN 'habilitado' END
         FROM   os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL),
        'pendiente');

    SET v_bloqueo = (SELECT eb.descripcion
                     FROM   orden_servicio os
                     JOIN   expediente_bloqueador eb ON eb.id_expediente = os.id_expediente
                     WHERE  os.id_os = p_id_os AND eb.resuelto = 0 AND eb.clase = 'bloqueo' AND eb.eliminado_en IS NULL
                     ORDER BY eb.id_bloqueador LIMIT 1);

    SET p_motivo = CASE
                       WHEN v_bloqueo IS NOT NULL      THEN v_bloqueo
                       WHEN v_ssoma = 'bloqueado'      THEN 'SSOMA bloqueado'
                       WHEN v_estado_os = 'bloqueada'  THEN 'Servicio bloqueado'
                   END;
END$$

DELIMITER ;
