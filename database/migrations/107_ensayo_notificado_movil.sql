-- ============================================================
-- Migración 107 — Ensayo con lecturas fuera de EMP y encargado notificado (App Mobile HU-10 / HU-16)
--   informe_tecnico.error_critico_notificado_en: cuándo se avisó al encargado del área (o a los administradores) del ensayo guardado con error crítico
--   ("Guardar de todas formas", SP_GuardarEnsayosMovil). NULL = nadie fue notificado. Con la notificación hecha, el ensayo ya no bloquea el cierre del equipo
--   (SP_ArmarEtapasEquipoMovil: etapa "notificado"): el informe se puede generar y queda registrado como resultado fuera de EMP.
--   Los informes que ya estaban guardados con error crítico toman la fecha de su notificación "Ensayo con error crítico" (la de la OS). No borra datos. IDEMPOTENTE.
-- ============================================================
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_notificado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_notificado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE informe_tecnico it
SET    it.error_critico_notificado_en = (SELECT MAX(n.fecha_creacion) FROM notificacion n
                                         WHERE n.titulo = 'Ensayo con error crítico' AND n.entidad_tipo = 'orden_servicio' AND n.id_entidad = it.id_os AND n.eliminado_en IS NULL)
WHERE  it.error_critico_motivo IS NOT NULL AND it.error_critico_notificado_en IS NULL AND it.eliminado_en IS NULL;
