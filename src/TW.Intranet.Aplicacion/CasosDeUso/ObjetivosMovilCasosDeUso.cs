using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-07 — Lista de objetivos y selección de equipos ───────────────────────────────

/// <summary>Validación y limpieza comunes de lo que envía la app (las reglas de negocio —Hard Stop, estado, permisos— viven en los SP).</summary>
public static class EntradaObjetivosMovil
{
    public const string SinServicio = "Servicio no encontrado o no asignado a tu usuario.";
    public const int MaxBusqueda = 100;
    public const int MaxCodigoQr = 300;
    public const int MinMotivo   = 3;
    public const int MaxMotivo   = 300;

    public static readonly IReadOnlySet<string> Acciones = new HashSet<string> { "iniciar", "pausar", "reanudar" };

    /// <summary>Quita caracteres de control y recorta; vacío = null.</summary>
    public static string? Limpiar(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var limpio = new string(texto.Where(c => !char.IsControl(c)).ToArray()).Trim();
        return limpio.Length == 0 ? null : limpio;
    }
}

/// <summary>
/// "Objetivos de hoy": los equipos de la OS numerados con su estado, los contadores y los tiempos del técnico.
/// Hard Stop (HU-06): sin llegada registrada el SP no entrega objetivos y responde la regla de negocio.
/// </summary>
public class ObtenerObjetivosMovilCasoDeUso(IObjetivosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ObjetivosMovilDto>> EjecutarAsync(long idUsuario, long idOs, string? buscar, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return Task.FromResult(new RespuestaDto<ObjetivosMovilDto>(1, EntradaObjetivosMovil.SinServicio));

        var texto = EntradaObjetivosMovil.Limpiar(buscar) ?? string.Empty;
        if (texto.Length > EntradaObjetivosMovil.MaxBusqueda)
            return Task.FromResult(new RespuestaDto<ObjetivosMovilDto>(1, $"La búsqueda puede tener hasta {EntradaObjetivosMovil.MaxBusqueda} caracteres."));

        return repositorio.ObtenerAsync(idUsuario, idOs, texto, ct);
    }
}

/// <summary>Selecciona un equipo escaneando su código de barras o QR: solo se acepta uno que sea de la lista de la OS.</summary>
public class BuscarEquipoQrMovilCasoDeUso(IObjetivosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ObjetivoEquipoMovilDto>> EjecutarAsync(long idUsuario, long idOs, string? codigo, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return Task.FromResult(new RespuestaDto<ObjetivoEquipoMovilDto>(1, EntradaObjetivosMovil.SinServicio));

        var limpio = EntradaObjetivosMovil.Limpiar(codigo);
        if (limpio is null || limpio.Length > EntradaObjetivosMovil.MaxCodigoQr)
            return Task.FromResult(new RespuestaDto<ObjetivoEquipoMovilDto>(1, "El código escaneado no es válido."));

        return repositorio.BuscarPorQrAsync(idUsuario, idOs, limpio, ct);
    }
}

/// <summary>
/// "Trabajar en el equipo" (iniciar), "Pausar" (con motivo) y "Reanudar". El SP decide si la acción corresponde (Hard Stop, estado del equipo,
/// un solo equipo a la vez, pausa que espera al supervisor) y es idempotente. Al terminar devuelve la lista de objetivos ya actualizada para que
/// la app la pinte sin otra consulta; si esa lectura fallara, la acción igual quedó hecha (responde éxito sin lista).
/// </summary>
public class CambiarEstadoEquipoMovilCasoDeUso(IObjetivosMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<ObjetivosMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, string? accion, PeticionCambioEstadoEquipoMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0)
            return new(1, "Servicio o equipo no encontrado.");

        var a = (accion ?? string.Empty).Trim().ToLowerInvariant();
        if (!EntradaObjetivosMovil.Acciones.Contains(a))
            return new(1, "La acción no es válida.");

        var motivo = EntradaObjetivosMovil.Limpiar(d?.Motivo);
        if (a == "pausar")
        {
            if (motivo is null || motivo.Length < EntradaObjetivosMovil.MinMotivo)
                return new(1, $"Indica el motivo de la pausa (mínimo {EntradaObjetivosMovil.MinMotivo} caracteres).");
        }
        else motivo = null;
        if (motivo is { Length: > EntradaObjetivosMovil.MaxMotivo })
            return new(1, $"El motivo puede tener hasta {EntradaObjetivosMovil.MaxMotivo} caracteres.");

        var r = await repositorio.CambiarEstadoAsync(idUsuario, idOs, idOsEquipo, a, motivo, RegistrarLlegadaMovilCasoDeUso.CapturaUtc(d?.CapturadoEn), ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);

        var lista = await repositorio.ObtenerAsync(idUsuario, idOs, string.Empty, ct);
        return new(2, r.Mensaje, lista.IdTipoMensaje == 2 ? lista.Datos : null);
    }
}

