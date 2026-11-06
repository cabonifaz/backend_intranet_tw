using System.Text.Json;
using System.Text.Json.Serialization;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Revisión Técnica (HU-56 a HU-59) y Precotizaciones Técnicas (HU-60). Las filas de los SPs se leen a los DTOs por nombre
/// de columna (snake_case → PascalCase), así que un SP puede sumar columnas sin romper el mapeo.
/// </summary>
public class RevisionTecnicaRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IRevisionTecnicaRepositorio
{
    // ── Servicio Técnico › Revisión de Informes ───────────────────────────────────────────────

    public Task<RespuestaDto<BandejaInformesDto>> ObtenerBandejaAsync(FiltrosBandejaInformesDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaInformesTecnicos",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_grupo",             Valor(f.Grupo));
                p.AddWithValue("p_busqueda",          Valor(f.Busqueda));
                p.AddWithValue("p_id_tecnico",        Valor(f.IdTecnico));
                p.AddWithValue("p_id_cliente",        Valor(f.IdCliente));
                p.AddWithValue("p_con_observaciones", f.ConObservaciones is null ? DBNull.Value : Bit(f.ConObservaciones.Value));
                p.AddWithValue("p_sla_vencido",       Bit(f.SlaVencido));
                p.AddWithValue("p_fecha_desde",       f.FechaDesde is null ? DBNull.Value : f.FechaDesde.Value.Date);
                p.AddWithValue("p_fecha_hasta",       f.FechaHasta is null ? DBNull.Value : f.FechaHasta.Value.Date);
                p.AddWithValue("p_pagina",            f.Pagina);
                p.AddWithValue("p_por_pagina",        f.PorPagina);
                p.AddWithValue("p_exportar",          Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = await LeerUnaAsync<TarjetasInformesDto>(r, ct) ?? new TarjetasInformesDto();
                await r.NextResultAsync(ct);
                var items = await LeerFilasAsync<ItemBandejaInformeDto>(r, ct);
                var total = await LeerTotalAsync(r, ct);
                await r.NextResultAsync(ct);
                var tecnicos = await LeerFilasAsync<OpcionInformeDto>(r, ct);
                await r.NextResultAsync(ct);
                var clientes = await LeerFilasAsync<OpcionInformeDto>(r, ct);
                return new RespuestaDto<BandejaInformesDto>(2, mensaje,
                    new BandejaInformesDto(tarjetas, items, total, f.Pagina, f.PorPagina, tecnicos, clientes));
            }, ct);

    public Task<RespuestaDto<DetalleInformeTecnicoDto>> ObtenerDetalleAsync(long idInforme, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleInformeTecnico",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraInformeDto>(r, ct);
                if (cabecera is null) return new RespuestaDto<DetalleInformeTecnicoDto>(1, "El informe no existe o no está en tu alcance.");
                await r.NextResultAsync(ct); var pasos   = await LeerFilasAsync<PasoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var ensayos = await LeerFilasAsync<EnsayoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var obs     = await LeerFilasAsync<ObservacionInformeDto>(r, ct);
                await r.NextResultAsync(ct); var recs    = await LeerFilasAsync<RecomendacionInformeDto>(r, ct);
                await r.NextResultAsync(ct); var fotos   = await LeerFilasAsync<FotoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var precot  = await LeerFilasAsync<ItemPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var hist    = await LeerFilasAsync<EventoRecienteDto>(r, ct);
                return new RespuestaDto<DetalleInformeTecnicoDto>(2, mensaje,
                    new DetalleInformeTecnicoDto(cabecera, pasos, ensayos, obs, recs, fotos, precot, hist));
            }, ct);

    public Task<RespuestaDto<InformeGuardadoDto>> GuardarInformeAsync(long idInforme, GuardarInformeTecnicoDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarInformeTecnico",
            p =>
            {
                p.AddWithValue("p_id_usuario",          idUsuario);
                p.AddWithValue("p_id_informe",          idInforme);
                p.AddWithValue("p_cambiar_descripcion", Bit(d.DescripcionComplementaria is not null));
                p.AddWithValue("p_descripcion",         (object?)d.DescripcionComplementaria ?? DBNull.Value);
                p.AddWithValue("p_resultado",           Json(d.Resultado));
                p.AddWithValue("p_procedimientos",      Json(d.Procedimiento));
                p.AddWithValue("p_ensayos",             Json(d.Ensayos));
                p.AddWithValue("p_observaciones",       Json(d.Observaciones));
                p.AddWithValue("p_recomendaciones",     Json(d.Recomendaciones));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var fila = await LeerUnaAsync<InformeGuardadoDto>(r, ct);
                return new RespuestaDto<InformeGuardadoDto>(2, mensaje, fila);
            }, ct);

    public Task<RespuestaDto<PrecotizacionGuardadaDto>> GuardarPrecotizacionAsync(long idInforme, GuardarPrecotizacionInformeDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarPrecotizacionInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_nota",       Valor(d.Nota));
                p.AddWithValue("p_items",      Json(d.Items));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var fila = await LeerUnaAsync<PrecotizacionGuardadaDto>(r, ct);
                return new RespuestaDto<PrecotizacionGuardadaDto>(2, mensaje, fila);
            }, ct);

    public Task<RespuestaDto<PreparacionRevisionInformeDto>> PrepararRevisionAsync(long idInforme, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararRevisionInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraRevisionInformeDto>(r, ct) ?? new CabeceraRevisionInformeDto();
                await r.NextResultAsync(ct);
                var checklist = await LeerFilasAsync<ItemChecklistRevisionDto>(r, ct);
                return new RespuestaDto<PreparacionRevisionInformeDto>(2, mensaje, new PreparacionRevisionInformeDto(cabecera, checklist));
            }, ct);

    public Task<RespuestaDto<InformeRevisadoDto>> RegistrarRevisionAsync(long idInforme, string? nota, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarRevisionInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_nota",       Valor(nota));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<InformeRevisadoDto>(2, mensaje, await LeerUnaAsync<InformeRevisadoDto>(r, ct));
            }, ct);

    public Task<RespuestaDto<HistorialInformeDto>> ObtenerHistorialAsync(long idInforme, string? categoria, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerHistorialInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_categoria",  Valor(categoria));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var contadores = await LeerUnaAsync<ContadoresHistorialInformeDto>(r, ct) ?? new ContadoresHistorialInformeDto();
                await r.NextResultAsync(ct);
                var eventos = await LeerFilasAsync<EventoHistorialInformeDto>(r, ct);
                return new RespuestaDto<HistorialInformeDto>(2, mensaje, new HistorialInformeDto(contadores, eventos));
            }, ct);

    // ── CRM › Precotizaciones Técnicas ────────────────────────────────────────────────────────

    public Task<RespuestaDto<BandejaPrecotizacionesDto>> ObtenerBandejaPrecotizacionesAsync(FiltrosPrecotizacionesDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaPrecotizaciones",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_estado",        Valor(f.Estado));
                p.AddWithValue("p_busqueda",      Valor(f.Busqueda));
                p.AddWithValue("p_id_supervisor", Valor(f.IdSupervisor));
                p.AddWithValue("p_fecha_desde",   f.FechaDesde is null ? DBNull.Value : f.FechaDesde.Value.Date);
                p.AddWithValue("p_fecha_hasta",   f.FechaHasta is null ? DBNull.Value : f.FechaHasta.Value.Date);
                p.AddWithValue("p_pagina",        f.Pagina);
                p.AddWithValue("p_por_pagina",    f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = await LeerUnaAsync<TarjetasPrecotizacionesDto>(r, ct) ?? new TarjetasPrecotizacionesDto();
                await r.NextResultAsync(ct);
                var items = await LeerFilasAsync<ItemBandejaPrecotizacionDto>(r, ct);
                var total = await LeerTotalAsync(r, ct);
                await r.NextResultAsync(ct);
                var supervisores = await LeerFilasAsync<OpcionInformeDto>(r, ct);
                return new RespuestaDto<BandejaPrecotizacionesDto>(2, mensaje,
                    new BandejaPrecotizacionesDto(tarjetas, items, total, f.Pagina, f.PorPagina, supervisores));
            }, ct);

    public Task<RespuestaDto<DetallePrecotizacionDto>> ObtenerDetallePrecotizacionAsync(long idPrecotizacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetallePrecotizacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_precotizacion", idPrecotizacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraPrecotizacionDto>(r, ct);
                if (cabecera is null) return new RespuestaDto<DetallePrecotizacionDto>(1, "La precotización no existe o no está en tu alcance.");
                await r.NextResultAsync(ct); var obs   = await LeerFilasAsync<ObservacionPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var items = await LeerFilasAsync<ItemPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var traza = await LeerFilasAsync<PasoTrazabilidadPrecotizacionDto>(r, ct);
                return new RespuestaDto<DetallePrecotizacionDto>(2, mensaje, new DetallePrecotizacionDto(cabecera, obs, items, traza));
            }, ct);

    public Task<RespuestaDto<PrecargaPrecotizacionDto>> ObtenerPrecargaPrecotizacionAsync(long idPrecotizacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPrecargaPrecotizacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_precotizacion", idPrecotizacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraPrecargaPrecotizacionDto>(r, ct) ?? new CabeceraPrecargaPrecotizacionDto();
                await r.NextResultAsync(ct);
                var items = await LeerFilasAsync<ItemPrecargaPrecotizacionDto>(r, ct);
                return new RespuestaDto<PrecargaPrecotizacionDto>(2, mensaje, new PrecargaPrecotizacionDto(cabecera, items));
            }, ct);

    public Task<RespuestaDto<PrecotizacionConvertidaDto>> ConvertirPrecotizacionAsync(long idPrecotizacion, long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ConvertirPrecotizacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_precotizacion", idPrecotizacion);
                p.AddWithValue("p_id_propuesta",     idPropuesta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<PrecotizacionConvertidaDto>(2, mensaje, await LeerUnaAsync<PrecotizacionConvertidaDto>(r, ct));
            }, ct);

    // ── Lectura genérica de filas ─────────────────────────────────────────────────────────────

    private static readonly JsonSerializerOptions OpcionesLectura = new()
    {
        PropertyNamingPolicy        = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        NumberHandling              = JsonNumberHandling.AllowReadingFromString,
        Converters                  = { new BooleanoFlexible() },
    };

    private static readonly JsonSerializerOptions OpcionesEscritura = new(JsonSerializerDefaults.Web);

    private static object Json<TV>(TV? valor) where TV : class
        => valor is null ? DBNull.Value : JsonSerializer.Serialize(valor, OpcionesEscritura);

    private static T LeerFila<T>(MySqlDataReader r)
    {
        var fila = new Dictionary<string, object?>(r.FieldCount, StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < r.FieldCount; i++)
        {
            fila[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i) switch
            {
                TimeSpan t => t.ToString(@"hh\:mm"),
                DateOnly d => d.ToDateTime(TimeOnly.MinValue),
                byte[] b   => Convert.ToBase64String(b),
                var v      => v,
            };
        }
        return JsonSerializer.Deserialize<T>(JsonSerializer.SerializeToUtf8Bytes(fila), OpcionesLectura)!;
    }

    private static async Task<List<T>> LeerFilasAsync<T>(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<T>();
        while (await r.ReadAsync(ct)) lista.Add(LeerFila<T>(r));
        return lista;
    }

    private static async Task<T?> LeerUnaAsync<T>(MySqlDataReader r, CancellationToken ct) where T : class
        => await r.ReadAsync(ct) ? LeerFila<T>(r) : null;

    /// <summary>MySQL devuelve los indicadores como 0/1 (BIGINT o TINYINT): se aceptan número, texto o booleano.</summary>
    private sealed class BooleanoFlexible : JsonConverter<bool>
    {
        public override bool Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) => reader.TokenType switch
        {
            JsonTokenType.True   => true,
            JsonTokenType.False  => false,
            JsonTokenType.Number => reader.TryGetDecimal(out var n) && n != 0,
            JsonTokenType.String => reader.GetString() is { } s && (s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase)),
            _                    => false,
        };

        public override void Write(Utf8JsonWriter writer, bool value, JsonSerializerOptions options) => writer.WriteBooleanValue(value);
    }
}
