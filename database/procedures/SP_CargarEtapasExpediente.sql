-- Expediente Digital (interno, HU-30/32): recorrido del expediente por las 10 etapas del refinamiento (stepper del
-- Resumen y pestaña Alertas SLA de la auditoría).
-- Requiere tmp_exp con UN expediente ya calculado (CALL SP_CalcularExpedientes(usuario, id) antes).
-- Llena tmp_exp_etp (el que llama hace DROP TEMPORARY TABLE tmp_exp_etp), una fila por etapa (sin "Cerrado"):
--   estado  completado (verde) | en_curso (azul) | bloqueado (rojo, etapa actual con bloqueos) | pendiente (gris)
--           | cancelado (el expediente se cerró en esa etapa) | no_aplica (se cerró antes de llegar)
--   inicio / fin de cada etapa (deducidos de los módulos origen), responsable, área, SLA configurado y horas reales.
-- Fechas: RQ (registro) → Propuesta (primera propuesta) → VB (primera solicitud) → Seguimiento (VB aprobado) →
--   OC (aceptación del cliente) → OS (OC validada) → Programación (confirmación del cliente) → SSOMA (personal asignado) →
--   Ejecución (primer evento de campo) → Cierre (OS finalizadas) → fin del Cierre (conformidad del cliente).
DROP PROCEDURE IF EXISTS SP_CargarEtapasExpediente;

DELIMITER $$

