namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-07 — Lista de objetivos y selección de equipos ───────────────────────────────

/// <summary>Una modificación del equipo (campo, valor anterior y actual): viene del historial del equipo y de los cambios de estado hechos desde la app.</summary>
public record CambioEquipoMovilDto(DateTime? Fecha, string Campo, string? ValorAnterior, string? ValorNuevo, string? Detalle, string? Usuario);

/// <summary>
/// Un objetivo de la OS = un equipo a intervenir. Estado: por_iniciar | en_ejecucion | pausado | completado | observado.
/// PuedeIniciar / PuedePausar / PuedeReanudar los decide el SP (la app solo habilita los botones). Bloqueado = no se puede seleccionar.
/// FaltaEquipo = el objetivo no tiene N/S ("FALTA EQUIPO/INSTRUMENTO"). EnCampo = lo registró el técnico como equipo nuevo (NEW).
/// RequiereAprobacion = pausa que espera a un supervisor: no se puede reanudar. Las horas son de Lima.
/// </summary>
public record ObjetivoEquipoMovilDto(
    long      IdOsEquipo,
    long      IdEquipo,
    int       Numero,
    string?   TipoIntervencion,
    string?   TipoCorto,
    string    Nombre,
    string?   CodigoTw,
    string?   CodigoCliente,
    string?   Marca,
    string?   Modelo,
    string?   NumeroSerie,
    string?   Ubicacion,
    string?   EstadoEquipo,
    bool      Bloqueado,
    bool      EnCampo,
    bool      FaltaEquipo,
    string    Estado,
    int?      TiempoEstimadoMin,
    int       TiempoRealMin,
    DateTime? IniciadoEn,
    string?   MotivoPausa,
    bool      RequiereAprobacion,
    string?   UltimaIntervencion,
    string?   UltimaParte,
    int       AlertasPendientes,
    bool      PuedeIniciar,
    bool      PuedePausar,
    bool      PuedeReanudar,
    List<CambioEquipoMovilDto> Cambios);

/// <summary>Encabezado de "Objetivos de hoy": cliente, sede y los tiempos del técnico (llegada, traslado, en planta, estimado). Horas de Lima.</summary>
public record ResumenObjetivosMovilDto(
    long      IdOs,
    string    NumeroOs,
    string    EstadoOs,
    string?   Cliente,
    string?   Sede,
    bool      LlegadaRegistrada,
    DateTime? SalidaEn,
    DateTime? LlegadaEn,
    int?      TrasladoMin,
    int       EnPlantaMin,
    int       EstimadoMin);

/// <summary>Contadores de TODOS los objetivos (aunque la lista esté filtrada por una búsqueda).</summary>
public record ContadoresObjetivosMovilDto(int Completados, int Pendientes, int Observados, int Total);

public record ObjetivosMovilDto(
    ResumenObjetivosMovilDto     Resumen,
    ContadoresObjetivosMovilDto  Contadores,
    List<ObjetivoEquipoMovilDto> Equipos);

/// <summary>Lo que envía la app al iniciar, pausar o reanudar. Motivo es obligatorio al pausar. CapturadoEn = hora (ISO 8601, UTC) en que el técnico tocó el botón.</summary>
public class PeticionCambioEstadoEquipoMovilDto
{
    public string? Motivo      { get; set; }
    public string? CapturadoEn { get; set; }
}

/// <summary>Resultado del cambio de estado. Repetida = ya estaba en ese estado (reintento). Diferida = se guardó sin conexión y llegó después.</summary>
public record ResultadoCambioEstadoEquipoMovilDto(long IdOsEquipo, string Accion, string Estado, bool Repetida, bool Diferida);

/// <summary>Tipo de equipo del formulario "Equipo nuevo": un suministro activo de clase equipo / instrumento / pesa.</summary>
public record TipoEquipoNuevoMovilDto(long IdSuministro, string Descripcion, string Clase, string? Marca, string? Modelo);

/// <summary>Listas del formulario "Equipo nuevo": marcas (catálogo MARCA_SUMINISTRO) y tipos de equipo.</summary>
public record OpcionesEquipoNuevoMovilDto(List<string> Marcas, List<TipoEquipoNuevoMovilDto> Tipos);

/// <summary>Datos del equipo nuevo que registra el técnico (la foto de la placa va aparte, solo cámara).</summary>
public record NuevoEquipoMovilDto(
    string? NumeroSerie, string? Codigo, string? Marca, string? Modelo, long IdSuministro, string? Ubicacion);

/// <summary>
/// Equipo registrado en campo. CodigoTw es PROVISIONAL (NEW-…): la intranet asigna el definitivo al aprobar el registro.
/// YaExistia = ya estaba en el maestro del cliente (no se duplicó, se agregó a la O/S). YaRegistrado = reintento: ya lo había registrado este técnico.
/// FotoGuardada = el equipo se creó con la foto enviada (si no, el back la borra).
/// </summary>
public record ResultadoEquipoNuevoMovilDto(
    long IdOsEquipo, long IdEquipo, string CodigoTw, bool YaExistia, bool YaRegistrado, bool FotoGuardada, int Notificados);
