-- ============================================================
-- Migración 102 — Asistente IA y Procedimientos (App Mobile HU-19)
--   asistente_consulta ... cada consulta del técnico al asistente: quién, sobre qué equipo, qué preguntó (texto, voz o sugerencia), qué documentos oficiales
--                          se le dieron a la IA, qué respondió y con qué motor, cuánto tardó y si el técnico la valoró (¿te sirvió la respuesta?).
--                          Es también la bitácora de uso del asistente y la base del límite de consultas (10 por minuto y 200 por día por técnico).
--     estado: procesando | respondida | sin_respuesta (la IA no lo encontró en los documentos) | sin_fuentes (el equipo no tiene documentos oficiales) | error_ia
--     creado_en / valorada_en se guardan en UTC (como las evidencias); los SP los devuelven en hora de Lima.
--   asistente_guardado ... copia de una respuesta o de un fragmento citado que el técnico guardó para leer sin conexión (soft delete).
--                          n = 0 para una respuesta; n = número de la fuente para un fragmento.
--   tabla_maestra SUGERENCIA_ASISTENTE ... catálogo editable de "Sugerencias para este equipo" (String1 = texto, String2 = código, String3 = palabra clave
--                          opcional: solo se sugiere a equipos cuyo suministro (tipo, subtipo o descripción) la contenga; vacío = a todos; Num1 = orden).
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS asistente_consulta (
    id_consulta      BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario       BIGINT          NOT NULL,
    id_os            BIGINT          NULL,
    id_os_equipo     BIGINT          NULL,
    id_equipo        BIGINT          NULL,
    pregunta         VARCHAR(500)    NOT NULL,
    origen           VARCHAR(12)     NOT NULL DEFAULT 'texto',
    estado           VARCHAR(20)     NOT NULL DEFAULT 'procesando',
    documentos_json  JSON            NULL,
    respuesta_json   JSON            NULL,
    motor_ia         VARCHAR(60)     NULL,
    duracion_ms      INT             NULL,
    util             TINYINT(1)      NULL,
    valorada_en      DATETIME        NULL,
    creado_en        DATETIME        NOT NULL,
    PRIMARY KEY (id_consulta),
    KEY ix_asistente_consulta_usuario (id_usuario, creado_en),
    KEY ix_asistente_consulta_equipo  (id_os_equipo, id_usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS asistente_guardado (
    id_guardado      BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario       BIGINT          NOT NULL,
    id_consulta      BIGINT          NOT NULL,
    tipo             VARCHAR(12)     NOT NULL,
    n                INT             NOT NULL DEFAULT 0,
    titulo           VARCHAR(200)    NOT NULL,
    subtitulo        VARCHAR(300)    NULL,
    contenido_json   JSON            NOT NULL,
    tamano_bytes     INT             NOT NULL DEFAULT 0,
    creado_en        DATETIME        NOT NULL,
    eliminado_en     DATETIME        NULL,
    eliminado_por    BIGINT          NULL,
    PRIMARY KEY (id_guardado),
    KEY ix_asistente_guardado_usuario  (id_usuario, eliminado_en, creado_en),
    KEY ix_asistente_guardado_consulta (id_consulta, id_usuario, tipo, n)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── Catálogo SUGERENCIA_ASISTENTE (referencia, editable desde el maestro; no son datos de prueba) ──────────────
SET @id_sug := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'SUGERENCIA_ASISTENTE');
SET @id_sug := IFNULL(@id_sug, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_sug, 'SUGERENCIA_ASISTENTE', v.orden, v.texto, v.codigo
FROM (
    SELECT 1 AS orden, 'Ajuste de excentricidad'        AS texto, 'AJUSTE_EXCENTRICIDAD'   AS codigo
    UNION ALL SELECT 2, 'Calibración con pesas',         'CALIBRACION_PESAS'
    UNION ALL SELECT 3, 'Verificación de linealidad',    'VERIFICACION_LINEALIDAD'
    UNION ALL SELECT 4, 'Errores del indicador',         'ERRORES_INDICADOR'
    UNION ALL SELECT 5, 'Reemplazo de celda de carga',   'REEMPLAZO_CELDA'
    UNION ALL SELECT 6, 'Humedad en caja de conexiones', 'HUMEDAD_CAJA_CONEXIONES'
    UNION ALL SELECT 7, 'Mantenimiento preventivo',      'MANTENIMIENTO_PREVENTIVO'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'SUGERENCIA_ASISTENTE' AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 102 (debe ser 9)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('asistente_consulta', 'asistente_guardado'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'SUGERENCIA_ASISTENTE' AND IdEmpresa = 1) AS valor;
