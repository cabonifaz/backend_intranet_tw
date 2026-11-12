-- ============================================================
-- Migración 106 — Etiquetas QR de los equipos (App Mobile HU-11 / HU-07)
--   Las etiquetas QR de Total Weight NO traen el código del equipo en texto: traen un enlace corto (q.me-qr.com/<id>, que redirige a tw.com.pe/e/<código>).
--   equipo_qr guarda a qué equipo pertenece cada QR (clave normalizada por SP_NormalizarQrMovil). La primera vez que el técnico escanea un QR de etiqueta
--   que todavía no pertenece a nadie, queda vinculado al equipo que está trabajando; si luego aparece en otro equipo se rechaza.
--   clave UNIQUE: un QR pertenece a un solo equipo (un equipo puede tener varias etiquetas, p. ej. una reimpresa). No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS equipo_qr (
    id_equipo_qr   BIGINT        NOT NULL AUTO_INCREMENT,
    id_equipo      BIGINT        NOT NULL,
    clave          VARCHAR(120)  NOT NULL,
    texto          VARCHAR(300)  NULL,
    -- AUDITORÍA
    creado_en      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT        NULL,
    eliminado_en   DATETIME      NULL,
    eliminado_por  BIGINT        NULL,
    PRIMARY KEY (id_equipo_qr),
    UNIQUE KEY ux_equipo_qr_clave (clave),
    KEY ix_equipo_qr_equipo (id_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
