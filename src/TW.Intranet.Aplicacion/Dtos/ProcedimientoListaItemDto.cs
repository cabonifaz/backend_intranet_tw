namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de procedimientos (HU-87). Coincide con ProcedimientoListaItem del front.</summary>
public record ProcedimientoListaItemDto(
    long      IdProcedimiento,
    string    Codigo,
    int       Anio,
    int       Version,
    bool      EsFormatoDigitalIso,
    string    NormaBase,
    string    AutorNorma,
    string    Descripcion,
    string    Estado,
    DateTime? FechaRegistro
);
