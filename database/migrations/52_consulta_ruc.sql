-- ============================================================
-- Migración 52 — Consulta de RUC por API externa (OpenRUC)
--   Reemplaza la idea de consultar SUNAT directo. El back consulta
--   https://openruc.com/api/ruc/{ruc} (gratis, sin API key, solo RUC 20)
--   y guarda el resultado en una caché para no repetir llamadas.
--
--   consulta_ruc      = última respuesta válida por RUC (caché, 1 fila por RUC,
--                       el SP controla el duplicado)
--   consulta_ruc_log  = cada llamada a un proveedor externo (para medir
--                       consumo mensual, errores y límites 429)
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

CREATE TABLE IF NOT EXISTS consulta_ruc (
    id_consulta_ruc BIGINT       NOT NULL AUTO_INCREMENT,
    ruc             CHAR(11)     NOT NULL,
    razon_social    VARCHAR(300) NOT NULL,
    estado          VARCHAR(40)  NULL,
    condicion       VARCHAR(40)  NULL,
    direccion       VARCHAR(500) NULL,
    ubigeo          CHAR(6)      NULL,
    fuente          VARCHAR(40)  NULL,
    fecha_dato      DATE         NULL,
    proveedor       VARCHAR(40)  NOT NULL,
    consultado_en   DATETIME     NOT NULL,
    SoftDelete      TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre          VARCHAR(100) NULL,
    FchCre          DATETIME     NULL,
    UsuMod          VARCHAR(100) NULL,
    FchMod          DATETIME     NULL,
    PRIMARY KEY (id_consulta_ruc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS consulta_ruc_log (
    id_consulta_ruc_log BIGINT       NOT NULL AUTO_INCREMENT,
    ruc                 CHAR(11)     NOT NULL,
    proveedor           VARCHAR(40)  NOT NULL,
    resultado           VARCHAR(20)  NOT NULL,   -- encontrado | no_encontrado | limite | error
    codigo_http         INT          NULL,
    detalle             VARCHAR(500) NULL,
    duracion_ms         INT          NULL,
    id_usuario          BIGINT       NULL,
    SoftDelete          TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre              VARCHAR(100) NULL,
    FchCre              DATETIME     NULL,
    UsuMod              VARCHAR(100) NULL,
    FchMod              DATETIME     NULL,
    PRIMARY KEY (id_consulta_ruc_log)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Acción para el endpoint de consumo (solo administración).
-- La consulta en sí usa la acción existente cliente_guardar.
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 4, 'Ver consumo de la consulta de RUC', 'consulta_ruc_uso', 'maestro_clientes'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra
                  WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'consulta_ruc_uso');
