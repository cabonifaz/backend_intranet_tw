-- HU-52 (Sprint 5) Ayuda interna del Detalle del Servicio en Ruta: valida el permiso (seg_bandeja) y el servicio, y arma el estado del día.
-- NO devuelve resultados; deja p_mensaje con el motivo cuando no se puede continuar (NULL = continuar). Solo LEE datos.
-- El servicio debe estar en la jornada de hoy (programación confirmada y OS/OM no anulada); si no, no se revela nada más.
-- Deja listas las tablas temporales tmp_sg_* de SP_ArmarSeguimientoOperativo; quien llama debe terminar con SP_LimpiarSeguimientoOperativo.
DROP PROCEDURE IF EXISTS SP_PrepararDetalleServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_PrepararDetalleServicioRuta(
    IN  p_id_usuario BIGINT,
    IN  p_id_os      BIGINT,
    OUT p_mensaje    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    SET p_mensaje = NULL;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SET p_mensaje = 'No tienes permiso para ver el seguimiento operativo.';
    ELSEIF IFNULL(p_id_os, 0) <= 0 THEN
        SET p_mensaje = 'El servicio indicado no es válido.';
    ELSE
        CALL SP_ArmarSeguimientoOperativo();
        SELECT COUNT(*) INTO v_existe FROM tmp_sg_os WHERE id_os = p_id_os;
        IF v_existe = 0 THEN
            CALL SP_LimpiarSeguimientoOperativo();
            SET p_mensaje = 'El servicio no está en la jornada de hoy o no existe.';
        END IF;
    END IF;
END$$

DELIMITER ;
