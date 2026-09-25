namespace TW.Intranet.Aplicacion.Dtos;

public record RequerimientoFichaDto(
    long      IdRequerimiento,
    string    Numero,
    long      IdCliente,
    string    RazonSocial,
    string    Ruc,
    long?     IdContacto,
    long?     IdSede,
    string?   NombreContacto,
    string?   NombreSede,
    int       IdOrigen,
    string?   OrigenLabel,
    int       IdArea,
    string?   AreaLabel,
    int       IdPrioridad,
    string?   PrioridadLabel,
    DateTime? FechaNecesidad,
    string    Descripcion,
    bool      NotificarCorreo,
    bool      RequiereVisita,
    bool      ClienteDeuda,
    string    Estado,
    string?   EstadoLabel
);
