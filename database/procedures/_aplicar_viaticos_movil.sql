-- Aplicar en la base (solo procedimientos, sin datos). NO subir al repositorio.

-- ============================================================
-- SP_ObtenerViaticosUsuarioMovil  (App Mobile HU-25/26 — apoyo, no es un endpoint)
-- Reglas de los viáticos y gastos del técnico, UNA sola vez (las usan el menú y "Viáticos y Gastos").
-- Modelo de la intranet (HU-45, migración 89): el Jefe de Operaciones asigna un adelanto por técnico y concepto
-- (gasto_viatico.tipo = 'viatico_asignado') al programar; el técnico rinde sus gastos (tipo = 'gasto_solicitado').
--   Depositado : viático asignado en estado 'aprobado' o 'rendido' (lo marca Contabilidad); el resto, pendiente de depósito.
--   Rendido    : gastos del técnico que no fueron rechazados (pendientes, observados y aprobados).
--   Por rendir : asignado - rendido (nunca negativo).
--   Activo     : viático de una programación vigente (no cancelada) cuya rendición aún no se cerró; finalizado = rendición cerrada.
--   Saldo final: solo con rendición cerrada = aprobado - asignado → reembolso (>0), devolución (<0) o cuadrado.
--   En revisión: gastos en estado 'pendiente'; observados: estado 'observado'.
-- Un gasto sin id_programacion (anterior a la migración 89) se atribuye a la programación vigente de su OS.
-- Deja DOS tablas temporales de la conexión que el SP que llama lee y debe borrar al terminar (y en su EXIT HANDLER):
--   tmp_gasto_mov : una fila por gasto/viático del técnico (con id_prog resuelto).
--   tmp_viat_mov  : una fila por programación con viático asignado (totales ya calculados).
-- Solo lectura sobre las tablas reales.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerViaticosUsuarioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticosUsuarioMovil(
    IN  p_id_usuario  BIGINT,
    OUT p_saldo       DECIMAL(12,2),
    OUT p_activos     INT,
    OUT p_finalizados INT,
    OUT p_rev_monto   DECIMAL(12,2),
    OUT p_rev_n       INT,
    OUT p_obs_n       INT
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;

    CREATE TEMPORARY TABLE tmp_gasto_mov AS
    SELECT g.id_gasto,
           g.tipo,
           g.estado,
           g.monto,
           g.id_concepto,
           IFNULL(cg.String1, 'Concepto')                                          AS concepto,
           IFNULL(mo.String2, 'S/')                                                AS moneda,
           COALESCE(g.fecha_gasto, g.fecha_solicitud)                              AS fecha,
           g.descripcion,
           g.comentario_revision,
           NULLIF(TRIM(CONCAT(IFNULL(rv.nombre, ''), ' ', IFNULL(rv.apellido, ''))), '') AS revisado_por,
           g.revisado_en,
           g.creado_en,
           g.fecha_deposito,
           IF(g.url_comprobante IS NULL OR g.url_comprobante = '', 0, 1)           AS tiene_comprobante,
           g.id_os,
           COALESCE(g.id_programacion,
                    (SELECT p2.id_programacion FROM programacion p2
                     WHERE  p2.id_os = g.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL
                     ORDER BY p2.id_programacion DESC LIMIT 1))                    AS id_prog
    FROM   gasto_viatico g
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 1  AND mo.IdEmpresa = 1 AND mo.Num1 = g.id_moneda
    LEFT JOIN usuario       rv ON rv.id_usuario = g.revisado_por
    WHERE  g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL;

    CREATE TEMPORARY TABLE tmp_viat_mov AS
    SELECT q.*,
           GREATEST(q.asignado - q.rendido, 0)                                     AS por_rendir,
           q.asignado - q.depositado                                               AS pendiente_deposito,
           ROUND(LEAST(q.rendido / NULLIF(q.asignado, 0), 1) * 100)                AS porcentaje_rendido,
           IF(q.cerrada = 1, q.aprobado - q.asignado, NULL)                        AS saldo_final,
           CASE WHEN q.cerrada = 0           THEN NULL
                WHEN q.aprobado > q.asignado THEN 'reembolso'
                WHEN q.aprobado < q.asignado THEN 'devolucion'
                ELSE 'cuadrado' END                                                AS tipo_saldo
    FROM (
        SELECT a.id_prog                                                           AS id_programacion,
               p.codigo,
               p.estado                                                            AS estado_prog,
               p.id_os,
               p.fecha_ejecucion,
               p.hora_inicio,
               p.hora_fin_estimada,
               a.asignado, a.depositado, a.rendido, a.aprobado,
               IF(EXISTS (SELECT 1 FROM programacion_rendicion r
                          WHERE r.id_programacion = a.id_prog AND r.eliminado_en IS NULL), 1, 0) AS cerrada,
               (SELECT MAX(r.cerrado_en) FROM programacion_rendicion r
                WHERE  r.id_programacion = a.id_prog AND r.eliminado_en IS NULL)   AS cerrado_en
        FROM (
            SELECT x.id_prog,
                   SUM(IF(x.tipo = 'viatico_asignado', x.monto, 0))                                          AS asignado,
                   SUM(IF(x.tipo = 'viatico_asignado' AND x.estado IN ('aprobado', 'rendido'), x.monto, 0)) AS depositado,
                   SUM(IF(x.tipo = 'gasto_solicitado' AND x.estado <> 'rechazado', x.monto, 0))              AS rendido,
                   SUM(IF(x.tipo = 'gasto_solicitado' AND x.estado = 'aprobado', x.monto, 0))                AS aprobado
            FROM   tmp_gasto_mov x
            WHERE  x.id_prog IS NOT NULL
            GROUP BY x.id_prog
            HAVING SUM(x.tipo = 'viatico_asignado') > 0
        ) a
        JOIN programacion p ON p.id_programacion = a.id_prog AND p.eliminado_en IS NULL AND p.estado <> 'cancelada'
    ) q;

    SELECT IFNULL(SUM(IF(cerrada = 0, por_rendir, 0)), 0), IFNULL(SUM(cerrada = 0), 0), IFNULL(SUM(cerrada = 1), 0)
      INTO p_saldo, p_activos, p_finalizados
    FROM   tmp_viat_mov;

    SELECT IFNULL(SUM(IF(estado = 'pendiente', monto, 0)), 0), IFNULL(SUM(estado = 'pendiente'), 0), IFNULL(SUM(estado = 'observado'), 0)
      INTO p_rev_monto, p_rev_n, p_obs_n
    FROM   tmp_gasto_mov
    WHERE  tipo = 'gasto_solicitado';
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerViaticosMovil  (App Mobile HU-25 "Rendición de viáticos" y HU-26 "Solicitudes de gastos" — lectura)
-- Viáticos que el Jefe de Operaciones asignó al técnico al programar el servicio y los gastos que rindió.
-- Las reglas (depositado, rendido, por rendir, activo/finalizado, saldo final) están en SP_ObtenerViaticosUsuarioMovil.
-- Solo ve lo suyo: el técnico sale del token. Solo lectura.
-- Resultados:
--   1. Mensaje
--   2. Resumen (1 fila): saldo_por_rendir, viaticos_activos, viaticos_finalizados, gastos_en_revision (monto y n), gastos_observados_n
--   3. Viáticos: una fila por programación con viático asignado (activos primero)
--   4. Adelanto por concepto de cada viático (asignado, depositado, rendido, por rendir)
--   5. Gastos rendidos por el técnico (más recientes primero, máx. 300)
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerViaticosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticosMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_saldo       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_activos     INT DEFAULT 0;
    DECLARE v_finalizados INT DEFAULT 0;
    DECLARE v_rev_monto   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rev_n       INT DEFAULT 0;
    DECLARE v_obs_n       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ObtenerViaticosUsuarioMovil(p_id_usuario, v_saldo, v_activos, v_finalizados, v_rev_monto, v_rev_n, v_obs_n);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen (encabezado de la pantalla y del menú)
    SELECT v_saldo       AS saldo_por_rendir,
           v_activos     AS viaticos_activos,
           v_finalizados AS viaticos_finalizados,
           v_rev_monto   AS gastos_en_revision,
           v_rev_n       AS gastos_en_revision_n,
           v_obs_n       AS gastos_observados_n;

    -- 3. Viáticos (uno por programación)
    SELECT t.id_programacion,
           t.codigo,
           t.estado_prog,
           CASE t.estado_prog WHEN 'confirmada' THEN 'Programado' WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente' ELSE 'Cancelada' END AS estado_prog_label,
           t.cerrada,
           t.id_os,
           os.numero                                                         AS numero_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           s.nombre                                                          AS sede,
           t.fecha_ejecucion,
           TIME_FORMAT(t.hora_inicio, '%H:%i')                               AS hora_inicio,
           TIME_FORMAT(t.hora_fin_estimada, '%H:%i')                         AS hora_fin,
           t.asignado, t.depositado, t.pendiente_deposito, t.rendido, t.por_rendir, t.porcentaje_rendido,
           t.cerrado_en, t.saldo_final, t.tipo_saldo
    FROM   tmp_viat_mov t
    JOIN   orden_servicio os ON os.id_os = t.id_os
    LEFT JOIN cliente      c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente s ON s.id_sede    = os.id_sede
    ORDER BY t.cerrada, t.fecha_ejecucion DESC, t.id_programacion DESC;

    -- 4. Adelanto por concepto de cada viático
    SELECT l.id_programacion, l.id_concepto, l.concepto, l.asignado, l.depositado, l.fecha_deposito, l.rendido,
           GREATEST(l.asignado - l.rendido, 0)                       AS por_rendir,
           IF(l.depositado >= l.asignado, 'depositado', 'pendiente') AS estado_deposito
    FROM (
        SELECT x.id_prog AS id_programacion, x.id_concepto, x.concepto,
               SUM(IF(x.tipo = 'viatico_asignado', x.monto, 0))                                          AS asignado,
               SUM(IF(x.tipo = 'viatico_asignado' AND x.estado IN ('aprobado', 'rendido'), x.monto, 0)) AS depositado,
               MAX(IF(x.tipo = 'viatico_asignado', x.fecha_deposito, NULL))                              AS fecha_deposito,
               SUM(IF(x.tipo = 'gasto_solicitado' AND x.estado <> 'rechazado', x.monto, 0))              AS rendido
        FROM   tmp_gasto_mov x
        JOIN   tmp_viat_mov  v ON v.id_programacion = x.id_prog
        GROUP BY x.id_prog, x.id_concepto, x.concepto
        HAVING SUM(x.tipo = 'viatico_asignado') > 0
    ) l
    ORDER BY l.id_programacion, l.id_concepto;

    -- 5. Gastos rendidos
    SELECT x.id_gasto,
           CONCAT('GS-', LPAD(x.id_gasto, 6, '0'))  AS codigo,
           x.fecha, x.id_concepto, x.concepto, x.monto, x.moneda, x.descripcion, x.estado,
           x.comentario_revision, x.revisado_por, x.revisado_en, x.creado_en, x.tiene_comprobante,
           x.id_os,
           os.numero                                AS numero_os,
           x.id_prog                                AS id_programacion,
           pr.codigo                                AS codigo_programacion
    FROM   tmp_gasto_mov x
    JOIN   orden_servicio os ON os.id_os = x.id_os
    LEFT JOIN programacion pr ON pr.id_programacion = x.id_prog
    WHERE  x.tipo = 'gasto_solicitado'
    ORDER BY x.fecha DESC, x.id_gasto DESC
    LIMIT 300;

    DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerResumenMenuMovil  (App Mobile HU-02 — Menú principal)
-- Indicadores del menú de la app para el técnico que inició sesión:
--   1) servicios_asignados : OS vigentes (hoy en adelante) donde es técnico
--                            principal o integra el personal (os_personal).
--   2) servicios_hoy       : de esas, las programadas para hoy (Ruta del Día).
--   3) Próximo servicio    : la OS en curso o la siguiente por fecha y hora
--                            (banner "Próximo Hit"). 0 filas si no hay.
--   4) Viáticos y Gastos   : saldo por rendir (viáticos activos), cantidad de viáticos activos y gastos en revisión
--                            (monto y cantidad). Las reglas están en SP_ObtenerViaticosUsuarioMovil (se leen en el
--                            mismo resultado de indicadores: viaticos_saldo, viaticos_activos, gastos_revision_monto, gastos_revision_n).
-- Fechas en hora de Lima (CURDATE / NOW, migración 63).
-- Solo lectura; no modifica datos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerResumenMenuMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenMenuMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_vi_saldo   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_vi_activos INT DEFAULT 0;
    DECLARE v_vi_final   INT DEFAULT 0;
    DECLARE v_gs_monto   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_gs_n       INT DEFAULT 0;
    DECLARE v_gs_obs     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El indicador de viáticos no debe tumbar el menú: si falla, esos números quedan en 0 y el resto del menú se muestra.
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET v_vi_saldo = 0, v_vi_activos = 0, v_gs_monto = 0, v_gs_n = 0;
        END;
        CALL SP_ObtenerViaticosUsuarioMovil(p_id_usuario, v_vi_saldo, v_vi_activos, v_vi_final, v_gs_monto, v_gs_n, v_gs_obs);
    END;
    DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- Indicadores
    WITH os_tecnico AS (
        SELECT os.fecha_ejecucion
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
          AND  (os.fecha_ejecucion >= CURDATE() OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    )
    SELECT COUNT(*)                                       AS servicios_asignados,
           COALESCE(SUM(fecha_ejecucion = CURDATE()), 0)  AS servicios_hoy,
           v_vi_saldo                                     AS viaticos_saldo,
           v_vi_activos                                   AS viaticos_activos,
           v_gs_monto                                     AS gastos_revision_monto,
           v_gs_n                                         AS gastos_revision_n
    FROM   os_tecnico;

    -- Próximo servicio (en curso primero; luego el más cercano por fecha y hora)
    SELECT os.id_os,
           os.numero,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente,
           s.nombre                                                 AS sede,
           s.distrito                                               AS distrito,
           ts.String1                                               AS tipo_servicio,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                     AS hora_inicio,
           os.estado
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente s  ON s.id_sede    = os.id_sede
    LEFT JOIN tabla_maestra ts
           ON ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
          AND ts.IdMaestro = (SELECT MAX(x.IdMaestro) FROM tabla_maestra x
                              WHERE x.Descripcion = 'TIPO_SERVICIO' AND x.IdEmpresa = 1)
    WHERE  os.eliminado_en IS NULL
      AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
      AND  (os.fecha_ejecucion >= CURDATE() OR os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ORDER BY (os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')) DESC,
             os.fecha_ejecucion, os.hora_inicio
    LIMIT 1;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos). Pedro Salazar = id_usuario 16.
-- ============================================================

-- 0) Qué viáticos y gastos tiene registrados Pedro en la intranet (tipo viatico_asignado = adelanto; gasto_solicitado = gasto rendido)
SELECT g.id_gasto, g.tipo, g.estado, g.id_programacion, g.id_os, g.id_concepto, g.monto, g.fecha_deposito
FROM   gasto_viatico g
WHERE  g.id_usuario = 16 AND g.eliminado_en IS NULL
ORDER BY g.id_gasto;

-- 1) Lo que recibe la app en "Viáticos y Gastos": 1.ª fila de resultados = mensaje; luego resumen, viáticos, adelanto por concepto y gastos
CALL SP_ObtenerViaticosMovil(16);

-- 2) Indicadores del menú: al final de la 2.ª pestaña deben estar viaticos_saldo, viaticos_activos, gastos_revision_monto y gastos_revision_n
CALL SP_ObtenerResumenMenuMovil(16);
