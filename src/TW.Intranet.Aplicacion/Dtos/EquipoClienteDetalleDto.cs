namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fotos del equipo. Upload real pendiente — se devuelven como placeholders vacíos.</summary>
public record FotoEquipoDto(string Tipo, string Label, string Url);

/// <summary>Resumen de OT dentro de la hoja de vida. Mock readonly hasta que exista el módulo de OTs.</summary>
public record OrdenTrabajoResumenDto(string NumeroOt, string Fecha, string Tecnico, string TipoServicio);

/// <summary>Ficha del equipo del cliente (HU-88). Coincide con EquipoClienteDetalle del front.</summary>
public record EquipoClienteDetalleDto(
    // Datos del listado
    long   IdEquipo,
    string NumSerie,
    long   IdCliente,
    string ClienteRazonSocial,
    long   IdSede,
    string SedeNombre,
    string CodigoCliente,
    string CodigoTw,
    string Clasificacion,
    string ClasificacionLabel,
    string Marca,
    string Modelo,
    string Estado,
    bool   EsActivo,

    // 01 — Datos generales y ubicación
    string    UbicacionEspecifica,
    bool      EsPreRevisado,
    string    UsuarioPreRevisor,
    DateTime? FechaPreRevision,
    bool      BloqueadoParaServicios,

    // 02 — Especificaciones metrológicas y técnicas
    long?  IdSuministro,
    string SuministroLabel,
    string DivisionMinima,
    string DivisionVerif,
    bool   DivisionVerifIgual,
    string ClaseExactitud,
    string AlcanceMaximo,
    string EscalaGraduacion,
    string PuntosCalibracion,
    string RangoOperativoReal,
    string Material,
    string ValorNominal,
    string Observaciones,

    // 03 — Estado operativo
    string EstadoOperativo,

    // Sidebar — placeholders hasta que exista upload / módulo OTs
    List<FotoEquipoDto>            Fotos,
    List<OrdenTrabajoResumenDto>   HojaVida,
    string                         ProximaCalibracion,

    // Auditoría
    string    UsuarioRegistro,
    DateTime? FechaRegistro,
    string    PcRegistro,
    DateTime? FechaModificacion
);
