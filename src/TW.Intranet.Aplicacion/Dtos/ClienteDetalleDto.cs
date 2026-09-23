namespace TW.Intranet.Aplicacion.Dtos;

public record ClienteDetalleDto(
    long     IdCliente,
    string   TipoDocumento,
    string   Ruc,
    string   TipoCliente,
    string   RazonSocial,
    string?  NombreComercial,
    string   CondicionFiscal,
    string   CondicionContribuyente,
    string?  CondicionPago,
    decimal? LineaCreditoUsd,
    string?  TelefonoCentral,
    string?  DomicilioFiscal,
    bool     EsVip,
    string?  ReglaVip,
    decimal? DescuentoVipPct,
    string?  PatronMasasAsignado,
    bool     SsomaPolizaSctr,
    bool     SsomaCamioneta4x4,
    bool     SsomaInduccionSsoma,
    bool     SsomaExamenMedico,
    string?  SsomaNotas,
    string   Estado
);
