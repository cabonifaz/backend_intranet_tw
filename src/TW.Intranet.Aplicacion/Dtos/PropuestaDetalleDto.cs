namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Propuesta completa (GET /api/crm/propuestas/{id}).</summary>
public class PropuestaDetalleDto
{
    public long    IdPropuesta         { get; set; }
    public string  Numero              { get; set; } = "";
    public int     Version             { get; set; }
    public string  Estado              { get; set; } = "";
    public long?   IdPropuestaPadre    { get; set; }
    /// <summary>true solo en "borrador". Si es false, la pantalla debe quedar en solo lectura.</summary>
    public bool    EsEditable          { get; set; }

    public long    IdRequerimiento     { get; set; }
    public string  NumeroRequerimiento { get; set; } = "";
    public long    IdCliente           { get; set; }
    public string  RazonSocial         { get; set; } = "";
    public string  Ruc                 { get; set; } = "";
    public long?   IdSede              { get; set; }
    public string? NombreSede          { get; set; }
    public long?   IdContacto          { get; set; }
    public string? NombreContacto      { get; set; }
    public string? CargoContacto       { get; set; }
    public long?   IdResponsable       { get; set; }
    public string? NombreResponsable   { get; set; }

    public string?      TipoServicio     { get; set; }
    public string?      Referencia       { get; set; }
    public string?      Introduccion     { get; set; }
    public string?      NotasGenerales   { get; set; }
    public List<string> SeccionesActivas { get; set; } = new();

    public bool    EsTercerizado      { get; set; }
    public string? TerceroRuc         { get; set; }
    public string? TerceroRazonSocial { get; set; }
    public string? TerceroDireccion   { get; set; }

    public int      IdMoneda              { get; set; }
    public string?  Moneda                { get; set; }
    public string?  MonedaSimbolo         { get; set; }
    public decimal? TipoCambio            { get; set; }
    public int?     GarantiaMeses         { get; set; }
    public bool     MostrarGarantia       { get; set; }
    public int?     PlazoEntregaDias      { get; set; }
    public string?  PlazoEntregaUnidad    { get; set; }
    public string?  PlazoEntregaCondicion { get; set; }
    public int?     VigenciaDias          { get; set; }
    public bool     AplicaIgv             { get; set; }
    public bool     PreciosIncluyenIgv    { get; set; }
    public decimal  IgvPct                { get; set; }

    // Totales (calculados por el back)
    public decimal  Subtotal            { get; set; }
    public decimal? DescuentoPct        { get; set; }
    public decimal  DescuentoMonto      { get; set; }
    public int?     IdMotivoDescuento   { get; set; }
    public decimal  IgvMonto            { get; set; }
    public decimal  Total               { get; set; }
    public decimal  SubtotalOpcionales  { get; set; }
    public decimal  DescuentoOpcionales { get; set; }
    public decimal  TotalOpcionales     { get; set; }

    public string?   NombreCreador    { get; set; }
    public DateTime? FechaCreacion    { get; set; }
    public DateTime? FechaEnvio       { get; set; }
    public string?   FechaExpiracion  { get; set; }

    // HU-10 — versión y última edición
    public int?      IdMotivoNuevaVersion { get; set; }
    public string?   MotivoNuevaVersion   { get; set; }
    public string?   DescripcionCambios   { get; set; }
    public DateTime? UltimaEdicionEn      { get; set; }
    public string?   UltimaEdicionPor     { get; set; }

    public List<PropuestaItemDto>      Items      { get; set; } = new();
    public List<PropuestaTextoDto>     Textos     { get; set; } = new();
    public List<PropuestaFormaPagoDto> FormasPago { get; set; } = new();
    public List<PropuestaEquipoDto>    Equipos    { get; set; } = new();
}
