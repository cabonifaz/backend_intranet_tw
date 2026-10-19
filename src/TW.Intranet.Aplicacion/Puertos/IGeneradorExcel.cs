namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Hoja de un libro Excel: nombre, encabezados y filas (string, números, DateTime, bool o null).</summary>
public record HojaExcel(string Nombre, IReadOnlyList<string> Encabezados, IReadOnlyList<IReadOnlyList<object?>> Filas);

/// <summary>HU-25 — Genera un libro .xlsx con una o varias hojas.</summary>
public interface IGeneradorExcel
{
    byte[] Generar(IReadOnlyList<HojaExcel> hojas);
}
