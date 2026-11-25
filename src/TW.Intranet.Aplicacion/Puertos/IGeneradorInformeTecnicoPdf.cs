using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>PDF A4 del informe técnico del servicio (lo que registró el técnico desde la app), generado por la intranet (24/11/2026).</summary>
public interface IGeneradorInformeTecnicoPdf
{
    byte[] Generar(DatosInformeTecnicoPdf datos);
}
