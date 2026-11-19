-- ============================================================
-- SP_ObtenerEquipoJefaturaMovil  (App Mobile HU-36 — «Mi equipo»: asistencia y ubicación de los técnicos de HOY · solo lectura)
-- El jefe ve a cada técnico de su equipo con su estado según el Reloj marcador (HU-20: en labores · refrigerio · tardanza · sin marcar · finalizada), el servicio que tiene hoy (OS u OM, su estado y la
-- planta) y su última ubicación. El equipo, el alcance Área + Rol y el estado de cada técnico los arma SP_ArmarEquipoJefaturaMovil (la MISMA fuente de los contadores del menú de Jefatura).
-- No exige un permiso propio: basta tener el menú de Jefatura (SP_ResolverAprobadorMovil); el Supervisor de Servicio Técnico / Metrología ve solo a su área.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 técnicos (uno por fila; sin marcar y tardanza primero, luego refrigerio, en labores y finalizada; luego por nombre).
--   KPIs: en_labores · refrigerio · tardanza · sin_marcar · finalizaron (jornada finalizada) · total · en_jornada (= en_labores + tardanza + refrigerio: los que están en su jornada ahora; es el
--   «N de M en labores» del menú) · actualizado (HH:mm de Lima) · refresco_segundos.
--   Técnico: estado · detalle (texto armado: «En labores · 07:58 (tardanza 13 min)», «En refrigerio desde 10:30 · vuelve 11:15», «Sin marcar inicio de labores») · hora_inicio · minutos_tardanza ·
--   id_os / numero_os / tipo_os (OS u OM) / estado_servicio (el del seguimiento operativo) / lugar (planta) del servicio actual · motivo_sin_servicio (SSOMA bloqueado o con documentos
--   faltantes cuando no tiene servicio) · latitud / longitud / minutos_ubicacion (última posición GPS de hoy).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEquipoJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEquipoJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_sin_menu TINYINT DEFAULT 0;
    DECLARE v_refresco INT DEFAULT 30;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarEquipoJefaturaMovil(p_id_usuario, NULL, 1, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_refresco = IFNULL((SELECT MAX(c.refresco) FROM tmp_sg_cfg c), 30);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 KPIs
    SELECT IFNULL(SUM(e.estado = 'en_labores'), 0)                              AS en_labores,
           IFNULL(SUM(e.estado = 'refrigerio'), 0)                              AS refrigerio,
           IFNULL(SUM(e.estado = 'tardanza'), 0)                                AS tardanza,
           IFNULL(SUM(e.estado = 'sin_marcar'), 0)                              AS sin_marcar,
           IFNULL(SUM(e.estado = 'finalizada'), 0)                              AS finalizaron,
           COUNT(*)                                                             AS total,
           IFNULL(SUM(e.estado IN ('en_labores', 'tardanza', 'refrigerio')), 0) AS en_jornada,
           DATE_FORMAT(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'), '%H:%i') AS actualizado,
           v_refresco                                                           AS refresco_segundos
    FROM   tmp_eq e;

    -- 3 Técnicos
    SELECT e.id_usuario, e.nombre, e.iniciales, e.cargo, e.estado, e.detalle, e.hora_inicio, e.min_tardanza AS minutos_tardanza,
           e.id_os, e.numero_os, e.tipo_os, e.estado_servicio, e.lugar, e.motivo_sin AS motivo_sin_servicio,
           e.latitud, e.longitud, e.min_ubic AS minutos_ubicacion
    FROM   tmp_eq e
    ORDER BY e.orden, e.nombre, e.id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
