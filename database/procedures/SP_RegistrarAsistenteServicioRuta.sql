-- HU-53 (Sprint 5) Registro operativo del Asistente de Seguimiento: registra desde la intranet, en nombre del técnico, una observación, una demora/incidente
-- o un cambio manual de estado del servicio. Requiere la acción seg_registrar (nivel editar) y que el servicio esté en la jornada de hoy.
--   p_modo: observacion | demora | cambio_estado
--   observacion : p_descripcion (1..500), p_fuente (opcional: llamada_telefonica|whatsapp|contacto_planta|observacion_directa), p_vinculo (opcional: clave del timeline de este servicio)
--   demora      : p_id_tipo (catálogo TIPO_DEMORA_INCIDENTE), p_descripcion (1..500), p_duracion (opcional 1..1440), p_impacto (retrasa|detiene; por defecto retrasa),
--                 p_evidencia (opcional: https://… o /ruta, ≤500). Si detiene → notifica a quienes tienen seg_alerta_registro (Jefe de Operaciones).
--   cambio_estado (crítico): p_nuevo_estado (salida|en_ruta|llegada|ingreso|inicio|finalizado; solo avanza), p_id_motivo (catálogo MOTIVO_CAMBIO_MANUAL),
--                 p_comentario (10..1000, obligatorio). Actualiza la OS, crea el hito del técnico, notifica siempre al Jefe y audita en la OS y el expediente.
-- Antiduplicado: mismo usuario + OS + modo + texto en 15 s → regla de negocio. Límite: 30 registros por usuario en 10 min.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) IdRegistro, Modo, Notificados, EstadoNuevo.
-- Concurrencia: serializa por usuario con GET_LOCK (doble clic, replay o ráfagas en paralelo no duplican ni saltan el límite) y delega en SP_RegistrarAsistenteServicioRutaInterno.
-- Requiere las migraciones 90, 91 y 92.
DROP PROCEDURE IF EXISTS SP_RegistrarAsistenteServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarAsistenteServicioRuta(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_modo        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fuente      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_vinculo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tipo     INT,
    IN p_duracion    INT,
    IN p_impacto     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_evidencia   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nuevo_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo   INT,
    IN p_comentario  VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_candado VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DO RELEASE_LOCK(v_candado);
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_candado = CONCAT('tw_reg_asistente_', IFNULL(p_id_usuario, 0));
    IF IFNULL(GET_LOCK(v_candado, 5), 0) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Hay otro registro en curso. Inténtalo de nuevo en unos segundos.' AS Mensaje;
    ELSE
        CALL SP_RegistrarAsistenteServicioRutaInterno(p_id_usuario, p_id_os, p_modo, p_descripcion, p_fuente, p_vinculo, p_id_tipo, p_duracion, p_impacto, p_evidencia, p_nuevo_estado, p_id_motivo, p_comentario);
        DO RELEASE_LOCK(v_candado);
    END IF;
END$$

DELIMITER ;
