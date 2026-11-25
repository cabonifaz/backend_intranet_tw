-- ============================================================
-- SP_LiberarRegistroIntranet  (HU-55 — cerrar o soltar el registro del informe de un equipo desde la intranet · escritura)
-- Libera el bloqueo del equipo que tiene quien llama: la sesión activa pasa a 'cerrado' si el informe del equipo ya se generó (la API lo llama justo después de generar) o a 'liberado'
-- si no (la persona suelta el equipo sin terminar). No cambia el estado del equipo ni de la OS: un equipo liberado sin informe queda en proceso con su tiempo ya cerrado
-- (reanudado_utc = NULL) y se puede retomar con SP_IniciarRegistroIntranet, o pausar con SP_PausarEquipoAbiertoIntranet.
-- Idempotente: si quien llama no tenía una sesión activa de ese equipo, responde éxito sin cambiar nada. Solo se puede liberar la sesión propia.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_LiberarRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_LiberarRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_generado TINYINT DEFAULT 0;
    DECLARE v_filas    INT     DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_generado
    FROM   informe_tecnico it
    JOIN   os_equipo oe ON oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.id_equipo = it.id_equipo
    WHERE  it.id_os = p_id_os AND it.generado_en IS NOT NULL AND it.eliminado_en IS NULL;

    UPDATE registro_informe_intranet
    SET    estado = IF(v_generado = 1, 'cerrado', 'liberado'), liberado_en = UTC_TIMESTAMP()
    WHERE  id_os = p_id_os AND id_os_equipo = p_id_os_equipo AND id_registrador = p_id_registrador AND estado = 'activo';
    SET v_filas = ROW_COUNT();

    SELECT 2 AS IdTipoMensaje, IF(v_filas > 0, 'Registro liberado.', 'No había un registro abierto de este equipo.') AS Mensaje;
END$$

DELIMITER ;
