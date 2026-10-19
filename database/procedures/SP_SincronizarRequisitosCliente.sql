-- Reemplaza los requisitos SSOMA asignados a un cliente.
--   p_requisitos: ["sctr","examen_medico",...] (códigos String2 del catálogo
--   REQUISITO_SSOMA IdMaestro=48). NULL = no cambia nada. Arreglo vacío = quita
--   todos los requisitos asignados al cliente.
--
--   Como la tabla `requisito_ssoma_cliente` tiene columnas opcionales de
--   granularidad (id_sede, id_tipo_servicio, es_obligatorio, bloquea_servicio),
--   este SP escribe asignaciones GENERALES (sin sede, sin tipo servicio,
--   no obligatorias, no bloqueantes). La granularidad fina queda disponible
--   para un futuro mantenimiento más detallado si TW lo necesita.
DROP PROCEDURE IF EXISTS SP_SincronizarRequisitosCliente;

DELIMITER $$

CREATE PROCEDURE SP_SincronizarRequisitosCliente(
    IN p_id_cliente BIGINT,
    IN p_requisitos JSON,
    IN p_id_usuario BIGINT
)
BEGIN
    IF p_requisitos IS NOT NULL THEN
        -- Soft-delete de todas las asignaciones generales previas (sin id_sede
        -- ni id_tipo_servicio). Las asignaciones específicas por sede/servicio
        -- (si existieran) NO se tocan.
        UPDATE requisito_ssoma_cliente
        SET eliminado_en = NOW(),
            eliminado_por = p_id_usuario
        WHERE id_cliente = p_id_cliente
          AND id_sede IS NULL
          AND id_tipo_servicio IS NULL
          AND eliminado_en IS NULL;

        -- Insertar la nueva lista. Resuelve el id_requisito (Num1) desde el
        -- código del catálogo (String2). Códigos inválidos se ignoran.
        INSERT INTO requisito_ssoma_cliente (
            id_requisito, id_cliente, es_obligatorio, bloquea_servicio,
            creado_en, creado_por
        )
        SELECT t.Num1, p_id_cliente, 0, 0, NOW(), p_id_usuario
        FROM JSON_TABLE(p_requisitos, '$[*]' COLUMNS (codigo VARCHAR(60) PATH '$')) j
        JOIN tabla_maestra t
          ON t.IdMaestro = 48 AND t.IdEmpresa = 1 AND t.String2 = j.codigo;
    END IF;
END$$

DELIMITER ;
