-- HU-52 (Sprint 5) Pestaña Viáticos del Detalle del Servicio en Ruta: lo asignado y lo rendido EN VIVO de la OS. SOLO LECTURA.
-- Acceso: seg_bandeja y el servicio en la jornada de hoy (SP_PrepararDetalleServicioRuta): el Asistente de Seguimiento ve sin tener los permisos prog_*.
-- puede_revisar / puede_gestionar: solo el Jefe de Operaciones (prog_aprobar_reprogramacion), con la programación confirmada y la rendición abierta.
--   puede_gestionar (editar la asignación) además exige que el servicio no haya salido a campo.
-- Resultados: 1 mensaje · 2 cabecera · 3 resumen · 4 líneas por técnico y concepto · 5 gastos (ver SP_ArmarViaticosOs).
DROP PROCEDURE IF EXISTS SP_ObtenerViaticosServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticosServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_prog     BIGINT;
    DECLARE v_codigo   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado   VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cerrada  TINYINT DEFAULT 0;
    DECLARE v_revisa   TINYINT DEFAULT 0;
    DECLARE v_en_campo TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LimpiarSeguimientoOperativo();

    SELECT MAX(id_programacion) INTO v_prog
    FROM programacion WHERE id_os = p_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    IF v_prog IS NOT NULL THEN
        SELECT codigo, estado INTO v_codigo, v_estado FROM programacion WHERE id_programacion = v_prog;
        SELECT IF(COUNT(*) > 0, 1, 0) INTO v_cerrada FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL;
    END IF;
    SELECT IF(estado IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada'), 1, 0) INTO v_en_campo FROM orden_servicio WHERE id_os = p_id_os;
    SET v_revisa = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 AND v_estado = 'confirmada' AND v_cerrada = 0, 1, 0);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT v_prog AS id_programacion, v_codigo AS codigo, v_estado AS estado,
           v_revisa AS puede_revisar, IF(v_revisa = 1 AND v_en_campo = 0, 1, 0) AS puede_gestionar,
           v_cerrada AS rendicion_cerrada, 'S/' AS moneda;

    CALL SP_ArmarViaticosOs(p_id_os, v_prog, v_revisa);
END$$

DELIMITER ;
