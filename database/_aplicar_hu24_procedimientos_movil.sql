-- HU-24: biblioteca de procedimientos en la app. Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- ============================================================
-- SP_ObtenerProcedimientosMovil  (App Mobile HU-24 — Biblioteca de procedimientos)
-- Procedimientos APROBADOS (estado activo) con su PDF cargado, para consultarlos en la app:
--   1) Header.
--   2) Procedimientos: código, norma, versión, año, tipo (calibración / verificación…), alcance, aprobado por, fecha de actualización,
--      datos del PDF (nombre, tamaño, hash para saber si el teléfono tiene la versión vigente) y `para_servicio_hoy`:
--      número de la OS de HOY del técnico cuyos conceptos usan ese procedimiento (misma regla que el Asistente IA: suministros de clase servicio →
--      id_primer_procedimiento / id_segundo_procedimiento, resueltos por código o por id). La app descarga esos solos al iniciar la jornada.
--   3) Historial de versiones anteriores (procedimiento_metrologico_version): la vigente es la fila del procedimiento.
-- Los inactivos, borradores o sin PDF no se muestran (no hay nada que consultar). Hora de Lima (CURDATE).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerProcedimientosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProcedimientosMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Procedimientos vigentes con PDF
    WITH os_hoy AS (
        SELECT os.id_os, os.numero
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  os.estado IN ('programada', 'en_ruta', 'en_ejecucion', 'pausada', 'reprogramada', 'bloqueada')
          AND  NOT EXISTS (SELECT 1 FROM os_constancia k WHERE k.id_os = os.id_os AND k.cerrada_en IS NOT NULL)
          AND  os.fecha_ejecucion = CURDATE()
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op
                           WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ),
    refs AS (
        SELECT h.numero, TRIM(su.id_primer_procedimiento) AS ref
        FROM   os_hoy h
        JOIN   os_concepto oc ON oc.id_os = h.id_os AND oc.eliminado_en IS NULL
        JOIN   suministros su ON su.id_suministro = oc.id_suministro AND su.eliminado_en IS NULL
        WHERE  NULLIF(TRIM(su.id_primer_procedimiento), '') IS NOT NULL
        UNION
        SELECT h.numero, TRIM(su.id_segundo_procedimiento)
        FROM   os_hoy h
        JOIN   os_concepto oc ON oc.id_os = h.id_os AND oc.eliminado_en IS NULL
        JOIN   suministros su ON su.id_suministro = oc.id_suministro AND su.eliminado_en IS NULL
        WHERE  NULLIF(TRIM(su.id_segundo_procedimiento), '') IS NOT NULL
    )
    SELECT pm.id_procedimiento,
           pm.codigo,
           pm.anio,
           pm.version,
           pm.norma_base,
           pm.autor_norma,
           pm.tipo_procedimiento,
           pm.descripcion,
           pm.alcance,
           pm.aprobado_por,
           DATE(COALESCE(pm.pdf_subido_en, pm.FchMod, pm.FchCre)) AS actualizado,
           pm.pdf_nombre_original                                 AS pdf_nombre,
           pm.pdf_tamano_bytes                                    AS pdf_tamano,
           pm.pdf_hash_sha256                                     AS pdf_hash,
           (SELECT MIN(r.numero)
            FROM   refs r
            WHERE  pm.codigo = TRIM(SUBSTRING_INDEX(r.ref, ' - ', 1))
               OR  CAST(pm.id_procedimiento AS CHAR) COLLATE utf8mb4_0900_ai_ci = r.ref) AS para_servicio_hoy
    FROM   procedimiento_metrologico pm
    WHERE  pm.SoftDelete = 0
      AND  pm.estado = 'activo'
      AND  NULLIF(TRIM(pm.url_pdf_aprobado), '') IS NOT NULL
    ORDER BY pm.codigo, pm.anio DESC, pm.version DESC;

    -- 3. Versiones anteriores (ya no se pueden usar)
    SELECT v.id_procedimiento,
           v.version,
           DATE(v.FchCre) AS reemplazada_el
    FROM   procedimiento_metrologico_version v
    JOIN   procedimiento_metrologico pm ON pm.id_procedimiento = v.id_procedimiento
                                       AND pm.SoftDelete = 0 AND pm.estado = 'activo'
                                       AND NULLIF(TRIM(pm.url_pdf_aprobado), '') IS NOT NULL
    WHERE  v.version < pm.version
    ORDER BY v.id_procedimiento, v.version DESC;
END$$

DELIMITER ;
