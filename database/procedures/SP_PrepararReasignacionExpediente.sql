-- HU-33 Datos del modal "Reasignar Responsable" (Opciones A y B). Acción expediente_reasignar (Jefe Comercial /
-- Administrador). Solo cuando el expediente está en una etapa comercial (RQ, Propuesta, VB, Seguimiento, OC u OS).
-- Resultados: 1 mensaje
--   2 datos: expediente, cliente, etapa, responsable actual (nombre, cargo, área), SLA de la etapa
--   3 árbol de entidades ACTIVAS reasignables (RQ, propuestas, OC y OS) con su responsable y su padre (clave_padre):
--     Opción A = cualquiera; Opción B = raíz + descendientes (el front arma el preview y la personalización)
--   4 motivos (MOTIVO_REASIGNACION_EXPEDIENTE, tal cual) · 5 gestión del SLA
-- El seguimiento no se lista: hereda el responsable de su propuesta. Las entidades finalizadas tampoco.
DROP PROCEDURE IF EXISTS SP_PrepararReasignacionExpediente;

DELIMITER $$

CREATE PROCEDURE SP_PrepararReasignacionExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_etapa     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comercial TINYINT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar responsables.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
    SELECT COUNT(*), MAX(etapa), MAX(etapa_comercial) INTO v_existe, v_etapa, v_comercial FROM tmp_exp;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado: sus entidades conservan su responsable histórico.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_comercial = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje,
               'La reasignación solo está disponible en las etapas comerciales (RQ, Propuesta, VB, Seguimiento, OC u OS).' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarEntidadesExpediente(p_id_expediente);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos
    SELECT x.id_expediente, x.numero, c.razon_social, c.ruc, x.etapa, x.etapa_nombre,
           x.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable, u.cargo AS cargo_responsable,
           a.String1 AS area_responsable, x.sla_horas, x.fecha_limite, x.sla_estado, x.sla_minutos_restantes,
           'Se notificará automáticamente al nuevo responsable y al responsable anterior por correo y en la intranet.' AS nota_impacto
    FROM tmp_exp x
    LEFT JOIN cliente c       ON c.id_cliente = x.id_cliente
    LEFT JOIN usuario u       ON u.id_usuario = x.id_responsable
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = u.area;

    -- 3. Entidades activas reasignables
    SELECT e.clave, e.clave_padre, e.nivel, e.entidad_tipo, e.id_entidad, e.codigo, e.version, e.estado, e.monto,
           mo.String2 AS simbolo_moneda, e.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           e.detalle, e.es_activa_exp
    FROM tmp_exp_ent e
    LEFT JOIN usuario u        ON u.id_usuario = e.id_responsable
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = e.id_moneda
    WHERE e.activa = 1 AND e.entidad_tipo IN ('requerimiento', 'propuesta', 'orden_compra', 'orden_servicio')
    ORDER BY e.nivel, e.orden, e.id_entidad DESC;

    -- 4. Motivos
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra WHERE IdMaestro = 100 AND IdEmpresa = 1 AND eliminado_en IS NULL ORDER BY Num1;

    -- 5. Gestión del SLA
    SELECT 'mantener' AS codigo, 'Mantener SLA restante' AS nombre UNION ALL
    SELECT 'reiniciar', 'Reiniciar SLA desde ahora';

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
