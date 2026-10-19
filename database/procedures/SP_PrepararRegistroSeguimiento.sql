-- HU-19 Datos para los modales Registrar Seguimiento, Registrar Llamada y Registrar Correo.
-- Solo para propuestas en seguimiento ABIERTO (en_seguimiento, sin_respuesta, requiere_ajuste)
-- del área del usuario y con la acción propuesta_seguimiento_registrar.
-- Resultados:
--   1 mensaje
--   2 cabecera: propuesta, cliente, contacto por defecto, usuario actual, fecha del servidor,
--     próxima acción actual y sugerencias (canal y plantilla) para el botón "Ejecutar ahora"
--   3 tipos de seguimiento (CANAL_COMUNICACION con Num2 = 1)
--   4 resultados (RESULTADO_SEGUIMIENTO)
--   5 contactos del cliente
--   6 tipos de tarea de la próxima acción (TIPO_ACCION_SEGUIMIENTO)
--   7 prioridades (PRIORIDAD)
--   8 responsables posibles de la próxima acción (usuarios activos del área)
--   9 plantillas de correo con las variables ya reemplazadas
--  10 último borrador de correo del usuario para esta propuesta (0 o 1 fila)
DROP PROCEDURE IF EXISTS SP_PrepararRegistroSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_PrepararRegistroSeguimiento(
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
    DECLARE v_id_responsable BIGINT;
    DECLARE v_area           VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar seguimientos.' AS Mensaje;
    ELSE
        CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                             v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

        SELECT COUNT(*), MAX(id_cliente), MAX(id_contacto), MAX(id_responsable),
               IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
          INTO v_existe, v_id_cliente, v_id_contacto, v_id_responsable, v_abierta
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
            SELECT area INTO v_area FROM usuario WHERE id_usuario = v_id_responsable;

            -- 1. Header
            SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

            -- 2. Cabecera
            SELECT
                t.id_propuesta, t.numero, t.version,
                t.id_cliente, c.razon_social, p.referencia,
                t.id_contacto, co.nombres AS contacto, co.telefono_movil AS telefono_contacto,
                co.correo AS correo_contacto,
                u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario,
                u.correo AS correo_usuario, u.cargo AS cargo_usuario,
                NOW() AS fecha_servidor,
                t.estado_seguimiento,
                t.proxima_accion_codigo, t.proxima_accion, t.vence_accion AS proxima_accion_fecha,
                CASE t.proxima_accion_codigo
                    WHEN 'LLAMADA'         THEN 'LLAMADA'
                    WHEN 'CORREO'          THEN 'CORREO'
                    WHEN 'REENVIO_AJUSTES' THEN 'CORREO'
                    WHEN 'REUNION'         THEN 'REUNION'
                    WHEN 'VISITA'          THEN 'VISITA'
                    ELSE 'LLAMADA'
                END AS canal_sugerido_codigo,
                CASE
                    WHEN t.proxima_accion_codigo = 'REENVIO_AJUSTES'
                      OR t.estado_seguimiento = 'requiere_ajuste' THEN 'ENVIO_AJUSTES'
                    WHEN t.estado_seguimiento = 'sin_respuesta'  THEN 'RECORDATORIO'
                    ELSE 'SEGUIMIENTO_INICIAL'
                END AS plantilla_sugerida_codigo
            FROM tmp_seg t
            JOIN propuesta_comercial p     ON p.id_propuesta = t.id_propuesta
            LEFT JOIN cliente c            ON c.id_cliente   = t.id_cliente
            LEFT JOIN contacto_cliente co  ON co.id_contacto = t.id_contacto
            LEFT JOIN usuario u            ON u.id_usuario   = p_id_usuario;

            -- 3. Tipos de seguimiento
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 26 AND IdEmpresa = 1 AND Num2 = 1
            ORDER BY FIELD(String2, 'LLAMADA', 'CORREO', 'WHATSAPP', 'REUNION', 'VISITA'), Num1;

            -- 4. Resultados
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 27 AND IdEmpresa = 1
            ORDER BY Num1;

            -- 5. Contactos del cliente
            SELECT co.id_contacto, co.nombres, co.cargo, co.correo, co.telefono_movil, co.telefono_anexo,
                   (co.id_contacto = IFNULL(v_id_contacto, 0))  AS es_contacto_propuesta,
                   CAST(co.es_contacto_principal AS UNSIGNED)   AS es_contacto_principal
            FROM contacto_cliente co
            WHERE co.id_cliente = v_id_cliente AND co.SoftDelete = 0
            ORDER BY (co.id_contacto = IFNULL(v_id_contacto, 0)) DESC, co.es_contacto_principal DESC, co.nombres;

            -- 6. Tipos de tarea
            SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
            FROM tabla_maestra
            WHERE Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND IdEmpresa = 1
            ORDER BY Num1;

            -- 7. Prioridades
            SELECT Num1 AS id, String1 AS nombre, String3 AS codigo
            FROM tabla_maestra
            WHERE IdMaestro = 7 AND IdEmpresa = 1
            ORDER BY Num1;

            -- 8. Responsables (usuarios activos del área del responsable de la propuesta)
            SELECT u.id_usuario AS id, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.cargo,
                   (u.id_usuario = p_id_usuario) AS es_usuario_actual
            FROM usuario u
            WHERE u.eliminado_en IS NULL AND u.estado = 'activo'
              AND (u.area = v_area OR u.id_usuario = p_id_usuario)
            ORDER BY (u.id_usuario = p_id_usuario) DESC, u.nombre, u.apellido;

            -- 9. Plantillas de correo con las variables reemplazadas
            SELECT pl.id_plantilla, pl.codigo, pl.nombre,
                   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(pl.asunto,
                       '{{contacto}}',         IFNULL(co.nombres, 'cliente')),
                       '{{numero_propuesta}}', t.numero),
                       '{{cliente}}',          IFNULL(c.razon_social, '')),
                       '{{referencia}}',       IFNULL(p.referencia, 'su requerimiento')),
                       '{{usuario}}',          CONCAT(u.nombre, ' ', u.apellido)),
                       '{{cargo_usuario}}',    IFNULL(u.cargo, 'Área Comercial')),
                       '{{fecha_envio}}',      DATE_FORMAT(t.fecha_envio, '%d/%m/%Y')) AS asunto,
                   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(pl.cuerpo_html,
                       '{{contacto}}',         IFNULL(co.nombres, 'cliente')),
                       '{{numero_propuesta}}', t.numero),
                       '{{cliente}}',          IFNULL(c.razon_social, '')),
                       '{{referencia}}',       IFNULL(p.referencia, 'su requerimiento')),
                       '{{usuario}}',          CONCAT(u.nombre, ' ', u.apellido)),
                       '{{cargo_usuario}}',    IFNULL(u.cargo, 'Área Comercial')),
                       '{{fecha_envio}}',      DATE_FORMAT(t.fecha_envio, '%d/%m/%Y')) AS cuerpo_html
            FROM plantilla_correo_seguimiento pl
            JOIN tmp_seg t ON 1 = 1
            JOIN propuesta_comercial p     ON p.id_propuesta = t.id_propuesta
            LEFT JOIN cliente c            ON c.id_cliente   = t.id_cliente
            LEFT JOIN contacto_cliente co  ON co.id_contacto = t.id_contacto
            LEFT JOIN usuario u            ON u.id_usuario   = p_id_usuario
            WHERE pl.eliminado_en IS NULL AND pl.activo = 1
            ORDER BY pl.orden, pl.id_plantilla;

            DROP TEMPORARY TABLE IF EXISTS tmp_seg;

            -- 10. Último borrador o envío fallido del usuario
            SELECT sc.id_correo, sc.id_plantilla, sc.para, sc.cc, sc.asunto, sc.cuerpo_html,
                   sc.estado, sc.error, COALESCE(sc.modificado_en, sc.creado_en) AS fecha
            FROM seguimiento_correo sc
            WHERE sc.id_propuesta = p_id_propuesta AND sc.id_usuario = p_id_usuario
              AND sc.estado IN ('borrador', 'error') AND sc.eliminado_en IS NULL
            ORDER BY COALESCE(sc.modificado_en, sc.creado_en) DESC, sc.id_correo DESC
            LIMIT 1;
        END IF;
    END IF;
END$$

DELIMITER ;
