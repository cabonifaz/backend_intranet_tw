-- ============================================================
-- 10_seed_catalogos_requerimiento.sql
-- Catálogos para el módulo CRM / Requerimientos
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1) VALUES
-- ORIGEN_REQUERIMIENTO (IdMaestro = 63)
(1, 63, 'ORIGEN_REQUERIMIENTO', 1, 'Llamada telefónica'),
(1, 63, 'ORIGEN_REQUERIMIENTO', 2, 'Correo electrónico'),
(1, 63, 'ORIGEN_REQUERIMIENTO', 3, 'WhatsApp'),
(1, 63, 'ORIGEN_REQUERIMIENTO', 4, 'Visita presencial'),
(1, 63, 'ORIGEN_REQUERIMIENTO', 5, 'Plataforma extranet'),
-- AREA_REQUERIMIENTO (IdMaestro = 64)
(1, 64, 'AREA_REQUERIMIENTO', 1, 'Calibración'),
(1, 64, 'AREA_REQUERIMIENTO', 2, 'Mantenimiento'),
(1, 64, 'AREA_REQUERIMIENTO', 3, 'Metrología'),
(1, 64, 'AREA_REQUERIMIENTO', 4, 'Soporte técnico'),
(1, 64, 'AREA_REQUERIMIENTO', 5, 'Instalación'),
-- PRIORIDAD_REQUERIMIENTO (IdMaestro = 65)
(1, 65, 'PRIORIDAD_REQUERIMIENTO', 1, 'Alta'),
(1, 65, 'PRIORIDAD_REQUERIMIENTO', 2, 'Media'),
(1, 65, 'PRIORIDAD_REQUERIMIENTO', 3, 'Baja');
