-- ============================================================
-- 11_seed_estado_requerimiento.sql
-- Catálogo de estados para el módulo CRM / Requerimientos
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1) VALUES
-- ESTADO_REQUERIMIENTO (IdMaestro = 66)
(1, 66, 'ESTADO_REQUERIMIENTO', 1, 'Nueva'),
(1, 66, 'ESTADO_REQUERIMIENTO', 2, 'En proceso'),
(1, 66, 'ESTADO_REQUERIMIENTO', 3, 'Con propuesta'),
(1, 66, 'ESTADO_REQUERIMIENTO', 4, 'Cerrado'),
(1, 66, 'ESTADO_REQUERIMIENTO', 5, 'Anulado');