/// <summary>Listas del formulario "Equipo nuevo": marcas y tipos de equipo.</summary>
public class ObtenerOpcionesEquipoNuevoMovilCasoDeUso(IObjetivosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<OpcionesEquipoNuevoMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0
            ? Task.FromResult(new RespuestaDto<OpcionesEquipoNuevoMovilDto>(1, EntradaObjetivosMovil.SinServicio))
            : repositorio.ObtenerOpcionesEquipoNuevoAsync(idUsuario, idOs, ct);
}

/// <summary>
/// El técnico registra en campo un equipo que no está en la lista de la OS. Valida los datos y la foto de la placa (obligatoria, JPEG de la cámara,
/// hasta 5 MB), guarda la foto en el almacenamiento de archivos y llama al SP, que valida el Hard Stop y la OS, no duplica equipos del maestro,
/// lo deja pendiente de aprobación (COD TW provisional) y avisa al área. Si el SP no usa la foto, no queda un archivo huérfano.
/// </summary>
public class RegistrarEquipoNuevoMovilCasoDeUso(IObjetivosMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoFotoBytes = 5 * 1024 * 1024;
    public const int  MaxCorto = 80;
    public const int  MaxUbicacion = 200;

    /// <summary>Valida los datos que llegan; null si están bien, o el mensaje para el técnico (los mismos que da el SP).</summary>
    public static string? Validar(NuevoEquipoMovilDto? d)
    {
        if (d is null) return "Datos incompletos.";
        if (EntradaObjetivosMovil.Limpiar(d.NumeroSerie) is not { } serie) return "Ingresa el N/S del equipo.";
        if (EntradaObjetivosMovil.Limpiar(d.Codigo) is not { } codigo) return "Ingresa el código del equipo.";
        if (EntradaObjetivosMovil.Limpiar(d.Marca) is null) return "Selecciona la marca.";
        if (EntradaObjetivosMovil.Limpiar(d.Modelo) is not { } modelo) return "Ingresa el modelo.";
        if (d.IdSuministro <= 0) return "Selecciona el tipo de equipo.";
        if (EntradaObjetivosMovil.Limpiar(d.Ubicacion) is not { } ubicacion) return "Ingresa la ubicación del equipo.";
        if (serie.Length > MaxCorto || codigo.Length > MaxCorto || modelo.Length > MaxCorto || ubicacion.Length > MaxUbicacion)
            return $"Algún dato supera el largo permitido (N/S, código y modelo: {MaxCorto}; ubicación: {MaxUbicacion}).";
        return null;
    }

    public async Task<RespuestaDto<ResultadoEquipoNuevoMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, NuevoEquipoMovilDto? equipo, Stream? foto, long tamanoFoto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, EntradaObjetivosMovil.SinServicio);

        var error = Validar(equipo);
        if (error is not null) return new(1, error);
        var limpio = equipo! with
        {
            NumeroSerie = EntradaObjetivosMovil.Limpiar(equipo.NumeroSerie),
            Codigo      = EntradaObjetivosMovil.Limpiar(equipo.Codigo),
            Marca       = EntradaObjetivosMovil.Limpiar(equipo.Marca),
            Modelo      = EntradaObjetivosMovil.Limpiar(equipo.Modelo),
            Ubicacion   = EntradaObjetivosMovil.Limpiar(equipo.Ubicacion),
        };

        // La foto de la placa es obligatoria: se valida y se guarda ANTES de registrar, y se borra si el SP no la usa
        if (foto is null || tamanoFoto <= 0) return new(1, "Toma la foto de la placa del equipo (solo cámara).");
        if (tamanoFoto > TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 5 MB.");

        using var buffer = new MemoryStream();
        await foto.CopyToAsync(buffer, ct);
        if (buffer.Length == 0) return new(1, "La foto está vacía.");
        if (buffer.Length > TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 5 MB.");
        if (!RegistrarDemoraMovilCasoDeUso.EsJpeg(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 3))))
            return new(1, "La foto debe ser una imagen JPEG tomada con la cámara.");

        var ruta = $"equipos-nuevos/{idOs}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);

        var r = await repositorio.RegistrarEquipoNuevoAsync(idUsuario, idOs, limpio, ruta, ct);

        if (r.IdTipoMensaje != 2 || r.Datos?.FotoGuardada != true)
            await almacen.EliminarAsync(ruta, CancellationToken.None);

        return r;
    }
}
