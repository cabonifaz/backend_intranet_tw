-- ============================================================
-- SP_ValidarNombreUsuario  (App Mobile HU-01 / HU-83 intranet)
-- Ficha de usuario: devuelve los usuarios de app vigentes que empiezan con el
-- texto indicado (el mismo texto incluido), para que el caso de uso decida si
-- el nombre está libre y proponga una variante (juan.perez2, juan.perez3...).
--   p_prefijo:            nombre de usuario ya normalizado (minúsculas).
--   p_excluir_id_usuario: en edición, el propio usuario (para no chocar consigo mismo).
-- No hay UNIQUE en la tabla por el borrado lógico: la unicidad la valida
-- SP_GuardarUsuario / SP_AsignarAccesoMovil; esto solo es la ayuda en línea.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValidarNombreUsuario;

DELIMITER $$

CREATE PROCEDURE SP_ValidarNombreUsuario(
    IN p_prefijo             VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_excluir_id_usuario  BIGINT
)
BEGIN
    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Nombres en uso con ese prefijo
    SELECT u.nombre_usuario
    FROM   usuario u
    WHERE  u.nombre_usuario IS NOT NULL
      AND  u.eliminado_en   IS NULL
      AND  (p_excluir_id_usuario IS NULL OR p_excluir_id_usuario = 0 OR u.id_usuario <> p_excluir_id_usuario)
      AND  LEFT(u.nombre_usuario, CHAR_LENGTH(p_prefijo)) = p_prefijo;
END$$

DELIMITER ;
