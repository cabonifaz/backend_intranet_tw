-- ============================================================
-- SP_ArmarOmTecnicoMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_rom_os` las OM (orden_servicio.tipo = 'OM', no eliminadas) a las que el técnico del token tiene acceso: es técnico principal o está en
-- os_personal (mismo criterio de HU-22). UNA sola vez: todos los SP de la recepción (lista, detalle, fotos, QR, registrar, constancia) piden el acceso aquí.
--   p_id_os = NULL → todas las OM del técnico; con un id → solo esa (vacía si no es suya o no es una OM: misma respuesta para «no existe» y «no es tuya»).
--   activa = 1 si el estado de la OM no es finalizada / anulada / reprogramada (solo las activas aceptan recepciones nuevas).
-- Columnas: id_os · numero · cliente · numero_rq · servicio · activa · id_cliente · id_contacto · id_expediente (para quien arma la constancia).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_rom_os. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarOmTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarOmTecnicoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    CREATE TEMPORARY TABLE tmp_rom_os (
        id_os BIGINT NOT NULL,
        numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        cliente VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        activa TINYINT NOT NULL DEFAULT 1,
        id_cliente BIGINT NULL,
        id_contacto BIGINT NULL,
        PRIMARY KEY (id_os));

    IF IFNULL(p_id_usuario, 0) > 0 THEN
        INSERT INTO tmp_rom_os (id_os, numero, cliente, numero_rq, servicio, activa, id_cliente, id_contacto)
        SELECT os.id_os, os.numero,
               LEFT(COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social), 200),
               (SELECT rq.numero FROM expediente_digital ed JOIN requerimiento rq ON rq.id_requerimiento = ed.id_requerimiento
                WHERE ed.id_expediente = os.id_expediente LIMIT 1),
               LEFT((SELECT tsv.String1 FROM tabla_maestra tsv
                     WHERE tsv.Descripcion = 'TIPO_SERVICIO' AND tsv.IdEmpresa = 1 AND tsv.Num1 = os.id_tipo_servicio
                     ORDER BY tsv.IdMaestro DESC LIMIT 1), 100),
               IF(os.estado IN ('finalizada', 'anulada', 'reprogramada'), 0, 1),
               os.id_cliente, os.id_contacto
        FROM   orden_servicio os
        LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
        WHERE  os.tipo = 'OM' AND os.eliminado_en IS NULL
          AND  (p_id_os IS NULL OR os.id_os = p_id_os)
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    END IF;
END$$

DELIMITER ;
