using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarContactoDto(
    long    IdContacto,
    long    IdCliente,
    long?   IdSede,
    [Required][StringLength(200, MinimumLength = 2)] string  Nombres,
    string? DocumentoIdentidad,
    string? Cargo,
    string? Area,
    [EmailAddress][StringLength(254)] string? Correo,
    [StringLength(20)]                string? TelefonoMovil,
    [StringLength(20)]                string? TelefonoAnexo,
    bool    EsContactoPrincipal,
    bool    AutorizadoAprobarCotizaciones,
    bool    RecibeAlertasCalibracion,
    bool    AutorizadoRecepcionTecnica
);
