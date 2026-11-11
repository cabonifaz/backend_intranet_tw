-- ============================================================
-- SP_ObtenerConstanciaMovil  (App Mobile HU-17 — "Constancia de servicio", "Falta una firma" y "Servicio cerrado" · solo lectura)
-- Datos de la constancia de una OS del técnico. El estado de firmas de los informes lo arma SP_ArmarFirmasOsMovil (una sola vez).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 equipos intervenidos (los informes completos) · 4 responsables que faltan firmar.
--   Cabecera: cliente, dirección fiscal, contacto en planta (nombre, cargo, teléfono, correo), RQ, OS, fecha (Lima) y el resumen de informes (firmados de N) ·
--     la firma del cliente (modo, quién firmó, cuándo, trazos; foto = hay formato físico) · generada_en · cerrada_en · envío (en_espera | enviado | error |
--     desactivado | sin_correo, a qué correo y cuándo) · puede_generar (hay firma del cliente y al menos un informe completo) · envio_activo (parámetro
--     CONSTANCIA_ENVIO_CORREO = 1: el caso de uso envía la constancia al correo del contacto al cerrar el servicio).
--   Equipo: marca, modelo, serie, capacidad, d y e (división mínima y de verificación), ubicación, procedencia (variables ambientales HU-09) y el certificado
--     del informe (informe_tecnico.numero_certificado, HU-14).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConstanciaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os AS id_os, v_num AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente, c.direccion_fiscal AS direccion,
           cc.nombres AS contacto_nombre, cc.cargo AS contacto_cargo, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono, NULLIF(TRIM(cc.correo), '') AS contacto_correo,
           (SELECT rq.numero FROM expediente_digital ed JOIN requerimiento rq ON rq.id_requerimiento = ed.id_requerimiento WHERE ed.id_expediente = os.id_expediente LIMIT 1) AS numero_rq,
           DATE_FORMAT(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'), '%Y-%m-%d') AS fecha,
           v_inf AS informes, v_comp AS completos, v_firm AS firmados, v_resp AS responsables, v_ok AS resueltos,
           k.modo AS modo, k.firmante_nombre AS firmante, CONVERT_TZ(k.firmado_en, '+00:00', '-05:00') AS firmado_en, CAST(k.trazos AS CHAR) AS trazos,
           IF(k.ruta_foto IS NULL, 0, 1) AS tiene_foto,
           IF(k.firmado_en IS NULL, 0, 1) AS firmada, CONVERT_TZ(k.generada_en, '+00:00', '-05:00') AS generada_en, CONVERT_TZ(k.cerrada_en, '+00:00', '-05:00') AS cerrada_en,
           IFNULL(k.envio_estado, 'en_espera') AS envio_estado, k.envio_destino AS envio_destino, CONVERT_TZ(k.envio_en, '+00:00', '-05:00') AS envio_en, k.envio_detalle AS envio_detalle,
           IF(k.firmado_en IS NOT NULL AND v_comp > 0 AND k.cerrada_en IS NULL, 1, 0) AS puede_generar,
           IF(IFNULL((SELECT MAX(m.Num2) FROM tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CONSTANCIA_ENVIO_CORREO' AND m.eliminado_en IS NULL), 0) = 1, 1, 0) AS envio_activo
    FROM   orden_servicio os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = os.id_contacto AND cc.SoftDelete = 0
    LEFT JOIN os_constancia k ON k.id_os = os.id_os
    WHERE  os.id_os = p_id_os;

    SELECT e.equipo AS equipo, ec.marca AS marca, ec.modelo AS modelo, NULLIF(TRIM(ec.num_serie), '') AS serie, ec.alcance_maximo AS capacidad,
           ec.division_minima AS d, ec.division_verif AS e, NULLIF(ec.ubicacion_especifica, '') AS ubicacion, e.codigo_equipo AS codigo,
           (SELECT va.procedencia FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = e.id_equipo AND va.eliminado_en IS NULL ORDER BY va.id_variable DESC LIMIT 1) AS procedencia,
           it.numero_certificado AS certificado
    FROM   tmp_fm_inf e
    JOIN   equipo_cliente ec ON ec.id_equipo = e.id_equipo
    LEFT JOIN informe_tecnico it ON it.id_informe = e.id_informe
    WHERE  e.completo = 1
    ORDER BY e.n;

    SELECT r.nombre AS nombre, r.cargo AS cargo, r.informes AS informes
    FROM   tmp_fm_resp r WHERE r.resuelto = 0 ORDER BY r.nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
END$$

DELIMITER ;
