using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Lo que necesita el PDF del pre-informe: la cabecera ya guardada del equipo y la hora de Lima en que se genera.</summary>
public record DatosPreInformePdf(CabeceraInformeMovilDto Cabecera, DateTime GeneradoEn);

/// <summary>Genera el PDF del pre-informe (App Mobile): la cabecera del informe del equipo con un espacio para la firma del encargado de planta.</summary>
public interface IGeneradorPreInformePdf
{
    byte[] Generar(DatosPreInformePdf datos);
}
