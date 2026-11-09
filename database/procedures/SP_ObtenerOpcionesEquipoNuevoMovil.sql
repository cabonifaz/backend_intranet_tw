-- ============================================================
-- SP_ObtenerOpcionesEquipoNuevoMovil  (App Mobile HU-07 — formulario "Equipo nuevo (NEW)" · lectura)
-- Listas que necesita el formulario para registrar en campo un equipo que no está en la lista de la O/S:
--   - marcas  : catálogo MARCA_SUMINISTRO (la marca se elige de la lista, no se escribe libre)
--   - tipos   : suministros ACTIVOS de clase equipo / instrumento / pesa ("Balanza industrial de plataforma"); la clasificación del equipo sale de su clase
-- La OS debe ser del técnico del token (misma respuesta si no existe o no es suya).
-- Resultados: 1 mensaje · 2 marcas (marca) · 3 tipos (id_suministro, descripcion, clase, marca, modelo).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerOpcionesEquipoNuevoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerOpcionesEquipoNuevoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1
                   FROM   orden_servicio os
                   WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
                     AND  (os.id_tecnico_principal = p_id_usuario
                           OR EXISTS (SELECT 1 FROM os_personal op
                                      WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))) THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.String1 AS marca
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'MARCA_SUMINISTRO' AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND NULLIF(TRIM(t.String1), '') IS NOT NULL
    ORDER BY t.String1;

    SELECT su.id_suministro, su.descripcion, su.clase, NULLIF(TRIM(su.marca), '') AS marca, NULLIF(TRIM(su.modelo), '') AS modelo
    FROM   suministros su
    WHERE  su.eliminado_en IS NULL AND su.estado = 'activo' AND su.clase IN ('equipo', 'instrumento', 'pesa')
    ORDER BY su.descripcion
    LIMIT 500;
END$$

DELIMITER ;
