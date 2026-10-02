namespace TW.Intranet.Aplicacion.Dtos;

public record ContactoClienteDto(
    long    IdContacto,
    long    IdCliente,
    long?   IdSede,
    string  Nombres,
    string? DocumentoIdentidad,
    string? Cargo,
    string? Area,
    string? Correo,
    string? TelefonoMovil,
    string? TelefonoAnexo,
    bool    EsContactoPrincipal,
    bool    AutorizadoAprobarCotizaciones,
    bool    RecibeAlertasCalibracion,
    bool    AutorizadoRecepcionTecnica,
    string  Estado
);
