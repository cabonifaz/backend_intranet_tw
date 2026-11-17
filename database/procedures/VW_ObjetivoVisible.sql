-- Objetivos VISIBLES de cada OS (os_equipo): una fila (id_os_equipo) por cada equipo que ve el técnico en la lista de objetivos de la app.
-- Misma regla que SP_ArmarObjetivosMovil (si se cambia una, cambiar la otra): se ve si lo registró el técnico en campo (ingresado_en_campo = 1), si la programación
-- vigente de la OS no elige equipos (se trabajan todos) o si está entre los equipos de esa programación.
-- La usan los detalles de la intranet (Avance por equipos, detalle del servicio y contadores del seguimiento) para mostrar los mismos equipos que la app.
-- Es una vista (no una función) porque crear funciones exige el privilegio SUPER cuando el log binario está activo.
CREATE OR REPLACE VIEW vw_objetivo_visible AS
SELECT oe.id AS id_os_equipo
FROM   os_equipo oe
WHERE  oe.ingresado_en_campo = 1
   OR  NOT EXISTS (SELECT 1 FROM programacion_equipo pe
                   WHERE  pe.eliminado_en IS NULL
                     AND  pe.id_programacion = (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                WHERE  pr.id_os = oe.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL))
   OR  EXISTS     (SELECT 1 FROM programacion_equipo pe
                   WHERE  pe.eliminado_en IS NULL AND pe.id_equipo = oe.id_equipo
                     AND  pe.id_programacion = (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                WHERE  pr.id_os = oe.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL));
