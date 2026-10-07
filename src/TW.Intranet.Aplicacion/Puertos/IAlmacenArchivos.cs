namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// Almacenamiento de archivos subidos (PDF de procedimientos y, más adelante,
/// fotos y manuales de suministros/equipos o el PDF de propuestas).
/// Las rutas son relativas al almacenamiento, con "/" como separador
/// (ej. "procedimientos/12/20261007_abc.pdf"). Hoy se implementa sobre disco
/// (volumen persistente de Railway). Cambiar a S3/R2 solo requiere otro adaptador.
/// </summary>
public interface IAlmacenArchivos
{
    /// <summary>Guarda el contenido en la ruta indicada. Falla si ya existe un archivo ahí.</summary>
    Task GuardarAsync(string ruta, Stream contenido, CancellationToken ct);

    /// <summary>Abre el archivo para lectura. Devuelve null si no existe.</summary>
    Task<Stream?> AbrirLecturaAsync(string ruta, CancellationToken ct);

    /// <summary>Elimina el archivo si existe.</summary>
    Task EliminarAsync(string ruta, CancellationToken ct);
}
