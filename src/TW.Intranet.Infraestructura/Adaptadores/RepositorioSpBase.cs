using System.Data;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Base para repositorios que llaman SPs con el patrón del proyecto:
/// 1er resultado = (IdTipoMensaje, Mensaje); si es 2, siguen los datos.
/// </summary>
public abstract class RepositorioSpBase(CadenaConexionBd conexion)
{
    protected async Task<RespuestaDto<T>> EjecutarAsync<T>(
        string sp,
        Action<MySqlParameterCollection> parametros,
        Func<MySqlDataReader, string, Task<RespuestaDto<T>>> leerDatos,
        CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand(sp, conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            parametros(cmd.Parameters);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<T>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = Convert.ToInt32(reader["IdTipoMensaje"]);
            string mensaje = Convert.ToString(reader["Mensaje"]) ?? "";

            if (idTipo != 2)
                return new RespuestaDto<T>(idTipo, mensaje);

            return await leerDatos(reader, mensaje);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<T>(3, ex.Message);
        }
    }

    // ── Parámetros ────────────────────────────────────────────────────────────
    protected static object Valor(string? v) =>
        string.IsNullOrWhiteSpace(v) ? DBNull.Value : v.Trim();

    protected static object Valor<TV>(TV? v) where TV : struct =>
        v.HasValue ? v.Value : DBNull.Value;

    protected static int Bit(bool v) => v ? 1 : 0;

    // ── Lectura segura de columnas ────────────────────────────────────────────
    protected static bool EsNulo(MySqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col));

    protected static string? Texto(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToString(r[col]);

    protected static int Entero(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? 0 : Convert.ToInt32(r[col]);

    protected static int? EnteroNulo(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToInt32(r[col]);

    protected static long EnteroLargo(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? 0 : Convert.ToInt64(r[col]);

    protected static long? EnteroLargoNulo(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToInt64(r[col]);

    protected static decimal? DecimalNulo(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToDecimal(r[col]);

    protected static bool Booleano(MySqlDataReader r, string col) =>
        !EsNulo(r, col) && Convert.ToBoolean(r[col]);

    protected static DateTime? FechaHora(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToDateTime(r[col]);

    /// <summary>Columnas DATE → "yyyy-MM-dd".</summary>
    protected static string? Fecha(MySqlDataReader r, string col)
    {
        if (EsNulo(r, col)) return null;
        return r[col] switch
        {
            DateTime d => d.ToString("yyyy-MM-dd"),
            DateOnly d => d.ToString("yyyy-MM-dd"),
            var otro   => Convert.ToString(otro)
        };
    }

    /// <summary>Lee el resultado de "total" de un SP paginado.</summary>
    protected static async Task<int> LeerTotalAsync(MySqlDataReader r, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        return await r.ReadAsync(ct) ? Entero(r, "total") : 0;
    }
}
