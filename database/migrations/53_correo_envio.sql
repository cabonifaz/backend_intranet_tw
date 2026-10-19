-- ============================================================
-- Migración 53 — Servicio de correo (Brevo por API HTTPS)
--   correo_envio = registro de cada correo que el sistema intenta enviar
--                  (credenciales de usuario, reenvíos, pruebas). Nunca guarda
--                  la contraseña ni el cuerpo del mensaje.
--   Acción correo_prueba (nivel 4, maestro_usuarios) para el endpoint
--   POST /api/admin/correo/prueba.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

CREATE TABLE IF NOT EXISTS correo_envio (
    id_correo_envio  BIGINT       NOT NULL AUTO_INCREMENT,
    tipo             VARCHAR(40)  NOT NULL,   -- credenciales | reenvio_credenciales | prueba
    destinatario     VARCHAR(200) NOT NULL,
    asunto           VARCHAR(300) NOT NULL,
    entidad_tipo     VARCHAR(40)  NULL,       -- usuario
    id_entidad       BIGINT       NULL,
    proveedor        VARCHAR(40)  NOT NULL,   -- brevo | no_configurado
    estado           VARCHAR(20)  NOT NULL,   -- enviado | error
    id_mensaje       VARCHAR(200) NULL,       -- messageId del proveedor
    error            VARCHAR(500) NULL,
    id_usuario       BIGINT       NULL,       -- quién lo disparó
    SoftDelete       TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre           VARCHAR(100) NULL,
    FchCre           DATETIME     NULL,
    UsuMod           VARCHAR(100) NULL,
    FchMod           DATETIME     NULL,
    PRIMARY KEY (id_correo_envio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 4, 'Enviar correo de prueba del sistema', 'correo_prueba', 'maestro_usuarios'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra
                  WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'correo_prueba');
