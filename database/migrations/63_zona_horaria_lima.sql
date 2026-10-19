-- ============================================================
-- Migración 63 — Zona horaria de Lima (UTC-5) en el servidor MySQL
--
--   El MySQL de Railway corre en UTC, así que NOW(), CURDATE() y los
--   DEFAULT CURRENT_TIMESTAMP de todos los SP y tablas guardaban la hora
--   5 horas adelantada respecto a Perú (y después de las 19:00 CURDATE()
--   ya devolvía el día siguiente).
--
--   SET PERSIST cambia la zona del servidor y la guarda en mysqld-auto.cnf
--   (en el volumen de datos), así que sobrevive a reinicios del MySQL.
--   Se usa el desfase fijo '-05:00' porque Perú no tiene horario de verano
--   y no depende de que el servidor tenga cargadas las tablas de zonas horarias.
--
--   Requisitos:
--     - Ejecutar con un usuario que tenga SYSTEM_VARIABLES_ADMIN (o SUPER),
--       por ejemplo root del servicio MySQL de Railway.
--     - Afecta a TODO el servidor MySQL (todas sus bases), una sola vez por servidor:
--       staging, pre-prod y producción por separado.
--     - Las conexiones abiertas conservan la zona anterior: reconectar DBeaver
--       y redesplegar el back después de ejecutarlo.
--
--   Los registros ya guardados NO se corrigen (quedan con hora UTC).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

SET PERSIST time_zone = '-05:00';
SET time_zone = '-05:00';

-- Verificación: zona_global y zona_sesion = -05:00, hora_lima = hora de Perú
SELECT @@global.time_zone  AS zona_global,
       @@session.time_zone AS zona_sesion,
       NOW()               AS hora_lima,
       UTC_TIMESTAMP()     AS hora_utc;
