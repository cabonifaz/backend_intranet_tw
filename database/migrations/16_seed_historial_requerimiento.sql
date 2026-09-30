-- ============================================================
-- Migración 16: Backfill historial de creación para RQs existentes
-- ============================================================
INSERT INTO historial_requerimiento (
    id_requerimiento, tipo, tipo_label, icono,
    descripcion, usuario, fecha, creado_en, creado_por
)
SELECT
    r.id_requerimiento,
    'creacion',
    'Requerimiento creado',
    'add_circle',
    CONCAT('Requerimiento ', r.numero, ' registrado. Estado inicial: Nueva.'),
    CONCAT(u.nombre, ' ', u.apellido),
    r.fecha_creacion,
    NOW(),
    r.id_usuario_creador
FROM requerimiento r
LEFT JOIN usuario u ON u.id_usuario = r.id_usuario_creador
WHERE r.SoftDelete = 0;
