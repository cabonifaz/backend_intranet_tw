-- HU-16 — Datos del modal "Reasignar Aprobador".
--   Aprobador actual con su fecha de asignación, SLA (horas hábiles transcurridas
--   y restantes), si el usuario puede reasignar y los motivos (MOTIVO_REASIGNACION_VB tal cual).
--   Resultados: 1 header · 2 resumen · 3 motivos
DROP PROCEDURE IF EXISTS SP_PrepararReasignacionVistoBueno;

DELIMITER $$

CREATE PROCEDURE SP_PrepararReasignacionVistoBueno(
    IN p_id_propuesta BIGINT,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_estado_p  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_vb     BIGINT;
    DECLARE v_puede     TINYINT DEFAULT 1;
    DECLARE v_bloqueo   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SELECT estado INTO v_estado_p
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado_p IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_vb INTO v_id_vb
    FROM visto_bueno
    WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente' AND eliminado_en IS NULL
    ORDER BY id_vb DESC LIMIT 1;

    IF v_id_vb IS NULL OR v_estado_p <> 'pendiente_vb' THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no tiene un visto bueno pendiente.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_reasignar') = 0 THEN
        SET v_puede = 0, v_bloqueo = 'No tiene permiso para reasignar el visto bueno.';
    ELSEIF FN_PuedeResolverVistoBueno(v_id_vb, p_id_usuario) = 0 THEN
        SET v_puede = 0, v_bloqueo = 'Solo el aprobador asignado puede reasignar este visto bueno.';
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT p.id_propuesta, p.numero, p.version,
           vb.id_vb                                                AS id_visto_bueno,
           FN_AprobadorVistoBueno(vb.id_vb)                        AS id_aprobador,
           CONCAT(ua.nombre, ' ', ua.apellido)                     AS nombre_aprobador,
           ua.cargo                                                AS cargo_aprobador,
           IF(vb.id_vb_origen IS NULL, vb.fecha_solicitud, vb.creado_en) AS fecha_asignacion,
           (vb.id_vb_origen IS NOT NULL)                           AS reasignado,
           vb.fecha_solicitud,
           vb.sla_horas,
           FN_HorasHabiles(vb.fecha_solicitud, NOW())              AS horas_transcurridas,
           GREATEST(vb.sla_horas - FN_HorasHabiles(vb.fecha_solicitud, NOW()), 0) AS horas_restantes,
           FN_SumarHorasHabiles(vb.fecha_solicitud, vb.sla_horas)  AS vence_en,
           COALESCE(p.id_responsable, p.id_creador)                AS id_comercial,
           CONCAT(uc.nombre, ' ', uc.apellido)                     AS nombre_comercial,
           v_puede                                                 AS puede_reasignar,
           v_bloqueo                                               AS motivo_bloqueo
    FROM visto_bueno vb
    JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
    LEFT JOIN usuario ua ON ua.id_usuario = FN_AprobadorVistoBueno(vb.id_vb)
    LEFT JOIN usuario uc ON uc.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE vb.id_vb = v_id_vb;

    SELECT Num1 AS id, String1 AS nombre
    FROM tabla_maestra
    WHERE Descripcion = 'MOTIVO_REASIGNACION_VB' AND eliminado_en IS NULL
    ORDER BY Num1;
END$$

DELIMITER ;
