namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Body de POST /api/crm/propuestas — guarda la propuesta COMPLETA.
/// IdPropuesta = 0 → crear (si IdPropuestaBase > 0, crea una NUEVA VERSIÓN de esa propuesta).
/// IdPropuesta > 0 → actualizar (solo en estado "borrador").
/// </summary>
public class GuardarPropuestaDto
{
    public long  IdPropuesta      { get; set; }
    public long? IdPropuestaBase  { get; set; }
    public long  IdRequerimiento  { get; set; }

    // 1. Configuración
    /// <summary>Si es null se hereda del requerimiento.</summary>
    public long?         IdSede           { get; set; }
    /// <summary>Si es null se hereda del requerimiento.</summary>
    public long?         IdContacto       { get; set; }
    /// <summary>Si es null se usa el usuario logueado.</summary>
    public long?         IdResponsable    { get; set; }
    public string?       TipoServicio     { get; set; }
    public List<string>? SeccionesActivas { get; set; }

    // Tercerización (certificado a nombre de un tercero)
    public bool    EsTercerizado      { get; set; }
    public string? TerceroRuc         { get; set; }
    public string? TerceroRazonSocial { get; set; }
    public string? TerceroDireccion   { get; set; }

    // 2. Datos de la propuesta (carátula)
    public string? Referencia     { get; set; }
    /// <summary>HTML del editor enriquecido.</summary>
    public string? Introduccion   { get; set; }
    public string? NotasGenerales { get; set; }

    // Forma de pago / condiciones generales
    /// <summary>Num1 del catálogo MONEDA: 1 = PEN, 2 = USD.</summary>
    public int      IdMoneda              { get; set; } = 2;
    public decimal? TipoCambio            { get; set; }
    public int?     GarantiaMeses         { get; set; }
    public bool     MostrarGarantia       { get; set; } = true;
    public int?     PlazoEntregaDias      { get; set; }
    /// <summary>"dias_habiles" | "dias_calendario".</summary>
    public string?  PlazoEntregaUnidad    { get; set; }
    public string?  PlazoEntregaCondicion { get; set; }
    public int?     VigenciaDias          { get; set; }
    public bool     AplicaIgv             { get; set; } = true;
    public bool     PreciosIncluyenIgv    { get; set; }

    // Descuentos globales (si DescuentoPct > 0 tiene prioridad sobre DescuentoMonto)
    public decimal? DescuentoPct         { get; set; }
    public decimal? DescuentoMonto       { get; set; }
    public int?     IdMotivoDescuento    { get; set; }
    public decimal? DescuentoOpcionales  { get; set; }

    // Detalle
    public List<PropuestaItemDto>      Items       { get; set; } = new();
    public List<PropuestaTextoDto>     Textos      { get; set; } = new();
    public List<PropuestaFormaPagoDto> FormasPago  { get; set; } = new();
    public List<PropuestaEquipoDto>    Equipos     { get; set; } = new();
}
