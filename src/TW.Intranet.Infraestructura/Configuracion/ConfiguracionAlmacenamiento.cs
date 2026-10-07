namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// Carpeta raíz del almacenamiento de archivos (Almacenamiento:RutaBase).
/// En Railway debe apuntar al volumen persistente, ej. /data/archivos
/// (variable de entorno Almacenamiento__RutaBase). En local, si no se configura,
/// se usa la carpeta "almacenamiento" junto a la API (ignorada por git).
/// </summary>
public record ConfiguracionAlmacenamiento(string RutaBase);
