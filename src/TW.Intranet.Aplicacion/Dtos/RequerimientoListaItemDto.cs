namespace TW.Intranet.Aplicacion.Dtos;

public record RequerimientoListaItemDto(
    long     IdRequerimiento,
    string   Numero,
    string   RazonSocial,
    string   Ruc,
    string?  NombreSede,
    string?  NombreContacto,
    string?  TipoLabel,
    string?  OrigenLabel,
    string?  PrioridadLabel,
    int      IdPrioridad,
    string?  Responsable,
    DateTime FechaCreacion,
    string   Estado,
    string?  EstadoLabel
);
