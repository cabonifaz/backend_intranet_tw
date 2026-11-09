-- HU-59 (Sprint 5) Revisión Técnica: pestaña "Historial" — auditoría inmutable del informe de servicio técnico.
-- Acceso: rt_bandeja (o precot_ver: Comercial ve el historial del informe que originó su precotización).
--   p_categoria: vacío o todos · edicion (ediciones del supervisor) · precotizacion · revision · sistema
-- Origen del evento: movil (lo registró el técnico desde la app), sistema (sin usuario) o el rol del usuario de la intranet.
-- Resultados: 1 mensaje, 2 contadores por categoría, 3 eventos (más reciente primero, hasta 500).
DROP PROCEDURE IF EXISTS SP_ObtenerHistorialInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerHistorialInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_categoria  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_categoria VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_tec    BIGINT;

    SET v_categoria = LOWER(TRIM(IFNULL(p_categoria, '')));
    IF v_categoria IN ('', 'todos') THEN SET v_categoria = 'todos'; END IF;
    IF v_categoria NOT IN ('todos', 'edicion', 'precotizacion', 'revision', 'sistema') THEN
        SELECT 1 AS IdTipoMensaje, 'Categoría no válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
        CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
        SELECT COUNT(*), MAX(id_tecnico) INTO v_existe, v_id_tec FROM tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    ELSEIF FN_PermisoAccion(p_id_usuario, 'precot_ver') = 1 THEN
        SELECT COUNT(*), MAX(it.id_tecnico) INTO v_existe, v_id_tec
        FROM informe_tecnico it
        JOIN precotizacion pc ON pc.id_informe = it.id_informe AND pc.eliminado_en IS NULL
        WHERE it.id_informe = p_id_informe AND it.eliminado_en IS NULL;
    END IF;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_hist;
    CREATE TEMPORARY TABLE tmp_rt_hist AS
    SELECT a.id_auditoria, a.accion, a.descripcion, a.registrado_en AS fecha, a.id_usuario,
           CASE WHEN a.id_usuario IS NULL THEN 'Sistema TotalWeight' ELSE TRIM(CONCAT(u.nombre, ' ', u.apellido)) END AS usuario,
           CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.categoria')) IN ('edicion', 'precotizacion', 'revision', 'sistema')
                    THEN JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.categoria'))
                WHEN a.accion LIKE 'edicion%'       THEN 'edicion'
                WHEN a.accion LIKE 'precotizacion%' THEN 'precotizacion'
                WHEN a.accion IN ('inicio_revision', 'revisado') THEN 'revision'
                ELSE 'sistema' END                                       AS categoria,
           CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.origen')) = 'movil' THEN 'movil'
                WHEN a.id_usuario IS NULL THEN 'sistema'
                WHEN a.id_usuario = v_id_tec AND a.accion IN ('generado', 'enviado_revision') THEN 'movil'
                ELSE 'intranet' END                                      AS origen,
           CASE WHEN a.id_usuario IS NULL THEN 'Sistema'
                WHEN JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.origen')) = 'movil' THEN 'Móvil'
                WHEN a.accion LIKE 'edicion%' THEN 'Edición'
                WHEN u.area = 'servicio_tecnico' AND u.rol_sistema IN ('supervisor', 'administrador') THEN 'Supervisor Técnico'
                WHEN u.area = 'metrologia' AND u.rol_sistema IN ('supervisor', 'administrador') THEN 'Supervisor de Metrología'
                WHEN u.area = 'comercial' THEN 'Comercial'
                ELSE 'Intranet' END                                      AS etiqueta,
           JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.cambios'))           AS cambios,
           JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.detalle'))           AS detalle,
           JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.nota'))              AS nota
    FROM auditoria_evento a
    LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
    WHERE a.entidad_tipo = 'informe_tecnico' AND a.id_entidad = p_id_informe;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT COUNT(*)                            AS todos,
           IFNULL(SUM(categoria = 'edicion'), 0)       AS edicion,
           IFNULL(SUM(categoria = 'precotizacion'), 0) AS precotizacion,
           IFNULL(SUM(categoria = 'revision'), 0)      AS revision,
           IFNULL(SUM(categoria = 'sistema'), 0)       AS sistema
    FROM tmp_rt_hist;

    SELECT id_auditoria, DATE(fecha) AS dia, fecha, accion, categoria, origen, etiqueta, id_usuario, usuario,
           descripcion, NULLIF(cambios, 'null') AS cambios, NULLIF(detalle, 'null') AS detalle, NULLIF(nota, 'null') AS nota
    FROM tmp_rt_hist
    WHERE v_categoria = 'todos' OR categoria = v_categoria
    ORDER BY fecha DESC, id_auditoria DESC
    LIMIT 500;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_hist;
END$$

DELIMITER ;
