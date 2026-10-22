-- HU-33 Opción C "Todo lo pendiente del comercial": impacto global de reasignar la cartera activa de un comercial en
-- TODOS los expedientes (uso: renuncia, vacaciones largas). Es informativo y masivo (sin exclusiones: para excluir se
-- usa la Opción B). Acción expediente_reasignar; se abre desde un expediente en etapa comercial.
-- p_id_responsable = comercial cuya cartera se reasigna (por defecto el responsable actual del expediente).
-- Resultados: 1 mensaje · 2 resumen (comercial, total de entidades, expedientes, RQ, propuestas, OC y OS activos)
--   · 3 expedientes afectados (código, cliente, etapa actual, SLA restante, entidades activas)
--   · 4 entidades de cada expediente (para expandir la fila)
DROP PROCEDURE IF EXISTS SP_ObtenerCarteraComercialExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCarteraComercialExpediente(
    IN p_id_usuario     BIGINT,
    IN p_id_expediente  BIGINT,
    IN p_id_responsable BIGINT
)
proc: BEGIN
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_etapa     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comercial TINYINT DEFAULT 0;
    DECLARE v_resp      BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar responsables.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Todos los expedientes (para la etapa y el SLA de cada uno)
    CALL SP_CalcularExpedientes(p_id_usuario, NULL);
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
    SELECT COUNT(*), MAX(etapa), MAX(etapa_comercial), MAX(id_responsable)
      INTO v_existe, v_etapa, v_comercial, v_resp
    FROM tmp_exp WHERE id_expediente = p_id_expediente;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' OR v_comercial = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje,
               'La reasignación solo está disponible en las etapas comerciales (RQ, Propuesta, VB, Seguimiento, OC u OS).' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_resp = IFNULL(NULLIF(p_id_responsable, 0), v_resp);
    IF v_resp IS NULL OR NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = v_resp) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'Seleccione el comercial cuya cartera se reasignará.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarCarteraComercial(v_resp);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT v_resp AS id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable, u.cargo AS cargo_responsable,
           a.String1 AS area_responsable,
           k.total_entidades, k.expedientes, k.requerimientos, k.propuestas, k.ordenes_compra, k.ordenes_servicio
    FROM usuario u
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = u.area
    CROSS JOIN (SELECT COUNT(*) AS total_entidades, COUNT(DISTINCT id_expediente) AS expedientes,
                       IFNULL(SUM(entidad_tipo = 'requerimiento'), 0) AS requerimientos,
                       IFNULL(SUM(entidad_tipo = 'propuesta'), 0) AS propuestas,
                       IFNULL(SUM(entidad_tipo = 'orden_compra'), 0) AS ordenes_compra,
                       IFNULL(SUM(entidad_tipo = 'orden_servicio'), 0) AS ordenes_servicio
                FROM tmp_cartera) k
    WHERE u.id_usuario = v_resp;

    -- 3. Expedientes afectados
    SELECT x.id_expediente, x.numero, c.razon_social AS cliente, x.etapa, x.etapa_nombre, x.sla_estado,
           x.sla_minutos_restantes, x.fecha_limite, k.entidades
    FROM (SELECT id_expediente, COUNT(*) AS entidades FROM tmp_cartera GROUP BY id_expediente) k
    JOIN tmp_exp x ON x.id_expediente = k.id_expediente
    LEFT JOIN cliente c ON c.id_cliente = x.id_cliente
    ORDER BY (x.sla_estado = 'vencido') DESC, x.sla_minutos_restantes, x.id_expediente DESC;

    -- 4. Entidades por expediente
    SELECT t.id_expediente, t.entidad_tipo, t.id_entidad, t.codigo, t.estado, t.detalle
    FROM tmp_cartera t
    ORDER BY t.id_expediente DESC, FIELD(t.entidad_tipo, 'requerimiento', 'propuesta', 'orden_compra', 'orden_servicio'), t.id_entidad;

    DROP TEMPORARY TABLE IF EXISTS tmp_cartera;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
