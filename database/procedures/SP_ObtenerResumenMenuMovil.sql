-- ============================================================
-- SP_ObtenerResumenMenuMovil  (App Mobile HU-02 — Menú principal)
-- Indicadores del menú de la app para el técnico que inició sesión:
--   1) servicios_asignados : OS vigentes (hoy en adelante) donde es técnico
--                            principal o integra el personal (os_personal).
--   2) servicios_hoy       : de esas, las programadas para hoy (Ruta del Día).
--   3) Próximo servicio    : la OS en curso o la siguiente por fecha y hora
--                            (banner "Próximo Hit"). 0 filas si no hay.
-- Fechas en hora de Lima (CURDATE / NOW, migración 63).
-- Solo lectura; no modifica datos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerResumenMenuMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenMenuMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

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
           COALESCE(SUM(fecha_ejecucion = CURDATE()), 0)  AS servicios_hoy
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
