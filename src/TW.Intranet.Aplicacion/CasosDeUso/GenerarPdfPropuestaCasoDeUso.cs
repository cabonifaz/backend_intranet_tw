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
