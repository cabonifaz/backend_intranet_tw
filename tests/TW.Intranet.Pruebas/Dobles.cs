using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Almacenamiento en memoria: registra lo que se guarda y lo que se borra.</summary>
internal sealed class AlmacenFalso : IAlmacenArchivos
{
    public Dictionary<string, byte[]> Archivos { get; } = [];
    public List<string> Eliminados { get; } = [];

    public async Task GuardarAsync(string ruta, Stream contenido, CancellationToken ct)
    {
        using var m = new MemoryStream();
        await contenido.CopyToAsync(m, ct);
        Archivos[ruta] = m.ToArray();
    }

    public Task<Stream?> AbrirLecturaAsync(string ruta, CancellationToken ct) =>
        Task.FromResult<Stream?>(Archivos.TryGetValue(ruta, out var b) ? new MemoryStream(b) : null);

    public Task EliminarAsync(string ruta, CancellationToken ct)
    {
        Eliminados.Add(ruta);
        Archivos.Remove(ruta);
        return Task.CompletedTask;
    }
}

internal sealed class LectorIaFalso(decimal? total) : ILectorComprobanteIa
{
    public int Llamadas { get; private set; }
    public Task<decimal?> LeerTotalAsync(byte[] imagenJpeg, CancellationToken ct) { Llamadas++; return Task.FromResult(total); }
}

/// <summary>Repositorio de gastos y aprobaciones de la app: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class GastosMovilRepoFalso : IGastosAprobacionesMovilRepositorio
{
    public RespuestaDto<ResultadoGastoMovilDto> RespuestaRendir { get; set; } =
        new(2, "OK", new ResultadoGastoMovilDto(10, "GS-000010", "pendiente", false, []));
    public ComandoGastoMovil? UltimoComando { get; private set; }
    public int Llamadas { get; private set; }
    public string? RutaArchivo { get; set; }

    public Task<RespuestaDto<ResultadoGastoMovilDto>> RendirGastoAsync(long idUsuario, ComandoGastoMovil comando, CancellationToken ct)
    { Llamadas++; UltimoComando = comando; return Task.FromResult(RespuestaRendir); }

    public Task<RespuestaDto<string>> ObtenerRutaFotoGastoAsync(long idUsuario, long idGasto, int n, CancellationToken ct)
    { Llamadas++; return Task.FromResult(RutaArchivo is null ? new RespuestaDto<string>(1, "No") : new RespuestaDto<string>(2, "OK", RutaArchivo)); }

    public Task<RespuestaDto<List<AprobacionMovilDto>>> ObtenerAprobacionesExtraAsync(long idUsuario, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<List<AprobacionMovilDto>>(2, "OK", [])); }

    public Task<RespuestaDto<DetalleAprobacionMovilDto>> ObtenerDetalleAsync(long idUsuario, string tipo, long id, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<DetalleAprobacionMovilDto>(1, "No")); }

    public Task<RespuestaDto<ArchivoAprobacionMovilDto>> ObtenerArchivoAsync(long idUsuario, string tipo, long id, int n, CancellationToken ct)
    { Llamadas++; return Task.FromResult(RutaArchivo is null ? new RespuestaDto<ArchivoAprobacionMovilDto>(1, "No")
                                                             : new RespuestaDto<ArchivoAprobacionMovilDto>(2, "OK", new(RutaArchivo, null, false))); }

    public Task<RespuestaDto<bool>> ResolverEvidenciaAsync(long idUsuario, long idEvidencia, bool aprobar, string? comentario, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<bool>(2, "OK", true)); }

    public Task<RespuestaDto<bool>> ResolverEnsayoAsync(long idUsuario, long idInforme, bool aprobar, string? comentario, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<bool>(2, "OK", true)); }

    public Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoAsync(long idUsuario, long idGasto, string accion, string? comentario, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, "No")); }
}

/// <summary>Repositorio de aprobaciones y viáticos de la intranet.</summary>
internal sealed class AprobacionesViaticosRepoFalso : IAprobacionesViaticosServicioRepositorio
{
    public int Llamadas { get; private set; }
    public string? RutaComprobante { get; set; }

    public Task<RespuestaDto<AprobacionesServicioDto>> ObtenerAprobacionesAsync(long idUsuario, long idOs, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<AprobacionesServicioDto>(1, "No")); }

    public Task<RespuestaDto<bool>> ResolverAprobacionAsync(long idUsuario, long idOs, string tipo, long id, bool aprobar, string comentario, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<bool>(2, "OK", true)); }

    public Task<RespuestaDto<ViaticosOsDto>> ObtenerViaticosServicioAsync(long idUsuario, long idOs, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<ViaticosOsDto>(1, "No")); }

    public Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoServicioAsync(long idUsuario, long idOs, long idGasto, string accion, string? comentario, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, "No")); }

    public Task<RespuestaDto<string>> ObtenerRutaComprobanteAsync(long idUsuario, long idOs, long idGasto, int n, CancellationToken ct)
    { Llamadas++; return Task.FromResult(RutaComprobante is null ? new RespuestaDto<string>(1, "El gasto no pertenece a este servicio.")
                                                                  : new RespuestaDto<string>(2, "OK", RutaComprobante)); }

    public Task<RespuestaDto<ViaticosOsDto>> ObtenerViaticosInformeAsync(long idUsuario, long idInforme, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<ViaticosOsDto>(1, "No")); }
}
