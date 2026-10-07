namespace TW.Intranet.API.Seguridad;

/// <summary>
/// Exige que el usuario pueda ejecutar al menos UNA de las acciones indicadas (ticket #4301).
/// Las acciones están en tabla_maestra (IdMaestro 88, ACCION_SISTEMA): cada una dice a qué módulo
/// pertenece y qué nivel exige. El acceso de cada área + rol está en permiso_area_rol.
/// Todo se configura en la BD; aquí solo se nombra la acción.
/// Acción especial "@catalogo": se resuelve según el catálogo de la ruta ({descripcion}).
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = false)]
public sealed class RequierePermisoAttribute(params string[] acciones) : Attribute
{
    public string[] Acciones { get; } = acciones;
}
