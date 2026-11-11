-- ============================================================
-- SP_FiltrarServiciosJefaturaMovil  (App Mobile HU-29 — apoyo, NO es un endpoint)
-- Deja en `tmp_sg_f` los servicios del día (id_os) que el jefe puede ver (alcance por área) y que cumplen la búsqueda y el filtro.
-- Requiere SP_ArmarSeguimientoOperativo (tmp_sg_*) y SP_ArmarAlcanceJefaturaMovil (tmp_jf_alc). Los parámetros ya vienen validados por quien llama.
--   p_busqueda : N° de OS/OM, cliente, RUC o técnico (la misma búsqueda de la bandeja de seguimiento, SP_FiltrarSeguimientoOperativo).
--   p_filtro   : NULL / '' = todos · activos (no finalizados) · demora (con demora o pausados) · incidencias (incidente crítico o que detiene) · finalizados.
-- Los filtros usan las banderas del servicio (no el estado único de la bandeja) para coincidir con los contadores del menú de Jefatura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_FiltrarServiciosJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_FiltrarServiciosJefaturaMovil(
    IN p_busqueda VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_filtro   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    CALL SP_FiltrarSeguimientoOperativo(NULL, NULL, NULL, NULL, NULLIF(TRIM(IFNULL(p_busqueda, '')), ''));

    -- Solo los servicios del alcance del jefe
    DELETE f FROM tmp_sg_f f LEFT JOIN tmp_jf_alc a ON a.id_os = f.id_os WHERE a.id_os IS NULL;

    IF NULLIF(p_filtro, '') IS NOT NULL THEN
        DELETE f FROM tmp_sg_f f JOIN tmp_sg_os o ON o.id_os = f.id_os
        WHERE NOT CASE p_filtro
                      WHEN 'activos'      THEN o.fase <> 'finalizado'
                      WHEN 'demora'       THEN o.fase <> 'finalizado' AND (o.n_demoras > 0 OR o.os_estado = 'pausada')
                      WHEN 'incidencias'  THEN o.fase <> 'finalizado' AND o.crit = 1
                      WHEN 'finalizados'  THEN o.fase = 'finalizado'
                      ELSE 1 END;
    END IF;
END$$

DELIMITER ;
