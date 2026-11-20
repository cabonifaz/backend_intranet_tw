-- ============================================================
-- SP_ArmarInstrumentosRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — apoyo, NO es un endpoint)
-- Con las OM de `tmp_rom_os` (SP_ArmarOmTecnicoMovil) deja en la tabla temporal `tmp_rom_inst` los instrumentos de cada una (os_equipo no eliminados) y si ya fueron
-- RECIBIDOS: UNA sola regla de «instrumento recibido» = tiene una fila no eliminada en om_recepcion_equipo cuya recepción (om_recepcion) tampoco está eliminada.
-- Un instrumento se recibe una sola vez por OM; si hubiera más de una fila se toma la primera.
-- Columnas: id_os · id_os_equipo · id_equipo · numero (1..n dentro de la OM) · nombre · marca · modelo · serie · capacidad · codigo_cliente · codigo_tw ·
--   recibido (0/1) · id_recepcion · id_recepcion_equipo · estado_fisico · observaciones · accesorios (JSON) · fotos (n.º de fotos de la recepción) · recibido_utc.
-- El nombre sale igual que en los objetivos del servicio (suministro → clasificación → «Equipo»).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarInstrumentosRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarInstrumentosRecepcionOmMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    CREATE TEMPORARY TABLE tmp_rom_inst (
        id_os BIGINT NOT NULL,
        id_os_equipo BIGINT NOT NULL,
        id_equipo BIGINT NOT NULL,
        numero INT NOT NULL,
        nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        marca VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        modelo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        capacidad VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_tw VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        recibido TINYINT NOT NULL DEFAULT 0,
        id_recepcion BIGINT NULL,
        id_recepcion_equipo BIGINT NULL,
        estado_fisico VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        observaciones VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        accesorios JSON NULL,
        fotos INT NOT NULL DEFAULT 0,
        recibido_utc DATETIME NULL,
        PRIMARY KEY (id_os_equipo));

    INSERT INTO tmp_rom_inst (id_os, id_os_equipo, id_equipo, numero, nombre, marca, modelo, serie, capacidad, codigo_cliente, codigo_tw,
                              recibido, id_recepcion, id_recepcion_equipo, estado_fisico, observaciones, accesorios, fotos, recibido_utc)
    SELECT oe.id_os, oe.id, oe.id_equipo,
           ROW_NUMBER() OVER (PARTITION BY oe.id_os ORDER BY IFNULL(oe.orden, oe.id), oe.id),
           LEFT(REPLACE(COALESCE(NULLIF(TRIM(su.descripcion), ''), tc.String1, ec.clasificacion, 'Equipo'), '|', ' '), 150),
           ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), ''), NULLIF(TRIM(ec.alcance_maximo), ''), NULLIF(ec.codigo_cliente, ''), ec.codigo_tw,
           IF(re.id_recepcion_equipo IS NULL, 0, 1), re.id_recepcion, re.id_recepcion_equipo, re.estado_fisico, re.observaciones, re.accesorios,
           (SELECT COUNT(*) FROM om_recepcion_foto f WHERE f.id_recepcion_equipo = re.id_recepcion_equipo AND f.eliminado_en IS NULL),
           r.recibido_utc
    FROM   os_equipo oe
    JOIN   tmp_rom_os o ON o.id_os = oe.id_os
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    LEFT JOIN (SELECT x.id_os_equipo, MIN(x.id_recepcion_equipo) AS id_recepcion_equipo
               FROM   om_recepcion_equipo x
               JOIN   om_recepcion xr ON xr.id_recepcion = x.id_recepcion AND xr.eliminado_en IS NULL
               WHERE  x.eliminado_en IS NULL
               GROUP BY x.id_os_equipo) pr ON pr.id_os_equipo = oe.id
    LEFT JOIN om_recepcion_equipo re ON re.id_recepcion_equipo = pr.id_recepcion_equipo
    LEFT JOIN om_recepcion r ON r.id_recepcion = re.id_recepcion
    WHERE  oe.eliminado_en IS NULL;
END$$

DELIMITER ;
