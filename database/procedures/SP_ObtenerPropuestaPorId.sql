-- HU-07 — Propuesta completa: cabecera, ítems, textos, formas de pago y equipos
-- HU-10 — + motivo/descripción de la versión y última edición (fecha y usuario)
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestaPorId;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestaPorId(
    IN p_id_propuesta BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
    ELSE
        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Cabecera
        SELECT
            p.id_propuesta, p.numero, p.version, p.estado, p.id_propuesta_padre,
            p.id_requerimiento, r.numero              AS numero_requerimiento,
            p.id_cliente, c.razon_social, c.ruc,
            p.id_sede,     sc.nombre                  AS nombre_sede,
            p.id_contacto, co.nombres                 AS nombre_contacto, co.cargo AS cargo_contacto,
            p.id_responsable, CONCAT(ur.nombre, ' ', ur.apellido) AS nombre_responsable,
            p.tipo_servicio, p.referencia, p.introduccion, p.notas_generales,
            p.secciones_activas,
            p.es_tercerizado, p.tercero_ruc, p.tercero_razon_social, p.tercero_direccion,
            p.id_moneda, tm_mon.String3 AS moneda, tm_mon.String2 AS moneda_simbolo,
            p.tipo_cambio, p.garantia_meses, p.mostrar_garantia,
            p.plazo_entrega_dias, p.plazo_entrega_unidad, p.plazo_entrega_condicion,
            p.vigencia_dias, p.aplica_igv, p.precios_incluyen_igv, p.igv_pct,
            p.subtotal, p.descuento_pct, p.descuento_monto, p.id_motivo_descuento,
            p.igv_monto, p.total,
            p.subtotal_opcionales, p.descuento_opcionales, p.total_opcionales,
            CONCAT(uc.nombre, ' ', uc.apellido)       AS nombre_creador,
            p.fecha_creacion, p.fecha_envio, p.fecha_expiracion,
            -- HU-10: versión y última edición
            p.id_motivo_nueva_version, tm_mot.String1 AS motivo_nueva_version, p.descripcion_cambios,
            COALESCE(p.modificado_en, p.creado_en)    AS ultima_edicion_en,
            CONCAT(um.nombre, ' ', um.apellido)       AS ultima_edicion_por
        FROM propuesta_comercial p
        JOIN requerimiento r          ON r.id_requerimiento = p.id_requerimiento
        JOIN cliente c                ON c.id_cliente       = p.id_cliente
        LEFT JOIN sede_cliente sc     ON sc.id_sede         = p.id_sede
        LEFT JOIN contacto_cliente co ON co.id_contacto     = p.id_contacto
        LEFT JOIN usuario ur          ON ur.id_usuario      = p.id_responsable
        LEFT JOIN usuario uc          ON uc.id_usuario      = p.id_creador
        LEFT JOIN tabla_maestra tm_mon ON tm_mon.IdMaestro = 1 AND tm_mon.IdEmpresa = 1 AND tm_mon.Num1 = p.id_moneda
        LEFT JOIN tabla_maestra tm_mot ON tm_mot.IdMaestro = 11 AND tm_mot.IdEmpresa = 1 AND tm_mot.Num1 = p.id_motivo_nueva_version
        LEFT JOIN usuario um          ON um.id_usuario      = COALESCE(p.modificado_por, p.creado_por)
        WHERE p.id_propuesta = p_id_propuesta;

        -- 3. Ítems (principales y opcionales)
        SELECT id_item, seccion, id_catalogo_item, descripcion, alcance, puntos_calibracion,
               cantidad, frecuencia, precio_unitario, descuento, subtotal, es_espaciado, orden
        FROM propuesta_item
        WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL
        ORDER BY seccion, orden, id_item;

        -- 4. Textos por sección
        SELECT id, seccion, tipo, texto, id_texto_base, orden
        FROM propuesta_texto
        WHERE id_propuesta = p_id_propuesta
        ORDER BY FIELD(seccion, 'detalle', 'recomendaciones', 'suministros_cliente', 'condiciones'), orden, id;

        -- 5. Formas de pago
        SELECT f.id, f.porcentaje, f.condicion, tm.String1 AS condicion_label, f.orden
        FROM propuesta_forma_pago f
        LEFT JOIN tabla_maestra tm ON tm.IdMaestro = 39 AND tm.IdEmpresa = 1 AND tm.String2 = f.condicion
        WHERE f.id_propuesta = p_id_propuesta
        ORDER BY f.orden, f.id;

        -- 6. Equipos
        SELECT id, id_equipo, local_sede, tipo, subtipo, num_serie, marca, modelo,
               codigo_cliente, codigo_tw, orden
        FROM propuesta_equipo
        WHERE id_propuesta = p_id_propuesta
        ORDER BY orden, id;
    END IF;
END$$

DELIMITER ;
