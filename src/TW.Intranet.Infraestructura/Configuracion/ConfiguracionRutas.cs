namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>Servicio de rutas por calles (OSRM). Sección "Rutas" de la configuración; todo es opcional.</summary>
public class ConfiguracionRutas
{
    public string OsrmUrl { get; set; } = "https://router.project-osrm.org";
    /// <summary>OSRM no conoce el tráfico: su tiempo se multiplica por este factor (entre 1 y 3).</summary>
    public double FactorTrafico { get; set; } = 1.3;
}
