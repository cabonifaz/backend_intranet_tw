using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarContactoDto(
    long    IdContacto,
    long    IdCliente,
    long?   IdSede,
    [Required] string  Nombres,
    string? DocumentoIdentidad,
    string? Cargo,
    string? Area,
    string? Correo,
    string? TelefonoMovil,
    string? TelefonoAnexo,
    bool    EsContactoPrincipal,
    bool    AutorizadoAprobarCotizaciones,
    bool    RecibeAlertasCalibracion,
    bool    AutorizadoRecepcionTecnica
);
