-- HU-28 Modal "Liberar para Programación".
-- Acción oc_liberar y OC del área del usuario.
-- Resultados:
--   1 mensaje
--   2 cabecera: OC, cliente, expediente (se crea al liberar si no existe), si se puede liberar,
--     si requiere confirmar alertas, impacto, siguiente etapa (Programación), responsable (Operaciones) y SLA
--   3 validaciones de cumplimiento (estado: cumple | alerta | bloqueante)
DROP PROCEDURE IF EXISTS SP_PrepararLiberacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararLiberacionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_bloqueantes INT DEFAULT 0;
    DECLARE v_alertas     INT DEFAULT 0;
    DECLARE v_texto_alert VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sla         INT DEFAULT 4;

    IF FN_PermisoAccion(p_id_usuario, 'oc_liberar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para liberar expedientes a programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*) INTO v_existe FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarLiberacionOrdenCompra(p_id_usuario, p_id_oc);
    SELECT IFNULL(SUM(estado = 'bloqueante'), 0), IFNULL(SUM(estado = 'alerta'), 0),
           GROUP_CONCAT(IF(estado = 'alerta', descripcion, NULL) ORDER BY orden SEPARATOR ', ')
      INTO v_bloqueantes, v_alertas, v_texto_alert
    FROM tmp_lib;

    SELECT CAST(IFNULL(MAX(Num2), 4) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'expediente' AND String2 = 'programacion';

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT oc.id_oc, oc.numero_oc, oc.id_cliente, c.razon_social,
           e.id_expediente, e.numero AS numero_expediente, e.etapa_actual AS etapa_expediente, e.estado AS estado_expediente,
           (e.id_expediente IS NULL)                         AS crea_expediente,
           IF(v_bloqueantes = 0, 1, 0)                       AS puede_liberar,
           IF(v_bloqueantes = 0 AND v_alertas > 0, 1, 0)     AS requiere_confirmacion,
           v_bloqueantes                                     AS bloqueantes,
           v_alertas                                         AS alertas,
           CASE WHEN v_bloqueantes > 0 THEN 'Resuelva los puntos bloqueantes antes de liberar el expediente.'
                WHEN v_alertas > 0     THEN CONCAT('Se liberará con requisitos pendientes (', v_texto_alert,
                                                   '). La responsabilidad de completarlos pasa a Operaciones antes de la salida a campo.')
                ELSE 'Todas las validaciones de cumplimiento están conformes.' END AS impacto,
           'La liberación para programación permite que el equipo de Operaciones asigne recursos. No constituye una habilitación inmediata para ejecución: el expediente debe completar las validaciones SSOMA definitivas antes de la salida a campo.' AS informacion_proceso,
           'programacion'                                    AS siguiente_etapa_codigo,
           'Programación'                                    AS siguiente_etapa,
           'Operaciones'                                     AS responsable_siguiente_etapa,
           v_sla                                             AS sla_horas
    FROM orden_compra oc
    LEFT JOIN cliente c ON c.id_cliente = oc.id_cliente
    LEFT JOIN expediente_digital e ON e.id_expediente = FN_ExpedienteDePropuesta(oc.id_propuesta)
    WHERE oc.id_oc = p_id_oc;

    -- 3. Validaciones de cumplimiento
    SELECT orden, codigo, descripcion, estado, fecha, detalle FROM tmp_lib ORDER BY orden;
    DROP TEMPORARY TABLE IF EXISTS tmp_lib;
END$$

DELIMITER ;
