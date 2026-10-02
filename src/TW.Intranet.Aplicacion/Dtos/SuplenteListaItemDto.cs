namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Asignación de suplencia (HU-82/84). Coincide con SuplenteListaItem del front.</summary>
public record SuplenteListaItemDto(
    long      IdAsignacion,
    long      IdTitular,
    string    TitularNombre,
    string    TitularApellido,
    string?   TitularCargo,
    long      IdSuplente,
    string    SuplenteNombre,
    string    SuplenteApellido,
    string?   SuplenteCargo,
    string    FechaInicio,
    string?   FechaFin,
    string    Estado,
    DateTime? FechaCreacion
);
