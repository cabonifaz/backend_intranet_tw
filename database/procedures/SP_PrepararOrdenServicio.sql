-- HU-40 / HU-43 (Sprint 4) Ficha Nueva / Editar OS-OM.
--   Nueva:  p_id_propuesta = propuesta aceptada, p_id_os = 0. Precarga los datos del cliente, la propuesta origen y,
--           como sugerencias, los equipos y los conceptos de la propuesta. Una propuesta puede ejecutarse en varias
--           OS/OM: se precargan solo los equipos cotizados que aún no están en una OS/OM activa de la propuesta; los
--           conceptos se precargan completos, uno por ítem de servicio (mismo suministro con otro alcance = otro concepto).
--   Editar: p_id_os = la OS/OM. Solo quien tiene una solicitud de edición APROBADA (HU-40, flujo con el Jefe Comercial).
--           Las OS/OM no tienen borrador: se emiten al guardar.
-- Tipo: OM si el área de la RQ es Metrología (catálogo AREA_REQUERIMIENTO 64); OS en cualquier otro caso.
-- Resultados: 1 mensaje, 2 ficha (cliente, propuesta origen, documento, certificado), 3 contactos del cliente,
--             4 conceptos (con alcance y si son de la propuesta), 5 equipos (con los conceptos que aplican: ids de
--             suministro y de os_concepto, si están en otra OS activa y si son de la propuesta).
DROP PROCEDURE IF EXISTS SP_PrepararOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_PrepararOrdenServicio(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_id_os        BIGINT
)
proc: BEGIN
    DECLARE v_id_os        BIGINT DEFAULT NULL;
    DECLARE v_id_prop      BIGINT;
    DECLARE v_estado_prop  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente   BIGINT;
    DECLARE v_estado_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resp         BIGINT;
    DECLARE v_tipo         CHAR(2);
    DECLARE v_otra         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_sol       BIGINT DEFAULT NULL;
    DECLARE v_modo         VARCHAR(20);
    DECLARE v_numero       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_prop     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_os_activas   INT DEFAULT 0;
    DECLARE v_eq_cotizados INT DEFAULT 0;
    DECLARE v_eq_pend      INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para crear o editar órdenes de servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_os, 0) > 0 THEN
        -- ── Editar ──────────────────────────────────────────────────────────
        SELECT os.id_os, os.id_propuesta, os.estado, os.id_responsable_comercial, os.tipo, os.numero
          INTO v_id_os, v_id_prop, v_estado_os, v_resp, v_tipo, v_numero
        FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;

        IF v_id_os IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_id_prop IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Esta orden es anterior al módulo y no tiene propuesta origen: no se puede editar aquí.' AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT MAX(s.id_solicitud) INTO v_id_sol FROM os_solicitud s
        WHERE s.id_os = v_id_os AND s.tipo = 'edicion' AND s.estado = 'aprobada' AND s.id_solicitante = p_id_usuario
          AND s.eliminado_en IS NULL;
        IF v_id_sol IS NULL OR v_estado_os NOT IN ('borrador', 'emitida', 'programada', 'reprogramada') THEN
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('La orden está ', UPPER(REPLACE(v_estado_os, '_', ' ')),
                          ': para modificarla solicite la edición al Jefe Comercial.') AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_modo = 'edicion_aprobada';
    ELSE
        -- ── Nueva ───────────────────────────────────────────────────────────
        SET v_id_prop = p_id_propuesta;
        SELECT estado INTO v_estado_prop FROM propuesta_comercial WHERE id_propuesta = v_id_prop AND eliminado_en IS NULL;
        IF v_estado_prop IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_estado_prop <> 'aceptado' THEN
            SELECT 1 AS IdTipoMensaje, 'La OS/OM solo se genera desde una propuesta aceptada por el cliente.' AS Mensaje; LEAVE proc;
        END IF;

        IF EXISTS (SELECT 1 FROM propuesta_comercial p, propuesta_comercial p2
                   WHERE p.id_propuesta = v_id_prop AND p2.numero = p.numero AND p2.estado = 'aceptado'
                     AND p2.eliminado_en IS NULL AND p2.version > p.version) THEN
            SELECT 1 AS IdTipoMensaje, 'Hay una versión aceptada más reciente de esta propuesta: genere la orden desde esa versión.' AS Mensaje;
            LEAVE proc;
        END IF;

        -- Varias OS/OM por propuesta: mientras queden equipos cotizados sin OS/OM activa
        SELECT numero INTO v_num_prop FROM propuesta_comercial WHERE id_propuesta = v_id_prop;
        SELECT COUNT(*) INTO v_os_activas
        FROM orden_servicio os JOIN propuesta_comercial po ON po.id_propuesta = os.id_propuesta AND po.numero = v_num_prop
        WHERE os.eliminado_en IS NULL AND os.estado <> 'anulada';
        SELECT COUNT(DISTINCT pe.id_equipo) INTO v_eq_cotizados
        FROM propuesta_equipo pe WHERE pe.id_propuesta = v_id_prop AND pe.id_equipo IS NOT NULL;
        SELECT COUNT(DISTINCT pe.id_equipo) INTO v_eq_pend
        FROM propuesta_equipo pe
        WHERE pe.id_propuesta = v_id_prop AND pe.id_equipo IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM os_equipo oe
                          JOIN orden_servicio os ON os.id_os = oe.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
                          JOIN propuesta_comercial po ON po.id_propuesta = os.id_propuesta AND po.numero = v_num_prop
                          WHERE oe.id_equipo = pe.id_equipo AND oe.eliminado_en IS NULL);
        IF (v_eq_cotizados > 0 AND v_eq_pend = 0) OR (v_eq_cotizados = 0 AND v_os_activas > 0) THEN
            SELECT 1 AS IdTipoMensaje,
                   IF(v_eq_cotizados > 0,
                      'Todos los equipos de la propuesta ya están en órdenes de servicio activas.',
                      'La propuesta ya tiene una orden de servicio activa.') AS Mensaje;
            LEAVE proc;
        END IF;

        SET v_modo = 'nueva';
        SELECT IF(IFNULL(a.String1, '') LIKE '%metrolog%', 'OM', 'OS') INTO v_tipo
        FROM propuesta_comercial p
        LEFT JOIN requerimiento r  ON r.id_requerimiento = p.id_requerimiento
        LEFT JOIN tabla_maestra a  ON a.IdMaestro = 64 AND a.IdEmpresa = 1 AND a.Num1 = r.id_area
        WHERE p.id_propuesta = v_id_prop;

        SELECT CONCAT(v_tipo, '-', LPAD(IFNULL(MAX(CAST(SUBSTRING(numero, 4) AS UNSIGNED)), 0) + 1, 6, '0')) INTO v_numero
        FROM orden_servicio WHERE numero REGEXP CONCAT('^', v_tipo, '-[0-9]+$');
    END IF;

    SELECT id_cliente INTO v_id_cliente FROM propuesta_comercial WHERE id_propuesta = v_id_prop;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Ficha
    SELECT
        v_modo                                                                 AS modo,
        v_id_os                                                                AS id_os,
        v_numero                                                               AS numero,
        v_tipo                                                                 AS tipo,
        IFNULL(os.estado, 'emitida')                                           AS estado,
        -- Edición autorizada (banner)
        v_id_sol                                                               AS id_solicitud_aprobada,
        (SELECT me.String1 FROM os_solicitud s JOIN tabla_maestra me
                 ON me.Descripcion = 'MOTIVO_EDICION_OS' AND me.Num1 = s.id_motivo
         WHERE s.id_solicitud = v_id_sol LIMIT 1)                              AS motivo_edicion,
        (SELECT CONCAT(ua.nombre, ' ', ua.apellido) FROM os_solicitud s JOIN usuario ua ON ua.id_usuario = s.resuelto_por
         WHERE s.id_solicitud = v_id_sol)                                      AS edicion_aprobada_por,
        (SELECT ua.cargo FROM os_solicitud s JOIN usuario ua ON ua.id_usuario = s.resuelto_por
         WHERE s.id_solicitud = v_id_sol)                                      AS cargo_aprobador_edicion,
        (SELECT s.fecha_resolucion FROM os_solicitud s WHERE s.id_solicitud = v_id_sol) AS fecha_aprobacion_edicion,
        -- 1. Cliente
        p.id_cliente, c.razon_social, c.ruc,
        p.id_sede, sc.nombre                                                   AS sede,
        COALESCE(NULLIF(sc.direccion_exacta, ''), NULLIF(c.direccion_fiscal, ''), c.domicilio_fiscal) AS direccion_operaciones,
        COALESCE(os.id_contacto, p.id_contacto)                                AS id_contacto,
        COALESCE(os.id_responsable_comercial, p.id_responsable, p.id_creador)  AS id_responsable,
        CONCAT(ur.nombre, ' ', ur.apellido)                                    AS responsable,
        ur.cargo                                                               AS cargo_responsable,
        -- 2. Propuesta origen
        p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta, p.estado AS estado_propuesta,
        COALESCE(NULLIF(TRIM(IF(p.tipo_servicio REGEXP '^[0-9]+$',
                                (SELECT ts.String1 FROM tabla_maestra ts WHERE ts.IdMaestro = 3 AND ts.IdEmpresa = 1
                                   AND ts.Num1 = CAST(p.tipo_servicio AS UNSIGNED) LIMIT 1), p.tipo_servicio)), ''),
                 (SELECT GROUP_CONCAT(DISTINCT ts.String1 ORDER BY ts.String1 SEPARATOR ', ')
                  FROM propuesta_item i JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = i.id_tipo_servicio
                  WHERE i.id_propuesta = p.id_propuesta AND i.eliminado_en IS NULL))   AS tipo_servicio,
        COALESCE((SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
                  WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion'),
                 (SELECT MIN(ae.registrado_en) FROM auditoria_evento ae
                  WHERE ae.entidad_tipo = 'propuesta' AND ae.id_entidad = p.id_propuesta AND ae.estado_nuevo = 'aceptado'),
                 IF(p.estado = 'aceptado', p.modificado_en, NULL))                   AS fecha_aceptacion,
        CONCAT(uc.nombre, ' ', uc.apellido)                                    AS comercial_emisor,
        (SELECT CONCAT(ua.nombre, ' ', ua.apellido) FROM visto_bueno v
         JOIN usuario ua ON ua.id_usuario = FN_AprobadorVistoBuenoExpediente(v.id_vb)
         WHERE v.id_propuesta = p.id_propuesta AND v.tipo = 'aprobacion' AND v.estado = 'aprobado' AND v.eliminado_en IS NULL
         ORDER BY v.id_vb DESC LIMIT 1)                                        AS aprobador_vb,
        p.total AS monto_total, m.String2 AS simbolo_moneda,
        (SELECT COUNT(*) FROM propuesta_equipo pe WHERE pe.id_propuesta = p.id_propuesta) AS equipos_cotizados,
        (SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = p.id_propuesta AND i.seccion = 'principal'
           AND IFNULL(i.es_espaciado, 0) = 0 AND i.eliminado_en IS NULL) AS conceptos_cotizados,
        COALESCE((SELECT cp.String1 FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1 AND cp.Num1 = p.id_condicion_pago
                    AND cp.eliminado_en IS NULL LIMIT 1),
                 (SELECT GROUP_CONCAT(CONCAT(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(f.porcentaje AS CHAR))), '% ',
                                             IFNULL((SELECT MAX(tm.String1) FROM tabla_maestra tm WHERE tm.IdMaestro = 39
                                                       AND tm.IdEmpresa = 1 AND tm.String2 = f.condicion), f.condicion))
                                      ORDER BY f.orden, f.id SEPARATOR ' · ')
                  FROM propuesta_forma_pago f WHERE f.id_propuesta = p.id_propuesta)) AS condicion_pago,
        v_os_activas                                                           AS os_activas,
        v_eq_pend                                                              AS equipos_pendientes,
        -- 3. Documento
        IFNULL(os.fecha_emision, NOW())                                        AS fecha_emision,
        p.id_requerimiento, r.numero AS numero_rq,
        os.fecha_programada_desde, os.fecha_programada_hasta,
        os.observaciones,
        -- 7. Certificado (solo OM). Tercerizado: los datos son editables y vienen del tercero de la propuesta.
        IFNULL(p.es_tercerizado, 0)                                            AS es_tercerizado,
        IF(os.id_os IS NOT NULL AND os.cert_razon_social IS NOT NULL, os.cert_razon_social,
           IF(IFNULL(p.es_tercerizado, 0) = 1, p.tercero_razon_social, c.razon_social))       AS cert_razon_social,
        IF(os.id_os IS NOT NULL AND os.cert_ruc IS NOT NULL, os.cert_ruc,
           IF(IFNULL(p.es_tercerizado, 0) = 1, p.tercero_ruc, c.ruc))                         AS cert_ruc,
        IF(os.id_os IS NOT NULL AND os.cert_direccion IS NOT NULL, os.cert_direccion,
           IF(IFNULL(p.es_tercerizado, 0) = 1, p.tercero_direccion,
              COALESCE(NULLIF(c.direccion_fiscal, ''), c.domicilio_fiscal)))                 AS cert_direccion,
        IF(os.id_os IS NOT NULL AND os.cert_contacto IS NOT NULL, os.cert_contacto,
           IF(IFNULL(p.es_tercerizado, 0) = 1, NULL, ct.nombres))                            AS cert_contacto
    FROM propuesta_comercial p
    JOIN cliente c                ON c.id_cliente = p.id_cliente
    LEFT JOIN orden_servicio os   ON os.id_os = v_id_os
    LEFT JOIN sede_cliente sc     ON sc.id_sede = p.id_sede
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = COALESCE(os.id_contacto, p.id_contacto)
    LEFT JOIN usuario ur          ON ur.id_usuario = COALESCE(os.id_responsable_comercial, p.id_responsable, p.id_creador)
    LEFT JOIN usuario uc          ON uc.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    LEFT JOIN requerimiento r     ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN tabla_maestra m     ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    WHERE p.id_propuesta = v_id_prop;

    -- 3. Contactos del cliente (dropdown)
    SELECT ct.id_contacto, ct.nombres, ct.cargo, ct.correo, ct.telefono_movil AS telefono,
           IFNULL(ct.es_contacto_principal, 0) AS es_principal, ct.id_sede
    FROM contacto_cliente ct
    WHERE ct.id_cliente = v_id_cliente AND ct.SoftDelete = 0 AND IFNULL(ct.estado, 'Activo') = 'Activo'
    ORDER BY ct.es_contacto_principal DESC, ct.nombres;

    -- 4. Conceptos (guardados o, en una OS nueva, los suministros de servicio de la propuesta como sugerencia)
    DROP TEMPORARY TABLE IF EXISTS tmp_os_conc;
    CREATE TEMPORARY TABLE tmp_os_conc (id_os_concepto BIGINT, id_suministro BIGINT, codigo VARCHAR(30), descripcion VARCHAR(300),
                                        alcance VARCHAR(100), orden INT, orden2 INT, sugerido TINYINT)
                                        DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF v_id_os IS NOT NULL THEN
        INSERT INTO tmp_os_conc
        SELECT oc.id, oc.id_suministro, oc.codigo, oc.descripcion, oc.alcance, oc.orden, oc.id, 0
        FROM os_concepto oc WHERE oc.id_os = v_id_os AND oc.eliminado_en IS NULL;
    ELSE
        -- Un concepto por ítem de servicio de la propuesta (no se fusionan los del mismo suministro)
        INSERT INTO tmp_os_conc
        SELECT NULL, s.id_suministro, s.codigo, s.descripcion, NULLIF(TRIM(i.alcance), ''),
               (CASE i.seccion WHEN 'principal' THEN 0 ELSE 100000 END) + IFNULL(i.orden, 0), i.id_item, 1
        FROM propuesta_item i
        JOIN suministros s ON s.id_suministro = i.id_catalogo_item AND s.clase = 'servicio' AND s.eliminado_en IS NULL
        WHERE i.id_propuesta = v_id_prop AND i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0;
    END IF;

    SELECT t.id_os_concepto, t.id_suministro, t.codigo, t.descripcion, t.alcance, t.sugerido,
           tt.String1 AS clasificacion,
           EXISTS (SELECT 1 FROM propuesta_item pi WHERE pi.id_propuesta = v_id_prop AND pi.id_catalogo_item = t.id_suministro
                     AND pi.eliminado_en IS NULL AND IFNULL(pi.es_espaciado, 0) = 0) AS de_la_propuesta
    FROM tmp_os_conc t
    LEFT JOIN suministros s    ON s.id_suministro = t.id_suministro
    LEFT JOIN tabla_maestra tt ON tt.IdMaestro = 72 AND tt.IdEmpresa = 1 AND tt.String2 = s.tipo
    ORDER BY t.orden, t.orden2;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_conc;

    -- 5. Equipos (guardados o, en una OS nueva, los equipos de la propuesta como sugerencia)
    DROP TEMPORARY TABLE IF EXISTS tmp_os_eqs;
    CREATE TEMPORARY TABLE tmp_os_eqs (id_equipo BIGINT, orden INT, conceptos VARCHAR(2000), conceptos_os VARCHAR(2000),
                                       sugerido TINYINT, estado_ejecucion VARCHAR(20))
                                       DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF v_id_os IS NOT NULL THEN
        INSERT INTO tmp_os_eqs
        SELECT oe.id_equipo, IFNULL(oe.orden, oe.id),
               (SELECT GROUP_CONCAT(DISTINCT oc.id_suministro ORDER BY oc.id_suministro)
                FROM os_concepto_equipo ce JOIN os_concepto oc ON oc.id = ce.id_os_concepto AND oc.eliminado_en IS NULL
                WHERE ce.id_os_equipo = oe.id AND ce.eliminado_en IS NULL),
               (SELECT GROUP_CONCAT(DISTINCT oc.id ORDER BY oc.id)
                FROM os_concepto_equipo ce JOIN os_concepto oc ON oc.id = ce.id_os_concepto AND oc.eliminado_en IS NULL
                WHERE ce.id_os_equipo = oe.id AND ce.eliminado_en IS NULL),
               0, oe.estado_ejecucion
        FROM os_equipo oe WHERE oe.id_os = v_id_os AND oe.eliminado_en IS NULL;
    ELSE
        -- Solo los equipos cotizados que aún no están en una OS/OM activa de la propuesta (de cualquier versión)
        INSERT INTO tmp_os_eqs
        SELECT pe.id_equipo, MIN(IFNULL(pe.orden, pe.id)), NULL, NULL, 1, 'pendiente'
        FROM propuesta_equipo pe
        JOIN equipo_cliente ec ON ec.id_equipo = pe.id_equipo AND ec.id_cliente = v_id_cliente AND ec.SoftDelete = 0
        WHERE pe.id_propuesta = v_id_prop AND pe.id_equipo IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM os_equipo oe
                          JOIN orden_servicio os ON os.id_os = oe.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
                          JOIN propuesta_comercial po ON po.id_propuesta = os.id_propuesta AND po.numero = v_num_prop
                          WHERE oe.id_equipo = pe.id_equipo AND oe.eliminado_en IS NULL)
        GROUP BY pe.id_equipo;
    END IF;

    SELECT ec.id_equipo, ec.codigo_tw, ec.num_serie, ec.codigo_cliente,
           ec.clasificacion, COALESCE(tc.String1, ec.clasificacion) AS clasificacion_label,
           ec.marca, ec.modelo, ec.alcance_maximo, ec.ubicacion_especifica, sc.nombre AS sede,
           ec.division_minima, ec.division_verif, ec.clase_exactitud, ec.escala_graduacion, ec.puntos_calibracion,
           ec.valor_nominal, ec.estado AS estado_equipo,
           t.conceptos, t.conceptos_os, t.sugerido, t.estado_ejecucion,
           EXISTS (SELECT 1 FROM propuesta_equipo pq WHERE pq.id_propuesta = v_id_prop AND pq.id_equipo = ec.id_equipo) AS de_la_propuesta,
           (SELECT CONCAT(o2.numero, '|', o2.estado) FROM os_equipo e2
            JOIN orden_servicio o2 ON o2.id_os = e2.id_os AND o2.eliminado_en IS NULL
            WHERE e2.id_equipo = ec.id_equipo AND e2.eliminado_en IS NULL AND o2.id_os <> IFNULL(v_id_os, 0)
              AND o2.estado NOT IN ('borrador', 'finalizada', 'anulada')
            ORDER BY o2.id_os DESC LIMIT 1)                               AS otra_os
    FROM tmp_os_eqs t
    JOIN equipo_cliente ec    ON ec.id_equipo = t.id_equipo
    LEFT JOIN sede_cliente sc ON sc.id_sede = ec.id_sede
    LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    ORDER BY t.orden, ec.id_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_eqs;
END$$

DELIMITER ;
