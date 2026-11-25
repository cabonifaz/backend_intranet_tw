using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>PDF A4 del Informe Complementario (Revisión Técnica, 23/11/2026): datos del servicio, resultado de los ensayos del técnico,
/// observaciones, recomendaciones, fotos y precotización del supervisor.</summary>
public interface IGeneradorInformeComplementarioPdf
{
    byte[] Generar(DatosInformeComplementarioPdf datos);
}
