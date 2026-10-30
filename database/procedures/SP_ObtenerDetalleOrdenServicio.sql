-- HU-42 (Sprint 4) Modal de Detalle de OS/OM: cabecera (con acciones y solicitud de edición pendiente), tab Resumen
-- (datos generales) y bloque "Avance por Equipos" (estado de ejecución por equipo, Módulo 11). Solo lectura.
-- Los demás tabs se cargan aparte (SP_ObtenerTabOrdenServicio).
-- Acceso: os_bandeja u os_bandeja_operaciones (Operaciones no ve borradores).
-- Resultados: 1 mensaje, 2 cabecera y resumen, 3 avance por equipos.
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_comercial TINYINT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_guardar   TINYINT;
    DECLARE v_jefe      TINYINT;
    DECLARE v_anular    TINYINT;

    SET v_comercial = FN_PermisoAccion(p_id_usuario, 'os_bandeja');
    SELECT estado INTO v_estado FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL;

    IF v_comercial = 0 AND FN_PermisoAccion(p_id_usuario, 'os_bandeja_operaciones') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado IS NULL OR (v_estado = 'borrador' AND v_comercial = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_guardar = FN_PermisoAccion(p_id_usuario, 'os_guardar');
    SET v_jefe    = FN_PermisoAccion(p_id_usuario, 'os_aprobar_edicion');
    SET v_anular  = FN_PermisoAccion(p_id_usuario, 'os_anular');

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera y Resumen
    SELECT os.id_os, os.tipo, os.numero, os.estado,
           CASE os.estado WHEN 'borrador' THEN 'borrador' WHEN 'emitida' THEN 'emitida' WHEN 'programada' THEN 'programada'
                          WHEN 'reprogramada' THEN 'programada' WHEN 'finalizada' THEN 'finalizada' WHEN 'anulada' THEN 'anulada'
                          ELSE 'en_ejecucion' END                                                     AS estado_grupo,
           CASE os.estado WHEN 'borrador' THEN 'Borrador' WHEN 'emitida' THEN 'Emitida' WHEN 'programada' THEN 'Programada'
                          WHEN 'reprogramada' THEN 'Reprogramada' WHEN 'en_ruta' THEN 'En ruta' WHEN 'en_ejecucion' THEN 'En ejecución'
                          WHEN 'pausada' THEN 'Pausada' WHEN 'bloqueada' THEN 'Bloqueada' WHEN 'finalizada' THEN 'Finalizada'
                          WHEN 'anulada' THEN 'Anulada' ELSE os.estado END                           AS estado_label,
           os.id_cliente, c.razon_social, c.ruc,
           COALESCE(NULLIF(sc.direccion_exacta, ''), NULLIF(c.direccion_fiscal, ''), c.domicilio_fiscal) AS direccion_operaciones,
           os.id_contacto, ct.nombres AS contacto, ct.cargo AS cargo_contacto, ct.telefono_movil AS telefono_contacto,
           ct.correo AS correo_contacto,
           os.id_responsable_comercial AS id_responsable, CONCAT(ur.nombre, ' ', ur.apellido) AS responsable,
           os.fecha_emision, COALESCE(os.fecha_emision, os.fecha_creacion, os.creado_en) AS fecha_documento,
           os.fecha_programada_desde, os.fecha_programada_hasta,
           COALESCE(os.id_propuesta, e.id_propuesta) AS id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta,
           COALESCE(os.id_requerimiento, p.id_requerimiento, e.id_requerimiento) AS id_requerimiento, r.numero AS numero_rq,
           os.id_expediente,
           (SELECT COUNT(*) FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.eliminado_en IS NULL)   AS n_equipos,
           (SELECT COUNT(*) FROM os_concepto oc WHERE oc.id_os = os.id_os AND oc.eliminado_en IS NULL) AS n_conceptos,
           -- Solicitud de edición pendiente (chip amarillo)
           sp.id_solicitud AS id_solicitud_pendiente, msp.String1 AS motivo_solicitud, sp.comentario AS comentario_solicitud,
           sp.fecha_solicitud, sp.id_solicitante, CONCAT(us.nombre, ' ', us.apellido) AS solicitante,
           sp.id_aprobador, CONCAT(uj.nombre, ' ', uj.apellido) AS aprobador_solicitud,
           (sa.id_solicitud IS NOT NULL)                                                                AS edicion_aprobada,
           -- Acciones
           -- Sin borradores: solo se edita con una solicitud de edición aprobada y aún no ejecutada
           (v_guardar = 1 AND sa.id_solicitud IS NOT NULL
            AND os.estado IN ('emitida', 'programada', 'reprogramada'))                               AS puede_editar,
           (v_guardar = 1 AND (os.id_responsable_comercial <=> p_id_usuario)
            AND os.estado IN ('emitida', 'programada', 'reprogramada') AND sp.id_solicitud IS NULL AND sa.id_solicitud IS NULL)
                                                                                                        AS puede_solicitar_edicion,
           (v_jefe = 1 AND sp.id_solicitud IS NOT NULL AND sp.id_solicitante <> p_id_usuario)           AS puede_resolver_solicitud,
           (v_anular = 1 AND os.estado IN ('borrador', 'emitida', 'programada', 'reprogramada'))        AS puede_anular,
           -- Anulación
           ma.String1 AS motivo_anulacion, os.comentario_anulacion, os.anulado_en, CONCAT(uan.nombre, ' ', uan.apellido) AS anulado_por,
           -- Footer: última actualización
           COALESCE(os.modificado_en, os.creado_en) AS ultima_actualizacion,
           IFNULL(CONCAT(um.nombre, ' ', um.apellido), 'Sistema') AS actualizado_por
    FROM orden_servicio os
    LEFT JOIN cliente c             ON c.id_cliente = os.id_cliente
    LEFT JOIN expediente_digital e  ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento r       ON r.id_requerimiento = COALESCE(os.id_requerimiento, p.id_requerimiento, e.id_requerimiento)
    LEFT JOIN sede_cliente sc       ON sc.id_sede = COALESCE(os.id_sede, p.id_sede)
    LEFT JOIN contacto_cliente ct   ON ct.id_contacto = os.id_contacto
    LEFT JOIN usuario ur            ON ur.id_usuario = os.id_responsable_comercial
    LEFT JOIN usuario um            ON um.id_usuario = COALESCE(os.modificado_por, os.creado_por)
    LEFT JOIN usuario uan           ON uan.id_usuario = os.anulado_por
    LEFT JOIN tabla_maestra ma      ON ma.Descripcion = 'MOTIVO_ANULACION_OS' AND ma.Num1 = os.id_motivo_anulacion
    LEFT JOIN os_solicitud sp       ON sp.id_solicitud = (SELECT MAX(s1.id_solicitud) FROM os_solicitud s1 WHERE s1.id_os = os.id_os
                                                            AND s1.tipo = 'edicion' AND s1.estado = 'pendiente' AND s1.eliminado_en IS NULL)
    LEFT JOIN tabla_maestra msp     ON msp.Descripcion = 'MOTIVO_EDICION_OS' AND msp.Num1 = sp.id_motivo
    LEFT JOIN usuario us            ON us.id_usuario = sp.id_solicitante
    LEFT JOIN usuario uj            ON uj.id_usuario = sp.id_aprobador
    LEFT JOIN os_solicitud sa       ON sa.id_solicitud = (SELECT MAX(s2.id_solicitud) FROM os_solicitud s2 WHERE s2.id_os = os.id_os
                                                            AND s2.tipo = 'edicion' AND s2.estado = 'aprobada'
                                                            AND s2.id_solicitante = p_id_usuario AND s2.eliminado_en IS NULL)
    WHERE os.id_os = p_id_os;

    -- 3. Avance por equipos (Módulo 11 Ejecución)
    SELECT oe.id AS id_os_equipo, ec.id_equipo, ec.codigo_tw, ec.clasificacion, COALESCE(tc.String1, ec.clasificacion) AS clasificacion_label,
           ec.marca, ec.modelo, ec.num_serie, oe.estado_ejecucion, oe.fecha_ejecucion, oe.observacion_ejecucion
    FROM os_equipo oe
    JOIN equipo_cliente ec     ON ec.id_equipo = oe.id_equipo
    LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    ORDER BY IFNULL(oe.orden, oe.id), oe.id;
END$$

DELIMITER ;
