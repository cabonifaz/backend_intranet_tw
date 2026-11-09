namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-08 / HU-09 — Trabajo en el equipo y variables ambientales ────────────────────

/// <summary>
/// Cabecera de "Trabajo en el equipo". TipoOrden = OS (servicio técnico) u OM (metrología) según el área de la RQ.
/// PuedeRegistrar = el equipo está en ejecución y el servicio en curso. PuedeFinalizar = las 5 etapas están conformes. Horas de Lima.
/// </summary>
public record CabeceraTrabajoEquipoMovilDto(
    long      IdOs,
    string    NumeroOs,
    string?   Cliente,
    string    TipoOrden,
    string?   NumeroRq,
    string?   ServicioSigla,
    string?   Servicio,
    long      IdOsEquipo,
    string    Nombre,
    string?   NumeroSerie,
    string?   CodigoCliente,
    string?   CodigoTw,
    string?   Marca,
    string?   Modelo,
    string?   Ubicacion,
    string    Estado,
    int?      TiempoEstimadoMin,
    int       TiempoRealMin,
    DateTime? IniciadoEn,
    bool      PuedeRegistrar,
    int       EtapasConformes,
    int       EtapasTotal,
    bool      PuedeFinalizar);

/// <summary>Condiciones ambientales registradas (HU-09). Fecha y hora las pone el servidor (hora de Lima).</summary>
public record VariablesAmbientalesMovilDto(decimal Temperatura, decimal Humedad, string Procedencia, DateTime? RegistradoEn);

/// <summary>
/// Una etapa del trabajo. Codigo: variables | fotos | ensayos | cabecera | correlativo.
/// Estado: conforme | en_curso | pendiente | bloqueado. Disponible = la etapa ya tiene pantalla en la app.
/// </summary>
public record EtapaTrabajoMovilDto(int Orden, string Codigo, string Nombre, string Estado, string? Detalle, bool Disponible);

public record TrabajoEquipoMovilDto(
    CabeceraTrabajoEquipoMovilDto  Cabecera,
    VariablesAmbientalesMovilDto?  Variables,
    List<EtapaTrabajoMovilDto>     Etapas);

/// <summary>Lo que envía la app: temperatura (°C), humedad (%) y procedencia opcional ("N.I" por defecto). CapturadoEn = hora (ISO 8601, UTC) del teléfono.</summary>
public class PeticionVariablesAmbientalesMovilDto
{
    public decimal? Temperatura { get; set; }
    public decimal? Humedad     { get; set; }
    public string?  Procedencia { get; set; }
    public string?  CapturadoEn { get; set; }
}

public record ResultadoVariablesAmbientalesMovilDto(
    decimal TemperaturaC, decimal HumedadPct, string Procedencia, DateTime? RegistradoEn, bool Actualizada, bool Repetida);
