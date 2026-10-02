using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarClienteDto(
    long     IdCliente,
    [Required]                                   string   TipoDocumento,
    [Required][StringLength(11, MinimumLength = 11)] string   Ruc,
    [Required]                                   string   TipoCliente,
    [Required][StringLength(300)]                string   RazonSocial,
    [StringLength(300)]                          string?  NombreComercial,
    [Required]                                   string   CondicionFiscal,
    [Required]                                   string   CondicionContribuyente,
    string?  CondicionPago,
    [Range(0, double.MaxValue)] decimal? LineaCreditoUsd,
    [StringLength(30)]          string?  TelefonoCentral,
    [StringLength(500)]         string?  DomicilioFiscal,
    bool     EsVip,
    string?  ReglaVip,
    [Range(0, 100)] decimal? DescuentoVipPct,
    string?  PatronMasasAsignado,
    bool     SsomaPolizaSctr,
    bool     SsomaCamioneta4x4,
    bool     SsomaInduccionSsoma,
    bool     SsomaExamenMedico,
    [StringLength(1000)] string?  SsomaNotas,
    int?     IdCategoria
);
