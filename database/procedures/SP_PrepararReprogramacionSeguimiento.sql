-- HU-20 Datos del modal "Reprogramar Próxima Acción".
-- Solo propuestas en seguimiento ABIERTO del área del usuario, con la acción
-- propuesta_seguimiento_reprogramar.
-- Resultados:
--   1 mensaje
--   2 acción actual: tipo, fecha programada, prioridad y responsable (origen 'programada' si se
--     registró en un seguimiento o reprogramación, 'calculada' si es el plazo por defecto del SLA)
--   3 tipos de acción (TIPO_ACCION_SEGUIMIENTO)
--   4 prioridades (PRIORIDAD)
--   5 responsables posibles (usuarios activos del área)
--   6 motivos de reprogramación (MOTIVO_REPROGRAMACION_SEGUIMIENTO)
--   7 historial de reprogramaciones de la propuesta (más reciente primero)
DROP PROCEDURE IF EXISTS SP_PrepararReprogramacionSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_PrepararReprogramacionSeguimiento(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT
)
BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_id_responsable BIGINT;
    DECLARE v_area           VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_reprogramar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reprogramar acciones de seguimiento.' AS Mensaje;
    ELSE
        CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                             v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

        SELECT COUNT(*), MAX(id_responsable),
               IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
          INTO v_existe, v_id_responsable, v_abierta
        FROM tmp_seg;

        IF v_existe = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje,
                   'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        ELSEIF v_abierta = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje,
                   'El seguimiento de esta propuesta ya está cerrado (aceptada o rechazada).' AS Mensaje;
        ELSE
            SELECT area INTO v_area FROM usuario WHERE id_usuario = v_id_responsable;

            -- 1. Header
            SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

            -- 2. Acción actual
            SELECT
                t.id_propuesta, t.numero, t.version, t.id_cliente, c.razon_social,
                t.proxima_accion_codigo, t.proxima_accion,
                t.id_tipo_proxima_accion                         AS id_tipo_accion,
                t.vence_accion                                   AS fecha_programada,
                t.id_prioridad_accion, pr.String1                AS prioridad, pr.String3 AS prioridad_codigo,
                COALESCE(t.id_responsable_accion, t.id_responsable) AS id_responsable_accion,
                (SELECT CONCAT(u.nombre, ' ', u.apellido) FROM usuario u
                 WHERE u.id_usuario = COALESCE(t.id_responsable_accion, t.id_responsable)) AS responsable_accion,
                IF(t.id_tipo_proxima_accion IS NULL AND t.proxima_accion_fecha IS NULL,
                   'calculada', 'programada')                    AS origen,
                t.sla_estado, t.estado_seguimiento,
                t.reprogramaciones,
                NOW()                                            AS fecha_servidor
            FROM tmp_seg t
            LEFT JOIN cliente c        ON c.id_cliente = t.id_cliente
            LEFT JOIN tabla_maestra pr ON pr.IdMaestro = 7 AND pr.IdEmpresa = 1 AND pr.Num1 = t.id_prioridad_accion;

            DROP TEMPORARY TABLE IF EXISTS tmp_seg;

            -- 3. Tipos de acción
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND IdEmpresa = 1
            ORDER BY Num1;

            -- 4. Prioridades
            SELECT Num1 AS id, String1 AS nombre, String3 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 7 AND IdEmpresa = 1
            ORDER BY Num1;

            -- 5. Responsables (usuarios activos del área del responsable de la propuesta)
            SELECT u.id_usuario AS id, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.cargo,
                   (u.id_usuario = p_id_usuario) AS es_usuario_actual
            FROM usuario u
            WHERE u.eliminado_en IS NULL AND u.estado = 'activo'
              AND (u.area = v_area OR u.id_usuario = p_id_usuario)
            ORDER BY (u.id_usuario = p_id_usuario) DESC, u.nombre, u.apellido;

            -- 6. Motivos
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE Descripcion = 'MOTIVO_REPROGRAMACION_SEGUIMIENTO' AND IdEmpresa = 1
            ORDER BY Num1;

            -- 7. Historial de reprogramaciones
            SELECT r.id_reprogramacion, r.creado_en AS fecha,
                   r.fecha_anterior, ta0.String1 AS tipo_anterior,
                   r.fecha_nueva,    ta1.String1 AS tipo_nuevo,
                   pr1.String1 AS prioridad_nueva,
                   CONCAT(un.nombre, ' ', un.apellido) AS responsable_nuevo,
                   mo.String1 AS motivo, mo.String2 AS motivo_codigo, r.detalle,
                   CONCAT(uc.nombre, ' ', uc.apellido) AS usuario
            FROM seguimiento_reprogramacion r
            LEFT JOIN tabla_maestra ta0 ON ta0.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND ta0.IdEmpresa = 1 AND ta0.Num1 = r.id_tipo_accion_anterior
            LEFT JOIN tabla_maestra ta1 ON ta1.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND ta1.IdEmpresa = 1 AND ta1.Num1 = r.id_tipo_accion_nueva
            LEFT JOIN tabla_maestra pr1 ON pr1.IdMaestro = 7 AND pr1.IdEmpresa = 1 AND pr1.Num1 = r.id_prioridad_nueva
            LEFT JOIN tabla_maestra mo  ON mo.Descripcion = 'MOTIVO_REPROGRAMACION_SEGUIMIENTO' AND mo.IdEmpresa = 1 AND mo.Num1 = r.id_motivo
            LEFT JOIN usuario un ON un.id_usuario = r.id_responsable_nuevo
            LEFT JOIN usuario uc ON uc.id_usuario = r.creado_por
            WHERE r.id_propuesta = p_id_propuesta AND r.eliminado_en IS NULL
            ORDER BY r.creado_en DESC, r.id_reprogramacion DESC;
        END IF;
    END IF;
END$$

DELIMITER ;
