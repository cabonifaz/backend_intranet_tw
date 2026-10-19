-- ============================================================
-- Migración 41 — #4301 Roles y permisos 100 % configurables desde la BD
--                + estado operativo de equipos con 3 estados (#4300)
--
--   PERMISOS (todo se edita con UPDATE/INSERT, sin tocar código):
--     tabla_maestra 68 ROL_SISTEMA ..... roles (ya existe)
--     tabla_maestra 79 AREA_USUARIO .... áreas (ya existe)
--     tabla_maestra 85 MODULO_SISTEMA .. vistas / módulos (ya existe)
--     tabla_maestra 88 ACCION_SISTEMA .. acciones: String2 = código, String3 = módulo,
--                                        Num1 = nivel exigido (1 ver, 2 editar, 3 supervisar, 4 administrar)
--     permiso_area_rol ................. matriz COMPLETA área × rol × módulo → acceso.
--                                        Sin fila = sin acceso. Ya no hay regla fija en el código.
--
--   Reglas de TW cargadas como datos (reunión y notas del 07-oct):
--     · Maestros: solo el rol Administrador.
--     · Servicio Técnico no accede al CRM.
--     · Comercial no anula un RQ con propuesta: solo el jefe comercial (acción rq_anular_con_propuesta).
--     · Excepción #4299: Servicio Técnico y Metrología guardan equipos del cliente (revisar / bloquear).
--
--   ESTADO OPERATIVO: solo 3 estados (oficina_tw, evaluacion, ejecucion). Sin movimiento = NULL.
--   IDEMPOTENTE. Las filas que ya existan en la matriz NO se pisan (se respetan cambios manuales).
-- ============================================================

-- ── 1. Acciones del sistema (catálogo 88) ────────────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', a.nivel, a.etiqueta, a.codigo, a.modulo
FROM (
          SELECT 1 AS nivel, 'Ver dashboard'                         AS etiqueta, 'dashboard_ver'            AS codigo, 'dashboard'               AS modulo
UNION ALL SELECT 1, 'Ver requerimientos',                      'rq_ver',                   'requerimientos'
UNION ALL SELECT 2, 'Crear / editar requerimiento',            'rq_guardar',               'requerimientos'
UNION ALL SELECT 2, 'Anular requerimiento propio (sin propuesta)', 'rq_anular',            'requerimientos'
UNION ALL SELECT 3, 'Anular requerimiento con propuesta',      'rq_anular_con_propuesta',  'requerimientos'
UNION ALL SELECT 1, 'Ver propuestas',                          'propuesta_ver',            'propuestas'
UNION ALL SELECT 2, 'Crear / editar propuesta',                'propuesta_guardar',        'propuestas'
UNION ALL SELECT 2, 'Crear nueva versión de propuesta',        'propuesta_nueva_version',  'propuestas'
UNION ALL SELECT 2, 'Agregar condición de pago',               'catalogo_condicion_pago',  'propuestas'
UNION ALL SELECT 1, 'Ver usuarios y suplencias',               'usuario_ver',              'maestro_usuarios'
UNION ALL SELECT 2, 'Crear / editar usuario',                  'usuario_guardar',          'maestro_usuarios'
UNION ALL SELECT 3, 'Activar / desactivar usuario',            'usuario_cambiar_estado',   'maestro_usuarios'
UNION ALL SELECT 2, 'Gestionar suplencias',                    'suplencia_guardar',        'maestro_usuarios'
UNION ALL SELECT 2, 'Crear / renombrar área de usuario',       'catalogo_area_usuario',    'maestro_usuarios'
UNION ALL SELECT 2, 'Crear / editar cliente, sede o contacto', 'cliente_guardar',          'maestro_clientes'
UNION ALL SELECT 3, 'Activar / desactivar cliente, sede o contacto', 'cliente_cambiar_estado', 'maestro_clientes'
UNION ALL SELECT 3, 'Gestionar categorías de cliente',         'categoria_guardar',        'maestro_clientes'
UNION ALL SELECT 2, 'Gestionar áreas y requisitos del cliente','cliente_areas_requisitos', 'maestro_clientes'
UNION ALL SELECT 2, 'Crear / editar suministro',               'suministro_guardar',       'maestro_suministros'
UNION ALL SELECT 3, 'Activar / desactivar suministro',         'suministro_cambiar_estado','maestro_suministros'
UNION ALL SELECT 2, 'Agregar tipo, subtipo, marca o modelo',   'catalogo_suministro',      'maestro_suministros'
UNION ALL SELECT 2, 'Crear / editar texto base',               'texto_base_guardar',       'maestro_textos_base'
UNION ALL SELECT 3, 'Activar / desactivar texto base',         'texto_base_cambiar_estado','maestro_textos_base'
UNION ALL SELECT 2, 'Crear / editar procedimiento',            'procedimiento_guardar',    'maestro_procedimientos'
UNION ALL SELECT 3, 'Activar / desactivar procedimiento',      'procedimiento_cambiar_estado','maestro_procedimientos'
UNION ALL SELECT 2, 'Guardar equipo del cliente',              'equipo_guardar',           'maestro_equipos_cliente'
UNION ALL SELECT 3, 'Activar / desactivar equipo',             'equipo_cambiar_estado',    'maestro_equipos_cliente'
UNION ALL SELECT 2, 'Marcar equipo como revisado (placa)',     'equipo_revisar',           'equipos_activos'
UNION ALL SELECT 3, 'Bloquear datos del equipo para certificación', 'equipo_bloquear',     'metrologia'
UNION ALL SELECT 2, 'Editar códigos de formato por ventana',   'formato_ventana_guardar',  'configuracion'
UNION ALL SELECT 2, 'Agregar valores a otros catálogos',       'catalogo_otro',            'configuracion'
UNION ALL SELECT 1, 'Ver matriz de permisos',                  'permisos_ver',             'configuracion'
UNION ALL SELECT 4, 'Modificar permisos',                      'permisos_guardar',         'configuracion'
) a
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 88 AND x.IdEmpresa = 1 AND x.String2 = a.codigo);

