namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarRequerimientoComandoDto(
    long      IdRequerimiento,
    long      IdCliente,
    long?     IdSede,
    long?     IdContacto,
    int       IdOrigen,
    int       IdArea,
    int       IdPrioridad,
    DateTime? FechaNecesidad,
    string    Descripcion,
    bool      NotificarCorreo,
    bool      RequiereVisita,
    bool      ClienteDeuda
);
