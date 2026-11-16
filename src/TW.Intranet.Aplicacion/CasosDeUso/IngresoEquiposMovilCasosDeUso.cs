using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>App Mobile HU-22 — Ingresos ya registrados de los equipos de una OS del técnico.</summary>
public class ObtenerIngresosEquiposMovilCasoDeUso(IIngresoEquiposMovilRepositorio repositorio)
{
    public Task<RespuestaDto<IngresosOsMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => idUsuario <= 0 || idOs <= 0
            ? Task.FromResult(new RespuestaDto<IngresosOsMovilDto>(1, EntradaObjetivosMovil.SinServicio))
            : repositorio.ObtenerAsync(idUsuario, idOs, ct);
}

/// <summary>
/// App Mobile HU-22 — Agrega a la lista de la OS un equipo YA REGISTRADO del mismo cliente, a partir del QR o código escaneado.
/// Si el código no corresponde a un equipo del cliente, el mensaje indica registrarlo como equipo nuevo (NEW).
/// </summary>
public class AgregarEquipoExistenteOsMovilCasoDeUso(IIngresoEquiposMovilRepositorio repositorio)
{
    public Task<RespuestaDto<EquipoAgregadoMovilDto>> EjecutarAsync(long idUsuario, long idOs, string? codigo, bool soloVerificar = false, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return Task.FromResult(new RespuestaDto<EquipoAgregadoMovilDto>(1, EntradaObjetivosMovil.SinServicio));
        var limpio = EntradaObjetivosMovil.Limpiar(codigo);
        if (limpio is null || limpio.Length > EntradaObjetivosMovil.MaxCodigoQr)
            return Task.FromResult(new RespuestaDto<EquipoAgregadoMovilDto>(1, "El código escaneado no es válido."));
        return repositorio.AgregarExistenteAsync(idUsuario, idOs, limpio, soloVerificar, ct);
    }
}

/// <summary>
/// App Mobile HU-22 — Registrar el ingreso de un equipo de la OS: estado de ingreso, observación y fotos de evidencia (solo cámara, JPEG, hasta 5 de 5 MB).
/// El back valida y guarda las fotos ANTES de llamar al SP y las borra si el SP no registra el ingreso.
/// </summary>
public class RegistrarIngresoEquipoMovilCasoDeUso(IIngresoEquiposMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoFotoBytes = 5 * 1024 * 1024;
    public const int  MaxFotos = 5;

    public static readonly string[] Estados = ["operativo", "con_observaciones", "inoperativo"];

    public async Task<RespuestaDto<ResultadoIngresoEquipoMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, string? estado, string? observacion,
        IReadOnlyList<(Stream Contenido, long Tamano)> fotos, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0)
            return new(1, EntradaObjetivosMovil.SinServicio);

        var est = (estado ?? string.Empty).Trim().ToLowerInvariant();
        if (!Estados.Contains(est)) return new(1, "Selecciona el estado de ingreso del equipo.");

        var obs = EntradaObjetivosMovil.Limpiar(observacion);
        if (obs is { Length: > 500 }) return new(1, "La observación puede tener hasta 500 caracteres.");
        if (est != "operativo")
        {
            if (obs is null || obs.Length < 3) return new(1, "Escribe la observación del estado del equipo (mínimo 3 caracteres).");
            if (fotos.Count < 1) return new(1, "Toma al menos una foto de evidencia (solo cámara).");
            if (fotos.Count > MaxFotos) return new(1, $"Puedes adjuntar hasta {MaxFotos} fotos.");
        }

        // Fotos: solo con observaciones o inoperativo. Se leen y validan todas antes de guardar alguna.
        var buffers = new List<MemoryStream>();
        var rutas = new List<string>();
        try
        {
            if (est != "operativo")
            {
                foreach (var (contenido, tamano) in fotos)
                {
                    if (tamano <= 0) return new(1, "Una de las fotos está vacía.");
                    if (tamano > TamanoMaximoFotoBytes) return new(1, "Cada foto puede pesar hasta 5 MB.");
                    var buffer = new MemoryStream();
                    await contenido.CopyToAsync(buffer, ct);
                    buffers.Add(buffer);
                    if (buffer.Length == 0) return new(1, "Una de las fotos está vacía.");
                    if (buffer.Length > TamanoMaximoFotoBytes) return new(1, "Cada foto puede pesar hasta 5 MB.");
                    if (!RegistrarDemoraMovilCasoDeUso.EsJpeg(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 3))))
                        return new(1, "Las fotos deben ser imágenes JPEG tomadas con la cámara.");
                }
                foreach (var b in buffers)
                {
                    var ruta = $"ingresos-equipos/{idOs}/{idOsEquipo}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
                    b.Position = 0;
                    await almacen.GuardarAsync(ruta, b, ct);
                    rutas.Add(ruta);
                }
            }

            var r = await repositorio.RegistrarAsync(idUsuario, idOs, idOsEquipo, est, obs, rutas, ct);
            if (r.IdTipoMensaje != 2)
                foreach (var ruta in rutas) await almacen.EliminarAsync(ruta, CancellationToken.None);
            return r;
        }
        finally
        {
            foreach (var b in buffers) b.Dispose();
        }
    }
}
