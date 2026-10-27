-- HU-40 (Sprint 4) Modal "Solicitar Edición al Jefe Comercial": valida que se pueda solicitar y devuelve los motivos
-- y el Jefe Comercial al que se dirige la solicitud.
-- Jefe Comercial: el jefe directo del responsable (usuario.id_supervisor) si tiene la acción os_aprobar_edicion;
-- si no, el primer supervisor (o administrador) de Comercial con esa acción.
-- Resultados: 1 mensaje, 2 orden y aprobador, 3 motivos (MOTIVO_EDICION_OS).
DROP PROCEDURE IF EXISTS SP_PrepararSolicitudEdicionOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_PrepararSolicitudEdicionOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resp      BIGINT;
    DECLARE v_aprobador BIGINT;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT estado, id_responsable_comercial INTO v_estado, v_resp
    FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SET v_error = 'Orden de servicio no encontrada.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 OR NOT (v_resp <=> p_id_usuario) THEN
        SET v_error = 'Solo el comercial responsable de la orden puede solicitar su edición.';
    ELSEIF v_estado NOT IN ('emitida', 'programada', 'reprogramada') THEN
        SET v_error = IF(v_estado = 'borrador', 'La orden está en borrador: puede editarla directamente.',
                         CONCAT('La orden está ', UPPER(REPLACE(v_estado, '_', ' ')), ': ya no se puede editar.'));
    ELSEIF EXISTS (SELECT 1 FROM os_solicitud WHERE id_os = p_id_os AND tipo = 'edicion' AND estado = 'pendiente' AND eliminado_en IS NULL) THEN
        SET v_error = 'Ya hay una solicitud de edición pendiente de aprobación.';
    ELSEIF EXISTS (SELECT 1 FROM os_solicitud WHERE id_os = p_id_os AND tipo = 'edicion' AND estado = 'aprobada' AND eliminado_en IS NULL) THEN
        SET v_error = 'Ya tiene una edición aprobada: puede editar la orden.';
    END IF;
    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje; LEAVE proc;
    END IF;

    SELECT u.id_supervisor INTO v_aprobador FROM usuario u WHERE u.id_usuario = p_id_usuario;
    IF v_aprobador IS NULL OR v_aprobador = p_id_usuario
       OR NOT EXISTS (SELECT 1 FROM usuario j WHERE j.id_usuario = v_aprobador AND j.estado = 'activo' AND j.eliminado_en IS NULL)
       OR FN_PermisoAccion(v_aprobador, 'os_aprobar_edicion') = 0 THEN
        SELECT j.id_usuario INTO v_aprobador FROM usuario j
        WHERE j.estado = 'activo' AND j.eliminado_en IS NULL AND j.id_usuario <> p_id_usuario
          AND j.area = 'comercial' AND FN_PermisoAccion(j.id_usuario, 'os_aprobar_edicion') = 1
        ORDER BY (j.rol_sistema = 'supervisor') DESC, j.id_usuario LIMIT 1;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os, os.numero, os.tipo, os.estado, c.razon_social,
           v_aprobador AS id_aprobador, CONCAT(j.nombre, ' ', j.apellido) AS aprobador, j.cargo AS cargo_aprobador,
           j.sede_operativa AS sede_aprobador, (j.estado = 'activo') AS aprobador_disponible
    FROM orden_servicio os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN usuario j ON j.id_usuario = v_aprobador
    WHERE os.id_os = p_id_os;

    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra WHERE Descripcion = 'MOTIVO_EDICION_OS' AND eliminado_en IS NULL ORDER BY Num1;
END$$

DELIMITER ;
