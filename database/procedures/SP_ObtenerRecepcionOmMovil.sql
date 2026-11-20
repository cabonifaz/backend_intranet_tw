-- ============================================================
-- SP_ObtenerRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — detalle de una OM · lectura)
-- Resumen de la OM, sus instrumentos (recibidos o pendientes) y las recepciones ya registradas. La OM debe ser del técnico (SP_ArmarOmTecnicoMovil); misma respuesta si no existe o no es suya.
--   cabecera.estado: por_recibir (ningún instrumento recibido) · parcial (faltan instrumentos) · observado (todos recibidos y alguno con estado físico observado) · conforme.
--   cabecera.puede_recibir = la OM está activa (no finalizada / anulada / reprogramada) y quedan instrumentos pendientes.
--   Instrumentos: numero 1..n, estado_fisico / observaciones / fotos / recibido_en (hora de Lima 'yyyy-MM-dd HH:mm') solo si ya se recibió.
--   Recepciones: de la más reciente a la más antigua; recibio = nombre del técnico; instrumentos = cuántos se recibieron en esa recepción; tiene_constancia = ya hay PDF.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 instrumentos · 4 recepciones. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRecepcionOmMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_total   INT DEFAULT 0;
    DECLARE v_recib   INT DEFAULT 0;
    DECLARE v_obs     INT DEFAULT 0;
    DECLARE v_activa  TINYINT DEFAULT 0;
    DECLARE v_existe  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*), IFNULL(MAX(o.activa), 0) INTO v_existe, v_activa FROM tmp_rom_os o;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    SELECT COUNT(*), IFNULL(SUM(i.recibido), 0), IFNULL(SUM(i.recibido = 1 AND i.estado_fisico = 'observado'), 0) INTO v_total, v_recib, v_obs FROM tmp_rom_inst i;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT o.id_os, o.numero, o.cliente, o.numero_rq, o.servicio, v_total AS total_instrumentos, v_recib AS recibidos,
           IF(v_activa = 1 AND v_recib < v_total, 1, 0) AS puede_recibir,
           CASE WHEN v_recib = 0 THEN 'por_recibir' WHEN v_recib < v_total THEN 'parcial' WHEN v_obs > 0 THEN 'observado' ELSE 'conforme' END AS estado
    FROM   tmp_rom_os o;

    -- 3. Instrumentos
    SELECT i.id_os_equipo, i.numero, i.nombre, i.marca, i.modelo, i.serie, i.capacidad, i.codigo_cliente, i.codigo_tw,
           i.recibido, i.estado_fisico, i.observaciones, i.fotos,
           DATE_FORMAT(CONVERT_TZ(i.recibido_utc, '+00:00', '-05:00'), '%Y-%m-%d %H:%i') AS recibido_en
    FROM   tmp_rom_inst i
    ORDER BY i.numero;

    -- 4. Recepciones registradas
    SELECT r.id_recepcion, r.numero_guia AS guia, r.medio_entrega AS medio, r.entrego_nombre AS entrego, r.entrego_cargo AS entrego_cargo,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS recibio,
           DATE_FORMAT(CONVERT_TZ(r.recibido_utc, '+00:00', '-05:00'), '%Y-%m-%d %H:%i') AS fecha,
           r.estado, r.motivo_parcial,
           (SELECT COUNT(*) FROM om_recepcion_equipo e WHERE e.id_recepcion = r.id_recepcion AND e.eliminado_en IS NULL) AS instrumentos,
           IF(r.ruta_constancia IS NULL, 0, 1) AS tiene_constancia
    FROM   om_recepcion r
    LEFT JOIN usuario u ON u.id_usuario = r.id_usuario_recibio
    WHERE  r.id_os = p_id_os AND r.eliminado_en IS NULL
    ORDER BY r.id_recepcion DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
END$$

DELIMITER ;
