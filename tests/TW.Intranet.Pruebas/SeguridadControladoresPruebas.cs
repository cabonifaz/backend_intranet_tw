using System.Reflection;
using TW.Intranet.API.Controllers;
using TW.Intranet.API.Seguridad;

namespace TW.Intranet.Pruebas;

/// <summary>
/// Pruebas de seguridad de los endpoints nuevos: qué permiso exige cada uno. RequierePermiso con varias acciones deja pasar con CUALQUIERA de ellas,
/// por eso la revisión de gastos debe exigir solo prog_aprobar_reprogramacion (el Asistente de Seguimiento recibe 403).
/// </summary>
public class SeguridadControladoresPruebas
{
    private static string[] Permisos(Type controlador, string metodo) =>
        controlador.GetMethod(metodo, BindingFlags.Public | BindingFlags.Instance)!
            .GetCustomAttribute<RequierePermisoAttribute>()!.Acciones.ToArray();

    [Fact]
    public void Revisar_gasto_desde_el_seguimiento_solo_lo_hace_el_jefe_de_operaciones()
        => Assert.Equal(["prog_aprobar_reprogramacion"], Permisos(typeof(DetalleServicioRutaController), nameof(DetalleServicioRutaController.RevisarGasto)));

    [Theory]
    [InlineData(nameof(DetalleServicioRutaController.Aprobaciones))]
    [InlineData(nameof(DetalleServicioRutaController.ResolverAprobacion))]
    [InlineData(nameof(DetalleServicioRutaController.Viaticos))]
    [InlineData(nameof(DetalleServicioRutaController.ComprobanteGasto))]
    public void Pestanas_del_seguimiento_exigen_seg_bandeja(string metodo)
        => Assert.Equal(["seg_bandeja"], Permisos(typeof(DetalleServicioRutaController), metodo));

    [Fact]
    public void Viaticos_del_informe_exigen_rt_bandeja()
        => Assert.Equal(["rt_bandeja"], Permisos(typeof(RevisionTecnicaController), nameof(RevisionTecnicaController.Viaticos)));
}
