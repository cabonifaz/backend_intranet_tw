using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Genera el PDF de un procedimiento a partir de la información registrada en la intranet (App Mobile HU-24).</summary>
public interface IGeneradorProcedimientoPdf
{
    byte[] Generar(ProcedimientoMovilDto procedimiento, DateTime generadoEnLima);
}
