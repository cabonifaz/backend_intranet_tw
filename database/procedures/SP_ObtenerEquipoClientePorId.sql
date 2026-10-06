DROP PROCEDURE IF EXISTS SP_ObtenerEquipoClientePorId;
DELIMITER $$
CREATE PROCEDURE SP_ObtenerEquipoClientePorId(
    IN p_id_equipo BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM equipo_cliente WHERE id_equipo = p_id_equipo AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Equipo no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            ec.id_equipo,
            ec.num_serie,
            ec.id_cliente,
            c.razon_social                            AS cliente_razon_social,
            ec.id_sede,
            s.nombre                                  AS sede_nombre,
            IFNULL(ec.codigo_cliente, '')             AS codigo_cliente,
            ec.codigo_tw,
            ec.clasificacion,
            COALESCE(tm_cl.String1, ec.clasificacion) AS clasificacion_label,
            ec.marca,
            ec.modelo,
            CASE ec.estado
                WHEN 'activo'   THEN 'Activo'
                WHEN 'inactivo' THEN 'Inactivo'
                WHEN 'borrador' THEN 'Borrador'
                ELSE ec.estado
            END                                       AS estado,
            ec.es_activo,

            IFNULL(ec.ubicacion_especifica, '')       AS ubicacion_especifica,
            ec.es_pre_revisado,
            IFNULL(ec.usuario_pre_revisor, '')        AS usuario_pre_revisor,
            ec.fecha_pre_revision,
            ec.bloqueado_para_servicios,

            ec.id_suministro,
            IFNULL(
                CONCAT_WS(' ', NULLIF(ci.marca, ''), NULLIF(ci.modelo, ''), NULLIF(ci.descripcion, '')),
                ''
            )                                         AS suministro_label,
            IFNULL(ec.division_minima, '')            AS division_minima,
            IFNULL(ec.division_verif, '')             AS division_verif,
            ec.division_verif_igual,
            IFNULL(ec.clase_exactitud, '')            AS clase_exactitud,
            IFNULL(ec.alcance_maximo, '')             AS alcance_maximo,
            IFNULL(ec.escala_graduacion, '')          AS escala_graduacion,
            IFNULL(ec.puntos_calibracion, '')         AS puntos_calibracion,
            IFNULL(ec.rango_operativo_real, '')       AS rango_operativo_real,
            IFNULL(ec.material, '')                   AS material,
            IFNULL(ec.valor_nominal, '')              AS valor_nominal,
            IFNULL(ec.observaciones, '')              AS observaciones,

            ec.estado_operativo,

            IFNULL(ec.usuario_registro,
                   COALESCE(CONCAT(u.nombre, ' ', u.apellido), 'Sistema')) AS usuario_registro,
            ec.FchCre                                 AS fecha_registro,
            IFNULL(ec.pc_registro, '')                AS pc_registro,
            COALESCE(ec.FchMod, ec.FchCre)            AS fecha_modificacion
        FROM   equipo_cliente ec
        LEFT   JOIN cliente c       ON c.id_cliente = ec.id_cliente
        LEFT   JOIN sede_cliente s  ON s.id_sede    = ec.id_sede
        LEFT   JOIN tabla_maestra tm_cl
                 ON tm_cl.IdMaestro = 71 AND tm_cl.IdEmpresa = 1 AND tm_cl.String2 = ec.clasificacion
        LEFT   JOIN suministros ci   ON ci.id_suministro = ec.id_suministro
        LEFT   JOIN usuario u        ON u.correo = ec.usuario_registro
        WHERE  ec.id_equipo = p_id_equipo;
    END IF;
END$$
DELIMITER ;
