-- HU-21 Datos de los modales Registrar Aceptación, Registrar Rechazo y Cerrar sin Venta.
-- Solo propuestas en seguimiento ABIERTO del área del usuario, con la acción propuesta_seguimiento_cerrar.
-- Resultados:
--   1 mensaje
--   2 cabecera: propuesta, cliente, monto, RQ, responsable, contacto por defecto y fecha del servidor
--   3 tipos de aceptación (TIPO_ACEPTACION_PROPUESTA)
--   4 motivos de rechazo (MOTIVO_RECHAZO, tal cual)
--   5 motivos de cierre sin venta (MOTIVO_CIERRE_SIN_VENTA, tal cual)
--   6 contactos del cliente (el de la propuesta primero)
DROP PROCEDURE IF EXISTS SP_PrepararCierreSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_PrepararCierreSeguimiento(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT
)
BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_contacto    BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_cerrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar el cierre del seguimiento.' AS Mensaje;
    ELSE
        CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                             v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

        SELECT COUNT(*), MAX(id_cliente), MAX(id_contacto),
               IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
          INTO v_existe, v_id_cliente, v_id_contacto, v_abierta
        FROM tmp_seg;

        IF v_existe = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje,
                   'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        ELSEIF v_abierta = 0 THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_seg;
            SELECT 1 AS IdTipoMensaje,
                   'El seguimiento de esta propuesta ya está cerrado (aceptada o rechazada).' AS Mensaje;
        ELSE
            -- 1. Header
            SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

            -- 2. Cabecera
            SELECT
                t.id_propuesta, t.numero, t.version,
                t.id_cliente, c.razon_social, c.ruc,
                t.id_requerimiento, r.numero AS numero_rq,
                t.total, t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo,
                t.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
                t.id_contacto, co.nombres AS contacto, co.cargo AS cargo_contacto,
                t.estado_seguimiento, t.dias_transcurridos,
                NOW() AS fecha_servidor
            FROM tmp_seg t
            LEFT JOIN cliente c           ON c.id_cliente       = t.id_cliente
            LEFT JOIN requerimiento r     ON r.id_requerimiento = t.id_requerimiento
            LEFT JOIN usuario u           ON u.id_usuario       = t.id_responsable
            LEFT JOIN contacto_cliente co ON co.id_contacto     = t.id_contacto
            LEFT JOIN tabla_maestra m     ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda;

            DROP TEMPORARY TABLE IF EXISTS tmp_seg;

            -- 3. Tipos de aceptación
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE Descripcion = 'TIPO_ACEPTACION_PROPUESTA' AND IdEmpresa = 1 AND eliminado_en IS NULL
            ORDER BY Num1;

            -- 4. Motivos de rechazo (tal cual)
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 10 AND IdEmpresa = 1 AND eliminado_en IS NULL
            ORDER BY Num1;

            -- 5. Motivos de cierre sin venta (tal cual)
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 12 AND IdEmpresa = 1 AND eliminado_en IS NULL
            ORDER BY Num1;

            -- 6. Contactos del cliente
            SELECT co.id_contacto, co.nombres, co.cargo, co.correo, co.telefono_movil, co.telefono_anexo,
                   (co.id_contacto = IFNULL(v_id_contacto, 0))  AS es_contacto_propuesta,
                   CAST(co.es_contacto_principal AS UNSIGNED)   AS es_contacto_principal
            FROM contacto_cliente co
            WHERE co.id_cliente = v_id_cliente AND co.SoftDelete = 0
            ORDER BY (co.id_contacto = IFNULL(v_id_contacto, 0)) DESC, co.es_contacto_principal DESC, co.nombres;
        END IF;
    END IF;
END$$

DELIMITER ;
