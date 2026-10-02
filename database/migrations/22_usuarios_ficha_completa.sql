-- ============================================================
-- Migración 22 — HU-82/83/84: ficha completa de usuario,
--   catálogo de roles, sedes operativas y sedes autorizadas
-- (YA EJECUTADA en total_weight_stg el 2026-10-01)
-- ============================================================

-- 1. Columnas nuevas en usuario
ALTER TABLE usuario
    ADD COLUMN tipo_documento                 VARCHAR(20)  NULL,
    ADD COLUMN telefono                       VARCHAR(30)  NULL,
    ADD COLUMN cargo                          VARCHAR(150) NULL,
    ADD COLUMN area_comercial                 VARCHAR(100) NULL,
    ADD COLUMN base_operativa                 VARCHAR(100) NULL,
    ADD COLUMN id_supervisor                  BIGINT       NULL,
    ADD COLUMN habilitado_firma_inacal        TINYINT(1)   NOT NULL DEFAULT 0,
    ADD COLUMN numero_registro_inacal         VARCHAR(50)  NULL,
    ADD COLUMN fecha_expiracion_certificacion DATE         NULL,
    ADD COLUMN requiere_induccion_sctr        TINYINT(1)   NOT NULL DEFAULT 0,
    ADD COLUMN forzar_cambio_contrasena       TINYINT(1)   NOT NULL DEFAULT 0,
    ADD COLUMN enviar_credenciales_correo     TINYINT(1)   NOT NULL DEFAULT 1,
    ADD COLUMN autenticacion_2fa              TINYINT(1)   NOT NULL DEFAULT 0;

-- 2. Permitir guardar usuarios como borrador
ALTER TABLE usuario
    MODIFY COLUMN estado ENUM('activo','inactivo','suspendido','borrador')
    NOT NULL DEFAULT 'activo';

-- 3. Usuarios existentes: tipo de documento por defecto
UPDATE usuario SET tipo_documento = 'DNI' WHERE tipo_documento IS NULL;

-- 4. Relación usuario ↔ sedes operativas autorizadas
CREATE TABLE IF NOT EXISTS usuario_sede_autorizada (
    id                 BIGINT       NOT NULL AUTO_INCREMENT,
    id_usuario         BIGINT       NOT NULL,
    id_sede_operativa  INT          NOT NULL,
    UsuCre             VARCHAR(100) NULL,
    FchCre             DATETIME     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_usuario_sede (id_usuario, id_sede_operativa)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 5. Catálogo de roles del sistema (IdMaestro 68)
--    String1 = etiqueta, String2 = código (usuario.rol_sistema)
--    Num2    = 1 si es rol comercial (puede ser suplente comercial)
--    Num3    = 1 si es rol de jefatura (puede ser supervisor directo)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2) VALUES
(1, 68, 'ROL_SISTEMA', 1, 0, 1, 'Administrador',       'admin'),
(1, 68, 'ROL_SISTEMA', 2, 0, 1, 'Gerencia',            'gerencia'),
(1, 68, 'ROL_SISTEMA', 3, 1, 1, 'Jefe Comercial',      'jefe_comercial'),
(1, 68, 'ROL_SISTEMA', 4, 1, 0, 'Comercial',           'comercial'),
(1, 68, 'ROL_SISTEMA', 5, 0, 1, 'Jefe de Metrología',  'jefe_metrologia'),
(1, 68, 'ROL_SISTEMA', 6, 0, 0, 'Metrólogo',           'metrologo'),
(1, 68, 'ROL_SISTEMA', 7, 0, 1, 'Jefe de Operaciones', 'jefe_operaciones'),
(1, 68, 'ROL_SISTEMA', 8, 0, 0, 'Operaciones',         'operaciones'),
(1, 68, 'ROL_SISTEMA', 9, 0, 0, 'Desarrollador',       'desarrollador');

-- 6. Catálogo de sedes operativas (IdMaestro 69)
--    String1 = nombre, String2 = ubicación, String3 = tipo
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3) VALUES
(1, 69, 'SEDE_OPERATIVA', 1, 'Sede Central Lima',           'Lima',      'Oficina'),
(1, 69, 'SEDE_OPERATIVA', 2, 'Mina Las Bambas',             'Apurímac',  'Mina'),
(1, 69, 'SEDE_OPERATIVA', 3, 'Mina Antamina',               'Áncash',    'Mina'),
(1, 69, 'SEDE_OPERATIVA', 4, 'Mina Cerro Verde',            'Arequipa',  'Mina'),
(1, 69, 'SEDE_OPERATIVA', 5, 'Mina Yanacocha',              'Cajamarca', 'Mina'),
(1, 69, 'SEDE_OPERATIVA', 6, 'Mina Toquepala',              'Tacna',     'Mina'),
(1, 69, 'SEDE_OPERATIVA', 7, 'Mina Constancia',             'Cusco',     'Mina'),
(1, 69, 'SEDE_OPERATIVA', 8, 'Planta Concentradora Callao', 'Callao',    'Planta');
