-- ============================================================
-- SP_ObtenerCabeceraInformeMovil  (App Mobile HU-15 — Cabecera del informe: Datos · Detalle Serv. · Observación y pruebas · solo lectura)
-- Todo lo que muestran las 3 pestañas de la cabecera del informe del equipo (informe_tecnico y sus hijas, migraciones 93 / 100 / 104). El técnico sale del token; el
-- contexto (OS suya, Hard Stop de llegada, equipo iniciado) lo valida SP_ContextoEquipoMovil, UNA sola vez; el tipo de orden OS / OM, SP_TipoOrdenMovil.
--   Datos: N° de informe (NNNN-AAAA al generar; antes NULL), RQ, orden, cliente (empresa, dirección, contacto), equipo (marca, modelo, serie, código, capacidad, d, e,
--     COD TW, ubicación, clase), datos del informe (propuesta, comercial, técnico, fecha, horas, tipo de servicio) y "Quién atiende en planta" (lo guardado o, si no hay,
--     el contacto de la OS).
--   puede_editar = el equipo está EN EJECUCIÓN y el informe aún no se generó (HU-16). Sin informe todavía, todo sale vacío: se crea al primer guardado.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 checklist de Detalle Serv. (catálogo CHECKLIST_SERVICIO del tipo OS / OM, con lo marcado) · 4 recomendaciones ·
--   5 fallas · 6 fotos de las fallas · 7 pruebas de las fallas · 8 ensayos de HU-10 (Pruebas generales, formato resumido) · 9 opciones (tipos de equipo, clasificación y
--   componente de las fallas).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCabeceraInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCabeceraInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_gen      DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);

    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera: Datos, Detalle Serv. (JSON), Diagnóstico final
    SELECT p_id_os AS id_os, v_num_os AS numero_os, v_tipo AS tipo_orden, v_rq AS numero_rq,
           v_informe AS id_informe, it.numero_informe, IF(v_gen IS NULL, 0, 1) AS generado,
           IF(v_estado = 'en_ejecucion' AND v_hab = 1 AND v_gen IS NULL, 1, 0) AS puede_editar,
           c.razon_social AS empresa, c.ruc AS ruc, sc.direccion_exacta AS direccion,
           co.nombres AS contacto, co.cargo AS contacto_cargo, NULLIF(TRIM(co.telefono_movil), '') AS contacto_telefono, NULLIF(TRIM(co.correo), '') AS contacto_correo,
           ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), '') AS num_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw,
           ec.alcance_maximo AS capacidad_max, ec.division_minima AS d, IF(ec.division_verif_igual = 1, ec.division_minima, ec.division_verif) AS e,
           NULLIF(ec.ubicacion_especifica, '') AS ubicacion, ec.clase_exactitud AS clase, ec.clasificacion AS tipo_equipo,
           pr.numero AS propuesta, NULLIF(TRIM(CONCAT(IFNULL(ucom.nombre, ''), ' ', IFNULL(ucom.apellido, ''))), '') AS comercial,
           NULLIF(TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))), '') AS tecnico,
           os.fecha_ejecucion AS fecha,
           TIME_FORMAT(COALESCE(os.hora_llegada_real, os.hora_inicio), '%H:%i') AS hora_inicio,
           TIME_FORMAT(COALESCE(os.hora_fin_real, os.hora_fin_estimada), '%H:%i') AS hora_fin,
           ts.String1 AS tipo_servicio,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), co.nombres)                  AS responsable_nombre,
           COALESCE(NULLIF(TRIM(it.responsable_cargo), ''), co.cargo)                     AS responsable_cargo,
           COALESCE(NULLIF(TRIM(it.responsable_telefono), ''), NULLIF(TRIM(co.telefono_movil), '')) AS responsable_telefono,
           it.detalle_servicio, it.comentario_pruebas, IFNULL(it.sin_recomendaciones, 0) AS sin_recomendaciones, IFNULL(it.sin_fallas, 0) AS sin_fallas,
           it.severidad_general, it.estado_equipo_final,
           IFNULL(it.rev_jefatura, 0) AS rev_jefatura, IFNULL(it.requiere_precotizacion, 0) AS requiere_precotizacion,
           IFNULL(it.segunda_visita, 0) AS segunda_visita, IFNULL(it.aplica_garantia, 0) AS aplica_garantia, it.cabecera_guardada_en AS guardada_en,
           it.error_critico_motivo AS error_critico, it.ensayos_finalizado_en AS ensayos_finalizados_en
    FROM   orden_servicio os
    JOIN   equipo_cliente ec          ON ec.id_equipo = v_id_eq
    LEFT JOIN informe_tecnico it      ON it.id_informe = v_informe
    LEFT JOIN cliente c               ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc         ON sc.id_sede = os.id_sede
    LEFT JOIN contacto_cliente co     ON co.id_contacto = os.id_contacto
    LEFT JOIN expediente_digital ed   ON ed.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial pr  ON pr.id_propuesta = COALESCE(os.id_propuesta, ed.id_propuesta)
    LEFT JOIN usuario ucom            ON ucom.id_usuario = pr.id_creador
    LEFT JOIN usuario ut              ON ut.id_usuario = p_id_usuario
    LEFT JOIN tabla_maestra ts        ON ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    WHERE  os.id_os = p_id_os;

    -- 3. Checklist de Detalle Serv.: el del tipo de orden (OS / OM), con lo marcado
    SELECT m.String2 AS codigo, m.String1 AS titulo, m.Num1 AS orden,
           IF(EXISTS (SELECT 1 FROM informe_procedimiento ip
                      WHERE ip.id_informe = v_informe AND ip.codigo = m.String2 AND ip.realizado = 1 AND ip.eliminado_en IS NULL), 1, 0) AS marcado
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    -- 4. Recomendaciones inmediatas
    SELECT r.id_recomendacion, r.codigo, r.titulo, r.descripcion, r.prioridad, r.plazo
    FROM   informe_recomendacion r
    WHERE  r.id_informe = v_informe AND r.origen = 'tecnico' AND r.eliminado_en IS NULL
    ORDER BY r.orden, r.id_recomendacion;

    -- 5. Fallas
    SELECT o.id_observacion, o.codigo, o.orden, o.clasificacion, o.componente, o.titulo AS componente_nombre, o.detalle_extra AS clasificacion_nombre,
           o.descripcion, o.nivel_afectacion
    FROM   informe_observacion o
    WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL
    ORDER BY o.orden, o.id_observacion;

    -- 6. Fotos de las fallas
    SELECT f.id_observacion, f.id_evidencia
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'falla' AND f.eliminado_en IS NULL AND f.id_observacion IS NOT NULL
      AND  EXISTS (SELECT 1 FROM informe_observacion o WHERE o.id_observacion = f.id_observacion AND o.id_informe = v_informe AND o.eliminado_en IS NULL)
    ORDER BY f.id_observacion, f.id_evidencia;

    -- 7. Pruebas que justifican cada falla
    SELECT p.id_observacion, p.tipo, p.orden, p.posicion, p.carga, p.indicacion, p.error, p.emp, p.resultado
    FROM   informe_observacion_prueba p
    JOIN   informe_observacion o ON o.id_observacion = p.id_observacion
    WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL AND p.eliminado_en IS NULL
    ORDER BY o.orden, p.tipo, p.orden, p.id_prueba;

    -- 8. Pruebas generales (formato resumido): lo que guardó Ensayos y Calibración (HU-10)
    SELECT en.tipo, IFNULL(en.grupo, 0) AS grupo, en.orden, en.punto, en.carga, en.lectura, en.error, en.tolerancia, en.resultado, en.critico
    FROM   informe_ensayo en
    WHERE  en.id_informe = v_informe AND en.origen = 'tecnico' AND en.eliminado_en IS NULL
    ORDER BY (en.tipo = 'excentricidad'), en.grupo, en.orden, en.id_ensayo;

    -- 9. Opciones de las listas
    SELECT 'tipo_equipo' AS lista, m.String2 AS codigo, m.String1 AS nombre, NULL AS padre
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'clasificacion', m.String2, m.String1, NULL
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'componente', m.String2, m.String1, m.String3
    FROM   tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY lista, nombre;
END$$

DELIMITER ;
