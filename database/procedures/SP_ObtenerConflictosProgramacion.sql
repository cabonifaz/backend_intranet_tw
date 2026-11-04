-- HU-39 (Sprint 5) Lista de ALERTAS de conflictos sobrevenidos (sección del tab Vista Principal, arriba de la matriz de carga).
-- Acceso: prog_bandeja. Solo lectura. Detecta en el momento (no guarda nada): baja o ausencia del técnico, habilitación SSOMA
-- vencida después de programar, solapamiento del mismo técnico y extensión de duración que pisa otra programación.
-- Cada alerta trae los servicios afectados y el motivo sugerido para el botón "Resolver" (abre el flujo de la HU-38 con el motivo
-- autocompletado). "modo" dice qué flujo corresponde al usuario del token: directa (Jefe: ficha en edición directa) o solicitud
-- (Asistente: modal de Solicitud de Reprogramación). La cancelación directa está siempre disponible como alternativa.
-- La HU no otorga permisos: puede_resolver = prog_gestionar, igual que la HU-38.
-- Resultados: 1 mensaje, 2 resumen, 3 conflictos, 4 servicios afectados.
DROP PROCEDURE IF EXISTS SP_ObtenerConflictosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConflictosProgramacion(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_gestiona TINYINT DEFAULT 0;
    DECLARE v_aprueba  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los conflictos de la programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_gestiona = FN_PermisoAccion(p_id_usuario, 'prog_gestionar');
    SET v_aprueba  = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');

    CALL SP_ArmarConflictosProgramacion();

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT COUNT(*)                                  AS total,
           IFNULL(SUM(severidad = 'critica'), 0)     AS criticas,
           IFNULL(SUM(tipo = 'baja'), 0)             AS baja,
           IFNULL(SUM(tipo = 'ssoma_vencido'), 0)    AS ssoma_vencido,
           IFNULL(SUM(tipo = 'solapamiento'), 0)     AS solapamiento,
           IFNULL(SUM(tipo = 'extension_duracion'), 0) AS extension_duracion,
           IF(v_aprueba = 1, 'directa', IF(v_gestiona = 1, 'solicitud', 'solo_lectura')) AS modo,
           v_gestiona                                AS puede_resolver
    FROM tmp_cf;

    -- 3. Conflictos
    SELECT c.clave, c.tipo,
           CASE c.tipo WHEN 'baja' THEN 'Técnico de baja o ausente'
                       WHEN 'ssoma_vencido' THEN 'Habilitación SSOMA vencida'
                       WHEN 'solapamiento' THEN 'Solapamiento horario'
                       ELSE 'Extensión de duración' END                    AS tipo_label,
           c.severidad, c.titulo, c.detalle, c.id_usuario AS id_tecnico, c.tecnico,
           c.fecha, c.n_servicios, c.id_os_a, c.id_os_b,
           TIME_FORMAT(c.solape_ini, '%H:%i') AS solape_inicio, TIME_FORMAT(c.solape_fin, '%H:%i') AS solape_fin,
           c.id_motivo AS id_motivo_sugerido, c.motivo_sugerido,
           IF(v_aprueba = 1, 'directa', IF(v_gestiona = 1, 'solicitud', 'solo_lectura')) AS modo,
           v_gestiona AS puede_resolver
    FROM tmp_cf c
    ORDER BY FIELD(c.tipo, 'baja', 'ssoma_vencido', 'solapamiento', 'extension_duracion'), c.fecha, c.clave
    LIMIT 100;

    -- 4. Servicios afectados
    SELECT s.clave, s.id_os, a.numero AS numero_os, a.tipo_os AS tipo, a.razon_social, a.tipo_servicio,
           s.id_programacion, a.estado_prog AS estado_programacion,
           s.fecha, TIME_FORMAT(a.hora_inicio, '%H:%i') AS hora_inicio, TIME_FORMAT(a.hora_fin, '%H:%i') AS hora_fin,
           IF(s.id_programacion IS NULL, 0, 1) AS resoluble
    FROM tmp_cf_serv s
    JOIN tmp_cf c ON c.clave = s.clave
    JOIN tmp_cf_asig a ON a.id_os = s.id_os AND a.id_usuario = s.id_usuario
    ORDER BY s.clave, s.fecha, a.hora_inicio, s.id_os;

    CALL SP_LimpiarConflictosProgramacion();
END$$

DELIMITER ;
