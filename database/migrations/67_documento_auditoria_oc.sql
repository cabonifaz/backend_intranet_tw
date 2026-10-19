-- ============================================================
-- Migración 67 — HU-25 Gestión de Documento y Auditoría de OC
--   1. Catálogo TIPO_DOCUMENTO_ADJUNTO (tipo 1 = Orden de compra) para documento_adjunto
--   2. Versiones del PDF de la OC en documento_adjunto (entidad_tipo = 'orden_compra'):
--      metadatos JSON con motivo, tamano_bytes y hash. Se cargan como v1 los PDF de las OC ya
--      registradas que aún no tengan versiones ("Versión inicial").
--   3. Acción oc_documento_reemplazar (nivel 2, módulo propuestas): asistente, jefe y admin comercial
--
--   Las versiones y la auditoría son de solo inserción: ningún SP las modifica ni las borra.
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Catálogo de tipos de documento adjunto (el IdMaestro se reserva al crear la primera fila)
SET @id_tipo_doc := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_DOCUMENTO_ADJUNTO');
SET @id_tipo_doc := IFNULL(@id_tipo_doc, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_tipo_doc, 'TIPO_DOCUMENTO_ADJUNTO', 1, 'Orden de compra (PDF)', 'ORDEN_COMPRA'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'TIPO_DOCUMENTO_ADJUNTO' AND String2 = 'ORDEN_COMPRA');

-- 2. v1 de los PDF ya registrados
INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                               version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
SELECT 'orden_compra', oc.id_oc, 1,
       LEFT(COALESCE(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')), 200),
       oc.url_archivo_pdf, 1, 1,
       JSON_OBJECT('motivo', 'Versión inicial', 'tamano_bytes', oc.tamano_pdf_bytes, 'hash', oc.hash_pdf),
       IFNULL(oc.creado_por, 0), oc.fecha_registro, oc.creado_por
FROM orden_compra oc
WHERE oc.url_archivo_pdf IS NOT NULL AND oc.eliminado_en IS NULL
  AND NOT EXISTS (SELECT 1 FROM documento_adjunto d
                  WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = oc.id_oc AND d.eliminado_en IS NULL);

-- 3. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Reemplazar el PDF de la orden de compra', 'oc_documento_reemplazar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_documento_reemplazar');
