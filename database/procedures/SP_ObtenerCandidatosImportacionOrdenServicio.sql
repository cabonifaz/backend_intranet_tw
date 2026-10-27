-- HU-44 (Sprint 4) Importación por Excel de equipos y conceptos de una OS/OM (plantilla oficial). No modifica nada.
-- p_codigos_tw: ["EQ-TW-2026-0041", ...] códigos TW leídos de la hoja Equipos.
-- Resultados: 1 mensaje,
--   2 equipos del cliente con esos códigos (con la OS/OM activa en la que ya estén, para la advertencia de doble registro),
--   3 códigos que existen pero son de OTRO cliente o están inactivos (error),
--   4 catálogo de conceptos: suministros de clase servicio activos (la aplicación los empareja por descripción o código).
DROP PROCEDURE IF EXISTS SP_ObtenerCandidatosImportacionOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCandidatosImportacionOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_cliente BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigos_tw JSON
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para crear o editar órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_imp_cod;
    CREATE TEMPORARY TABLE tmp_os_imp_cod (codigo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PRIMARY KEY);
    INSERT IGNORE INTO tmp_os_imp_cod
    SELECT UPPER(TRIM(j.codigo)) FROM JSON_TABLE(IFNULL(p_codigos_tw, JSON_ARRAY()), '$[*]'
                                   COLUMNS (codigo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$')) j
    WHERE IFNULL(TRIM(j.codigo), '') <> '';

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT ec.id_equipo, ec.codigo_tw, ec.num_serie, ec.codigo_cliente, ec.clasificacion,
           COALESCE(tc.String1, ec.clasificacion) AS clasificacion_label,
           ec.marca, ec.modelo, ec.alcance_maximo, ec.ubicacion_especifica, sc.nombre AS sede,
           ec.division_minima, ec.division_verif, ec.clase_exactitud, ec.escala_graduacion, ec.puntos_calibracion, ec.valor_nominal,
           (SELECT CONCAT(o2.numero, '|', o2.estado) FROM os_equipo e2
            JOIN orden_servicio o2 ON o2.id_os = e2.id_os AND o2.eliminado_en IS NULL
            WHERE e2.id_equipo = ec.id_equipo AND e2.eliminado_en IS NULL AND o2.id_os <> IFNULL(p_id_os, 0)
              AND o2.estado NOT IN ('borrador', 'finalizada', 'anulada')
            ORDER BY o2.id_os DESC LIMIT 1) AS otra_os
    FROM equipo_cliente ec
    JOIN tmp_os_imp_cod t      ON t.codigo = ec.codigo_tw
    LEFT JOIN sede_cliente sc  ON sc.id_sede = ec.id_sede
    LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    WHERE ec.id_cliente = p_id_cliente AND ec.SoftDelete = 0 AND ec.estado = 'activo';

    SELECT ec.codigo_tw,
           IF(ec.id_cliente <> p_id_cliente, CONCAT('es de otro cliente (', IFNULL(c.razon_social, '—'), ')'),
              CONCAT('está ', ec.estado, ' en el catálogo del cliente')) AS motivo
    FROM equipo_cliente ec
    JOIN tmp_os_imp_cod t ON t.codigo = ec.codigo_tw
    LEFT JOIN cliente c   ON c.id_cliente = ec.id_cliente
    WHERE ec.SoftDelete = 0 AND (ec.id_cliente <> p_id_cliente OR ec.estado <> 'activo');

    DROP TEMPORARY TABLE IF EXISTS tmp_os_imp_cod;

    SELECT s.id_suministro, s.codigo, s.descripcion, tt.String1 AS tipo_label
    FROM suministros s
    LEFT JOIN tabla_maestra tt ON tt.IdMaestro = 72 AND tt.IdEmpresa = 1 AND tt.String2 = s.tipo
    WHERE s.clase = 'servicio' AND s.estado = 'activo' AND s.eliminado_en IS NULL
    ORDER BY s.descripcion;
END$$

DELIMITER ;
