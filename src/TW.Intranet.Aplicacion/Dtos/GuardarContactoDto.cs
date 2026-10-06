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
    bool    AutorizadoRecepcionTecnica,
    /// <summary>Sedes vinculadas (mínimo una). Null = se usa IdSede (compatibilidad).</summary>
    List<ContactoSedeDto>? Sedes = null,
    /// <summary>Principal de la empresa (solo uno por cliente). Si viene, reemplaza a EsContactoPrincipal.</summary>
    bool? EsPrincipalEmpresa = null
);

/// <summary>Vínculo contacto ↔ sede, con contacto principal por sede.</summary>
public record ContactoSedeDto(long IdSede, string? NombreSede = null, bool EsPrincipalSede = false);
