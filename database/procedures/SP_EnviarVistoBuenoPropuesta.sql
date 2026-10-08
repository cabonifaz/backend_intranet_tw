-- HU-12 — Envío a Visto Bueno
--   p_solo_preparar = 1 devuelve lo que muestra el modal sin cambiar nada:
--     validaciones, destinatario, SLA, fecha límite y alerta de aprobación especial.
--   p_solo_preparar = 0 envía: la propuesta pasa a 'pendiente_vb', se crea el
--     registro en visto_bueno, una notificación al aprobador y la auditoría.
--   Solo la última versión y en 'borrador'.
--   Destinatario: jefe directo (usuario.id_supervisor) del comercial responsable
--     o, si ese jefe tiene un suplente vigente (usuario_suplente), el suplente.
--   SLA: CONFIG_SLA propuesta / pendiente_vb (Num2 = horas).
--   Aprobación especial: descuento global sobre el subtotal mayor al parámetro
--     DESCUENTO_APROBACION_ESPECIAL. Aproxima el margen hasta que existan costos.
--     Si aplica, el comentario es obligatorio al enviar.
--   Resultados: 1 header · 2 resumen · 3 validaciones
DROP PROCEDURE IF EXISTS SP_EnviarVistoBuenoPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_EnviarVistoBuenoPropuesta(
    IN p_id_propuesta   BIGINT,
    IN p_comentario     TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_preparar  TINYINT,
    IN p_id_usuario     BIGINT
)
proc: BEGIN
    DECLARE v_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_id_contacto   BIGINT;
    DECLARE v_id_rq         BIGINT;
    DECLARE v_autor         BIGINT;
    DECLARE v_subtotal      DECIMAL(14,2);
    DECLARE v_descuento     DECIMAL(14,2);
    DECLARE v_total         DECIMAL(14,2);
    DECLARE v_fecha_pdf     DATETIME;
    DECLARE v_jefe          BIGINT;
    DECLARE v_suplente      BIGINT;
    DECLARE v_aprobador     BIGINT;
    DECLARE v_sla           INT;
    DECLARE v_desc_pct      DECIMAL(7,2) DEFAULT 0;
    DECLARE v_umbral        DECIMAL(7,2);
    DECLARE v_exigir_pdf    TINYINT;
    DECLARE v_exigir_eq     TINYINT;
    DECLARE v_requiere_esp  TINYINT DEFAULT 0;
    DECLARE v_puede         TINYINT DEFAULT 0;
    DECLARE v_faltantes     TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_vb         BIGINT DEFAULT NULL;
    DECLARE v_usu_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_rq     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vb_validaciones;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_solo_preparar = IFNULL(p_solo_preparar, 0);

    -- ── Propuesta ───────────────────────────────────────────────────────
    SELECT estado, numero, version, id_cliente, id_contacto, id_requerimiento,
           COALESCE(id_responsable, id_creador), subtotal, descuento_monto, total, fecha_pdf
      INTO v_estado, v_numero, v_version, v_id_cliente, v_id_contacto, v_id_rq,
           v_autor, v_subtotal, v_descuento, v_total, v_fecha_pdf
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM propuesta_comercial
               WHERE numero = v_numero AND version > v_version AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo la última versión de la propuesta puede enviarse a visto bueno.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'borrador' THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('La propuesta está en estado "', v_estado, '". Solo se envía a visto bueno desde borrador.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Parámetros ──────────────────────────────────────────────────────
    SELECT IFNULL(MAX(CASE WHEN String2 = 'DESCUENTO_APROBACION_ESPECIAL' THEN Num2 END), 10),
           IFNULL(MAX(CASE WHEN String2 = 'VB_EXIGIR_PDF'                  THEN Num2 END), 0),
           IFNULL(MAX(CASE WHEN String2 = 'VB_EXIGIR_EQUIPOS'              THEN Num2 END), 1)
      INTO v_umbral, v_exigir_pdf, v_exigir_eq
    FROM tabla_maestra
    WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND eliminado_en IS NULL;

    SELECT IFNULL(MAX(CAST(Num2 AS SIGNED)), 24) INTO v_sla
    FROM tabla_maestra
    WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'propuesta' AND String2 = 'pendiente_vb'
      AND eliminado_en IS NULL;

    -- ── Destinatario: jefe directo o su suplente vigente ────────────────
    SELECT u.id_supervisor INTO v_jefe
    FROM usuario u
    JOIN usuario j ON j.id_usuario = u.id_supervisor AND j.eliminado_en IS NULL AND j.estado = 'activo'
    WHERE u.id_usuario = v_autor;

    IF v_jefe IS NOT NULL THEN
        SELECT us.id_suplente INTO v_suplente
        FROM usuario_suplente us
        JOIN usuario s ON s.id_usuario = us.id_suplente AND s.eliminado_en IS NULL AND s.estado = 'activo'
        WHERE us.id_titular = v_jefe AND us.SoftDelete = 0 AND us.activo = 1
          AND us.fecha_inicio <= CURDATE()
          AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
        ORDER BY us.fecha_inicio DESC
        LIMIT 1;
    END IF;

    SET v_aprobador = COALESCE(v_suplente, v_jefe);

    -- ── Aprobación especial (aproximación por descuento) ────────────────
    IF IFNULL(v_subtotal, 0) > 0 THEN
        SET v_desc_pct = ROUND(IFNULL(v_descuento, 0) * 100 / v_subtotal, 2);
    END IF;
    SET v_requiere_esp = IF(v_desc_pct > v_umbral, 1, 0);

    -- ── Validaciones ────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_vb_validaciones;
    CREATE TEMPORARY TABLE tmp_vb_validaciones (
        orden       INT,
        codigo      VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etiqueta    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cumple      TINYINT,
        obligatoria TINYINT,
        detalle     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    INSERT INTO tmp_vb_validaciones VALUES
    (1, 'cliente_valido', 'Cliente válido',
        EXISTS (SELECT 1 FROM cliente c WHERE c.id_cliente = v_id_cliente AND c.SoftDelete = 0
                AND LOWER(IFNULL(c.estado, 'activo')) = 'activo'),
        1, 'El cliente debe existir y estar activo.'),
    (2, 'contacto_definido', 'Contacto definido',
        EXISTS (SELECT 1 FROM contacto_cliente cc WHERE cc.id_contacto = v_id_contacto AND cc.SoftDelete = 0),
        1, 'La propuesta debe tener una persona de contacto.'),
    (3, 'items_agregados', 'Ítems agregados',
        EXISTS (SELECT 1 FROM propuesta_item i WHERE i.id_propuesta = p_id_propuesta AND i.eliminado_en IS NULL
                AND i.seccion = 'principal' AND i.es_espaciado = 0 AND i.subtotal > 0),
        1, 'Agregue al menos un ítem principal con monto.'),
    (4, 'forma_pago_definida', 'Forma de pago definida',
        (SELECT IFNULL(SUM(fp.porcentaje), 0) = 100 FROM propuesta_forma_pago fp WHERE fp.id_propuesta = p_id_propuesta),
        1, 'Las formas de pago deben sumar 100%.'),
    (5, 'condiciones_definidas', 'Condiciones definidas',
        EXISTS (SELECT 1 FROM propuesta_texto t WHERE t.id_propuesta = p_id_propuesta AND t.seccion = 'condiciones'),
        1, 'Agregue al menos una condición comercial.'),
    (6, 'equipos_asociados', 'Equipos asociados',
        EXISTS (SELECT 1 FROM propuesta_equipo e WHERE e.id_propuesta = p_id_propuesta),
        v_exigir_eq, 'Asocie al menos un equipo del cliente.'),
    (7, 'pdf_generado', 'PDF generado',
        v_fecha_pdf IS NOT NULL,
        v_exigir_pdf, 'Genere la vista previa en PDF de la propuesta.'),
    (8, 'jefe_directo', 'Aprobador asignado',
        v_aprobador IS NOT NULL,
        1, 'El comercial responsable no tiene jefe directo activo en su ficha de usuario.');

    SELECT IF(COUNT(*) = 0, 1, 0),
           GROUP_CONCAT(etiqueta ORDER BY orden SEPARATOR ', ')
      INTO v_puede, v_faltantes
    FROM tmp_vb_validaciones
    WHERE obligatoria = 1 AND cumple = 0;

    -- ── Enviar ──────────────────────────────────────────────────────────
    IF p_solo_preparar = 0 THEN
        IF FN_PermisoAccion(p_id_usuario, 'propuesta_enviar_vb') = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_vb_validaciones;
            SELECT 1 AS IdTipoMensaje, 'No tiene permiso para enviar propuestas a visto bueno.' AS Mensaje;
            LEAVE proc;
        END IF;

        IF v_puede = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_vb_validaciones;
            SELECT 1 AS IdTipoMensaje, CONCAT('Faltan requisitos para enviar a visto bueno: ', v_faltantes, '.') AS Mensaje;
            LEAVE proc;
        END IF;

        IF v_requiere_esp = 1 AND TRIM(IFNULL(p_comentario, '')) = '' THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_vb_validaciones;
            SELECT 1 AS IdTipoMensaje,
                   'La propuesta requiere aprobación especial. Explique el motivo en los comentarios.' AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT CONCAT(nombre, ' ', apellido) INTO v_usu_nombre FROM usuario WHERE id_usuario = p_id_usuario;
        SELECT numero INTO v_numero_rq FROM requerimiento WHERE id_requerimiento = v_id_rq;

        START TRANSACTION;

        UPDATE propuesta_comercial
           SET estado = 'pendiente_vb', modificado_en = NOW(), modificado_por = p_id_usuario
         WHERE id_propuesta = p_id_propuesta;

        INSERT INTO visto_bueno (id_propuesta, id_aprobador, estado, comentario, sla_horas, fecha_solicitud, creado_por)
        VALUES (p_id_propuesta, v_aprobador, 'pendiente', NULLIF(TRIM(p_comentario), ''), v_sla, NOW(), p_id_usuario);
        SET v_id_vb = LAST_INSERT_ID();

        -- Canal 5 = Notificación en la plataforma (CANAL_COMUNICACION)
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_aprobador, 5,
                CONCAT('Visto bueno pendiente: ', v_numero, ' v', v_version),
                CONCAT(v_usu_nombre, ' envió la propuesta ', v_numero, ' v', v_version,
                       ' para su visto bueno. Plazo: ', v_sla, ' horas.',
                       IF(v_requiere_esp = 1, ' Requiere aprobación especial.', '')),
                'propuesta', p_id_propuesta, NOW(), p_id_usuario);

        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta', 'Propuesta enviada a VB', 'task_alt',
                CONCAT('Propuesta ', v_numero, ' v', v_version, ' enviada a visto bueno.'),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('propuesta', p_id_propuesta, 'envio_vb', 'borrador', 'pendiente_vb',
                CONCAT('Enviada a visto bueno de ', IFNULL((SELECT CONCAT(nombre, ' ', apellido) FROM usuario WHERE id_usuario = v_aprobador), '-'),
                       IF(v_suplente IS NOT NULL, ' (suplente del jefe directo)', ''), '.'),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_vb',                  v_id_vb,
                            'id_aprobador',           v_aprobador,
                            'id_jefe_directo',        v_jefe,
                            'es_suplente',            v_suplente IS NOT NULL,
                            'sla_horas',              v_sla,
                            'aprobacion_especial',    v_requiere_esp = 1,
                            'descuento_pct',          v_desc_pct,
                            'umbral_descuento_pct',   v_umbral));

        COMMIT;
    END IF;

    -- ── Resultado ───────────────────────────────────────────────────────
    SELECT 2 AS IdTipoMensaje,
           IF(p_solo_preparar = 1, 'Éxito.', 'Propuesta enviada a visto bueno.') AS Mensaje;

    SELECT p.id_propuesta, p.numero, p.version,
           IF(p_solo_preparar = 1, v_estado, 'pendiente_vb')   AS estado,
           c.razon_social                                       AS cliente,
           r.numero                                             AS numero_requerimiento,
           p.total, tm_mon.String2                              AS moneda_simbolo,
           v_aprobador                                          AS id_aprobador,
           CONCAT(ua.nombre, ' ', ua.apellido)                  AS nombre_aprobador,
           ua.cargo                                             AS cargo_aprobador,
           (v_suplente IS NOT NULL)                             AS es_suplente,
           v_jefe                                               AS id_jefe_directo,
           CONCAT(uj.nombre, ' ', uj.apellido)                  AS nombre_jefe_directo,
           v_sla                                                AS sla_horas,
           DATE_ADD(NOW(), INTERVAL v_sla HOUR)                 AS fecha_limite,
           v_requiere_esp                                       AS requiere_aprobacion_especial,
           IF(v_requiere_esp = 1,
              CONCAT('El descuento aplicado (', v_desc_pct, '%) supera el máximo permitido sin aprobación especial (', v_umbral, '%).'),
              NULL)                                             AS motivo_alerta,
           v_desc_pct                                           AS descuento_pct,
           v_umbral                                             AS umbral_descuento_pct,
           v_puede                                              AS puede_enviar,
           v_id_vb                                              AS id_visto_bueno
    FROM propuesta_comercial p
    JOIN cliente c                 ON c.id_cliente = p.id_cliente
    LEFT JOIN requerimiento r      ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN tabla_maestra tm_mon ON tm_mon.IdMaestro = 1 AND tm_mon.IdEmpresa = 1 AND tm_mon.Num1 = p.id_moneda
    LEFT JOIN usuario ua           ON ua.id_usuario = v_aprobador
    LEFT JOIN usuario uj           ON uj.id_usuario = v_jefe
    WHERE p.id_propuesta = p_id_propuesta;

    SELECT codigo, etiqueta, cumple, obligatoria, detalle
    FROM tmp_vb_validaciones
    ORDER BY orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_vb_validaciones;
END$$

DELIMITER ;
