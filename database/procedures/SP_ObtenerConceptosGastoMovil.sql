-- ============================================================
-- SP_ObtenerConceptosGastoMovil  (App Mobile HU-27 — "Nueva solicitud de gasto" · lectura)
-- Catálogo de conceptos del gasto (CONCEPTO_GASTO, el mismo de la intranet) para elegir el concepto de un reembolso. es_otro = 1 en "Otro":
-- la app pide entonces el texto del concepto. Solo se listan los conceptos activos; "Otro" va al final. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConceptosGastoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConceptosGastoMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT m.Num1 AS id_concepto, m.String1 AS concepto, IF(m.String3 = 'OTRO', 1, 0) AS es_otro
    FROM   tabla_maestra m
    WHERE  m.IdMaestro = 25 AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL AND m.Num1 IS NOT NULL
    ORDER BY (m.String3 = 'OTRO'), m.String1;
END$$

DELIMITER ;
