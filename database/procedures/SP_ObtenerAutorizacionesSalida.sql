-- ============================================================
-- SP_ObtenerAutorizacionesSalida  (Intranet · App Mobile HU-04)
-- Bandeja de solicitudes de visto bueno de salida de los técnicos.
--   p_estado: pendiente | aprobada | rechazada | (vacío = todas)
--   Encargado de área (Jefe de Servicio Técnico / Jefe de Metrología, o el supervisor del área Metrología): solo las de SU área
--   (y las que no tienen área en la RQ). Jefe/Coordinador de Operaciones, supervisor del área Operaciones y administradores: todas.
-- id_tecnico (última columna): quién la pidió; la app móvil del Jefe lo usa para mostrar el checklist de ese técnico.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAutorizacionesSalida;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAutorizacionesSalida(
    IN p_id_usuario BIGINT,
    IN p_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM usuario u
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo';
    -- Regla Área + Rol (SP_ResolverAprobadorMovil): otras áreas con cualquier rol y Administradores ven todo; Supervisor de ST / Metrología, solo su área
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

    IF v_existe = 0 OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los encargados de Servicio Técnico y Metrología pueden ver las autorizaciones de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = LOWER(TRIM(IFNULL(p_estado, '')));
    IF v_estado NOT IN ('', 'pendiente', 'aprobada', 'rechazada') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use pendiente, aprobada o rechazada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT a.id_autorizacion,
           a.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           os.estado                                                        AS estado_os,
           NULLIF(TRIM(CONCAT(IFNULL(tc.nombre, ''), ' ', IFNULL(tc.apellido, ''))), '') AS tecnico,
           a.motivo,
           a.pendientes,
           a.estado,
           a.area_destino,
           ar.String1                                                       AS area,
           a.solicitado_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS jefe,
           a.resuelto_en,
           a.comentario,
           a.id_tecnico
    FROM   autorizacion_salida_os a
    JOIN   orden_servicio os ON os.id_os = a.id_os AND os.eliminado_en IS NULL
    LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    LEFT JOIN usuario tc ON tc.id_usuario = a.id_tecnico
    LEFT JOIN usuario jf ON jf.id_usuario = a.id_jefe
    LEFT JOIN tabla_maestra ar ON ar.IdMaestro = 79 AND ar.IdEmpresa = 1 AND ar.String2 = a.area_destino
    WHERE  a.eliminado_en IS NULL
      AND  (v_estado = '' OR a.estado = v_estado)
      AND  (v_general = 1 OR a.area_destino IS NULL OR a.area_destino = v_area_jefe)
    ORDER BY (a.estado = 'pendiente') DESC, IFNULL(a.solicitado_en, a.creado_en) DESC
    LIMIT 200;
END$$

DELIMITER ;
