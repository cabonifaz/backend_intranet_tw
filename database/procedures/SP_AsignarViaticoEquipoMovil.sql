-- ============================================================
-- SP_AsignarViaticoEquipoMovil  (App Mobile HU-35 — "Asignar viático" a un técnico del servicio, por concepto · escritura)
-- El jefe asigna a UN técnico del servicio los montos de Movilidad, Alimentación, Alojamiento y Otros, y puede dejarlo marcado como «Ya depositado». El técnico lo ve al instante en
-- «Viáticos y Gastos» de su app (HU-25) y recibe la notificación «Viático asignado».
-- NO duplica las reglas de la intranet (HU-45): arma la asignación COMPLETA de la programación (las líneas de los demás técnicos y los demás conceptos del técnico quedan tal cual;
-- los 4 conceptos del técnico se ponen con los montos recibidos) y la guarda con SP_GuardarViaticosProgramacion, que valida: prog_aprobar_reprogramacion, programación confirmada,
-- rendición abierta, servicio sin salir a campo, tope VIATICOS_MONTO_MAXIMO, concurrencia por versión, líneas depositadas inmutables, auditoría y aviso a Contabilidad.
--   p_version : la huella (SP_ObtenerViaticoServicioEquipoMovil.version) con la que el jefe abrió el servicio; si cambió mientras tanto, se rechaza y hay que recargar.
--   Un monto 0 (o vacío) quita esa línea si todavía no está depositada; una línea depositada no se puede cambiar ni quitar (mensaje de negocio).
--   p_depositado = 1 : los viáticos PENDIENTES de ese técnico quedan depositados (estado 'aprobado' + fecha de depósito) en la misma transacción.
--     EXCEPCIÓN pedida por el usuario a la regla de HU-45 «el módulo nunca marca Depositado» (lo hacía solo Contabilidad): ver la cabecera de SP_GuardarViaticosProgramacion.
--     Un depósito no se puede revertir: si todo lo del técnico ya está depositado y llega p_depositado = 0, se responde con un mensaje de negocio.
--     Contabilidad: lo pendiente se les sigue avisando; lo que el jefe deja depositado no.
--   Alcance (Área + Rol): SP_ArmarAlcanceViaticosMovil. El técnico debe ser del personal de la programación.
-- Resultados: los de SP_GuardarViaticosProgramacion (1 mensaje · 2 resultado: total_asignado, total_depositado, total_pendiente, notificados_contabilidad, sin_cambios, version…)
--   y, solo si guardó, 3: total_tecnico (lo asignado a ese técnico), depositado (1 si todo lo del técnico está depositado), tecnico_notificado (1 si se le avisó), version.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AsignarViaticoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_AsignarViaticoEquipoMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_id_tecnico  BIGINT,
    IN p_movilidad   DECIMAL(12,2),
    IN p_alimentacion DECIMAL(12,2),
    IN p_alojamiento DECIMAL(12,2),
    IN p_otros       DECIMAL(12,2),
    IN p_depositado  TINYINT,
    IN p_version     VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_sin       TINYINT DEFAULT 0;
    DECLARE v_prog      BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_json      JSON DEFAULT NULL;
    DECLARE v_cap       DECIMAL(18,6) DEFAULT 5000;
    DECLARE v_mov       INT DEFAULT NULL;
    DECLARE v_ali       INT DEFAULT NULL;
    DECLARE v_alo       INT DEFAULT NULL;
    DECLARE v_otr       INT DEFAULT NULL;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_concepto  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_v0        VARCHAR(80);
    DECLARE v_v1        VARCHAR(80);
    DECLARE v_total_tec DECIMAL(12,2) DEFAULT 0;
    DECLARE v_n_tec     INT DEFAULT 0;
    DECLARE v_pend_tec  INT DEFAULT 0;
    DECLARE v_depos_tec INT DEFAULT 0;
    DECLARE v_notif     TINYINT DEFAULT 0;
    DECLARE v_lista     TEXT;
    DECLARE v_dep_prev  INT DEFAULT 0;
    DECLARE v_pend_nuevo INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_vi_deposita_jefe = NULL, @tw_vi_deposita_prog = NULL, @tw_vi_deposita_tecnico = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET SESSION group_concat_max_len = 32768;
    SET @tw_vi_deposita_jefe = NULL, @tw_vi_deposita_prog = NULL, @tw_vi_deposita_tecnico = NULL, @tw_vi_ok = 0;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede asignar viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el técnico al que se asigna el viático.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_version, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la versión de la asignación: vuelve a abrir los viáticos del servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET p_movilidad    = IFNULL(p_movilidad, 0);
    SET p_alimentacion = IFNULL(p_alimentacion, 0);
    SET p_alojamiento  = IFNULL(p_alojamiento, 0);
    SET p_otros        = IFNULL(p_otros, 0);
    IF p_movilidad < 0 OR p_alimentacion < 0 OR p_alojamiento < 0 OR p_otros < 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Los montos no pueden ser negativos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_movilidad + p_alimentacion + p_alojamiento + p_otros <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica al menos un monto mayor a 0.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LeerParametroProgramacion('VIATICOS_MONTO_MAXIMO', 5000, v_cap);
    IF p_movilidad > v_cap OR p_alimentacion > v_cap OR p_alojamiento > v_cap OR p_otros > v_cap THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Cada monto debe ser de hasta S/ ', FORMAT(v_cap, 2), '.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Alcance: el servicio debe ser de los que el jefe ve y operar
    CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, p_id_os, v_sin);
    IF v_sin = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tmp_vi_alc WHERE id_os = p_id_os) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no tiene programación o no pertenece a tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;

    SELECT MAX(p2.id_programacion) INTO v_prog
    FROM programacion p2 WHERE p2.id_os = p_id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL;
    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) INTO v_numero, v_cliente
    FROM orden_servicio os LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente WHERE os.id_os = p_id_os;

    IF NOT EXISTS (SELECT 1 FROM programacion_tecnico pt
                   WHERE pt.id_programacion = v_prog AND pt.id_usuario = p_id_tecnico AND pt.eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Los viáticos solo se asignan al personal de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Los 4 conceptos fijos del catálogo CONCEPTO_GASTO (el catálogo de la intranet)
    SELECT MIN(Num1) INTO v_mov FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'MOVILIDAD';
    SELECT MIN(Num1) INTO v_ali FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'ALIMENTACION';
    SELECT MIN(Num1) INTO v_alo FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'ALOJAMIENTO';
    SELECT MIN(Num1) INTO v_otr FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'OTRO';
    IF v_mov IS NULL OR v_ali IS NULL OR v_alo IS NULL OR v_otr IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El catálogo de conceptos de gasto no tiene Movilidad, Alimentación, Alojamiento u Otro: pídele a TI que lo complete.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;
    CREATE TEMPORARY TABLE tmp_vi_pedido (id_concepto INT NOT NULL, monto DECIMAL(12,2) NOT NULL, PRIMARY KEY (id_concepto));
    INSERT INTO tmp_vi_pedido (id_concepto, monto)
    VALUES (v_mov, p_movilidad), (v_ali, p_alimentacion), (v_alo, p_alojamiento), (v_otr, p_otros);

    -- Un viático ya depositado no se modifica ni se quita
    SELECT MIN(IFNULL(cg.String1, 'Concepto')) INTO v_concepto
    FROM gasto_viatico g
    JOIN tmp_vi_pedido d ON d.id_concepto = g.id_concepto
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico AND g.estado IN ('aprobado', 'rendido')
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
      AND g.monto <> d.monto;
    IF v_concepto IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;
        SELECT 1 AS IdTipoMensaje, CONCAT('El viático de ', v_concepto, ' ya está depositado: no se puede modificar ni quitar.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Asignación completa: lo ajeno y lo que no se toca queda igual; los 4 conceptos del técnico salen del formulario
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
    CREATE TEMPORARY TABLE tmp_vi_lin (id_gasto BIGINT NULL, id_usuario BIGINT NOT NULL, id_concepto INT NOT NULL, monto DECIMAL(12,2) NOT NULL);

    INSERT INTO tmp_vi_lin (id_gasto, id_usuario, id_concepto, monto)
    SELECT g.id_gasto, g.id_usuario, g.id_concepto, g.monto
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
      AND NOT (g.id_usuario = p_id_tecnico AND g.id_concepto IN (v_mov, v_ali, v_alo, v_otr));

    INSERT INTO tmp_vi_lin (id_gasto, id_usuario, id_concepto, monto)
    SELECT g.id_gasto, p_id_tecnico, d.id_concepto, d.monto
    FROM tmp_vi_pedido d
    LEFT JOIN gasto_viatico g ON g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico AND g.id_concepto = d.id_concepto
                              AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    WHERE d.monto > 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;

    -- Un depósito no se revierte: si todo lo del técnico ya está depositado y se pide «Pendiente», no hay nada que hacer
    SELECT IFNULL(SUM(g.estado IN ('aprobado', 'rendido')), 0) INTO v_dep_prev
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));
    SELECT COUNT(*) INTO v_pend_nuevo
    FROM tmp_vi_lin l
    LEFT JOIN gasto_viatico g ON g.id_gasto = l.id_gasto
    WHERE l.id_usuario = p_id_tecnico AND (l.id_gasto IS NULL OR g.estado NOT IN ('aprobado', 'rendido'));
    IF IFNULL(p_depositado, 0) = 0 AND v_dep_prev > 0 AND v_pend_nuevo = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
        SELECT 1 AS IdTipoMensaje, 'Los viáticos de este técnico ya están depositados: no se puede volver a Pendiente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT JSON_ARRAYAGG(JSON_OBJECT('idGasto', l.id_gasto, 'idTecnico', l.id_usuario, 'idConcepto', l.id_concepto, 'monto', l.monto))
      INTO v_json
    FROM tmp_vi_lin l;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
    IF v_json IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay nada que asignar.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_VersionViaticosProgramacion(v_prog, p_id_os, 1, v_v0);

    -- Guardar con las reglas de HU-45 (y, si el jefe lo pidió, dejar el depósito marcado en la misma transacción)
    IF IFNULL(p_depositado, 0) = 1 THEN
        SET @tw_vi_deposita_jefe = p_id_usuario, @tw_vi_deposita_prog = v_prog, @tw_vi_deposita_tecnico = p_id_tecnico;
    END IF;
    SET @tw_vi_ok = 0;
    CALL SP_GuardarViaticosProgramacion(p_id_usuario, v_prog, TRIM(p_version), v_json);
    SET @tw_vi_deposita_jefe = NULL, @tw_vi_deposita_prog = NULL, @tw_vi_deposita_tecnico = NULL;

    -- Solo si guardó: aviso al técnico y totales de su asignación
    IF @tw_vi_ok = 1 THEN
        SET @tw_vi_ok = 0;
        CALL SP_VersionViaticosProgramacion(v_prog, p_id_os, 1, v_v1);

        SELECT IFNULL(SUM(g.monto), 0), COUNT(*), IFNULL(SUM(g.estado NOT IN ('aprobado', 'rendido')), 0),
               GROUP_CONCAT(CONCAT(IFNULL(cg.String1, 'Concepto'), ' S/ ', FORMAT(g.monto, 2)) ORDER BY g.id_gasto SEPARATOR ', ')
          INTO v_total_tec, v_n_tec, v_pend_tec, v_lista
        FROM gasto_viatico g
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
        WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico
          AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));
        SET v_depos_tec = IF(v_n_tec > 0 AND v_pend_tec = 0, 1, 0);

        IF v_v1 <> v_v0 AND p_id_tecnico <> p_id_usuario AND v_n_tec > 0 THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por, prioridad_origen)
            VALUES (p_id_tecnico, 5, LEFT(CONCAT('Viático asignado: S/ ', FORMAT(v_total_tec, 2)), 150),
                    LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), '. ', IFNULL(v_lista, ''), '. ',
                                IF(v_depos_tec = 1, 'Ya está depositado.', 'Pendiente de depósito.'), ' Míralo en Viáticos y Gastos.'), 3000),
                    'programacion', v_prog, NOW(), p_id_usuario, 'alta');
            SET v_notif = 1;
        END IF;

        SELECT v_total_tec AS total_tecnico, v_depos_tec AS depositado, v_notif AS tecnico_notificado, v_v1 AS version;
    END IF;
END$$

DELIMITER ;
