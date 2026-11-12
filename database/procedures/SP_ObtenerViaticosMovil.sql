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
--   5. Gastos rendidos por el técnico (más recientes primero, máx. 300), con origen, concepto "Otro", motivo sin foto, lectura de la IA y n_fotos
--   6. Reparto de sus gastos entre las líneas del adelanto · 7. Fotos de sus gastos (orden). Requiere la migración 114.
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

    -- 4. Adelanto por concepto de cada viático. id_viatico_linea = la línea a usar en el reparto al rendir un gasto (HU-27).
    --    Rendido de la línea: lo repartido en ella por gastos no rechazados + los gastos antiguos sin reparto del mismo concepto.
    SELECT l.id_programacion, l.id_viatico_linea, l.id_concepto, l.concepto, l.asignado, l.depositado, l.fecha_deposito, l.rendido,
           GREATEST(l.asignado - l.rendido, 0)                       AS por_rendir,
           IF(l.depositado >= l.asignado, 'depositado', 'pendiente') AS estado_deposito
    FROM (
        SELECT x.id_prog AS id_programacion, x.id_gasto AS id_viatico_linea, x.id_concepto, x.concepto,
               x.monto                                                                                   AS asignado,
               IF(x.estado IN ('aprobado', 'rendido'), x.monto, 0)                                       AS depositado,
               x.fecha_deposito,
               IFNULL((SELECT SUM(rp.monto) FROM gasto_viatico_reparto rp
                       JOIN gasto_viatico s ON s.id_gasto = rp.id_gasto AND s.eliminado_en IS NULL AND s.estado <> 'rechazado'
                       WHERE rp.id_viatico_linea = x.id_gasto AND rp.eliminado_en IS NULL), 0)
             + IFNULL((SELECT SUM(s.monto) FROM gasto_viatico s
                       WHERE s.id_usuario = p_id_usuario AND s.tipo = 'gasto_solicitado' AND s.origen IS NULL AND s.estado <> 'rechazado'
                         AND s.eliminado_en IS NULL AND s.id_concepto = x.id_concepto
                         AND (s.id_programacion = x.id_prog OR (s.id_programacion IS NULL AND s.id_os = x.id_os))), 0) AS rendido
        FROM   tmp_gasto_mov x
        JOIN   tmp_viat_mov  v ON v.id_programacion = x.id_prog
        WHERE  x.tipo = 'viatico_asignado'
    ) l
    ORDER BY l.id_programacion, l.id_concepto, l.id_viatico_linea;

    -- 5. Gastos rendidos
    SELECT x.id_gasto,
           CONCAT('GS-', LPAD(x.id_gasto, 6, '0'))  AS codigo,
           x.fecha, x.id_concepto, x.concepto, x.monto, x.moneda, x.descripcion, x.estado,
           x.comentario_revision, x.revisado_por, x.revisado_en, x.creado_en, IF(x.n_fotos > 0, 1, 0) AS tiene_comprobante,
           x.id_os,
           os.numero                                AS numero_os,
           x.id_prog                                AS id_programacion,
           pr.codigo                                AS codigo_programacion,
           x.origen, x.concepto_texto, x.motivo_sin_foto, x.monto_ia, x.coincide_ia, x.n_fotos
    FROM   tmp_gasto_mov x
    JOIN   orden_servicio os ON os.id_os = x.id_os
    LEFT JOIN programacion pr ON pr.id_programacion = x.id_prog
    WHERE  x.tipo = 'gasto_solicitado'
    ORDER BY x.fecha DESC, x.id_gasto DESC
    LIMIT 300;

    -- 6. Reparto de los gastos del técnico (para mostrarlo y para corregir un gasto observado)
    SELECT rp.id_gasto, rp.id_viatico_linea, IFNULL(cg.String1, 'Viático') AS concepto, rp.monto
    FROM   gasto_viatico_reparto rp
    JOIN   gasto_viatico g ON g.id_gasto = rp.id_gasto AND g.id_usuario = p_id_usuario AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
    LEFT JOIN gasto_viatico l  ON l.id_gasto = rp.id_viatico_linea
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = l.id_concepto
    WHERE  rp.eliminado_en IS NULL
    ORDER BY rp.id_gasto, rp.id_reparto;

    -- 7. Fotos de los gastos del técnico (orden = n de GET api/movil/viaticos/gastos/{idGasto}/fotos/{n} y de fotosConservar)
    SELECT f.id_gasto, f.orden
    FROM   gasto_viatico_foto f
    JOIN   gasto_viatico g ON g.id_gasto = f.id_gasto AND g.id_usuario = p_id_usuario AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
    WHERE  f.eliminado_en IS NULL
    ORDER BY f.id_gasto, f.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_viat_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_gasto_mov;
END$$

DELIMITER ;
