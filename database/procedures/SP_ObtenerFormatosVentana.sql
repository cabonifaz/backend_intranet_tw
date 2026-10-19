-- Códigos de formato por ventana (calidad / procedimientos acreditados).
--   p_clave NULL → todas; con clave → una sola. "etiqueta" es lo que se muestra en pantalla.
DROP PROCEDURE IF EXISTS SP_ObtenerFormatosVentana;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFormatosVentana(
    IN p_clave VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT clave, nombre_ventana, codigo_formato, version,
           CASE
               WHEN codigo_formato IS NULL THEN NULL
               WHEN version IS NULL        THEN codigo_formato
               ELSE CONCAT(codigo_formato, '-', LPAD(version, 2, '0'))
           END AS etiqueta,
           FchMod AS fecha_modificacion
    FROM formato_ventana
    WHERE p_clave IS NULL OR p_clave = '' OR clave = p_clave
    ORDER BY nombre_ventana;
END$$

DELIMITER ;
