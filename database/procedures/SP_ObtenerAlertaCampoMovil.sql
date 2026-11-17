-- ============================================================
-- SP_ObtenerAlertaCampoMovil  (App Mobile HU-32 — "Alerta de campo": pedido de apoyo del técnico ante un error crítico en un ensayo · lectura)
-- El jefe abre desde Notificaciones el aviso "Ensayo con error crítico" (HU-10) y ve: quién pidió apoyo y hace cuánto, la OS, el equipo y la tabla del ensayo
-- (carga L, indicación I, error E y EMP, con las lecturas críticas marcadas) para decidir.
--   - El aviso debe ser del jefe del token y ser un "Ensayo con error crítico" de una OS. La OS debe estar en el alcance del jefe (SP_ResolverJefaturaMovil +
--     SP_ArmarAlcanceJefaturaMovil: los servicios de su área; aquí cualquier fecha).
--   - El equipo es el último con una lectura crítica en esa OS (informe_ensayo.critico = 1).
-- Resultados: 1 mensaje · 2 alerta (1 fila) · 3 pesaje · 4 excentricidad.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAlertaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAlertaCampoMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT
)
proc: BEGIN
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen    TINYINT;
    DECLARE v_titulo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuerpo     VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha      DATETIME;
    DECLARE v_tec        BIGINT;
    DECLARE v_id_os      BIGINT;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_informe    BIGINT DEFAULT NULL;
    DECLARE v_id_eq      BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT n.titulo, n.cuerpo, n.fecha_creacion, n.creado_por, n.id_entidad INTO v_titulo, v_cuerpo, v_fecha, v_tec, v_id_os
    FROM   notificacion n
    WHERE  n.id_notificacion = p_id_notificacion AND n.id_usuario_destino = p_id_usuario AND n.entidad_tipo = 'orden_servicio'
      AND  n.titulo LIKE 'Ensayo con error cr%'
    LIMIT 1;
    IF v_titulo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La alerta no existe o no es tuya.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarAlcanceJefaturaMovil(v_area, v_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = v_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio de esta alerta no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El equipo con la lectura crítica más reciente de la OS
    SELECT it.id_informe, it.id_equipo INTO v_informe, v_id_eq
    FROM   informe_tecnico it
    JOIN   informe_ensayo ie ON ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL
    WHERE  it.id_os = v_id_os AND it.eliminado_en IS NULL
    ORDER BY ie.id_ensayo DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT n.id_notificacion, n.titulo, n.cuerpo,
           CONVERT_TZ(n.fecha_creacion, '+00:00', '-05:00') AS creada_en,
           GREATEST(0, TIMESTAMPDIFF(MINUTE, n.fecha_creacion, UTC_TIMESTAMP())) AS hace_min,
           os.id_os, os.numero AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente, sc.nombre AS sede,
           u.id_usuario AS id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS tecnico, NULLIF(TRIM(u.telefono), '') AS telefono,
           v_id_eq AS id_equipo,
           (SELECT oe.id FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.id_equipo = v_id_eq AND oe.eliminado_en IS NULL LIMIT 1) AS id_os_equipo,
           (SELECT CONCAT_WS(' · ', NULLIF(ec.codigo_cliente, ''), NULLIF(ec.codigo_tw, '')) FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq) AS equipo_codigo,
           (SELECT CONCAT_WS(' ', NULLIF(ec.marca, ''), NULLIF(ec.modelo, '')) FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq) AS equipo_descripcion,
           (SELECT NULLIF(ec.ubicacion_especifica, '') FROM equipo_cliente ec WHERE ec.id_equipo = v_id_eq) AS equipo_ubicacion
    FROM   notificacion n
    JOIN   orden_servicio os ON os.id_os = n.id_entidad
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede = os.id_sede
    LEFT JOIN usuario u ON u.id_usuario = n.creado_por
    WHERE  n.id_notificacion = p_id_notificacion;

    SELECT ie.orden, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'pesaje' AND ie.eliminado_en IS NULL
    ORDER BY ie.orden, ie.id_ensayo;

    SELECT ie.grupo, ie.orden AS posicion, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'excentricidad' AND ie.eliminado_en IS NULL
    ORDER BY ie.grupo, ie.orden, ie.id_ensayo;
END$$

DELIMITER ;
