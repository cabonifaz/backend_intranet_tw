-- ============================================================
-- SP_ObtenerPanelCampoMovil  (App Mobile HU-29 — Panel de campo en tiempo real · solo lectura)
-- El jefe de área ve dónde están sus técnicos y en qué estado va cada servicio de HOY (fecha de Lima, UTC-5).
-- Reutiliza el motor de la bandeja de Seguimiento Operativo (HU-51, SP_ArmarSeguimientoOperativo: servicios confirmados del día, estado, GPS y alertas)
-- y el alcance del menú de Jefatura (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil: área de la RQ para ST/Metrología; las demás áreas ven todo).
-- Quien lo ve no necesita seg_bandeja: el permiso es ser jefe (menú de Jefatura) y el alcance por área. No escribe nada.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 pines del mapa (un técnico por fila) · 4 alertas críticas (primero las críticas; máx. 10).
--   KPIs (banderas de la OS, mismas que el menú de Jefatura; no son excluyentes entre sí):
--     en_ruta        OS en ruta (con o sin llegada)          ejecucion   OS en ejecución o pausada
--     demora         con demora/incidencia no crítica o pausada (no finalizada)      incidencia  incidente crítico o que detiene (no finalizada)
--     finalizados    OS finalizadas hoy                       programados total del alcance
--   Pin: estado del técnico = el de su servicio más urgente (HU-51). lat/lon NULL = el técnico aún no envía posición hoy (el mapa no lo dibuja).
--   Alertas (tipo): error_critico (ensayo con error crítico aceptado, HU-10: informe_tecnico.error_critico_motivo) · incidente (demora/incidencia que
--     detiene) · demora (demoras e incidencias del día) · perdida_contacto · gps_parado · sin_ingreso_post_llegada · sin_iniciar_servicio (alertas automáticas HU-51).
-- Requiere las migraciones 90 a 92, 97 y 100.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerPanelCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPanelCampoMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_pc_al;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);
    CALL SP_FiltrarServiciosJefaturaMovil(NULL, NULL);   -- tmp_sg_f = servicios del día dentro del alcance del jefe

    -- Alertas: error crítico de ensayo + demoras/incidencias del día + alertas automáticas de la bandeja (sin la proximidad ni el incidente, que ya sale como demora/incidencia)
    DROP TEMPORARY TABLE IF EXISTS tmp_pc_al;
    CREATE TEMPORARY TABLE tmp_pc_al (
        id        INT NOT NULL AUTO_INCREMENT,
        clave     VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        severidad VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        titulo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_os     BIGINT,
        numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tecnico   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        equipo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        minutos   INT,
        PRIMARY KEY (id)
    );
    INSERT INTO tmp_pc_al (clave, tipo, severidad, titulo, detalle, id_os, numero, cliente, tecnico, equipo, minutos)
    SELECT CONCAT('ensayo:', it.id_informe), 'error_critico', 'critica', 'Error crítico', LEFT(it.error_critico_motivo, 300), o.id_os, o.numero, o.razon_social,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido)), COALESCE(ec.codigo_cliente, ec.codigo_tw),
           GREATEST(0, TIMESTAMPDIFF(MINUTE, COALESCE(it.modificado_en, it.creado_en), NOW()))
    FROM   informe_tecnico it
    JOIN   tmp_sg_f f  ON f.id_os = it.id_os
    JOIN   tmp_sg_os o ON o.id_os = it.id_os
    LEFT JOIN usuario ut ON ut.id_usuario = it.id_tecnico
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    WHERE  it.eliminado_en IS NULL AND NULLIF(TRIM(it.error_critico_motivo), '') IS NOT NULL AND o.fase <> 'finalizado';

    INSERT INTO tmp_pc_al (clave, tipo, severidad, titulo, detalle, id_os, numero, cliente, tecnico, equipo, minutos)
    SELECT i.clave, IF(i.impacto = 'detiene', 'incidente', 'demora'), IF(i.impacto = 'detiene', 'critica', 'advertencia'),
           IF(i.impacto = 'detiene', 'Incidente', 'Demora'),
           LEFT(CONCAT(i.tipo, IF(i.duracion_min IS NULL, '', CONCAT(' +', i.duracion_min, ' min')),
                       IF(IFNULL(i.descripcion, '') = '', '', CONCAT(' · ', i.descripcion))), 300),
           o.id_os, o.numero, o.razon_social, i.tecnico, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, i.fecha, c.ahora))
    FROM   tmp_sg_inc i
    JOIN   tmp_sg_f f  ON f.id_os = i.id_os
    JOIN   tmp_sg_os o ON o.id_os = i.id_os
    JOIN   tmp_sg_cfg c
    WHERE  o.fase <> 'finalizado';

    INSERT INTO tmp_pc_al (clave, tipo, severidad, titulo, detalle, id_os, numero, cliente, tecnico, equipo, minutos)
    SELECT a.clave, a.tipo, a.severidad, a.titulo, a.detalle, o.id_os, o.numero, o.razon_social, a.tecnico, NULL, a.minutos
    FROM   tmp_sg_alerta a
    JOIN   tmp_sg_f f  ON f.id_os = a.id_os
    JOIN   tmp_sg_os o ON o.id_os = a.id_os
    WHERE  a.severidad IN ('critica', 'advertencia') AND a.tipo NOT IN ('incidente', 'proximidad');

    -- Pines: un técnico por fila (los de los servicios del alcance)
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_tf;
    CREATE TEMPORARY TABLE tmp_sg_tf (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_sg_tf SELECT DISTINCT ut.id_usuario FROM tmp_sg_ut ut JOIN tmp_sg_f f ON f.id_os = ut.id_os;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 KPIs
    SELECT COUNT(*)                                                                                                AS programados,
           IFNULL(SUM(o.fase IN ('en_ruta', 'en_planta')), 0)                                                       AS en_ruta,
           IFNULL(SUM(o.fase = 'en_ejecucion'), 0)                                                                  AS ejecucion,
           IFNULL(SUM(o.fase <> 'finalizado' AND (o.n_demoras > 0 OR o.os_estado = 'pausada')), 0)                  AS demora,
           IFNULL(SUM(o.fase <> 'finalizado' AND o.crit = 1), 0)                                                    AS incidencia,
           IFNULL(SUM(o.fase = 'finalizado'), 0)                                                                    AS finalizados,
           DATE_FORMAT(MAX(c.ahora), '%H:%i')                                                                       AS actualizado,
           IFNULL(MAX(c.refresco), 30)                                                                              AS refresco_segundos
    FROM   tmp_sg_f f
    JOIN   tmp_sg_os o ON o.id_os = f.id_os
    JOIN   tmp_sg_cfg c;

    -- 3 Pines del mapa
    SELECT t.id_usuario AS id_usuario, t.nombre AS tecnico, t.iniciales AS iniciales, t.estado_seg AS estado,
           p.lat AS latitud, p.lon AS longitud,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion,
           t.id_os_actual AS id_os, o.numero AS numero_os, o.razon_social AS cliente
    FROM   tmp_sg_tec t
    JOIN   tmp_sg_tf tf ON tf.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_os  o ON o.id_os = t.id_os_actual
    JOIN   tmp_sg_cfg c
    ORDER BY t.nombre;

    -- 4 Alertas críticas primero (luego advertencias), las más recientes antes
    SELECT al.clave AS clave, al.tipo AS tipo, al.severidad AS severidad, al.titulo AS titulo, al.detalle AS detalle, al.id_os AS id_os,
           al.numero AS numero_os, al.cliente AS cliente, al.tecnico AS tecnico, al.equipo AS equipo, al.minutos AS minutos
    FROM   tmp_pc_al al
    ORDER BY FIELD(al.severidad, 'critica', 'advertencia'), al.minutos, al.id
    LIMIT 10;

    DROP TEMPORARY TABLE IF EXISTS tmp_pc_al;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
