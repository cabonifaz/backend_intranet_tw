namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>Dirección por coordenadas (Nominatim / OpenStreetMap). Sección "Nominatim" de la configuración; todo es opcional.</summary>
public class ConfiguracionNominatim
{
    /// <summary>false = no se consulta y la dirección sale null (el ubigeo sigue funcionando).</summary>
    public bool Habilitado { get; set; } = true;
    public string Url { get; set; } = "https://nominatim.openstreetmap.org";
    /// <summary>La política de Nominatim pide un User-Agent que identifique la aplicación (se puede añadir un contacto con Nominatim__UserAgent).</summary>
    public string UserAgent { get; set; } = "TW-Intranet/1.0";
    /// <summary>Tiempo máximo de espera, en milisegundos (entre 500 y 5000).</summary>
    public int TiempoMaximoMs { get; set; } = 2000;
}
