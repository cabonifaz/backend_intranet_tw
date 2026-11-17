using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// App Mobile HU-24 — Biblioteca de procedimientos: los aprobados (activos) y cuáles usa el técnico en sus servicios de hoy
/// (los que la app descarga sola al iniciar la jornada).
/// </summary>
public class ObtenerBibliotecaProcedimientosMovilCasoDeUso(IProcedimientosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<BibliotecaProcedimientosMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<BibliotecaProcedimientosMovilDto>(1, "No se pudo identificar al usuario."))
            : repositorio.ObtenerBibliotecaAsync(idUsuario, ct);
}

/// <summary>PDF de un procedimiento de la biblioteca: se genera con la información registrada en la intranet (solo los aprobados y vigentes).</summary>
public class ObtenerPdfProcedimientoMovilCasoDeUso(IProcedimientosMovilRepositorio repositorio, IGeneradorProcedimientoPdf generador)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idUsuario, long idProcedimiento, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idProcedimiento <= 0)
            return new RespuestaDto<ArchivoDescargaDto>(1, "Procedimiento no válido.");

        var biblioteca = await repositorio.ObtenerBibliotecaAsync(idUsuario, ct);
        if (biblioteca.IdTipoMensaje != 2 || biblioteca.Datos is null)
            return new RespuestaDto<ArchivoDescargaDto>(biblioteca.IdTipoMensaje, biblioteca.Mensaje);
        var p = biblioteca.Datos.Procedimientos.FirstOrDefault(x => x.IdProcedimiento == idProcedimiento);
        if (p is null)
            return new RespuestaDto<ArchivoDescargaDto>(1, "Este procedimiento ya no está aprobado o no existe.");

        var bytes = generador.Generar(p, DateTime.UtcNow.AddHours(-5));
        var invalidos = Path.GetInvalidFileNameChars();
        var nombre = $"{string.Concat(p.Codigo.Select(c => invalidos.Contains(c) ? '_' : c))}_v{p.Version}.pdf";
        return new RespuestaDto<ArchivoDescargaDto>(2, "Éxito.", new ArchivoDescargaDto(new MemoryStream(bytes), nombre, "application/pdf"));
    }
}
