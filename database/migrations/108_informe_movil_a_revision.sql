-- Informes técnicos generados desde la app móvil (HU-16) -> bandeja de Revisión Técnica de la intranet (HU-56/57).
-- Los informes ya generados que se quedaron en 'borrador' pasan a 'pendiente_revision' (la fecha de envío es la de generación).
-- Idempotente: solo toca los que están en borrador y ya tienen generado_en.
UPDATE informe_tecnico
SET    estado = 'pendiente_revision',
       fecha_envio_revision = COALESCE(fecha_envio_revision, CONVERT_TZ(generado_en, '+00:00', '-05:00'), NOW())
WHERE  estado = 'borrador' AND generado_en IS NOT NULL AND eliminado_en IS NULL;
