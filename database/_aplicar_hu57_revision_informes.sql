-- Aplicar en DBeaver con Alt+X (responder No al aviso Large script). Reiniciar la API después.
-- Informes técnicos generados desde la app móvil (HU-16) -> bandeja de Revisión Técnica de la intranet (HU-56/57).
-- Los informes ya generados que se quedaron en 'borrador' pasan a 'pendiente_revision' (la fecha de envío es la de generación).
-- Idempotente: solo toca los que están en borrador y ya tienen generado_en.
UPDATE informe_tecnico
SET    estado = 'pendiente_revision',
       fecha_envio_revision = COALESCE(fecha_envio_revision, CONVERT_TZ(generado_en, '+00:00', '-05:00'), NOW())
WHERE  estado = 'borrador' AND generado_en IS NOT NULL AND eliminado_en IS NULL;

-- Revisión Técnica (Sprint 5, HU-56 a HU-59): cálculo compartido de los informes de servicio técnico.
-- Llena tmp_rt_base (una fila por informe; el que llama hace DROP TEMPORARY TABLE tmp_rt_base al terminar).
--   p_id_informe NULL = todos (bandeja). Solo informes ya enviados por el técnico (no borradores).
--   Alcance: gerencia / TI ven todo; el resto, los informes de los técnicos de su área ("informes de mis técnicos").
-- grupo_estado (bandeja y tarjetas):
--   pendiente_revision       enviado o en revisión, sin observaciones o con la precotización ya registrada
--   pendiente_precotizacion  enviado o en revisión, con observaciones y sin precotización (no se puede marcar revisado)
--   revisado_sin_precot      revisado sin precotización
--   revisado_con_precot      revisado con precotización (generó oportunidad comercial)
-- SLA: horas desde que llegó a la bandeja (fecha_envio_revision) contra RT_SLA_REVISION_HORAS (48 h por defecto).
DROP PROCEDURE IF EXISTS SP_ArmarBaseInformes;

DELIMITER $$

