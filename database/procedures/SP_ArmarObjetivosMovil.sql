-- ============================================================
-- SP_ArmarObjetivosMovil  (App Mobile HU-07 — apoyo, no es un endpoint)
-- Arma, UNA sola vez, los objetivos de la OS (un objetivo = un equipo a intervenir, `os_equipo`) en la tabla temporal `tmp_obj_mov`,
-- con su estado, tiempos y lo que el técnico puede hacer. Lo usan la lista, la búsqueda por QR y las acciones (iniciar/pausar/reanudar):
-- la regla de qué botón se habilita vive solo aquí. Los SP que la llaman deben terminar con DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov.
--   Objetivos = equipos de la OS que se confirmaron en la programación vigente (sin selección, todos) + los registrados en campo (NEW).
--   estado: por_iniciar | en_ejecucion | pausado | completado | observado
--   Observados (contador) = observado + pausados que esperan aprobación de un supervisor (esos NO se pueden reanudar).
--   Tiempo estimado = Num2 del tipo de intervención (TIPO_INTERVENCION_EQUIPO) o el parámetro OBJETIVO_MINUTOS_POR_DEFECTO (60).
--   Nombre = descripción del suministro del equipo ("Balanza industrial unicelda de piso"); sin suministro, su clasificación (Equipo / Instrumento / Pesa).
--   Bloqueado (no se puede seleccionar) = equipo inactivo o "En Evaluación" (en el laboratorio, no está en la planta).
--   falta_equipo = el objetivo no tiene N/S ni equipo identificado ("FALTA EQUIPO/INSTRUMENTO").
--   puede_iniciar / puede_pausar / puede_reanudar: solo con la llegada registrada y el servicio en curso (SP_EvaluarCampoMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarObjetivosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarObjetivosMovil(
    IN  p_id_os       BIGINT,
    OUT p_estado      VARCHAR(20),
    OUT p_salida_utc  DATETIME,
    OUT p_llegada_utc DATETIME,
    OUT p_habilitado  TINYINT,
    OUT p_motivo      VARCHAR(200)
)
BEGIN
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_n_eq_prog INT    DEFAULT 0;
    DECLARE v_min_def   DECIMAL(18,6);
    DECLARE v_ahora_utc DATETIME;

    CALL SP_EvaluarCampoMovil(p_id_os, p_estado, p_salida_utc, p_llegada_utc, p_habilitado, p_motivo);
    CALL SP_LeerParametroProgramacion('OBJETIVO_MINUTOS_POR_DEFECTO', 60, v_min_def);
    SET v_ahora_utc = UTC_TIMESTAMP();

    SELECT pr.id_programacion INTO v_id_prog
    FROM   programacion pr
    WHERE  pr.id_os = p_id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC LIMIT 1;

    SELECT COUNT(*) INTO v_n_eq_prog
    FROM   programacion_equipo pe
    WHERE  pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    CREATE TEMPORARY TABLE tmp_obj_mov (
        id_os_equipo BIGINT NOT NULL, id_equipo BIGINT NOT NULL, orden_clave BIGINT, numero INT DEFAULT 0,
        tipo_intervencion VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo_corto VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        codigo_tw VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        marca VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, modelo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        num_serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ubicacion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado_equipo VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, bloqueado TINYINT DEFAULT 0, en_campo TINYINT DEFAULT 0, falta_equipo TINYINT DEFAULT 0,
        estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, observado_cuenta TINYINT DEFAULT 0,
        tiempo_estimado_min INT, tiempo_real_min INT, iniciado_utc DATETIME,
        motivo_pausa VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, requiere_aprobacion TINYINT DEFAULT 0,
        ultima_intervencion DATE, ultima_parte VARCHAR(320) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, alertas_pendientes INT DEFAULT 0,
        puede_iniciar TINYINT DEFAULT 0, puede_pausar TINYINT DEFAULT 0, puede_reanudar TINYINT DEFAULT 0,
        PRIMARY KEY (id_os_equipo)
    );

    INSERT INTO tmp_obj_mov (id_os_equipo, id_equipo, orden_clave, tipo_intervencion, tipo_corto, nombre, codigo_tw, codigo_cliente, marca, modelo, num_serie, ubicacion,
                             estado_equipo, bloqueado, en_campo, falta_equipo, estado, observado_cuenta, tiempo_estimado_min, tiempo_real_min, iniciado_utc,
                             motivo_pausa, requiere_aprobacion, ultima_intervencion, ultima_parte, alertas_pendientes)
    SELECT oe.id, oe.id_equipo, IFNULL(oe.orden, oe.id),
           ti.String1, NULLIF(ti.String3, ''),
           LEFT(COALESCE(NULLIF(TRIM(su.descripcion), ''), tc.String1, ec.clasificacion, 'Equipo'), 150),
           ec.codigo_tw, NULLIF(ec.codigo_cliente, ''), ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), ''), NULLIF(ec.ubicacion_especifica, ''),
           teo.String1,
           IF(ec.es_activo = 0 OR ec.estado = 'inactivo' OR ec.estado_operativo = 'evaluacion', 1, 0),
           oe.ingresado_en_campo,
           IF(NULLIF(TRIM(ec.num_serie), '') IS NULL, 1, 0),
           CASE WHEN oe.estado_ejecucion = 'ejecutado' THEN 'completado'
                WHEN oe.pausado = 1 THEN 'pausado'
                WHEN oe.estado_ejecucion = 'observado' THEN 'observado'
                WHEN oe.estado_ejecucion = 'en_proceso' THEN 'en_ejecucion'
                ELSE 'por_iniciar' END,
           IF(oe.estado_ejecucion = 'observado' OR (oe.pausado = 1 AND oe.pausa_requiere_aprobacion = 1), 1, 0),
           COALESCE(ti.Num2, v_min_def),
           FLOOR((oe.acumulado_seg + IF(oe.reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, oe.reanudado_utc, v_ahora_utc)))) / 60),
           oe.iniciado_utc,
           IF(oe.pausado = 1, oe.motivo_pausa, NULL), IF(oe.pausado = 1, oe.pausa_requiere_aprobacion, 0),
           (SELECT DATE(MAX(x.fecha_ejecucion)) FROM os_equipo x
            WHERE x.id_equipo = oe.id_equipo AND x.id_os <> oe.id_os AND x.estado_ejecucion = 'ejecutado' AND x.eliminado_en IS NULL),
           (SELECT LEFT(CONCAT(h.campo_modificado, ': ', h.valor_nuevo), 320) FROM equipo_historial h
            WHERE h.id_equipo = oe.id_equipo ORDER BY h.registrado_en DESC, h.id_historial DESC LIMIT 1),
           (SELECT COUNT(*) FROM alerta_predictiva ap WHERE ap.id_equipo = oe.id_equipo AND ap.resuelta = 0 AND ap.eliminado_en IS NULL)
    FROM   os_equipo oe
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN tabla_maestra ti  ON ti.Descripcion  = 'TIPO_INTERVENCION_EQUIPO' AND ti.IdEmpresa  = 1 AND ti.Num1 = oe.id_tipo_intervencion
    LEFT JOIN suministros   su  ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc  ON tc.IdMaestro    = 71                         AND tc.IdEmpresa  = 1 AND tc.String2 = ec.clasificacion
    LEFT JOIN tabla_maestra teo ON teo.Descripcion = 'ESTADO_OPERATIVO_EQUIPO'   AND teo.IdEmpresa = 1 AND teo.String2 = ec.estado_operativo
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
      AND  (v_n_eq_prog = 0 OR oe.ingresado_en_campo = 1
            OR EXISTS (SELECT 1 FROM programacion_equipo pe
                       WHERE pe.id_programacion = v_id_prog AND pe.id_equipo = oe.id_equipo AND pe.eliminado_en IS NULL));

    SET @n_obj_mov := 0;
    UPDATE tmp_obj_mov SET numero = (@n_obj_mov := @n_obj_mov + 1) ORDER BY orden_clave, id_os_equipo;

    UPDATE tmp_obj_mov
    SET puede_iniciar   = IF(p_habilitado = 1 AND bloqueado = 0 AND estado IN ('por_iniciar', 'observado'), 1, 0),
        puede_pausar    = IF(p_habilitado = 1 AND estado = 'en_ejecucion', 1, 0),
        puede_reanudar  = IF(p_habilitado = 1 AND estado = 'pausado' AND requiere_aprobacion = 0 AND bloqueado = 0, 1, 0);
END$$

DELIMITER ;