CREATE PROCEDURE SP_CargarEtapasExpediente()
BEGIN
    DECLARE v_etapa       VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa_real  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_orden       INT;
    DECLARE v_orden_real  INT;
    DECLARE v_bloqueos    INT;
    DECLARE v_inicio_sla  DATETIME;
    DECLARE v_inicio_base DATETIME;

    SELECT MAX(etapa), MAX(orden_etapa), MAX(bloqueos), MAX(inicio_etapa), MAX(inicio_etapa_base),
           MAX(CASE
                   WHEN id_propuesta IS NULL                                         THEN 'requerimiento'
                   WHEN cantidad_os > 0 AND os_sin_pendientes = 1                    THEN 'cierre'
                   WHEN cantidad_os > 0 AND os_en_ejecucion = 1                      THEN 'ejecucion'
                   WHEN cantidad_os > 0 AND os_confirmada = 1 AND personal_os > 0    THEN 'ssoma'
                   WHEN cantidad_os > 0 AND os_confirmada = 1                        THEN 'programacion'
                   WHEN oc_valida = 1 OR cantidad_os > 0                             THEN 'orden_servicio'
                   WHEN estado_propuesta = 'aceptado'                                THEN 'orden_compra'
                   WHEN estado_propuesta IN ('aprobado', 'enviado')                  THEN 'seguimiento'
                   WHEN estado_propuesta = 'rechazado' AND rango_propuesta = 6       THEN 'seguimiento'
                   WHEN estado_propuesta IN ('pendiente_vb', 'pendiente_revocacion') THEN 'visto_bueno'
                   ELSE 'propuesta' END)
      INTO v_etapa, v_orden, v_bloqueos, v_inicio_sla, v_inicio_base, v_etapa_real
    FROM tmp_exp;

    SELECT Num1 INTO v_orden_real FROM tabla_maestra
    WHERE IdMaestro = 97 AND IdEmpresa = 1 AND String2 = v_etapa_real AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp1;
    CREATE TEMPORARY TABLE tmp_exp_etp1 AS
    SELECT t.Num1 AS orden, t.String2 AS etapa, t.String1 AS nombre, t.String3 AS area,
           CASE t.String2
               WHEN 'requerimiento'  THEN x.fecha_rq
               WHEN 'propuesta'      THEN x.fecha_primera_propuesta
               WHEN 'visto_bueno'    THEN x.fecha_primera_vb
               WHEN 'seguimiento'    THEN COALESCE(x.fecha_aprobacion_vb, IF(x.rango_propuesta IN (1, 2, 6), x.fecha_envio, NULL))
               WHEN 'orden_compra'   THEN IF(x.estado_propuesta = 'aceptado', COALESCE(x.fecha_aceptacion, x.propuesta_modificada), NULL)
               WHEN 'orden_servicio' THEN COALESCE(x.fecha_liberacion_oc, x.fecha_primera_os)
               WHEN 'programacion'   THEN x.fecha_confirmacion
               WHEN 'ssoma'          THEN IF(x.fecha_confirmacion IS NULL, NULL, GREATEST(x.fecha_confirmacion, IFNULL(x.fecha_primer_personal, x.fecha_confirmacion)))
               WHEN 'ejecucion'      THEN x.fecha_inicio_ejecucion
               WHEN 'cierre'         THEN IF(x.cantidad_os > 0 AND x.os_sin_pendientes = 1, x.fecha_fin_ejecucion, NULL)
           END AS inicio,
           CASE t.String2
               WHEN 'requerimiento'  THEN x.id_responsable_rq
               WHEN 'propuesta'      THEN x.id_responsable_propuesta
               WHEN 'visto_bueno'    THEN IFNULL(x.id_aprobador_vb, x.id_responsable_propuesta)
               WHEN 'seguimiento'    THEN x.id_responsable_propuesta
               WHEN 'orden_compra'   THEN IFNULL(x.id_responsable_oc, x.id_responsable_propuesta)
               WHEN 'orden_servicio' THEN COALESCE(x.id_responsable_os, x.id_responsable_oc, x.id_responsable_propuesta)
               WHEN 'programacion'   THEN x.id_responsable_actual
               WHEN 'ssoma'          THEN x.id_responsable_actual
               WHEN 'ejecucion'      THEN x.id_tecnico_principal
               WHEN 'cierre'         THEN COALESCE(x.id_responsable_os, x.id_responsable_propuesta)
           END AS id_responsable,
           (SELECT CAST(MAX(s.Num2) AS SIGNED) FROM tabla_maestra s
            WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = t.String2 AND s.eliminado_en IS NULL) AS sla_horas,
           (SELECT CAST(MAX(s.Num3) AS SIGNED) FROM tabla_maestra s
            WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = t.String2 AND s.eliminado_en IS NULL) AS sla_alerta_horas,
           IF(t.String2 = 'cierre', x.fecha_conformidad, NULL) AS fin_cierre
    FROM tabla_maestra t
    CROSS JOIN tmp_exp x
    WHERE t.IdMaestro = 97 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.String2 <> 'cerrado';

    -- La etapa en curso (o en la que se cerró) empieza cuando lo indica el cálculo del expediente si no tiene fecha propia
    UPDATE tmp_exp_etp1 SET inicio = IFNULL(inicio, v_inicio_base) WHERE orden = v_orden_real AND v_etapa <> 'cerrado';

    -- Fin de cada etapa = inicio de la siguiente etapa que ya empezó (la etapa en curso no tiene fin)
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp2;
    CREATE TEMPORARY TABLE tmp_exp_etp2 AS
    SELECT e.*,
           IF(e.etapa = 'cierre', e.fin_cierre, CAST(NULL AS DATETIME)) AS fin
    FROM tmp_exp_etp1 e;

    -- (no se puede reabrir tmp_exp_etp1 en la misma consulta: se copia para buscar el inicio de la etapa siguiente)
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp_sig;
    CREATE TEMPORARY TABLE tmp_exp_etp_sig AS SELECT orden, inicio FROM tmp_exp_etp1 WHERE inicio IS NOT NULL;

    UPDATE tmp_exp_etp2 e
    SET e.fin = (SELECT MIN(s.inicio) FROM tmp_exp_etp_sig s WHERE s.orden > e.orden)
    WHERE e.etapa <> 'cierre' AND e.orden < v_orden_real;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp_sig;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp1;

    -- Etapas ya pasadas sin fecha propia de inicio: empiezan cuando terminó la anterior; si los datos origen vienen
    -- desordenados (inicio posterior al fin), el inicio se ajusta al fin
    UPDATE tmp_exp_etp2 SET inicio = fin WHERE orden < v_orden_real AND fin IS NOT NULL AND (inicio IS NULL OR inicio > fin);

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;
    CREATE TEMPORARY TABLE tmp_exp_etp AS
    SELECT e.orden, e.etapa, e.nombre, e.area, a.String1 AS area_nombre, e.inicio, e.fin,
           IF(e.inicio IS NULL, NULL, e.id_responsable) AS id_responsable,
           IF(e.inicio IS NULL, NULL, CONCAT(u.nombre, ' ', u.apellido)) AS responsable,
           IF(e.inicio IS NULL, NULL, u.cargo) AS cargo_responsable,
           e.sla_horas, e.sla_alerta_horas,
           CASE
               WHEN v_etapa = 'cerrado' AND e.fin IS NOT NULL                       THEN 'completado'
               WHEN v_etapa = 'cerrado' AND e.orden = v_orden_real                  THEN 'cancelado'
               WHEN v_etapa = 'cerrado'                                             THEN 'no_aplica'
               WHEN e.orden < v_orden                                               THEN 'completado'
               WHEN e.orden = v_orden AND v_bloqueos > 0                            THEN 'bloqueado'
               WHEN e.orden = v_orden                                               THEN 'en_curso'
               ELSE 'pendiente'
           END AS estado,
           -- Inicio para el SLA (la etapa actual respeta el reinicio por reasignación)
           IF(e.etapa = v_etapa, IFNULL(v_inicio_sla, e.inicio), e.inicio) AS inicio_sla
    FROM tmp_exp_etp2 e
    LEFT JOIN usuario u       ON u.id_usuario = e.id_responsable
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = e.area;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp2;

    ALTER TABLE tmp_exp_etp
        ADD COLUMN horas_reales DECIMAL(10,1) NULL,
        ADD COLUMN cumple_sla TINYINT NULL;

    UPDATE tmp_exp_etp SET
        horas_reales = IF(inicio_sla IS NULL OR estado IN ('pendiente', 'no_aplica'), NULL,
                          GREATEST(ROUND(TIMESTAMPDIFF(MINUTE, inicio_sla, IFNULL(fin, NOW())) / 60, 1), 0)),
        cumple_sla   = IF(sla_horas IS NULL OR inicio_sla IS NULL OR estado IN ('pendiente', 'no_aplica'), NULL,
                          IFNULL(fin, NOW()) <= inicio_sla + INTERVAL sla_horas HOUR);
END$$

DELIMITER ;
