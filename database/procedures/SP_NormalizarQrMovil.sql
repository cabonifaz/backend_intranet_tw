-- ============================================================
-- SP_NormalizarQrMovil  (App Mobile HU-11 / HU-07 — apoyo, NO es un endpoint)
-- Convierte lo que leyó la cámara en una CLAVE estable de etiqueta QR de Total Weight, UNA sola vez (la usan SP_RegistrarEvidenciaMovil y SP_BuscarEquipoQrMovil):
--   https://q.me-qr.com/<id>        → 'meqr:<id>'     (el enlace corto del QR impreso; redirige a tw.com.pe/e/<código>)
--   https://www.tw.com.pe/e/<cód>   → 'twe:<CÓD>'     (el destino directo)
--   cualquier otra cosa (un código de texto como COD-0003067, un N/S…) → NULL: esos se comparan por texto con el equipo, como siempre.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_NormalizarQrMovil;

DELIMITER $$

CREATE PROCEDURE SP_NormalizarQrMovil(
    IN  p_texto VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_clave VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_t VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_clave = NULL;
    SET v_t = TRIM(IFNULL(p_texto, ''));
    IF v_t REGEXP '^https?://q\\.me-qr\\.com/[A-Za-z0-9_-]{4,40}/?([?#].*)?$' THEN
        SET p_clave = CONCAT('meqr:', REGEXP_SUBSTR(REGEXP_REPLACE(v_t, '^https?://q\\.me-qr\\.com/', ''), '^[A-Za-z0-9_-]+'));
    ELSEIF v_t REGEXP '^https?://(www\\.)?tw\\.com\\.pe/e/[A-Za-z0-9_-]{3,40}/?([?#].*)?$' THEN
        SET p_clave = CONCAT('twe:', UPPER(REGEXP_SUBSTR(REGEXP_REPLACE(v_t, '^https?://(www\\.)?tw\\.com\\.pe/e/', ''), '^[A-Za-z0-9_-]+')));
    END IF;
END$$

DELIMITER ;