-- ── 2. Matriz completa área × rol × módulo ───────────────────────────────
-- Nivel por rol dentro de su propia área.
--   administrador = administrar · supervisor = supervisar · usuario = editar · visor = ver
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod)
SELECT ar.String2, r.String2, m.String2,
       CASE
           -- Administradores de Gerencia y TI: todo
           WHEN r.String2 = 'administrador' AND ar.String2 IN ('gerencia', 'ti') THEN 'administrar'
           -- Maestros: solo el rol Administrador (de cualquier área)
           WHEN m.String2 LIKE 'maestro\_%' THEN IF(r.String2 = 'administrador', 'administrar', 'ninguno')
           -- Dashboard: todos lo ven
           WHEN m.String3 = '*' THEN IF(r.String2 = 'administrador', 'administrar', 'ver')
           -- Módulos de su propia área
           WHEN m.String3 = ar.String2 THEN
               CASE r.String2 WHEN 'administrador' THEN 'administrar' WHEN 'supervisor' THEN 'supervisar'
                              WHEN 'usuario' THEN 'editar' ELSE 'ver' END
           ELSE 'ninguno'
       END AS acceso,
       'migracion_41', NOW()
FROM tabla_maestra ar
CROSS JOIN tabla_maestra r
CROSS JOIN tabla_maestra m
WHERE ar.IdMaestro = 79 AND ar.IdEmpresa = 1
  AND r.IdMaestro  = 68 AND r.IdEmpresa  = 1
  AND m.IdMaestro  = 85 AND m.IdEmpresa  = 1
HAVING acceso <> 'ninguno';

-- Excepciones entre áreas (cargadas como datos: se pueden quitar o cambiar)
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod) VALUES
-- El metrólogo consulta informes y fotos de Servicio Técnico (reunión 02-oct)
('metrologia',       'usuario',    'servicio_tecnico',        'ver',    'migracion_41', NOW()),
('metrologia',       'supervisor', 'servicio_tecnico',        'ver',    'migracion_41', NOW()),
-- #4299: Metrología revisa equipos (placa) igual que Servicio Técnico
('metrologia',       'usuario',    'equipos_activos',         'editar', 'migracion_41', NOW()),
('metrologia',       'supervisor', 'equipos_activos',         'editar', 'migracion_41', NOW()),
-- #4299: Servicio Técnico y Metrología guardan la ficha del equipo (excepción a "Maestros solo administrador")
('servicio_tecnico', 'usuario',    'maestro_equipos_cliente', 'editar', 'migracion_41', NOW()),
('servicio_tecnico', 'supervisor', 'maestro_equipos_cliente', 'editar', 'migracion_41', NOW()),
('metrologia',       'usuario',    'maestro_equipos_cliente', 'editar', 'migracion_41', NOW()),
('metrologia',       'supervisor', 'maestro_equipos_cliente', 'editar', 'migracion_41', NOW());

-- La migración 40 dio 'supervisar' al administrador de Metrología: con la nueva regla tiene 'administrar'
UPDATE permiso_area_rol SET acceso = 'administrar', UsuMod = 'migracion_41', FchMod = NOW()
WHERE area = 'metrologia' AND rol = 'administrador' AND modulo = 'maestro_equipos_cliente' AND UsuMod = 'migracion_40';

-- ── 3. Estado operativo: solo 3 estados (#4300) ─────────────────────────
--   oficina_tw  : el equipo tiene un control de ingreso (CIE)
--   evaluacion  : tiene una evaluación pendiente
--   ejecucion   : tiene una orden de servicio / mantenimiento (OS u OM)
--   Sin ninguno de los tres → NULL ("sin movimiento")
UPDATE equipo_cliente SET estado_operativo = NULL WHERE estado_operativo = 'operativo_planta';
DELETE FROM tabla_maestra WHERE IdMaestro = 83 AND IdEmpresa = 1 AND String2 = 'operativo_planta';
UPDATE tabla_maestra SET String1 = 'En oficina'    WHERE IdMaestro = 83 AND IdEmpresa = 1 AND String2 = 'oficina_tw';
UPDATE tabla_maestra SET String1 = 'En evaluación' WHERE IdMaestro = 83 AND IdEmpresa = 1 AND String2 = 'evaluacion';
UPDATE tabla_maestra SET String1 = 'En ejecución'  WHERE IdMaestro = 83 AND IdEmpresa = 1 AND String2 = 'ejecucion';

SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente'
                       AND COLUMN_NAME = 'estado_operativo' AND IS_NULLABLE = 'NO'),
    'ALTER TABLE equipo_cliente MODIFY COLUMN estado_operativo VARCHAR(40) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
