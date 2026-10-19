using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// Genera el PDF comercial de una propuesta a partir del detalle completo.
/// Implementación: PropuestaPdfGeneradorQuestPdf (QuestPDF).
/// </summary>
public interface IPropuestaPdfGenerador
{
    byte[] Generar(PropuestaDetalleModalDto detalle);
}
