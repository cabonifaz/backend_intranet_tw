-- ============================================================
-- Migración 106 — Flag "requiere duración" en RESULTADO_SEGUIMIENTO (IdMaestro 27)
--   Num2 = 1: hubo conversación efectiva → la llamada exige duración y notas (mín. 5 caracteres).
--   Num2 = 0: sin conversación (No contesta, Buzón, Correo enviado, Pendiente) → duración y notas opcionales.
--   OJO: Num1 es el id del resultado (seguimiento_comercial.id_resultado); no se toca.
--
--   IDEMPOTENTE. Se puede re-ejecutar. Correr en staging, pre-prod y prod.
-- ============================================================

UPDATE tabla_maestra
SET Num2 = IF(String2 IN ('CONTACTADO', 'REUNION_AGENDADA', 'SOLICITA_AJUSTE'), 1, 0)
WHERE IdMaestro = 27 AND IdEmpresa = 1 AND Descripcion = 'RESULTADO_SEGUIMIENTO';

-- Verificación
SELECT Num1 AS id, String1 AS nombre, String2 AS codigo, Num2 AS requiere_duracion,
       IF(IFNULL(Num2, -1) = IF(String2 IN ('CONTACTADO', 'REUNION_AGENDADA', 'SOLICITA_AJUSTE'), 1, 0),
          'OK', 'REVISAR') AS verificacion
FROM tabla_maestra
WHERE IdMaestro = 27 AND IdEmpresa = 1
ORDER BY Num1;
