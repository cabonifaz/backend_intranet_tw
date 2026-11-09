using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Genera el PDF comercial de una propuesta (vista previa / descarga).
/// Reutiliza ObtenerDetallePropuestaCasoDeUso para traer todos los datos.
/// </summary>
public class GenerarPdfPropuestaCasoDeUso(
    ObtenerDetallePropuestaCasoDeUso obtenerDetalle,
    IPropuestaPdfGenerador           generador)
{
    public async Task<RespuestaDto<byte[]>> EjecutarAsync(long idPropuesta, CancellationToken ct = default)
    {
        var detalle = await obtenerDetalle.EjecutarAsync(idPropuesta, ct);
        if (detalle.IdTipoMensaje != 2 || detalle.Datos is null)
            return new RespuestaDto<byte[]>(detalle.IdTipoMensaje, detalle.Mensaje);

        try
        {
            var pdf = generador.Generar(detalle.Datos);
            return new RespuestaDto<byte[]>(2, "PDF generado correctamente.", pdf);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<byte[]>(3, $"Error al generar el PDF: {ex.Message}");
        }
    }
}

/// <summary>
/// Vista previa del PDF con el borrador del wizard SIN guardar (feedback cliente 04/11, edición post-VB).
/// Parte de la propuesta guardada (cliente, contacto, responsable, número/versión) y le aplica los datos del body
/// (mismo DTO que "Guardar"): textos, ítems, formas de pago, equipos, moneda, IGV y descuentos. Los totales se
/// recalculan con la misma fórmula de SP_GuardarPropuesta. No toca la BD.
/// </summary>
public class GenerarPdfPreviewPropuestaCasoDeUso(
    ObtenerDetallePropuestaCasoDeUso obtenerDetalle,
    IPropuestaPdfGenerador           generador)
{
    private static readonly Dictionary<int, string> SimbolosMoneda = new() { [1] = "S/", [2] = "$", [3] = "COP$" };

    public async Task<RespuestaDto<byte[]>> EjecutarAsync(long idPropuesta, GuardarPropuestaDto borrador, CancellationToken ct = default)
    {
        if (borrador is null) return new RespuestaDto<byte[]>(1, "Envíe los datos de la propuesta.");

        var detalle = await obtenerDetalle.EjecutarAsync(idPropuesta, ct);
        if (detalle.IdTipoMensaje != 2 || detalle.Datos is null)
            return new RespuestaDto<byte[]>(detalle.IdTipoMensaje, detalle.Mensaje);

        var p = detalle.Datos.Propuesta;
        var etiquetasPago = p.FormasPago.Where(f => f.Condicion is not null)
                                        .GroupBy(f => f.Condicion!).ToDictionary(g => g.Key, g => g.First().CondicionLabel);

        // Cabecera (la referencia es siempre el detalle del RQ: se conserva la guardada)
        p.TipoServicio       = borrador.TipoServicio ?? p.TipoServicio;
        p.Introduccion       = borrador.Introduccion;
        p.NotasGenerales     = borrador.NotasGenerales;
        if (borrador.SeccionesActivas is not null) p.SeccionesActivas = borrador.SeccionesActivas;
        if (borrador.IdMoneda != p.IdMoneda && SimbolosMoneda.TryGetValue(borrador.IdMoneda, out var simbolo))
            p.MonedaSimbolo = simbolo;
        p.IdMoneda           = borrador.IdMoneda;
        p.AplicaIgv          = borrador.AplicaIgv;
        p.PreciosIncluyenIgv = borrador.PreciosIncluyenIgv;

        // Detalle
        foreach (var i in borrador.Items)
        {
            i.Seccion  = string.Equals(i.Seccion?.Trim(), "opcional", StringComparison.OrdinalIgnoreCase) ? "opcional" : "principal";
            i.Subtotal = i.EsEspaciado ? 0 : Math.Max(Math.Round(i.Cantidad * i.Frecuencia * i.PrecioUnitario - i.Descuento, 2), 0);
        }
        p.Items  = borrador.Items;
        p.Textos = borrador.Textos.Where(t => !string.IsNullOrWhiteSpace(t.Texto)).ToList();
        foreach (var f in borrador.FormasPago)
            if (string.IsNullOrWhiteSpace(f.CondicionLabel))
                f.CondicionLabel = f.Condicion is not null && etiquetasPago.TryGetValue(f.Condicion, out var et) ? et : f.Condicion;
        p.FormasPago = borrador.FormasPago;
        p.Equipos    = borrador.Equipos;

        // Totales (misma fórmula que SP_GuardarPropuesta)
        decimal sub    = borrador.Items.Where(i => !i.EsEspaciado && i.Seccion == "principal").Sum(i => i.Subtotal);
        decimal subOpc = borrador.Items.Where(i => !i.EsEspaciado && i.Seccion == "opcional").Sum(i => i.Subtotal);
        decimal desc   = borrador.DescuentoPct is > 0 ? Math.Round(sub * borrador.DescuentoPct.Value / 100, 2)
                                                      : borrador.DescuentoMonto ?? 0;
        desc = Math.Min(Math.Max(desc, 0), sub);
        decimal baseImp = sub - desc, igv, total;
        if (borrador.PreciosIncluyenIgv) { total = baseImp; igv = Math.Round(baseImp - baseImp / (1 + p.IgvPct / 100), 2); }
        else if (borrador.AplicaIgv)     { igv = Math.Round(baseImp * p.IgvPct / 100, 2); total = baseImp + igv; }
        else                             { igv = 0; total = baseImp; }
        decimal descOpc = Math.Min(Math.Max(borrador.DescuentoOpcionales ?? 0, 0), subOpc);

        p.Subtotal            = sub;
        p.DescuentoPct        = borrador.DescuentoPct is > 0 ? borrador.DescuentoPct : null;
        p.DescuentoMonto      = desc;
        p.IgvMonto            = igv;
        p.Total               = total;
        p.SubtotalOpcionales  = subOpc;
        p.DescuentoOpcionales = descOpc;
        p.TotalOpcionales     = subOpc - descOpc;

        try
        {
            return new RespuestaDto<byte[]>(2, "Vista previa generada (sin guardar).", generador.Generar(detalle.Datos));
        }
        catch (Exception ex)
        {
            return new RespuestaDto<byte[]>(3, $"Error al generar el PDF: {ex.Message}");
        }
    }
}
