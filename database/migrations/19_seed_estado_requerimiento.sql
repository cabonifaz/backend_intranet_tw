-- ============================================================
-- 19_seed_estado_requerimiento.sql
-- Catálogo de estados del módulo CRM / Requerimientos.
-- IdMaestro = 67
-- Num1 = orden · String1 = label visible · String2 = código BD
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 67, 'ESTADO_REQUERIMIENTO', 1, 'Nueva',         'nuevo'),
(1, 67, 'ESTADO_REQUERIMIENTO', 2, 'En proceso',    'en_proceso'),
(1, 67, 'ESTADO_REQUERIMIENTO', 3, 'Con propuesta', 'con_propuesta'),
(1, 67, 'ESTADO_REQUERIMIENTO', 4, 'Cerrado',       'cerrado'),
(1, 67, 'ESTADO_REQUERIMIENTO', 5, 'Anulado',       'anulado');
