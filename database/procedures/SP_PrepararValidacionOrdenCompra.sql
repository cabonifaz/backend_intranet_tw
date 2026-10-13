-- HU-26 Modales "Validar Orden de Compra" y "Observar Orden de Compra".
-- Acción oc_validar (jefe comercial) y OC del área del usuario.
-- Se puede validar u observar una OC pendiente de validación sin observación abierta.
-- Una OC observada se corrige con "Guardar y revalidar" (HU-24) y vuelve a quedar lista para validar.
-- Resultados:
--   1 mensaje
--   2 resumen comparativo: OC, propuesta, RQ, cliente/RUC, montos, PDF y dictamen
--     (aprobable | con_alertas | no_aprobable) con puede_validar y puede_observar
--   3 checklist de validación (requiere_confirmacion = 1: el validador lo confirma contra la OC física)
--   4 motivos de observación (MOTIVO_OBSERVACION_OC, tal cual)
--   5 responsables de corrección (usuarios que pueden editar la OC, el responsable comercial primero)
--   6 observaciones anteriores de la OC
DROP PROCEDURE IF EXISTS SP_PrepararValidacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararValidacionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_estado        VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_visual VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp       BIGINT;
    DECLARE v_area_resp     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_os          INT DEFAULT 0;
    DECLARE v_obs_abierta   INT DEFAULT 0;
    DECLARE v_fallan        INT DEFAULT 0;
    DECLARE v_puede         TINYINT DEFAULT 0;
    DECLARE v_motivo_no     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_validar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para validar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(estado_visual), MAX(id_responsable), MAX(ordenes_servicio)
      INTO v_existe, v_estado, v_estado_visual, v_id_resp, v_n_os
    FROM tmp_oc;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_obs_abierta
    FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL;
    SELECT area INTO v_area_resp FROM usuario WHERE id_usuario = v_id_resp;

    CALL SP_EvaluarValidacionOrdenCompra(p_id_oc);
    SELECT COUNT(*) INTO v_fallan FROM tmp_oc_check WHERE cumple_auto = 0;

    SET v_motivo_no = CASE
        WHEN v_estado <> 'pendiente_validacion' THEN 'La orden de compra ya fue validada.'
        WHEN v_obs_abierta > 0 THEN 'La OC tiene una observación abierta: debe corregirse y reenviarse a validación.'
        ELSE NULL END;
    SET v_puede = IF(v_motivo_no IS NULL, 1, 0);

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen comparativo
    SELECT t.id_oc, t.numero_oc, t.estado_bd AS estado, t.estado_visual,
           t.id_propuesta, t.numero_propuesta, t.version_propuesta,
           t.id_requerimiento, r.numero AS numero_rq,
           t.id_cliente, c.razon_social, c.ruc,
           t.monto_oc, t.monto_propuesta, t.id_moneda, m.String2 AS moneda_simbolo, m.String1 AS moneda_nombre,
           t.cobertura_pct, t.cobertura_proyectada,
           t.fecha_oc, t.fecha_recepcion, t.vigencia_hasta,
           oc.nombre_archivo_pdf,
           IF(t.tiene_pdf = 1, CONCAT('/api/crm/ordenes-compra/', t.id_oc, '/pdf'), NULL) AS url_pdf,
           t.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           CASE WHEN v_fallan = 0 THEN 'aprobable' WHEN v_fallan <= 1 THEN 'con_alertas' ELSE 'no_aprobable' END AS dictamen,
           CASE WHEN v_fallan = 0 THEN 'No se detectaron inconsistencias críticas entre el documento y el sistema.'
                ELSE CONCAT('Se detectaron ', v_fallan, ' inconsistencia(s). Corrija la OC u obsérvela.') END AS dictamen_mensaje,
           v_fallan                                       AS inconsistencias,
           IF(v_puede = 1 AND v_fallan = 0, 1, 0)         AS puede_validar,
           v_puede                                        AS puede_observar,
           v_motivo_no                                    AS motivo_no_disponible
    FROM tmp_oc t
    JOIN orden_compra oc      ON oc.id_oc = t.id_oc
    LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
    LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
    LEFT JOIN usuario u       ON u.id_usuario       = t.id_responsable
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    -- 3. Checklist
    SELECT orden, codigo, descripcion, valor_sistema, valor_referencia, cumple_auto, requiere_confirmacion, detalle
    FROM tmp_oc_check ORDER BY orden;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_check;

    -- 4. Motivos de observación (tal cual)
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra
    WHERE IdMaestro = 14 AND IdEmpresa = 1 AND eliminado_en IS NULL
    ORDER BY Num1;

    -- 5. Responsables de corrección
    SELECT u.id_usuario AS id,
           CONCAT(u.nombre, ' ', u.apellido) AS nombre,
           CONCAT(u.nombre, ' ', u.apellido,
                  IF(u.id_usuario = v_id_resp, ' (Comercial responsable)',
                     CONCAT(' (', CASE u.rol_sistema WHEN 'supervisor' THEN 'Jefe' WHEN 'administrador' THEN 'Administrador'
                                                     ELSE 'Asistente' END, ' ', u.area, ')'))) AS etiqueta,
           (u.id_usuario = v_id_resp) AS es_responsable_propuesta
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo'
      AND u.area = v_area_resp
      AND FN_PermisoAccion(u.id_usuario, 'oc_editar') = 1
    ORDER BY (u.id_usuario = v_id_resp) DESC, nombre;

    -- 6. Observaciones anteriores
    SELECT o.id_observacion, o.estado, o.detalle, o.fecha_observacion, o.fecha_levantamiento,
           CONCAT(uc.nombre, ' ', uc.apellido) AS observado_por,
           CONCAT(ur.nombre, ' ', ur.apellido) AS responsable_correccion,
           (SELECT GROUP_CONCAT(tm.String1 ORDER BY tm.Num1 SEPARATOR ', ')
            FROM orden_compra_observacion_motivo om
            JOIN tabla_maestra tm ON tm.IdMaestro = 14 AND tm.IdEmpresa = 1 AND tm.Num1 = om.id_motivo
            WHERE om.id_observacion = o.id_observacion AND om.eliminado_en IS NULL) AS motivos
    FROM orden_compra_observacion o
    LEFT JOIN usuario uc ON uc.id_usuario = o.creado_por
    LEFT JOIN usuario ur ON ur.id_usuario = o.id_responsable_correccion
    WHERE o.id_oc = p_id_oc AND o.eliminado_en IS NULL
    ORDER BY o.fecha_observacion DESC;
END$$

DELIMITER ;
