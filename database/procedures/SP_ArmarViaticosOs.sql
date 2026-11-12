-- HU-52 / HU-57 (Sprint 5) Ayuda interna: viáticos de una OS vistos desde el Seguimiento (durante) y desde la Revisión de Informes (después).
-- NO valida permisos (lo hace quien llama) y solo LEE. Requiere la migración 114. Devuelve 4 resultados (A a D):
--   A. resumen (1 fila): asignado, depositado, pendiente de depósito, rendido (presentado − rechazado), aprobado, rechazado, por revisar
--      (pendiente + observado), por rendir (asignado − rendido, mínimo 0), saldo (rendido − asignado) y tipo de saldo (reembolso | devolucion | cuadrado)
--   B. líneas de la asignación por técnico y concepto: asignado, rendido (lo repartido en la línea por gastos no rechazados + gastos antiguos sin
--      reparto del mismo técnico y concepto), por rendir y depósito
--   C. gastos rendidos con su estado, origen (viatico | reembolso), fotos, motivo sin foto y lectura de la IA (monto_ia, coincide_ia)
--   D. reparto de los gastos entre las líneas del adelanto (id_gasto, id_viatico_linea, concepto, monto)
--   p_id_programacion: la programación de la OS (NULL = solo lo que no tiene programación). p_gestiona = 1 habilita puede_revisar por gasto.
-- Mismo universo que SP_ObtenerViaticosProgramacion: lo de la programación o, sin programación asignada, lo de la OS.
DROP PROCEDURE IF EXISTS SP_ArmarViaticosOs;

DELIMITER $$

CREATE PROCEDURE SP_ArmarViaticosOs(
    IN p_id_os           BIGINT,
    IN p_id_programacion BIGINT,
    IN p_gestiona        TINYINT
)
BEGIN
    DECLARE v_asignado DECIMAL(12,2) DEFAULT 0;
    DECLARE v_deposit  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sol      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_apr      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rec      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rev      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_n_rev    INT DEFAULT 0;
    DECLARE v_rendido  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_saldo    DECIMAL(12,2) DEFAULT 0;

    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0)
      INTO v_asignado, v_deposit
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = p_id_os));

    SELECT IFNULL(SUM(g.monto), 0),
           IFNULL(SUM(IF(g.estado = 'aprobado', g.monto, 0)), 0),
           IFNULL(SUM(IF(g.estado = 'rechazado', g.monto, 0)), 0),
           IFNULL(SUM(IF(g.estado IN ('pendiente', 'observado'), g.monto, 0)), 0),
           IFNULL(SUM(g.estado IN ('pendiente', 'observado')), 0)
      INTO v_sol, v_apr, v_rec, v_rev, v_n_rev
    FROM gasto_viatico g
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = p_id_os));

    SET v_rendido = v_sol - v_rec;
    SET v_saldo   = v_rendido - v_asignado;

    -- A. Resumen
    SELECT v_asignado AS asignado, v_deposit AS depositado, v_asignado - v_deposit AS pendiente_deposito,
           v_rendido AS rendido, v_apr AS aprobado, v_rec AS rechazado, v_rev AS por_revisar, v_n_rev AS n_por_revisar,
           GREATEST(v_asignado - v_rendido, 0) AS por_rendir, v_saldo AS saldo,
           CASE WHEN v_saldo > 0 THEN 'reembolso' WHEN v_saldo < 0 THEN 'devolucion' ELSE 'cuadrado' END AS tipo_saldo;

    -- B. Líneas de la asignación por técnico y concepto
    SELECT x.id_gasto, x.id_tecnico, x.tecnico, x.rol, x.id_concepto, x.concepto, x.asignado, x.rendido,
           GREATEST(x.asignado - x.rendido, 0) AS por_rendir, x.estado_deposito, x.fecha_deposito
    FROM (
        SELECT g.id_gasto, g.id_usuario AS id_tecnico, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico, IFNULL(pt.rol, 'apoyo') AS rol,
               g.id_concepto, IFNULL(cg.String1, 'Concepto') AS concepto, g.monto AS asignado,
               -- Rendido de la línea: lo repartido en ella por gastos no rechazados (migración 114) + los gastos antiguos sin reparto del mismo
               -- técnico y concepto
               IFNULL((SELECT SUM(rp.monto) FROM gasto_viatico_reparto rp
                       JOIN gasto_viatico s ON s.id_gasto = rp.id_gasto AND s.eliminado_en IS NULL AND s.estado <> 'rechazado'
                       WHERE rp.id_viatico_linea = g.id_gasto AND rp.eliminado_en IS NULL), 0)
             + IFNULL((SELECT SUM(s.monto) FROM gasto_viatico s
                       WHERE s.tipo = 'gasto_solicitado' AND s.eliminado_en IS NULL AND s.estado <> 'rechazado' AND s.origen IS NULL
                         AND s.id_usuario = g.id_usuario AND s.id_concepto = g.id_concepto
                         AND (s.id_programacion = p_id_programacion OR (s.id_programacion IS NULL AND s.id_os = p_id_os))), 0) AS rendido,
               IF(g.estado IN ('aprobado', 'rendido'), 'depositado', 'pendiente') AS estado_deposito,
               g.fecha_deposito,
               IF(pt.rol = 'principal', 0, 1) AS ord_rol, u.nombre AS ord_nombre
        FROM gasto_viatico g
        JOIN usuario u ON u.id_usuario = g.id_usuario
        LEFT JOIN programacion_tecnico pt ON pt.id_programacion = p_id_programacion AND pt.id_usuario = g.id_usuario AND pt.eliminado_en IS NULL
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
        WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ) x
    ORDER BY x.ord_rol, x.ord_nombre, x.id_gasto;

    -- C. Gastos rendidos
    SELECT g.id_gasto, COALESCE(g.fecha_gasto, g.fecha_solicitud) AS fecha, g.id_usuario AS id_tecnico,
           TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico, g.id_concepto,
           IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, CONCAT('Otro: ', g.concepto_texto), IFNULL(cg.String1, 'Concepto')) AS concepto,
           g.descripcion, g.monto, g.estado, g.comentario_revision,
           NULLIF(TRIM(CONCAT(IFNULL(rv.nombre, ''), ' ', IFNULL(rv.apellido, ''))), '') AS revisado_por, g.revisado_en,
           GREATEST((SELECT COUNT(*) FROM gasto_viatico_foto f WHERE f.id_gasto = g.id_gasto AND f.eliminado_en IS NULL),
                    IF(NULLIF(TRIM(IFNULL(g.url_comprobante, '')), '') IS NULL, 0, 1)) AS n_fotos,
           g.motivo_sin_foto, g.monto_ia, g.coincide_ia, g.origen,
           IF(IFNULL(p_gestiona, 0) = 1 AND g.estado IN ('pendiente', 'observado'), 1, 0) AS puede_revisar
    FROM gasto_viatico g
    JOIN usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN usuario rv ON rv.id_usuario = g.revisado_por
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ORDER BY COALESCE(g.fecha_gasto, g.fecha_solicitud), g.id_gasto;

    -- D. Reparto de los gastos entre las líneas del adelanto
    SELECT rp.id_gasto, rp.id_viatico_linea, IFNULL(cg.String1, 'Viático') AS concepto, rp.monto
    FROM gasto_viatico_reparto rp
    JOIN gasto_viatico g ON g.id_gasto = rp.id_gasto AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
    LEFT JOIN gasto_viatico l  ON l.id_gasto = rp.id_viatico_linea
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = l.id_concepto
    WHERE rp.eliminado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ORDER BY rp.id_gasto, rp.id_reparto;
END$$

DELIMITER ;
