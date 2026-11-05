using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// Genera el PDF oficial de una OS / OM (#4436) a partir del detalle, conceptos, equipos y programación.
/// Implementación: OrdenServicioPdfGeneradorQuestPdf (QuestPDF).
/// </summary>
public interface IOrdenServicioPdfGenerador
{
    byte[] Generar(OrdenServicioPdfDto datos);
}
