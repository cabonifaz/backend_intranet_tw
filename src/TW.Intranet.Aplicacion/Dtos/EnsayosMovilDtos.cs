namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-10 — Ensayos y Calibración (pesaje y excentricidad) ──────────────────────────

/// <summary>
/// Cabecera de los ensayos. Evaluable = el equipo tiene clase de exactitud y e (sin eso no hay EMP).
/// FormaPlato: rectangular | circular | triangular. AceptaError = el técnico guardó "de todas formas" con un motivo.
/// </summary>
public record CabeceraEnsayosMovilDto(
    long      IdOs,
    long      IdOsEquipo,
    string    NumeroOs,
    string    Nombre,
    int       Numero,
    string    Unidad,
    string?   Clase,
    decimal?  CapMaxima,
    decimal?  D,
    decimal?  E,
    bool      Evaluable,
    string    FormaPlato,
    string?   MotivoErrorCritico,
    bool      AceptaError,
    bool      Finalizado,
    DateTime? FinalizadoEn,
    bool      PuedeRegistrar,
    string?   AreaEncargado);

/// <summary>Lectura de pesaje: carga L e indicación I las digita el técnico; Error, Emp y Resultado (conforme | no_conforme) los calcula el servidor.</summary>
public record LecturaPesajeMovilDto(int Orden, decimal Carga, decimal? Indicacion, decimal? Error, decimal? Emp, string? Resultado, bool Critico);

/// <summary>Lectura de excentricidad: Grupo = número de la carga de prueba; Posicion 1 = centro.</summary>
public record LecturaExcentricidadMovilDto(int Grupo, int Posicion, decimal Carga, decimal? Indicacion, decimal? Error, decimal? Emp, string? Resultado, bool Critico);

/// <summary>Encargado del área responsable de la OS según la RQ (a quien llamar ante un error crítico).</summary>
public record EncargadoEnsayoMovilDto(long IdUsuario, string Nombre, string? Cargo, string? Telefono, string? Area);

public record EnsayosMovilDto(
    CabeceraEnsayosMovilDto             Cabecera,
    List<LecturaPesajeMovilDto>         Pesaje,
    List<LecturaExcentricidadMovilDto>  Excentricidad,
    EncargadoEnsayoMovilDto?            Encargado);

public class CargaPesajeEnvioDto
{
    public decimal? Carga      { get; set; }
    public decimal? Indicacion { get; set; }
}

public class CargaExcentricidadEnvioDto
{
    public decimal?        Carga    { get; set; }
    /// <summary>Indicaciones por posición (la 1 es el centro); null = aún sin leer.</summary>
    public List<decimal?>? Lecturas { get; set; }
}

/// <summary>Lo que envía la app al guardar: solo L e I. MotivoErrorCritico = "Guardar de todas formas". Finalizar = cierra la etapa.</summary>
public class GuardarEnsayosMovilDto
{
    public string?                          FormaPlato          { get; set; }
    public List<CargaPesajeEnvioDto>?        Pesaje              { get; set; }
    public List<CargaExcentricidadEnvioDto>? Excentricidad       { get; set; }
    public string?                          MotivoErrorCritico  { get; set; }
    public bool                             Finalizar           { get; set; }
}

public record ResultadoGuardarEnsayosMovilDto(long IdInforme, int Criticos, bool Finalizado, int Notificados);

public class PeticionLlamadaEnsayoMovilDto
{
    public string? Detalle { get; set; }
}

public record ResultadoLlamadaEnsayoMovilDto(string Nombre, string? Cargo, string Telefono, string? Area);
