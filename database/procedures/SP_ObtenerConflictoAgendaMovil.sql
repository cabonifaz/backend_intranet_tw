-- ============================================================
-- SP_ObtenerConflictoAgendaMovil  (App Mobile HU-37 — modal «Conflicto de programación»: los servicios, el motivo sugerido y el técnico sugerido · solo lectura)
-- ENVUELVE SP_ObtenerConflictoProgramacion (HU-39 de la intranet: vuelve a detectar el conflicto, trae los servicios, las opciones y los recursos sugeridos con SSOMA conforme y carga) sin repetir
-- ninguna de sus reglas; solo añade el alcance del jefe y el catálogo de motivos:
--   · el técnico del conflicto debe ser del equipo del jefe (SP_ArmarEquipoAgendaMovil: regla Área + Rol, incluidos los dados de baja); si no → «El técnico del conflicto no pertenece a tu equipo.».
--   · permiso prog_bandeja (lo valida el SP envuelto).
-- Resultados (los 5 primeros son los del SP envuelto, tal cual; la API arma el modal con ellos):
--   1 mensaje · 2 conflicto · 3 servicios (orden, etiqueta, id_os, id_programacion, numero_os, tipo, razon_social, tipo_servicio, estado_programacion, fecha, hora_inicio, hora_fin, horas, resoluble) ·
--   4 opciones · 5 recursos sugeridos por servicio (puntaje: a menos carga de la semana, más puntos)
--   6 (añadido) los técnicos del alcance del jefe (id_tecnico): la API solo sugiere a quien el jefe puede asignar ·
--   7 (añadido) motivos de reprogramación (catálogo MOTIVO_REPROGRAMACION: id_motivo, nombre).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConflictoAgendaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConflictoAgendaMovil(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico BIGINT,
    IN p_id_os_a    BIGINT,
    IN p_id_os_b    BIGINT
)
proc: BEGIN
    DECLARE v_sin_menu TINYINT DEFAULT 0;
    DECLARE v_en       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_eq_inactivos = 0;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Alcance Área + Rol
    CALL SP_ArmarEquipoAgendaMovil(p_id_usuario, NULL, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_en FROM tmp_eq e WHERE e.id_usuario = p_id_tecnico;
    IF v_en = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'El técnico del conflicto no pertenece a tu equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El detalle del conflicto es el de la intranet (sus resultados 1 a 5 salen tal cual)
    CALL SP_ObtenerConflictoProgramacion(p_id_usuario, p_tipo, p_id_tecnico, p_id_os_a, p_id_os_b);

    -- 6 Técnicos del alcance (para sugerir solo a quien el jefe puede asignar)
    SELECT e.id_usuario AS id_tecnico FROM tmp_eq e;

    -- 7 Motivos de reprogramación
    SELECT t.Num1 AS id_motivo, t.String1 AS nombre
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.Num1 IS NOT NULL
    ORDER BY t.Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
END$$

DELIMITER ;
