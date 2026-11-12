using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>App Mobile HU-27 (rendir gastos) y HU-31 (bandeja del jefe: evidencias, ensayos y gastos). Todo pasa por SPs parametrizados.</summary>
public class GastosAprobacionesMovilRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IGastosAprobacionesMovilRepositorio
{
    private static bool? Logico(MySqlDataReader r, string c) => DecimalNulo(r, c) is { } v ? v != 0 : null;

    // ── Técnico ─────────────────────────────────────────────────────────────────────────────

    public Task<RespuestaDto<ResultadoGastoMovilDto>> RendirGastoAsync(long idUsuario, ComandoGastoMovil c, CancellationToken ct)
        => EjecutarAsync("SP_RendirGastoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_gasto",        c.IdGasto);
                p.AddWithValue("p_id_cliente_app",  Valor(c.IdCliente));
                p.AddWithValue("p_origen",          c.Origen);
                p.AddWithValue("p_id_os",           c.IdOs);
                p.AddWithValue("p_id_concepto",     Valor(c.IdConcepto));
                p.AddWithValue("p_concepto_texto",  Valor(c.ConceptoTexto));
                p.AddWithValue("p_monto",           c.Monto);
                p.AddWithValue("p_fecha_gasto",     c.FechaGasto.ToDateTime(TimeOnly.MinValue));
                p.AddWithValue("p_descripcion",     Valor(c.Descripcion));
                p.AddWithValue("p_reparto",         Valor(c.RepartoJson));
                p.AddWithValue("p_motivo_sin_foto", Valor(c.MotivoSinFoto));
                p.AddWithValue("p_fotos_nuevas",    System.Text.Json.JsonSerializer.Serialize(c.FotosNuevas));
                p.AddWithValue("p_fotos_conservar", Valor(c.FotosConservarJson));
                p.AddWithValue("p_monto_ia",        Valor(c.MontoIa));
                p.AddWithValue("p_coincide_ia",     c.CoincideIa is null ? DBNull.Value : Bit(c.CoincideIa.Value));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoGastoMovilDto>(3, "El gasto se guardó pero el procedimiento no devolvió su detalle.");
                var id = EnteroLargo(r, "id_gasto"); var codigo = Texto(r, "codigo") ?? ""; var estado = Texto(r, "estado") ?? "pendiente";
                var duplicado = Booleano(r, "duplicado");
                var advertencias = new List<string>();
                if (await r.NextResultAsync(ct))
                    while (await r.ReadAsync(ct))
                        if (Texto(r, "advertencia") is { } a) advertencias.Add(a);
                return new RespuestaDto<ResultadoGastoMovilDto>(2, mensaje,
                    new ResultadoGastoMovilDto(id, codigo, estado, duplicado, advertencias, c.MontoIa, c.CoincideIa));
            },
            ct);

    public Task<RespuestaDto<string>> ObtenerRutaFotoGastoAsync(long idUsuario, long idGasto, int n, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerFotoGastoMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_gasto", idGasto); p.AddWithValue("p_n", n); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct) && Texto(r, "ruta") is { } ruta
                    ? new RespuestaDto<string>(2, mensaje, ruta)
                    : new RespuestaDto<string>(1, "El gasto no tiene esa foto.");
            },
            ct);

    // ── Jefe ────────────────────────────────────────────────────────────────────────────────

    public Task<RespuestaDto<List<AprobacionMovilDto>>> ObtenerAprobacionesExtraAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAprobacionesExtraMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<AprobacionMovilDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new AprobacionMovilDto(Texto(r, "tipo") ?? "", EnteroLargo(r, "id"), Texto(r, "titulo") ?? "",
                        Texto(r, "numero_os") ?? "", Texto(r, "tecnico"), Texto(r, "cliente"), Texto(r, "detalle"),
                        Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), Booleano(r, "urgente"), FechaHora(r, "solicitada_en")));
                return new RespuestaDto<List<AprobacionMovilDto>>(2, mensaje, items);
            },
            ct);

    public Task<RespuestaDto<DetalleAprobacionMovilDto>> ObtenerDetalleAsync(long idUsuario, string tipo, long id, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAprobacionDetalleMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_tipo", tipo); p.AddWithValue("p_id", id); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleAprobacionMovilDto>(1, "No se encontró la aprobación o no corresponde a tu área.");
                var cab = new CabeceraAprobacionMovilDto(
                    Texto(r, "tipo") ?? tipo, EnteroLargo(r, "id"), Texto(r, "titulo") ?? "", Texto(r, "estado") ?? "pendiente",
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? "", Texto(r, "cliente"), Texto(r, "sede"), Texto(r, "tecnico"),
                    Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), FechaHora(r, "solicitada_en"), Texto(r, "motivo"), Texto(r, "detalle"),
                    Texto(r, "comentario"), Texto(r, "resuelto_por"), FechaHora(r, "resuelto_en"), Booleano(r, "puede_resolver"),
                    Texto(r, "codigo_evidencia"), Texto(r, "motivo_rechazo_ia"), Logico(r, "es_video"),
                    Texto(r, "equipo"), EnteroNulo(r, "n_criticas"),
                    Texto(r, "codigo"), Texto(r, "origen"), Texto(r, "concepto"), DecimalNulo(r, "monto"), Fecha(r, "fecha_gasto"),
                    Texto(r, "descripcion"), Texto(r, "motivo_sin_foto"), DecimalNulo(r, "monto_ia"), Logico(r, "coincide_ia"),
                    Texto(r, "codigo_programacion"));

                // 3. Líneas: reparto (gasto) o lecturas fuera del EMP (ensayo)
                var reparto = new List<RepartoGastoMovilDto>();
                var lecturas = new List<LecturaEnsayoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                {
                    if (cab.Tipo == "gasto")
                        reparto.Add(new RepartoGastoMovilDto(cab.Id, EnteroLargo(r, "id_viatico_linea"), Texto(r, "concepto") ?? "", DecimalNulo(r, "monto") ?? 0m));
                    else if (cab.Tipo == "ensayo")
                        lecturas.Add(new LecturaEnsayoMovilDto(Texto(r, "tipo"), Texto(r, "punto"), DecimalNulo(r, "carga"), DecimalNulo(r, "lectura"),
                            DecimalNulo(r, "error"), DecimalNulo(r, "tolerancia")));
                }

                // 4. Fotos
                var fotos = new List<FotoAprobacionMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    fotos.Add(new FotoAprobacionMovilDto(Entero(r, "orden"), Booleano(r, "es_video"), Booleano(r, "tiene_cuadro")));

                return new RespuestaDto<DetalleAprobacionMovilDto>(2, mensaje, new DetalleAprobacionMovilDto(cab, reparto, lecturas, fotos));
            },
            ct);

    public Task<RespuestaDto<ArchivoAprobacionMovilDto>> ObtenerArchivoAsync(long idUsuario, string tipo, long id, int n, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerArchivoAprobacionMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_tipo", tipo); p.AddWithValue("p_id", id); p.AddWithValue("p_n", n); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct) && Texto(r, "ruta") is { } ruta
                    ? new RespuestaDto<ArchivoAprobacionMovilDto>(2, mensaje, new ArchivoAprobacionMovilDto(ruta, Texto(r, "ruta_cuadro"), Booleano(r, "es_video")))
                    : new RespuestaDto<ArchivoAprobacionMovilDto>(1, "Archivo no encontrado.");
            },
            ct);

    public Task<RespuestaDto<bool>> ResolverEvidenciaAsync(long idUsuario, long idEvidencia, bool aprobar, string? comentario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverEvidenciaForzada",
            p =>
            {
                p.AddWithValue("p_id_jefe",      idUsuario);
                p.AddWithValue("p_id_os",        DBNull.Value);   // la OS se toma de la evidencia
                p.AddWithValue("p_id_evidencia", idEvidencia);
                p.AddWithValue("p_aprobar",      Bit(aprobar));
                p.AddWithValue("p_comentario",   Valor(comentario));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)),
            ct);

    public Task<RespuestaDto<bool>> ResolverEnsayoAsync(long idUsuario, long idInforme, bool aprobar, string? comentario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverEnsayoConError",
            p =>
            {
                p.AddWithValue("p_id_jefe",    idUsuario);
                p.AddWithValue("p_id_os",      DBNull.Value);     // la OS se toma del informe
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_aprobar",    Bit(aprobar));
                p.AddWithValue("p_comentario", Valor(comentario));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)),
            ct);

    public Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoAsync(long idUsuario, long idGasto, string accion, string? comentario, CancellationToken ct)
        => EjecutarAsync("SP_RevisarGastoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_gasto",   idGasto);
                p.AddWithValue("p_accion",     accion);
                p.AddWithValue("p_comentario", Valor(comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RevisarGastoResultadoDto>(3, "El cambio se guardó pero el procedimiento no devolvió su detalle.");
                var idProg = EnteroLargo(r, "id_programacion"); var g = EnteroLargo(r, "id_gasto");
                var estado = Texto(r, "estado") ?? ""; var tec = EnteroLargo(r, "id_tecnico");
                await r.NextResultAsync(ct);
                var resumen = await r.ReadAsync(ct) ? ProgramacionViaticosRepositorio.LeerResumen(r) : ProgramacionViaticosRepositorio.ResumenVacio;
                return new RespuestaDto<RevisarGastoResultadoDto>(2, mensaje, new RevisarGastoResultadoDto(idProg, g, estado, tec, resumen));
            },
            ct);
}
