using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// #4436 — PDF oficial de la OS / OM, en cualquier estado. Reúne el detalle (con el control de acceso de su SP), los
/// conceptos, los equipos, la programación y las observaciones, y lo renderiza con el generador.
/// Si un tab no responde (por ejemplo, sin programación) la sección sale vacía en vez de fallar todo el PDF.
/// </summary>
public class GenerarPdfOrdenServicioCasoDeUso(
    ObtenerDetalleOrdenServicioCasoDeUso detalle,
    IOrdenServicioRepositorio            repositorio,
    IOrdenServicioPdfGenerador           generador)
{
    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(long idOs, long idUsuario, CancellationToken ct = default)
    {
        var d = await detalle.EjecutarAsync(idOs, idUsuario, ct);
        if (d.IdTipoMensaje != 2 || d.Datos is null)
            return new(d.IdTipoMensaje, d.Mensaje);

        var conceptos     = await repositorio.ObtenerConceptosAsync(idOs, idUsuario, ct);
        var equipos       = await repositorio.ObtenerEquiposAsync(idOs, idUsuario, ct);
        var programacion  = await repositorio.ObtenerProgramacionAsync(idOs, idUsuario, ct);
        var observaciones = await repositorio.ObtenerObservacionesAsync(idOs, idUsuario, ct);

        var datos = new OrdenServicioPdfDto(
            d.Datos,
            conceptos.IdTipoMensaje == 2 ? conceptos.Datos ?? [] : [],
            equipos.IdTipoMensaje   == 2 ? equipos.Datos   ?? [] : [],
            programacion.IdTipoMensaje == 2 ? programacion.Datos : null,
            observaciones.IdTipoMensaje == 2 ? observaciones.Datos : null);

        try
        {
            var pdf    = generador.Generar(datos);
            var nombre = $"{(string.IsNullOrWhiteSpace(d.Datos.Numero) ? $"orden-{idOs}" : d.Datos.Numero)}.pdf";
            return new(2, "PDF generado correctamente.", new ArchivoGeneradoDto(pdf, nombre, "application/pdf"));
        }
        catch (Exception ex)
        {
            return new(3, $"Error al generar el PDF: {ex.Message}");
        }
    }
}
