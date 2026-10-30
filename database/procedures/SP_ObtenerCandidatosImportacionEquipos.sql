-- Propuestas — Importación de equipos desde Excel con IA (Sprint 4).
-- Datos para conciliar las filas del Excel (no modifica nada):
--   1. cliente (razón social)
--   2. equipos del cliente (todos los no eliminados, con su estado)
--   3. sedes activas del cliente
--   4. catálogo de suministros de clase equipo / instrumento / pesa (activos)
--   5. equipos de OTROS clientes cuya serie normalizada está en p_series_json (para no duplicarlos)
--   6. clasificaciones válidas para un equipo nuevo (IdMaestro 71 sin "servicio")
-- p_series_json: ["MT864429", ...] series en mayúsculas, solo letras y dígitos.
DROP PROCEDURE IF EXISTS SP_ObtenerCandidatosImportacionEquipos;
DELIMITER $$
CREATE PROCEDURE SP_ObtenerCandidatosImportacionEquipos(
    IN p_id_cliente   BIGINT,
    IN p_series_json  LONGTEXT,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET p_series_json = IFNULL(NULLIF(TRIM(p_series_json), ''), '[]');
    IF JSON_VALID(p_series_json) = 0 THEN
        SET p_series_json = '[]';
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 1. Cliente
    SELECT c.razon_social
    FROM   cliente c
    WHERE  c.id_cliente = p_id_cliente;

    -- 2. Equipos del cliente
    SELECT ec.id_equipo,
           ec.codigo_tw,
           ec.num_serie,
           ec.codigo_cliente,
           ec.clasificacion,
           COALESCE(tm_cl.String1, ec.clasificacion) AS clasificacion_label,
           ec.marca,
           ec.modelo,
           ec.id_sede,
           s.nombre                                  AS sede_nombre,
           ec.ubicacion_especifica,
           ec.alcance_maximo,
           ec.estado,
           su.tipo                                   AS suministro_tipo,
           su.subtipo                                AS suministro_subtipo
    FROM   equipo_cliente ec
    LEFT   JOIN sede_cliente s   ON s.id_sede = ec.id_sede
    LEFT   JOIN suministros  su  ON su.id_suministro = ec.id_suministro
    LEFT   JOIN tabla_maestra tm_cl
             ON tm_cl.IdMaestro = 71 AND tm_cl.IdEmpresa = 1 AND tm_cl.String2 = ec.clasificacion
    WHERE  ec.id_cliente = p_id_cliente
      AND  ec.SoftDelete = 0
    ORDER  BY ec.id_equipo;

    -- 3. Sedes del cliente
    SELECT s.id_sede, s.nombre
    FROM   sede_cliente s
    WHERE  s.id_cliente = p_id_cliente
      AND  s.SoftDelete = 0
      AND  IFNULL(s.estado, 'Activo') = 'Activo'
    ORDER  BY s.nombre;

    -- 4. Catálogo de suministros (modelos de equipo, instrumento y pesa)
    SELECT su.id_suministro,
           su.codigo,
           su.descripcion,
           su.clase,
           su.tipo,
           su.subtipo,
           su.marca,
           su.modelo
    FROM   suministros su
    WHERE  su.eliminado_en IS NULL
      AND  su.estado = 'activo'
      AND  su.clase IN ('equipo', 'instrumento', 'pesa')
    ORDER  BY su.id_suministro;

    -- 5. La misma serie registrada en otros clientes
    SELECT ec.id_equipo,
           ec.codigo_tw,
           ec.num_serie,
           ec.marca,
           ec.modelo,
           c.razon_social
    FROM   equipo_cliente ec
    JOIN   JSON_TABLE(p_series_json, '$[*]'
               COLUMNS (serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$')) jt
             ON jt.serie = REGEXP_REPLACE(UPPER(ec.num_serie), '[^A-Z0-9]', '')
    LEFT   JOIN cliente c ON c.id_cliente = ec.id_cliente
    WHERE  ec.id_cliente <> p_id_cliente
      AND  ec.SoftDelete = 0;

    -- 6. Clasificaciones para un equipo nuevo
    SELECT tm.String2 AS codigo,
           tm.String1 AS nombre
    FROM   tabla_maestra tm
    WHERE  tm.IdMaestro = 71
      AND  tm.IdEmpresa = 1
      AND  tm.String2 <> 'servicio'
    ORDER  BY tm.Num1;
END$$
DELIMITER ;
