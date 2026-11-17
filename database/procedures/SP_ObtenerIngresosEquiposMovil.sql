-- ============================================================
-- SP_ObtenerIngresosEquiposMovil  (App Mobile HU-22 — Ingreso de equipos (OS) · lectura)
-- Ingresos ya registrados de los equipos de una OS del técnico (la lista de equipos sale de SP_ObtenerObjetivosMovil).
--   - El técnico sale del token; la OS debe ser suya.
-- Resultados: 1 mensaje · 2 una fila por equipo ingresado (id_os_equipo, estado_ingreso, observacion, ingresado_en en hora de Lima, fotos).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerIngresosEquiposMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIngresosEquiposMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1
                   FROM   orden_servicio os
                   WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
                     AND  (os.id_tecnico_principal = p_id_usuario
                           OR EXISTS (SELECT 1 FROM os_personal op
                                      WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))) THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT i.id_os_equipo,
           i.estado_ingreso,
           i.observacion,
           CONVERT_TZ(i.ingresado_utc, '+00:00', '-05:00') AS ingresado_en,
           (SELECT COUNT(*) FROM os_equipo_ingreso_foto f WHERE f.id_ingreso = i.id) AS fotos
    FROM   os_equipo_ingreso i
    WHERE  i.id_os = p_id_os AND i.eliminado_en IS NULL
    ORDER BY i.id;
END$$

DELIMITER ;
