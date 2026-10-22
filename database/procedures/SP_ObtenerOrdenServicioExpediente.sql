-- HU-30 Tab ⚙️ OS de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Datos de la OS vinculada al expediente (el módulo de OS la genera; "Ir al módulo OS" para editar).
-- p_id_os = OS elegida (por defecto la primera no anulada). Si aún no hay OS, devuelve las listas vacías.
-- Resultados: 1 mensaje · 2 OS del expediente (pills) · 3 datos de la OS (cronograma, sede, técnico principal,
--   responsable comercial, estado, confirmación del cliente, costo estimado) · 4 personal técnico asignado
--   · 5 equipos a intervenir · 6 viáticos y gastos · 7 órdenes de metrología del expediente
DROP PROCEDURE IF EXISTS SP_ObtenerOrdenServicioExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerOrdenServicioExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_os         BIGINT
)
proc: BEGIN
    DECLARE v_id_os BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_os, 0) > 0 THEN
        SELECT id_os INTO v_id_os FROM orden_servicio
        WHERE id_os = p_id_os AND id_expediente = p_id_expediente AND eliminado_en IS NULL;
        IF v_id_os IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La orden de servicio no pertenece a este expediente.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SELECT id_os INTO v_id_os FROM orden_servicio
        WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL
        ORDER BY (estado = 'anulada'), id_os LIMIT 1;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OS (pills)
    SELECT os.id_os, os.numero, os.estado, os.fecha_ejecucion, (os.id_os = v_id_os) AS seleccionada
    FROM orden_servicio os WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL ORDER BY os.id_os;

    -- 3. Datos de la OS
    SELECT os.id_os, os.numero, os.estado, os.fecha_creacion, os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada,
           os.hora_llegada_real, os.hora_fin_real, os.costo_total_estimado,
           ts.String1 AS tipo_servicio, s.nombre AS sede, s.direccion_exacta AS sede_direccion,
           os.id_tecnico_principal, CONCAT(ut.nombre, ' ', ut.apellido) AS tecnico_principal,
           os.id_responsable_comercial, CONCAT(uc.nombre, ' ', uc.apellido) AS responsable_comercial,
           os.confirmacion_cliente, os.fecha_confirmacion_cliente, cn.String1 AS canal_confirmacion,
           ct.nombres AS contacto_confirma, os.notas_operativas,
           os.creado_por AS id_generado_por, CONCAT(ug.nombre, ' ', ug.apellido) AS generado_por
    FROM orden_servicio os
    LEFT JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN sede_cliente s   ON s.id_sede = os.id_sede
    LEFT JOIN usuario ut       ON ut.id_usuario = os.id_tecnico_principal
    LEFT JOIN usuario uc       ON uc.id_usuario = os.id_responsable_comercial
    LEFT JOIN usuario ug       ON ug.id_usuario = os.creado_por
    LEFT JOIN tabla_maestra cn ON cn.IdMaestro = 26 AND cn.IdEmpresa = 1 AND cn.Num1 = os.id_canal_confirmacion
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = os.id_contacto_confirma
    WHERE os.id_os = v_id_os;

    -- 4. Personal técnico asignado
    SELECT p.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.cargo, p.rol_en_servicio, p.estado_ssoma
    FROM os_personal p LEFT JOIN usuario u ON u.id_usuario = p.id_usuario
    WHERE p.id_os = v_id_os AND p.eliminado_en IS NULL ORDER BY p.id;

    -- 5. Equipos a intervenir
    SELECT oe.id_equipo, COALESCE(ec.codigo_tw, e.codigo_tw) AS codigo_tw, ec.codigo_cliente,
           COALESCE(ec.marca, NULL) AS marca, COALESCE(ec.modelo, e.modelo) AS modelo,
           COALESCE(ec.num_serie, e.numero_serie) AS numero_serie, COALESCE(ec.ubicacion_especifica, e.ubicacion) AS ubicacion,
           ti.String1 AS tipo_intervencion, oe.ingresado_en_campo
    FROM os_equipo oe
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN equipo e          ON e.id_equipo = oe.id_equipo
    LEFT JOIN tabla_maestra ti  ON ti.IdMaestro = 31 AND ti.IdEmpresa = 1 AND ti.Num1 = oe.id_tipo_intervencion
    WHERE oe.id_os = v_id_os AND oe.eliminado_en IS NULL ORDER BY oe.id;

    -- 6. Viáticos y gastos
    SELECT g.id_gasto, g.tipo, cg.String1 AS concepto, g.monto, m.String2 AS simbolo_moneda, g.descripcion, g.estado,
           g.fecha_solicitud, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM gasto_viatico g
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = g.id_moneda
    LEFT JOIN usuario u        ON u.id_usuario = g.id_usuario
    WHERE g.id_os = v_id_os AND g.eliminado_en IS NULL ORDER BY g.fecha_solicitud, g.id_gasto;

    -- 7. Órdenes de metrología del expediente
    SELECT om.id_om, om.numero, om.estado, om.fecha_calibracion, om.numero_certificado, om.fecha_emision_certificado,
           CONCAT(u.nombre, ' ', u.apellido) AS metrologo
    FROM orden_metrologia om LEFT JOIN usuario u ON u.id_usuario = om.id_metrologo
    WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL ORDER BY om.id_om;
END$$

DELIMITER ;
