-- ============================================================
-- SP_ListarEnviosDiferidosMovil  (App móvil sin señal — trazabilidad · solo lectura)
-- Lista los registros que la app envió tarde (sin señal) de un servicio, del más reciente al más antiguo. La usan la app de Jefatura (Seguimiento del servicio) y la intranet
-- (Seguimiento Operativo / detalle del servicio). Con p_id_os_equipo se limita a ese equipo. Máximo 200 filas.
-- Las horas salen en hora de Lima. retraso_seg = cuánto pasó entre que el técnico lo tomó y que llegó al servidor.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 envíos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ListarEnviosDiferidosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ListarEnviosDiferidosMovil(
    IN p_id_os     BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT e.id_envio, e.id_usuario,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS tecnico,
           e.id_os, e.id_os_equipo, e.tipo, e.metodo,
           CONVERT_TZ(e.capturado_utc, '+00:00', '-05:00') AS capturado_en,
           CONVERT_TZ(e.recibido_utc,  '+00:00', '-05:00') AS recibido_en,
           e.retraso_seg, e.motivo, e.intentos
    FROM   envio_diferido_movil e
    LEFT JOIN usuario u ON u.id_usuario = e.id_usuario
    WHERE  e.id_os = p_id_os
      AND  (IFNULL(p_id_os_equipo, 0) = 0 OR e.id_os_equipo = p_id_os_equipo)
    ORDER BY e.capturado_utc DESC, e.id_envio DESC
    LIMIT 200;
END$$

DELIMITER ;
