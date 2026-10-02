namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Datos heredados del requerimiento para iniciar una propuesta (HU-07).</summary>
public record DatosNuevaPropuestaDto(
    long    IdRequerimiento,
    string  NumeroRequerimiento,
    string  EstadoRequerimiento,
    long    IdCliente,
    string  RazonSocial,
    string  Ruc,
    long?   IdSede,
    string? NombreSede,
    long?   IdContacto,
    string? NombreContacto,
    string? CargoContacto,
    int?    IdArea,
    string? AreaLabel,
    int?    IdPrioridad,
    string? PrioridadLabel,
    string  Descripcion,
    /// <summary>Null si el RQ todavía no tiene propuesta.</summary>
    PropuestaExistenteDto? PropuestaExistente
);
