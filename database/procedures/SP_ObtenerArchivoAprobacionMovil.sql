-- ============================================================
-- SP_ObtenerArchivoAprobacionMovil  (App Mobile HU-31 — foto de una evidencia forzada o de un gasto para el jefe · lectura)
--   p_tipo: evidencia (id = id_evidencia; n se ignora) | gasto (id = id_gasto; n = orden de la foto, 1 a 5).
--   Mismas reglas de acceso que SP_ObtenerAprobacionDetalleMovil: evidencia → encargado del área de la RQ, supervisión general o administrador;
--   gasto → prog_aprobar_reprogramacion. Solo devuelve rutas; la API abre el archivo con autenticación.
-- Resultados: 1 mensaje · 2 (ruta, ruta_cuadro, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoAprobacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoAprobacionMovil(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id         BIGINT,
    IN p_n          INT
)
proc: BEGIN
    DECLARE v_tipo      VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_id_os     BIGINT;
    DECLARE v_area_os   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ruta      VARCHAR(500);
    DECLARE v_cuadro    VARCHAR(500);
    DECLARE v_video     TINYINT DEFAULT 0;
    DECLARE v_url       VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('evidencia', 'gasto') OR IFNULL(p_id, 0) <= 0 OR (v_tipo = 'gasto' AND IFNULL(p_n, 0) NOT BETWEEN 1 AND 5) THEN
        SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_tipo = 'evidencia' THEN
        SELECT f.id_os, NULLIF(TRIM(IFNULL(f.url_archivo, '')), ''), NULLIF(TRIM(IFNULL(f.ruta_cuadro, '')), ''), IFNULL(f.es_video, 0)
          INTO v_id_os, v_ruta, v_cuadro, v_video
        FROM evidencia_fotografica f WHERE f.id_evidencia = p_id AND f.override_aprobado = 1 AND f.eliminado_en IS NULL;

        SELECT COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                        IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
               (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
                OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
        INTO   v_area_jefe, v_general
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
        LIMIT 1;

        SELECT asr.area_usuario INTO v_area_os
        FROM orden_servicio os
        LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
        LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
        WHERE os.id_os = v_id_os;

        IF v_id_os IS NULL OR v_ruta IS NULL
           OR NOT (IFNULL(v_general, 0) = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))) THEN
            SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
        SELECT MAX(url_comprobante), MAX(id_os) INTO v_url, v_id_os
        FROM gasto_viatico WHERE id_gasto = p_id AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
        SELECT url INTO v_ruta FROM gasto_viatico_foto WHERE id_gasto = p_id AND orden = p_n AND eliminado_en IS NULL ORDER BY id_foto DESC LIMIT 1;
        IF v_ruta IS NULL AND p_n = 1 AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto WHERE id_gasto = p_id AND eliminado_en IS NULL) THEN
            SET v_ruta = NULLIF(TRIM(IFNULL(v_url, '')), '');
        END IF;
        IF v_id_os IS NULL OR v_ruta IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
END$$

DELIMITER ;
