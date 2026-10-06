-- ============================================================
-- Migración 37 — Revertir modelo de áreas del cliente (decisión Jazir 06-oct-2026)
--   La migración 35 cambió áreas del cliente a asignaciones del catálogo
--   global AREA_USUARIO. Esto mezclaba el organigrama corporativo de TW
--   (Comercial, Metrología, SSOMA, etc.) con áreas operativas específicas
--   del cliente ("Zona de carnes", "Patio norte", "Laboratorio C"), que son
--   realidades distintas.
--
--   Esta migración vuelve al modelo de la migración 33:
--     · area_cliente = áreas propias por cliente, con nombres libres,
--       estado activo/inactivo y SoftDelete.
--     · equipo_cliente.ubicacion_especifica = string del nombre del área
--       (al renombrarla, el SP_GuardarAreaCliente la cascade).
--
--   La tabla cliente_area (asignaciones) se elimina. Si tenía datos, se
--   migran creando un area_cliente por cada combinación distinta
--   (id_cliente, area) con el nombre resuelto desde AREA_USUARIO.
--
--   IDEMPOTENTE. Se puede re-ejecutar sin romper nada. Ejecutar junto con
--   SP_GuardarAreaCliente, SP_CambiarEstadoAreaCliente y la versión nueva
--   de SP_ObtenerAreasCliente.
-- ============================================================

-- ── 1. (Re)crear la tabla area_cliente ──────────────────────
CREATE TABLE IF NOT EXISTS area_cliente (
    id_area     BIGINT       NOT NULL AUTO_INCREMENT,
    id_cliente  BIGINT       NOT NULL,
    nombre      VARCHAR(150) NOT NULL,
    estado      ENUM('activo','inactivo') NOT NULL DEFAULT 'activo',
    SoftDelete  TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre      VARCHAR(100) NULL,
    FchCre      DATETIME     NULL,
    UsuMod      VARCHAR(100) NULL,
    FchMod      DATETIME     NULL,
    PRIMARY KEY (id_area),
    UNIQUE KEY ux_area_cliente (id_cliente, nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Migrar datos de cliente_area → area_cliente (si existieran) ──
--      Resuelve el nombre humano usando tabla_maestra AREA_USUARIO (79).
--      Si cliente_area no existe, el bloque no hace nada.
SET @cliente_area_existe := IF(EXISTS (
    SELECT 1 FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cliente_area'), 1, 0);

SET @sql := IF(@cliente_area_existe = 1, '
    INSERT IGNORE INTO area_cliente (id_cliente, nombre, UsuCre, FchCre)
    SELECT ca.id_cliente,
           COALESCE(t.String1, ca.area) AS nombre,
           COALESCE(ca.UsuCre, ''migracion_37'') AS UsuCre,
           COALESCE(ca.FchCre, NOW()) AS FchCre
    FROM cliente_area ca
    LEFT JOIN tabla_maestra t
      ON t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = ca.area
', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Reconstruir ubicacion_especifica de los equipos ──────
--      Los equipos deben apuntar al NOMBRE del área (no al código).
--      Si el campo tenía código (ej. 'comercial'), se resuelve al nombre.
UPDATE equipo_cliente e
JOIN area_cliente a
  ON a.id_cliente = e.id_cliente
LEFT JOIN tabla_maestra t
  ON t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = e.ubicacion_especifica
SET e.ubicacion_especifica = a.nombre
WHERE e.ubicacion_especifica IS NOT NULL
  AND e.ubicacion_especifica <> ''
  AND (a.nombre = e.ubicacion_especifica OR a.nombre = t.String1);

-- ── 4. Eliminar la tabla cliente_area (modelo asignaciones) ──
DROP TABLE IF EXISTS cliente_area;

-- ── 5. Los SPs eliminados por la migración 35 se vuelven a crear
--      ejecutando SP_GuardarAreaCliente.sql y SP_CambiarEstadoAreaCliente.sql
--      por separado (están en /database/procedures/).
--      SP_ObtenerAreasCliente también se re-escribe para leer directamente
--      de area_cliente (sin JOIN con AREA_USUARIO).
--      SP_SincronizarAreasCliente deja de usarse (SP_GuardarCliente ya no
--      debe llamarla — ver issue separado para limpiarlo).
