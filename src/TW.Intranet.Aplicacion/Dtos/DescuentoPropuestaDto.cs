namespace TW.Intranet.Aplicacion.Dtos;

// ─────────────────────────────────────────────────────────────────────────────
// HU-11 — Aplicación de Descuento Comercial
//   POST   /api/crm/propuestas/{id}/descuento/previsualizar
//   PUT    /api/crm/propuestas/{id}/descuento
//   DELETE /api/crm/propuestas/{id}/descuento
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Modal "Aplicar Descuento Global".</summary>
public class AplicarDescuentoPropuestaDto
{
    /// <summary>porcentaje | monto</summary>
    public string Tipo              { get; set; } = "";
    /// <summary>Porcentaje (0 &lt; valor ≤ 100) o monto fijo (0 &lt; valor ≤ subtotal).</summary>
    public decimal Valor            { get; set; }
    /// <summary>Num1 de MOTIVO_DESCUENTO (GET /api/maestros/catalogos/MOTIVO_DESCUENTO). Obligatorio al aplicar.</summary>
    public int? IdMotivoDescuento   { get; set; }
}

/// <summary>Montos actuales y nuevos (lo que muestra el modal).</summary>
public class DescuentoPropuestaResultadoDto
{
    public decimal  SubtotalActual     { get; set; }
    public decimal  DescuentoActual    { get; set; }
    public decimal? PorcentajeActual   { get; set; }
    public decimal  IgvActual          { get; set; }
    public decimal  TotalActual        { get; set; }

    /// <summary>porcentaje | monto | ninguno</summary>
    public string   Tipo               { get; set; } = "";
    public decimal? Porcentaje         { get; set; }
    public decimal  DescuentoNuevo     { get; set; }
    /// <summary>Subtotal menos el descuento (base imponible).</summary>
    public decimal  SubtotalNuevo      { get; set; }
    public decimal  IgvNuevo           { get; set; }
    public decimal  TotalNuevo         { get; set; }
    public decimal  IgvPct             { get; set; }

    public int?     IdMotivoDescuento  { get; set; }
    public string?  MotivoDescuento    { get; set; }
    /// <summary>false en la previsualización.</summary>
    public bool     Guardado           { get; set; }
}
