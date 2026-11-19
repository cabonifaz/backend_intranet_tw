-- ============================================================
-- SP_ObtenerInformesRevisionMovil  (App Mobile HU-33 — "Informes por revisar" del Jefe de Área · solo lectura)
-- La misma bandeja de Revisión Técnica de la intranet (HU-56): SP_ArmarBaseInformes, permiso rt_bandeja, con el alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil).
--   p_grupo (pestaña): por_revisar (vacío = por_revisar) · en_correccion · aprobados.
--     por_revisar   informes enviados por el técnico y aún sin revisar (pendiente_revision y pendiente_precotizacion de la bandeja) que NO están observados.
--     en_correccion informes OBSERVADOS por el jefe (estado observado): esperan la corrección del técnico.
--     aprobados     informes revisados (revisado / aprobado): los 30 más recientes.
--   p_busqueda (hasta 80 caracteres): N° de informe, N° de OS, cliente, técnico, equipo, código TW o N° de serie.
--   KPIs (siempre sobre TODO el alcance, sin pestaña ni búsqueda): pendientes (= por_revisar) · observados (= en_correccion) · sin_evidencias (por_revisar sin fotos) ·
--     sla_vencido (por_revisar con más horas de espera que RT_SLA_REVISION_HORAS, 48 h por defecto).
--   Orden: por_revisar → SLA vencido primero y luego los más antiguos · en_correccion → plazo más próximo · aprobados → los más recientes.
--   firmado_cliente: la OS del informe ya tiene una firma de responsable (dispositivo o formato físico, no "ausente"); el detalle muestra el estado exacto del informe.
--   Fechas: texto ISO sin zona (yyyy-MM-ddTHH:mm:ss, hora de Lima), como el resto de la app.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 informes. Requiere las migraciones 93 y 121.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerInformesRevisionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerInformesRevisionMovil(
    IN p_id_usuario BIGINT,
    IN p_grupo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_grupo    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_patron   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tiene    TINYINT DEFAULT 0;
    DECLARE v_limite   INT DEFAULT 200;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_irm;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_grupo = LOWER(TRIM(IFNULL(p_grupo, '')));
    IF v_grupo = '' THEN SET v_grupo = 'por_revisar'; END IF;
    IF v_grupo NOT IN ('por_revisar', 'en_correccion', 'aprobados') THEN
        SELECT 1 AS IdTipoMensaje, 'El grupo de informes no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_busqueda = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');
    IF v_busqueda IS NOT NULL AND CHAR_LENGTH(v_busqueda) > 80 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda no puede superar los 80 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_busqueda IS NOT NULL THEN
        SET v_patron = CONCAT('%', REPLACE(REPLACE(REPLACE(v_busqueda, '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;
    IF v_grupo = 'aprobados' THEN SET v_limite = 30; END IF;

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_irm;
    CREATE TEMPORARY TABLE tmp_irm AS
    SELECT b.id_informe,
           b.numero_informe,
           b.numero_os,
           b.razon_social                                   AS cliente,
           b.equipo,
           b.codigo_tw,
           b.numero_serie,
           b.tecnico,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN 'aprobados'
                WHEN b.estado = 'observado'               THEN 'en_correccion'
                ELSE 'por_revisar' END                      AS pestana,
           b.n_fotos                                        AS evidencias,
           b.n_forzadas                                     AS forzadas,
           IF(EXISTS (SELECT 1 FROM os_firma_responsable f WHERE f.id_os = b.id_os AND f.modo IN ('dispositivo', 'fisico')), 1, 0) AS firmado_cliente,
           b.horas_espera,
           b.sla_vencido,
           c.plazo_en,
           b.fecha_revision
    FROM   tmp_rt_base b
    LEFT JOIN informe_correccion c ON c.id_informe = b.id_informe AND c.estado = 'pendiente' AND c.eliminado_en IS NULL;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 KPIs (todo el alcance)
    SELECT IFNULL(SUM(pestana = 'por_revisar'), 0)                                     AS pendientes,
           IFNULL(SUM(pestana = 'en_correccion'), 0)                                   AS observados,
           IFNULL(SUM(pestana = 'por_revisar' AND evidencias = 0), 0)                  AS sin_evidencias,
           IFNULL(SUM(pestana = 'por_revisar' AND sla_vencido = 1), 0)                 AS sla_vencido,
           DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%H:%i')                     AS actualizado,
           30                                                                          AS refresco_segundos
    FROM   tmp_irm;

    -- 3 Informes de la pestaña
    SELECT i.id_informe, i.numero_informe, i.numero_os, i.cliente, i.equipo, i.codigo_tw, i.tecnico,
           CASE i.pestana WHEN 'aprobados' THEN 'aprobado' ELSE i.pestana END            AS estado,
           i.evidencias, i.forzadas, i.firmado_cliente, i.horas_espera, i.sla_vencido,
           DATE_FORMAT(i.plazo_en, '%Y-%m-%dT%H:%i:%s')                                  AS plazo_en
    FROM   tmp_irm i
    WHERE  i.pestana = v_grupo
      AND  (v_patron IS NULL
            OR CONCAT_WS(' ', i.numero_informe, i.numero_os, i.cliente, i.tecnico, i.equipo, i.codigo_tw, i.numero_serie) LIKE v_patron)
    ORDER BY IF(v_grupo = 'por_revisar', i.sla_vencido, 0) DESC,
             IF(v_grupo = 'por_revisar', i.horas_espera, 0) DESC,
             IF(v_grupo = 'en_correccion', i.plazo_en, NULL) ASC,
             IF(v_grupo = 'aprobados', i.fecha_revision, NULL) DESC,
             i.id_informe DESC
    LIMIT v_limite;

    DROP TEMPORARY TABLE IF EXISTS tmp_irm;
END$$

DELIMITER ;
