using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// App Mobile HU-24 — Biblioteca de procedimientos: los aprobados con PDF y cuáles usa el técnico en sus servicios de hoy
/// (los que la app descarga sola al iniciar la jornada).
/// </summary>
public class ObtenerBibliotecaProcedimientosMovilCasoDeUso(IProcedimientosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<BibliotecaProcedimientosMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<BibliotecaProcedimientosMovilDto>(1, "No se pudo identificar al usuario."))
            : repositorio.ObtenerBibliotecaAsync(idUsuario, ct);
}

/// <summary>PDF de un procedimiento de la biblioteca (solo los aprobados y vigentes; no se abre uno inactivo por su id).</summary>
public class ObtenerPdfProcedimientoMovilCasoDeUso(IProcedimientosMovilRepositorio repositorio, ObtenerPdfProcedimientoCasoDeUso pdf)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idUsuario, long idProcedimiento, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idProcedimiento <= 0)
            return new RespuestaDto<ArchivoDescargaDto>(1, "Procedimiento no válido.");

        var biblioteca = await repositorio.ObtenerBibliotecaAsync(idUsuario, ct);
        if (biblioteca.IdTipoMensaje != 2 || biblioteca.Datos is null)
            return new RespuestaDto<ArchivoDescargaDto>(biblioteca.IdTipoMensaje, biblioteca.Mensaje);
        if (biblioteca.Datos.Procedimientos.All(p => p.IdProcedimiento != idProcedimiento))
            return new RespuestaDto<ArchivoDescargaDto>(1, "Este procedimiento ya no está aprobado o no existe.");

        return await pdf.EjecutarAsync(idProcedimiento, ct);
    }
}
