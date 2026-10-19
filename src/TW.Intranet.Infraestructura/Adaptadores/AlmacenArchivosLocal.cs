using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Almacenamiento en disco. En Railway la RutaBase vive en un volumen persistente
/// (los archivos sobreviven a los redeploys). Protege contra rutas que intenten
/// salir de la carpeta base (../).
/// </summary>
public class AlmacenArchivosLocal(ConfiguracionAlmacenamiento configuracion) : IAlmacenArchivos
{
    private const int TamanoBufferIo = 81920;

    private readonly string _rutaBase = Path.GetFullPath(configuracion.RutaBase);

    public async Task GuardarAsync(string ruta, Stream contenido, CancellationToken ct)
    {
        var destino = RutaCompleta(ruta);
        Directory.CreateDirectory(Path.GetDirectoryName(destino)!);

        // Se escribe a un temporal y se mueve al final para no dejar archivos a medias
        var temporal = destino + ".tmp";
        try
        {
            await using (var archivo = new FileStream(temporal, FileMode.CreateNew, FileAccess.Write,
                                                      FileShare.None, TamanoBufferIo, useAsync: true))
            {
                await contenido.CopyToAsync(archivo, ct);
            }
            File.Move(temporal, destino, overwrite: false);
        }
        catch
        {
            if (File.Exists(temporal)) File.Delete(temporal);
            throw;
        }
    }

    public Task<Stream?> AbrirLecturaAsync(string ruta, CancellationToken ct)
    {
        var origen = RutaCompleta(ruta);
        Stream? stream = File.Exists(origen)
            ? new FileStream(origen, FileMode.Open, FileAccess.Read, FileShare.Read, TamanoBufferIo, useAsync: true)
            : null;
        return Task.FromResult(stream);
    }

    public Task EliminarAsync(string ruta, CancellationToken ct)
    {
        var archivo = RutaCompleta(ruta);
        if (File.Exists(archivo)) File.Delete(archivo);
        return Task.CompletedTask;
    }

    private string RutaCompleta(string ruta)
    {
        if (string.IsNullOrWhiteSpace(ruta))
            throw new ArgumentException("Ruta de archivo vacía.", nameof(ruta));

        var completa = Path.GetFullPath(Path.Combine(_rutaBase, ruta.Replace('\\', '/').TrimStart('/')));
        var comparacion = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

        if (!completa.StartsWith(_rutaBase.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, comparacion))
            throw new InvalidOperationException("Ruta de archivo fuera del almacenamiento.");

        return completa;
    }
}
