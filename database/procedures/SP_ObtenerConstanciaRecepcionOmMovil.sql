-- ============================================================
-- SP_ObtenerConstanciaRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — datos de la constancia de recepción · lectura)
-- Todo lo que necesita el PDF de la constancia de UNA recepción registrada: la OM, el cliente y su contacto, la trazabilidad de entrega, los instrumentos recibidos en ESA recepción y los
-- que seguían pendientes cuando se registró. La OM de la recepción debe ser del técnico (SP_ArmarOmTecnicoMovil); misma respuesta si no existe o no es suya.
--   cabecera: id_recepcion · numero_om · cliente · direccion · contacto_nombre · contacto_correo · numero_rq · guia · medio · entrego · entrego_cargo · recibio · recibido_en (Lima 'yyyy-MM-dd HH:mm') ·
--             estado · motivo_parcial · firma_trazos (JSON) · ruta_constancia · correo_enviado · envio_activo (parámetro CONSTANCIA_ENVIO_CORREO = 1: el caso de uso envía la constancia al contacto).
--   instrumentos (de esta recepción): nombre · marca · modelo · serie · codigo · estado_fisico · observaciones · accesorios (JSON con los códigos) · fotos.
--   pendientes: instrumentos de la OM que aún no estaban recibidos al registrar esta recepción (nombre, marca, modelo, serie, codigo).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 instrumentos · 4 pendientes. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConstanciaRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConstanciaRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_recepcion BIGINT
)
proc: BEGIN
    DECLARE v_os     BIGINT DEFAULT NULL;
    DECLARE v_existe INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_recepcion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Constancia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT r.id_os INTO v_os FROM om_recepcion r WHERE r.id_recepcion = p_id_recepcion AND r.eliminado_en IS NULL;
    IF v_os IS NOT NULL THEN
        CALL SP_ArmarOmTecnicoMovil(p_id_usuario, v_os);
        SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    END IF;
    IF v_os IS NULL OR v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Constancia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT r.id_recepcion, o.numero AS numero_om, o.cliente, c.direccion_fiscal AS direccion,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.correo), '') AS contacto_correo, o.numero_rq,
           r.numero_guia AS guia, r.medio_entrega AS medio, r.entrego_nombre AS entrego, r.entrego_cargo,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS recibio,
           DATE_FORMAT(CONVERT_TZ(r.recibido_utc, '+00:00', '-05:00'), '%Y-%m-%d %H:%i') AS recibido_en,
           r.estado, r.motivo_parcial, CAST(r.firma_trazos AS CHAR) AS firma_trazos, r.ruta_constancia, r.correo_enviado,
           IF(IFNULL((SELECT MAX(m.Num2) FROM tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CONSTANCIA_ENVIO_CORREO' AND m.eliminado_en IS NULL), 0) = 1, 1, 0) AS envio_activo
    FROM   om_recepcion r
    JOIN   tmp_rom_os o ON o.id_os = r.id_os
    LEFT JOIN cliente c ON c.id_cliente = o.id_cliente
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = o.id_contacto AND cc.SoftDelete = 0
    LEFT JOIN usuario u ON u.id_usuario = r.id_usuario_recibio
    WHERE  r.id_recepcion = p_id_recepcion;

    -- 3. Instrumentos recibidos en esta recepción
    SELECT i.nombre, i.marca, i.modelo, i.serie, COALESCE(i.codigo_cliente, i.codigo_tw) AS codigo,
           i.estado_fisico, i.observaciones, CAST(i.accesorios AS CHAR) AS accesorios, i.fotos
    FROM   tmp_rom_inst i
    WHERE  i.id_recepcion = p_id_recepcion
    ORDER BY i.numero;

    -- 4. Pendientes al registrar esta recepción
    SELECT i.nombre, i.marca, i.modelo, i.serie, COALESCE(i.codigo_cliente, i.codigo_tw) AS codigo
    FROM   tmp_rom_inst i
    WHERE  i.id_recepcion IS NULL OR i.id_recepcion > p_id_recepcion
    ORDER BY i.numero;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
END$$

DELIMITER ;
