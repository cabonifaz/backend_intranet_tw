-- HU-51 (Sprint 5) Filtros globales de la bandeja de seguimiento. Ayuda interna: NO devuelve resultados. Requiere SP_ArmarSeguimientoOperativo.
-- Deja en tmp_sg_f los servicios (id_os) que cumplen TODOS los filtros recibidos (NULL = sin filtro). Los parámetros ya vienen validados
-- por el backend; aun así se usan solo como VALORES (nunca se arma SQL con ellos). La búsqueda escapa % _ y \ y busca por N° OS/OM,
-- cliente, RUC o técnico (cualquiera de los asignados al servicio).
DROP PROCEDURE IF EXISTS SP_FiltrarSeguimientoOperativo;

DELIMITER $$

CREATE PROCEDURE SP_FiltrarSeguimientoOperativo(
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_like VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    IF NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NOT NULL THEN
        SET v_like = CONCAT('%', REPLACE(REPLACE(REPLACE(TRIM(p_busqueda), '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_sg_f;
    CREATE TEMPORARY TABLE tmp_sg_f (id_os BIGINT NOT NULL, PRIMARY KEY (id_os));
    INSERT INTO tmp_sg_f
    SELECT o.id_os
    FROM tmp_sg_os o
    WHERE (p_id_cliente IS NULL OR o.id_cliente = p_id_cliente)
      AND (NULLIF(TRIM(IFNULL(p_estado, '')), '') IS NULL OR o.estado_seg = p_estado)
      AND (NULLIF(TRIM(IFNULL(p_zona, '')), '') IS NULL OR o.zona = p_zona)
      AND (p_id_tecnico IS NULL OR EXISTS (SELECT 1 FROM tmp_sg_ut ut WHERE ut.id_os = o.id_os AND ut.id_usuario = p_id_tecnico))
      AND (v_like IS NULL OR o.numero LIKE v_like OR o.razon_social LIKE v_like OR IFNULL(o.ruc, '') LIKE v_like
           OR EXISTS (SELECT 1 FROM tmp_sg_utn n WHERE n.id_os = o.id_os AND n.nombre LIKE v_like));
END$$

DELIMITER ;
