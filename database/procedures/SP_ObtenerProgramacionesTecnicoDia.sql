-- HU-39 (Sprint 5) Panel lateral de la matriz de carga: al hacer clic en una celda (técnico y día) lista las programaciones que
-- tiene asignadas ese técnico ese día. Acceso: prog_bandeja. Solo lectura.
--   Usa la misma base que la matriz de la HU-35 (SP_ArmarBaseProgramacion), así el total de horas y el ranking de la celda
--   coinciden con lo que ve el Jefe: libre = 0 · baja < 6 · óptimo 6 a 8 · alta > 8 a 10 · sobrecarga > 10 h o servicios solapados.
--   Cuenta al técnico principal y al personal de apoyo. Los finalizados del día también cuentan (días ya trabajados).
--   p_fecha: obligatorio (el día de la celda).
-- Resultados: 1 mensaje, 2 técnico y resumen del día, 3 programaciones del día.
DROP PROCEDURE IF EXISTS SP_ObtenerProgramacionesTecnicoDia;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProgramacionesTecnicoDia(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_fecha      DATE
)
proc: BEGIN
    DECLARE v_horas    DECIMAL(8,2) DEFAULT 0;
    DECLARE v_servicios INT DEFAULT 0;
    DECLARE v_conflicto TINYINT DEFAULT 0;
    DECLARE v_gestiona  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarBaseProgramacion();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la carga de los técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_fecha IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el día de la celda.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_tecnico AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El técnico no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_gestiona = FN_PermisoAccion(p_id_usuario, 'prog_gestionar');

    CALL SP_ArmarBaseProgramacion(p_fecha, p_fecha);

    SELECT IFNULL(ROUND(SUM(s.horas), 2), 0), COUNT(s.id_os)
      INTO v_horas, v_servicios
    FROM tmp_prog_asig s
    WHERE s.id_usuario = p_id_tecnico AND s.fecha_ejecucion = p_fecha;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_conflicto
    FROM tmp_prog_conf_ud c WHERE c.id_usuario = p_id_tecnico AND c.fecha_ejecucion = p_fecha;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Técnico y resumen del día
    SELECT u.id_usuario AS id_tecnico, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico,
           COALESCE(cg.String1, u.cargo) AS cargo, so.String1 AS sede_operativa, u.estado AS estado_usuario,
           p_fecha AS fecha, v_horas AS horas, v_servicios AS servicios, v_conflicto AS conflicto,
           CASE WHEN v_conflicto = 1 OR v_horas > 10 THEN 'sobrecarga'
                WHEN v_horas > 8                     THEN 'alta'
                WHEN v_horas >= 6                    THEN 'optimo'
                WHEN v_horas > 0                     THEN 'baja'
                ELSE 'libre' END AS nivel,
           v_gestiona AS puede_gestionar
    FROM usuario u
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tabla_maestra so ON so.IdMaestro = 69 AND so.IdEmpresa = 1 AND so.String2 = u.sede_operativa
    WHERE u.id_usuario = p_id_tecnico;

    -- 3. Programaciones del día
    SELECT b.id_os, b.tipo, b.numero AS numero_os, b.estado AS estado_os, b.sub_estado, s.rol,
           pr.id_programacion, pr.codigo, pr.estado AS estado_programacion,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada' THEN 'Programado' ELSE NULL END AS estado_programacion_label,
           b.razon_social, b.sede, b.tipo_servicio,
           TIME_FORMAT(s.hora_inicio, '%H:%i') AS hora_inicio, TIME_FORMAT(s.hora_fin, '%H:%i') AS hora_fin, s.horas,
           b.en_conflicto,
           IF(b.id_reprogramacion_pendiente IS NULL, 0, 1) AS solicitud_pendiente
    FROM tmp_prog_asig s
    JOIN tmp_prog_base b ON b.id_os = s.id_os
    LEFT JOIN programacion pr ON pr.id_programacion = (SELECT MAX(p2.id_programacion) FROM programacion p2
                                                        WHERE p2.id_os = s.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL)
    WHERE s.id_usuario = p_id_tecnico AND s.fecha_ejecucion = p_fecha
    ORDER BY s.hora_inicio, b.id_os;

    CALL SP_LimpiarBaseProgramacion();
END$$

DELIMITER ;
