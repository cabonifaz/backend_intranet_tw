-- HU-16 — Candidatos a nuevo aprobador (buscador del modal).
--   Usuarios activos que pueden resolver VB (acción propuesta_vb_resolver), cuyo rol
--   puede supervisar (ROL_SISTEMA Num3 = 1) y no es inferior al del comercial autor
--   (ROL_SISTEMA Num1: menor número = rol más alto).
--   Se excluyen el comercial autor y el aprobador actual. p_buscar filtra por nombre,
--   apellido, correo o cargo. Máximo 20 resultados.
--   Resultados: 1 header · 2 candidatos
DROP PROCEDURE IF EXISTS SP_ObtenerCandidatosReasignacionVb;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCandidatosReasignacionVb(
    IN p_id_propuesta BIGINT,
    IN p_buscar       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_vb      BIGINT;
    DECLARE v_autor      BIGINT;
    DECLARE v_aprobador  BIGINT;
    DECLARE v_nivel_aut  INT;

    SELECT vb.id_vb, COALESCE(p.id_responsable, p.id_creador)
      INTO v_id_vb, v_autor
    FROM visto_bueno vb
    JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta AND p.eliminado_en IS NULL
    WHERE vb.id_propuesta = p_id_propuesta AND vb.estado = 'pendiente' AND vb.eliminado_en IS NULL
    ORDER BY vb.id_vb DESC LIMIT 1;

    IF v_id_vb IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no tiene un visto bueno pendiente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_aprobador = FN_AprobadorVistoBueno(v_id_vb);
    SET p_buscar    = NULLIF(TRIM(p_buscar), '');

    SELECT IFNULL(t.Num1, 99) INTO v_nivel_aut
    FROM usuario u
    LEFT JOIN tabla_maestra t ON t.IdMaestro = 68 AND t.IdEmpresa = 1 AND t.String2 = u.rol_sistema
    WHERE u.id_usuario = v_autor;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT u.id_usuario,
           CONCAT(u.nombre, ' ', u.apellido) AS nombre,
           u.cargo, u.area, u.rol_sistema, u.correo
    FROM usuario u
    JOIN tabla_maestra t ON t.IdMaestro = 68 AND t.IdEmpresa = 1 AND t.String2 = u.rol_sistema AND t.Num3 = 1
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo'
      AND u.id_usuario <> v_autor
      AND u.id_usuario <> IFNULL(v_aprobador, 0)
      AND IFNULL(t.Num1, 99) <= IFNULL(v_nivel_aut, 99)
      AND FN_PermisoAccion(u.id_usuario, 'propuesta_vb_resolver') = 1
      AND (p_buscar IS NULL
           OR CONCAT(u.nombre, ' ', u.apellido) LIKE CONCAT('%', p_buscar, '%')
           OR u.correo LIKE CONCAT('%', p_buscar, '%')
           OR u.cargo  LIKE CONCAT('%', p_buscar, '%'))
    ORDER BY t.Num1, u.nombre, u.apellido
    LIMIT 20;
END$$

DELIMITER ;
