namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Fila leída de una hoja de cálculo: número de fila (base 1, como en Excel) y el texto de cada celda (A, B, C…).</summary>
public record FilaLeida(int Numero, IReadOnlyList<string> Celdas);

/// <summary>Hoja leída: nombre y filas con algún dato (las filas vacías se omiten).</summary>
public record HojaLeida(string Nombre, IReadOnlyList<FilaLeida> Filas);

/// <summary>Resultado de la lectura: Hoja o Error (nunca lanza excepción por un archivo inválido). ExcedeMaximo = más filas que maxFilas.</summary>
public record ResultadoLecturaHoja(HojaLeida? Hoja, string? Error, bool ExcedeMaximo = false);

/// <summary>Libro leído: todas las hojas visibles (con o sin datos). HojaExcedida = hoja con más filas que el máximo.</summary>
public record ResultadoLecturaLibro(IReadOnlyList<HojaLeida>? Hojas, string? Error, string? HojaExcedida = null);

/// <summary>Lee la primera hoja con datos de un Excel (.xlsx) o un CSV, como texto.</summary>
public interface ILectorHojaCalculo
{
    /// <param name="maxFilas">Si la hoja tiene más filas con datos, devuelve Error.</param>
    ResultadoLecturaHoja Leer(Stream contenido, string nombreArchivo, int maxFilas);

    /// <summary>Lee todas las hojas visibles de un .xlsx (plantillas con varias hojas, ej. Conceptos y Equipos).</summary>
    /// <param name="maxFilasPorHoja">Si una hoja tiene más filas con datos, devuelve Error y HojaExcedida.</param>
    ResultadoLecturaLibro LeerLibro(Stream contenido, string nombreArchivo, int maxFilasPorHoja);
}