CREATE PROCEDURE SP_ArmarBaseInformes(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
BEGIN
    DECLARE v_area     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ver_todo TINYINT DEFAULT 0;
    DECLARE v_sla      INT DEFAULT 48;

    SELECT area INTO v_area FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo' LIMIT 1;
    SET v_ver_todo = IF(IFNULL(v_area, '') IN ('gerencia', 'ti'), 1, 0);

    SELECT CAST(IFNULL(MAX(Num2), 48) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'RT_SLA_REVISION_HORAS';

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    CREATE TEMPORARY TABLE tmp_rt_base (PRIMARY KEY (id_informe)) AS
    SELECT it.id_informe,
           it.numero                                                   AS numero_informe,
           it.version,
           it.estado,
           it.url_pdf,
           it.diagnostico_principal                                    AS diagnostico,
           it.id_os,
           os.numero                                                   AS numero_os,
           os.tipo                                                     AS tipo_os,
           it.id_equipo,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), NULLIF(TRIM(CONCAT_WS(' ', ec.marca, ec.modelo)), ''), ec.codigo_tw) AS equipo,
           ec.codigo_tw                                                AS codigo_tw,
           ec.num_serie                                                AS numero_serie,
           ec.marca, ec.modelo,
           COALESCE(cl.String1, ec.clasificacion)                      AS tipo_equipo,
           os.id_cliente,
           c.razon_social,
           c.ruc,
           os.id_sede,
           sc.nombre                                                   AS sede,
           os.id_tipo_servicio,
           ts.String1                                                  AS tipo_servicio,
           it.id_tecnico,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido))                   AS tecnico,
           ut.area                                                     AS area_tecnico,
           COALESCE(os.fecha_ejecucion, DATE(it.fecha_creacion))       AS fecha_ejecucion,
           TIME_FORMAT(COALESCE(os.hora_llegada_real, os.hora_inicio), '%H:%i')  AS hora_inicio,
           TIME_FORMAT(COALESCE(os.hora_fin_real, os.hora_fin_estimada), '%H:%i') AS hora_fin,
           IF(COALESCE(os.hora_llegada_real, os.hora_inicio) IS NULL OR COALESCE(os.hora_fin_real, os.hora_fin_estimada) IS NULL, NULL,
              GREATEST(TIMESTAMPDIFF(MINUTE, COALESCE(os.hora_llegada_real, os.hora_inicio),
                                             COALESCE(os.hora_fin_real, os.hora_fin_estimada)), 0)) AS duracion_min,
           COALESCE(os.id_propuesta, e.id_propuesta)                   AS id_propuesta,
           pr.numero                                                   AS numero_propuesta,
           pr.version                                                  AS version_propuesta,
           rq.id_requerimiento,
           rq.numero                                                   AS numero_rq,
           rq.id_responsable                                           AS id_responsable_rq,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), co.nombres) AS contacto,
           it.fecha_envio_revision,
           it.fecha_inicio_revision,
           it.fecha_revision,
           it.nota_revision,
           it.id_revisor,
           TRIM(CONCAT(ur.nombre, ' ', ur.apellido))                   AS revisor,
           v_sla                                                       AS sla_horas,
           TIMESTAMPDIFF(HOUR, COALESCE(it.fecha_envio_revision, it.fecha_creacion),
                         IF(it.estado IN ('revisado', 'aprobado'), IFNULL(it.fecha_revision, NOW()), NOW())) AS horas_espera,
           (SELECT COUNT(*) FROM informe_observacion o WHERE o.id_informe = it.id_informe AND o.eliminado_en IS NULL)    AS n_observaciones,
           (SELECT COUNT(*) FROM informe_recomendacion r WHERE r.id_informe = it.id_informe AND r.eliminado_en IS NULL)  AS n_recomendaciones,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7)
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_fotos,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.validacion_ia <> 'rechazada'
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_fotos_validas,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL)      AS n_ensayos,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL
              AND en.resultado IS NULL)                                                                                  AS n_ensayos_sin_resultado,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL
              AND en.resultado = 'no_conforme')                                                                          AS n_ensayos_no_conformes,
           (SELECT COUNT(*) FROM informe_procedimiento ip WHERE ip.id_informe = it.id_informe AND ip.eliminado_en IS NULL) AS n_pasos,
           (SELECT COUNT(*) FROM informe_procedimiento ip WHERE ip.id_informe = it.id_informe AND ip.eliminado_en IS NULL
              AND ip.realizado = 1)                                                                                       AS n_pasos_realizados,
           pc.id_precotizacion,
           pc.numero                                                   AS numero_precot,
           pc.estado                                                   AS estado_precot,
           pc.fecha_envio                                              AS fecha_precot,
           pc.id_creador                                               AS id_autor_precot,
           TRIM(CONCAT(up.nombre, ' ', up.apellido))                   AS autor_precot,
           (SELECT COUNT(*) FROM precotizacion_item pi WHERE pi.id_precotizacion = pc.id_precotizacion AND pi.eliminado_en IS NULL) AS n_items_precot,
           pd.id_propuesta                                             AS id_propuesta_derivada,
           pd.numero                                                   AS numero_propuesta_derivada,
           pd.version                                                  AS version_propuesta_derivada,
           pd.estado                                                   AS estado_propuesta_derivada
    FROM informe_tecnico it
    LEFT JOIN orden_servicio os      ON os.id_os = it.id_os
    LEFT JOIN expediente_digital e   ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial pr ON pr.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento rq       ON rq.id_requerimiento = COALESCE(os.id_requerimiento, pr.id_requerimiento, e.id_requerimiento)
    LEFT JOIN cliente c              ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc        ON sc.id_sede = os.id_sede
    LEFT JOIN contacto_cliente co    ON co.id_contacto = os.id_contacto
    LEFT JOIN equipo_cliente ec      ON ec.id_equipo = it.id_equipo
    LEFT JOIN suministros su         ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra cl       ON cl.IdMaestro = 71 AND cl.IdEmpresa = 1 AND cl.String2 = ec.clasificacion
    LEFT JOIN tabla_maestra ts       ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario ut             ON ut.id_usuario = it.id_tecnico
    LEFT JOIN usuario ur             ON ur.id_usuario = it.id_revisor
    LEFT JOIN precotizacion pc       ON pc.id_precotizacion = (SELECT MAX(p2.id_precotizacion) FROM precotizacion p2
                                                               WHERE p2.id_informe = it.id_informe AND p2.eliminado_en IS NULL)
    LEFT JOIN usuario up             ON up.id_usuario = pc.id_creador
    LEFT JOIN propuesta_comercial pd ON pd.id_propuesta = pc.id_propuesta_generada
    WHERE it.eliminado_en IS NULL
      AND it.estado <> 'borrador'
      AND (p_id_informe IS NULL OR it.id_informe = p_id_informe)
      -- solo la última versión del informe de cada OS + equipo
      AND NOT EXISTS (SELECT 1 FROM informe_tecnico i2
                      WHERE i2.eliminado_en IS NULL AND i2.id_os <=> it.id_os AND i2.id_equipo <=> it.id_equipo
                        AND i2.estado <> 'borrador' AND i2.id_os IS NOT NULL
                        AND (i2.version > it.version OR (i2.version = it.version AND i2.id_informe > it.id_informe)))
      AND (v_ver_todo = 1 OR (v_area IS NOT NULL AND ut.area = v_area));

    ALTER TABLE tmp_rt_base
        ADD COLUMN grupo_estado VARCHAR(30) NULL,
        ADD COLUMN sla_vencido  TINYINT     NOT NULL DEFAULT 0;

    UPDATE tmp_rt_base SET
        grupo_estado = CASE
            WHEN estado IN ('revisado', 'aprobado') AND id_precotizacion IS NOT NULL THEN 'revisado_con_precot'
            WHEN estado IN ('revisado', 'aprobado')                                  THEN 'revisado_sin_precot'
            WHEN n_observaciones > 0 AND IFNULL(n_items_precot, 0) = 0               THEN 'pendiente_precotizacion'
            ELSE 'pendiente_revision' END,
        sla_vencido = IF(estado NOT IN ('revisado', 'aprobado') AND horas_espera > sla_horas, 1, 0);
