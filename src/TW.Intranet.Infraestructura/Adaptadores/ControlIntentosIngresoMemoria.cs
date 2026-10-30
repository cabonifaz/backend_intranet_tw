using System.Collections.Concurrent;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// App Mobile — Intentos fallidos de ingreso en memoria del servidor (sin tablas nuevas).
/// Con MaxIntentosFallidos fallos dentro de la ventana, la clave queda bloqueada MinutosBloqueo minutos.
/// Se reinicia con cada despliegue; para varias instancias del back habría que llevarlo a la BD.
/// </summary>
public class ControlIntentosIngresoMemoria(OpcionesSeguridadMovil opciones) : IControlIntentosIngreso
{
    private const int MaximoClaves = 10_000;

    private sealed record Registro(int Fallos, DateTime PrimerFalloUtc, DateTime? BloqueadoHastaUtc);

    private readonly ConcurrentDictionary<string, Registro> _registros = new(StringComparer.Ordinal);

    private TimeSpan Ventana => TimeSpan.FromMinutes(Math.Max(1, opciones.MinutosBloqueo));

    public TimeSpan? TiempoBloqueoRestante(string clave)
    {
        if (!_registros.TryGetValue(Normalizar(clave), out var r) || r.BloqueadoHastaUtc is null)
            return null;

        var restante = r.BloqueadoHastaUtc.Value - DateTime.UtcNow;
        return restante > TimeSpan.Zero ? restante : null;
    }

    public void RegistrarFallo(string clave)
    {
        var ahora = DateTime.UtcNow;
        if (_registros.Count >= MaximoClaves) Limpiar(ahora);

        _registros.AddOrUpdate(
            Normalizar(clave),
            _ => Evaluar(new Registro(1, ahora, null), ahora),
            (_, r) =>
            {
                // Bloqueo vencido o ventana vencida: se empieza a contar de nuevo.
                if ((r.BloqueadoHastaUtc is { } hasta && hasta <= ahora) ||
                    (r.BloqueadoHastaUtc is null && ahora - r.PrimerFalloUtc > Ventana))
                    return Evaluar(new Registro(1, ahora, null), ahora);

                return Evaluar(r with { Fallos = r.Fallos + 1 }, ahora);
            });
    }

    public void Reiniciar(string clave) => _registros.TryRemove(Normalizar(clave), out _);

    private Registro Evaluar(Registro r, DateTime ahora) =>
        r.BloqueadoHastaUtc is null && r.Fallos >= Math.Max(1, opciones.MaxIntentosFallidos)
            ? r with { BloqueadoHastaUtc = ahora.Add(Ventana) }
            : r;

    private void Limpiar(DateTime ahora)
    {
        foreach (var (clave, r) in _registros)
        {
            var vencido = r.BloqueadoHastaUtc is { } hasta ? hasta <= ahora : ahora - r.PrimerFalloUtc > Ventana;
            if (vencido) _registros.TryRemove(clave, out _);
        }
    }

    private static string Normalizar(string clave) => (clave ?? string.Empty).Trim().ToLowerInvariant();
}
