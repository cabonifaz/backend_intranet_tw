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