END$$

DELIMITER ;

-- ============================================================
-- SP_GenerarInformeEquipoMovil  (App Mobile HU-16 — "Generar informe técnico" tras la Validación completa)
-- Con las 5 etapas conformes el técnico genera el informe técnico del equipo:
--   · el equipo pasa a COMPLETADO (os_equipo.estado_ejecucion = 'ejecutado'; se cierra su tramo de tiempo),
--   · el informe recibe su N° definitivo NNNN-AAAA de la secuencia propia (informe_secuencia, atómica; se copia también a informe_tecnico.numero, que era el borrador
--     BRR-########) y queda con generado_en / generado_por. Un informe generado es el que lista y firma la HU-17 (Firma de informes).
--   Al generarse, el informe pasa a 'pendiente_revision' con fecha_envio_revision: aparece en la bandeja «Revisión de Informes Técnicos» de la intranet (HU-56/57) para que
--   el Supervisor / Jefe de Servicio Técnico lo revise. (Antes se quedaba en 'borrador' y la intranet no lo mostraba.)
--   Reglas (una sola vez): el contexto lo valida SP_ContextoEquipoMovil (OS del técnico del token, Hard Stop de llegada, equipo iniciado); las 5 etapas
--   SP_ArmarEtapasEquipoMovil (la misma regla de SP_ValidarCierreEquipoMovil). Equipo EN EJECUCIÓN (no pausado). Idempotente: si el informe ya estaba generado
--   responde éxito con el mismo número (repetida = 1) sin tocar nada. Orden de bloqueos fijo: os_equipo → informe técnico → secuencia del año.
--   Auditoría: auditoria_evento (os_equipo y informe_tecnico).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_informe, numero_informe, estado_equipo, repetida.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarInformeEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_GenerarInformeEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_numero    INT DEFAULT NULL;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe        BIGINT DEFAULT NULL;
    DECLARE v_informe   BIGINT DEFAULT NULL;
    DECLARE v_gen       DATETIME DEFAULT NULL;
    DECLARE v_num_inf   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes INT DEFAULT 0;
    DECLARE v_anio      SMALLINT;
    DECLARE v_ultimo    INT DEFAULT 0;
    DECLARE v_n         INT;
    DECLARE v_cod       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora_utc DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Bloqueos en orden fijo: el equipo (objetivo) y luego su informe
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    SELECT it.id_informe, it.generado_en, it.numero_informe INTO v_informe, v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;

    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, 'El informe técnico ya estaba generado.' AS Mensaje;
        SELECT v_informe AS id_informe, v_num_inf AS numero_informe, 'completado' AS estado_equipo, 1 AS repetida;
        LEAVE proc;
    END IF;
    IF v_estado = 'pausado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo está pausado: reanúdalo para generar el informe.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado <> 'en_ejecucion' OR v_hab = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo debe estar en ejecución para generar el informe técnico.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop: las 5 etapas conformes (la misma regla que SP_ValidarCierreEquipoMovil)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_eq, v_conformes);
    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    IF v_informe IS NULL OR v_conformes < 5 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('No es posible finalizar el trabajo en el equipo: ', 5 - v_conformes, IF(5 - v_conformes = 1, ' etapa está incompleta o no conforme.', ' etapas están incompletas o no conformes.'),
                      ' Revisa los pendientes.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- N° del informe: la secuencia propia del año (se salta cualquier número ya usado)
    SET v_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    INSERT IGNORE INTO informe_secuencia (anio, ultimo) VALUES (v_anio, 0);
    SELECT s.ultimo INTO v_ultimo FROM informe_secuencia s WHERE s.anio = v_anio FOR UPDATE;
    SET v_n = v_ultimo + 1;
    SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    WHILE v_n <= 9999 AND EXISTS (SELECT 1 FROM informe_tecnico x WHERE x.numero_informe = v_cod OR x.numero = v_cod) DO
        SET v_n = v_n + 1;
        SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    END WHILE;
    IF v_n > 9999 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Se agotaron los números de informe del año.' AS Mensaje; LEAVE proc;
    END IF;
    UPDATE informe_secuencia SET ultimo = v_n WHERE anio = v_anio;

    SET v_ahora_utc = UTC_TIMESTAMP();
    UPDATE informe_tecnico
    SET    numero_informe = v_cod, numero = v_cod, generado_en = UTC_TIMESTAMP(), generado_por = p_id_usuario, modificado_por = p_id_usuario,
           estado = IF(estado = 'borrador', 'pendiente_revision', estado), fecha_envio_revision = IFNULL(fecha_envio_revision, NOW())
    WHERE  id_informe = v_informe;

    -- «Quién atiende en planta»: si el técnico no lo escribió en la cabecera, el informe queda con el contacto de la OS (el mismo que muestra la pestaña Datos)
    -- para que se pueda firmar (HU-17). Lo ya escrito no se toca.
    UPDATE informe_tecnico it
    JOIN   orden_servicio osr ON osr.id_os = it.id_os
    JOIN   contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    SET    it.responsable_nombre   = cc.nombres,
           it.responsable_cargo    = LEFT(NULLIF(TRIM(cc.cargo), ''), 100),
           it.responsable_telefono = LEFT(NULLIF(TRIM(cc.telefono_movil), ''), 30)
    WHERE  it.id_informe = v_informe AND NULLIF(TRIM(it.responsable_nombre), '') IS NULL AND NULLIF(TRIM(cc.nombres), '') IS NOT NULL;

    -- El equipo queda COMPLETADO y se cierra su tramo de tiempo
    UPDATE os_equipo
    SET    estado_ejecucion = 'ejecutado', fecha_ejecucion = NOW(),
           acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_ahora_utc))),
           reanudado_utc = NULL, pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, modificado_por = p_id_usuario
    WHERE  id = p_id_os_equipo;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'finalizar_equipo', 'en ejecución', 'completado',
            LEFT(CONCAT('Trabajo finalizado en ', IFNULL(v_nombre, 'el equipo'), ' (', v_num_os, '). Informe técnico ', v_cod, '.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'numero_informe', v_cod));
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'generar_informe', 'borrador', 'pendiente_revision',
            LEFT(CONCAT('Informe técnico ', v_cod, ' generado desde la app (HU-16) con las 5 etapas conformes; enviado a Revisión Técnica.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', p_id_os_equipo, 'numero_informe', v_cod));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Informe técnico ', v_cod, ' generado.') AS Mensaje;
    SELECT v_informe AS id_informe, v_cod AS numero_informe, 'completado' AS estado_equipo, 0 AS repetida;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerArchivoFotoInforme  (Revisión Técnica HU-57 — ruta del archivo de una foto del informe, para mostrar la vista previa · lectura)
-- Acceso: rt_bandeja y el informe dentro del alcance del usuario (SP_ArmarBaseInformes). La evidencia debe ser del informe (id_informe) o, si no tiene informe asignado,
-- de la misma OS y equipo (la misma regla de SP_ObtenerDetalleInformeTecnico). Las del QR no tienen archivo.
-- Resultados: 1 mensaje; 2 (ruta, ruta_cuadro, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoFotoInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoFotoInforme(
    IN p_id_usuario   BIGINT,
    IN p_id_informe   BIGINT,
    IN p_id_evidencia BIGINT
)
proc: BEGIN
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM   evidencia_fotografica f
    JOIN   tmp_rt_base b ON b.id_informe = p_id_informe
    WHERE  f.id_evidencia = p_id_evidencia AND f.eliminado_en IS NULL AND f.url_archivo NOT LIKE 'qr://%'
      AND  (f.id_informe = p_id_informe
            OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;

SELECT id_informe, numero, estado, fecha_envio_revision, generado_en FROM informe_tecnico WHERE generado_en IS NOT NULL ORDER BY id_informe DESC LIMIT 10;
