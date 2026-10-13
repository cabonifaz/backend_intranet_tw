-- ============================================================
-- Migración 61 — HU-13b: Estado 'revocada' para propuestas
--   Cuando el jefe aprueba una solicitud de revocación de VB:
--     * La versión aprobada queda terminal como 'revocada' (preserva auditoría).
--     * Se auto-crea una nueva versión en 'borrador' para edición.
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

ALTER TABLE propuesta_comercial
    MODIFY COLUMN estado ENUM(
        'borrador', 'pendiente_vb', 'enviado', 'aprobado',
        'rechazado', 'anulado', 'vencido', 'pendiente_revocacion', 'revocada'
    ) NOT NULL DEFAULT 'borrador';
