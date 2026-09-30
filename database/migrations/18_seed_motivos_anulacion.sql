-- ============================================================
-- Migración 18: Motivos de anulación de requerimiento
-- IdMaestro = 66
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1) VALUES
(1, 66, 'MOTIVO_ANULACION', 1, 'Solicitud duplicada'),
(1, 66, 'MOTIVO_ANULACION', 2, 'Cliente desistió'),
(1, 66, 'MOTIVO_ANULACION', 3, 'Presupuesto no aprobado'),
(1, 66, 'MOTIVO_ANULACION', 4, 'Cambio de prioridades'),
(1, 66, 'MOTIVO_ANULACION', 5, 'Error en el registro'),
(1, 66, 'MOTIVO_ANULACION', 6, 'Servicio no disponible'),
(1, 66, 'MOTIVO_ANULACION', 7, 'Otro');
