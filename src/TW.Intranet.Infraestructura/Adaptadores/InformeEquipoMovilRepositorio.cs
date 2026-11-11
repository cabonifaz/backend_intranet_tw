using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Cabecera del informe y Hard Stop de cierre del trabajo en el equipo de la app móvil (App Mobile HU-15 / HU-16).</summary>
public class InformeEquipoMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IInformeEquipoMovilRepositorio
{
    /// <summary>Severidad de la falla: la columna nivel_afectacion de la observación (bajo · medio · alto · crítico) ↔ Baja · Media · Alta · Crítica de la app.</summary>
    public static string SeveridadDe(string? nivel) => nivel switch { "bajo" => "baja", "medio" => "media", "alto" => "alta", _ => "critica" };

    /// <summary>Lee el JSON guardado en detalle_servicio; si no es válido, un detalle vacío (la app lo muestra sin marcar).</summary>
    public static (string? Tipo, List<decimal> Celdas, decimal? Suma, decimal? Comp, bool? Anillos) LeerDetalle(string? json)
    {
        var celdas = new List<decimal>();
        if (string.IsNullOrWhiteSpace(json)) return (null, celdas, null, null, null);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var raiz = doc.RootElement;
            if (raiz.ValueKind != JsonValueKind.Object) return (null, celdas, null, null, null);
            string? tipo = raiz.TryGetProperty("tipoEquipo", out var t) && t.ValueKind == JsonValueKind.String && t.GetString() is { Length: > 0 } s ? s : null;
            if (raiz.TryGetProperty("celdas", out var c) && c.ValueKind == JsonValueKind.Array)
                foreach (var x in c.EnumerateArray().Take(12))
                    if (x.ValueKind == JsonValueKind.Number && x.TryGetDecimal(out var d)) celdas.Add(d);
            decimal? Num(string n) => raiz.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetDecimal(out var d) ? d : null;
            bool? anillos = raiz.TryGetProperty("anillosFijacion", out var a) && a.ValueKind is JsonValueKind.True or JsonValueKind.False ? a.GetBoolean() : null;
            return (tipo, celdas, Num("sumatoriaHasta"), Num("comparacionHasta"), anillos);
        }
        catch (JsonException) { return (null, celdas, null, null, null); }
    }

    public Task<RespuestaDto<CabeceraInformeMovilDto>> ObtenerCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<CabeceraInformeMovilDto>("SP_ObtenerCabeceraInformeMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                // 2 · Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<CabeceraInformeMovilDto>(1, "Servicio o equipo no encontrado.");
                var datos = new DatosInformeMovilDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "tipo_orden") ?? "OS", Texto(r, "numero_rq"), EnteroLargoNulo(r, "id_informe"),
                    Texto(r, "numero_informe"), Booleano(r, "generado"), Booleano(r, "puede_editar"),
                    Texto(r, "empresa"), Texto(r, "ruc"), Texto(r, "direccion"), Texto(r, "contacto"), Texto(r, "contacto_cargo"), Texto(r, "contacto_telefono"), Texto(r, "contacto_correo"),
                    Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "num_serie"), Texto(r, "codigo_cliente"), Texto(r, "codigo_tw"), Texto(r, "capacidad_max"), Texto(r, "d"), Texto(r, "e"),
                    Texto(r, "ubicacion"), Texto(r, "clase"),
                    Texto(r, "propuesta"), Texto(r, "comercial"), Texto(r, "tecnico"), Fecha(r, "fecha"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"), Texto(r, "tipo_servicio"),
                    Texto(r, "responsable_nombre"), Texto(r, "responsable_cargo"), Texto(r, "responsable_telefono"), FechaHora(r, "guardada_en"));
                var det = LeerDetalle(Texto(r, "detalle_servicio"));
                var guardado = !EsNulo(r, "detalle_servicio");
                var tipoEquipoEquipo = Texto(r, "tipo_equipo");
                var comentario = Texto(r, "comentario_pruebas");
                var sinRec = Booleano(r, "sin_recomendaciones");
                var sinFal = Booleano(r, "sin_fallas");
                var diag = new DiagnosticoInformeMovilDto(Texto(r, "severidad_general"), Texto(r, "estado_equipo_final"), Booleano(r, "rev_jefatura"),
                    Booleano(r, "requiere_precotizacion"), Booleano(r, "segunda_visita"), Booleano(r, "aplica_garantia"));
                var errorCritico = Texto(r, "error_critico");
                var finalizado = !EsNulo(r, "ensayos_finalizados_en");

                // 3 · Checklist
                await r.NextResultAsync(ct);
                var checklist = new List<PasoChecklistMovilDto>();
                while (await r.ReadAsync(ct))
                    checklist.Add(new PasoChecklistMovilDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "titulo") ?? string.Empty, Entero(r, "orden"), Booleano(r, "marcado")));

                // 4 · Recomendaciones
                await r.NextResultAsync(ct);
                var recomendaciones = new List<RecomendacionInformeMovilDto>();
                while (await r.ReadAsync(ct))
                    recomendaciones.Add(new RecomendacionInformeMovilDto(EnteroLargo(r, "id_recomendacion"), Texto(r, "codigo") ?? string.Empty, Texto(r, "titulo") ?? string.Empty,
                        Texto(r, "descripcion"), Texto(r, "prioridad") ?? "alta", Texto(r, "plazo")));

                // 5 · Fallas (sin fotos ni pruebas todavía)
                await r.NextResultAsync(ct);
                var cabFallas = new List<(long Id, string Codigo, string Cla, string Com, string? ClaN, string? ComN, string Des, string Sev)>();
                while (await r.ReadAsync(ct))
                    cabFallas.Add((EnteroLargo(r, "id_observacion"), Texto(r, "codigo") ?? string.Empty, Texto(r, "clasificacion") ?? string.Empty, Texto(r, "componente") ?? string.Empty,
                        Texto(r, "clasificacion_nombre"), Texto(r, "componente_nombre"), Texto(r, "descripcion") ?? string.Empty, SeveridadDe(Texto(r, "nivel_afectacion"))));

                // 6 · Fotos de las fallas
                await r.NextResultAsync(ct);
                var fotos = new List<(long Obs, long Ev)>();
                while (await r.ReadAsync(ct)) fotos.Add((EnteroLargo(r, "id_observacion"), EnteroLargo(r, "id_evidencia")));

                // 7 · Pruebas de las fallas
                await r.NextResultAsync(ct);
                var pruebas = new List<(long Obs, PruebaFallaMovilDto P)>();
                while (await r.ReadAsync(ct))
                    pruebas.Add((EnteroLargo(r, "id_observacion"), new PruebaFallaMovilDto(Texto(r, "tipo") ?? "pesaje", Entero(r, "orden"), EnteroNulo(r, "posicion"),
                        DecimalNulo(r, "carga") ?? 0m, DecimalNulo(r, "indicacion") ?? 0m, DecimalNulo(r, "error") ?? 0m, DecimalNulo(r, "emp"), Texto(r, "resultado"))));
                var fallas = cabFallas.Select(f => new FallaInformeMovilDto(f.Id, f.Codigo, f.Cla, f.Com, f.ClaN, f.ComN, f.Des, f.Sev,
                    fotos.Where(x => x.Obs == f.Id).Select(x => x.Ev).ToList(), pruebas.Where(x => x.Obs == f.Id).Select(x => x.P).ToList())).ToList();

                // 8 · Pruebas generales (Ensayos y Calibración, HU-10)
                await r.NextResultAsync(ct);
                var pesaje = new List<LecturaGeneralMovilDto>();
                var grupos = new SortedDictionary<int, (decimal? Carga, List<LecturaGeneralMovilDto> Lecturas)>();
                while (await r.ReadAsync(ct))
                {
                    var lectura = new LecturaGeneralMovilDto(Entero(r, "orden"), DecimalNulo(r, "carga"), DecimalNulo(r, "lectura"), DecimalNulo(r, "error"), DecimalNulo(r, "tolerancia"),
                        Texto(r, "resultado"), Booleano(r, "critico"));
                    if (Texto(r, "tipo") == "pesaje") { pesaje.Add(lectura); continue; }
                    var g = Entero(r, "grupo");
                    if (!grupos.TryGetValue(g, out var existente)) grupos[g] = existente = (lectura.Carga, []);
                    existente.Lecturas.Add(lectura);
                }
                var excentricidad = grupos.Select(g => new CargaExcentricidadMovilDto(g.Key, g.Value.Carga, g.Value.Lecturas)).ToList();

                // 9 · Opciones
                await r.NextResultAsync(ct);
                var tipos = new List<OpcionInformeMovilDto>();
                var clasificaciones = new List<OpcionInformeMovilDto>();
                var componentes = new List<OpcionInformeMovilDto>();
                while (await r.ReadAsync(ct))
                {
                    var o = new OpcionInformeMovilDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "padre"));
                    switch (Texto(r, "lista"))
                    {
                        case "tipo_equipo": tipos.Add(o with { Clasificacion = null }); break;
                        case "clasificacion": clasificaciones.Add(o with { Clasificacion = null }); break;
                        default: componentes.Add(o); break;
                    }
                }

                var detalle = new DetalleServicioInformeMovilDto(det.Tipo ?? tipoEquipoEquipo, det.Celdas, det.Suma, det.Comp, det.Anillos, guardado, checklist);
                return new RespuestaDto<CabeceraInformeMovilDto>(2, mensaje, new CabeceraInformeMovilDto(datos, detalle, recomendaciones, sinRec, fallas, sinFal,
                    new PruebasGeneralesMovilDto(finalizado, errorCritico, pesaje, excentricidad), comentario, diag, new OpcionesInformeMovilDto(tipos, clasificaciones, componentes)));
            }, ct);

    public Task<RespuestaDto<ResultadoGuardarCabeceraMovilDto>> GuardarCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, string json, CancellationToken ct) =>
        EjecutarAsync<ResultadoGuardarCabeceraMovilDto>("SP_GuardarCabeceraInformeMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_json",         json);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ResultadoGuardarCabeceraMovilDto>(1, "No se pudo guardar la cabecera del informe.");
                return new RespuestaDto<ResultadoGuardarCabeceraMovilDto>(2, mensaje,
                    new ResultadoGuardarCabeceraMovilDto(EnteroLargo(r, "id_informe"), FechaHora(r, "guardada_en"), Entero(r, "n_fallas"), Entero(r, "n_recomendaciones")));
            }, ct);

    public Task<RespuestaDto<FotoFallaMovilDto>> RegistrarFotoFallaAsync(
        long idUsuario, long idOs, long idOsEquipo, string rutaArchivo, decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, CancellationToken ct) =>
        EjecutarAsync<FotoFallaMovilDto>("SP_RegistrarFotoFallaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_os",         idOs);
                p.AddWithValue("p_id_os_equipo",  idOsEquipo);
                p.AddWithValue("p_ruta_archivo",  rutaArchivo);
                p.AddWithValue("p_latitud",       Valor(latitud));
                p.AddWithValue("p_longitud",      Valor(longitud));
                p.AddWithValue("p_precision",     Valor(precision));
                p.AddWithValue("p_capturado_utc", Valor(capturadoUtc));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<FotoFallaMovilDto>(1, "No se pudo guardar la foto.");
                return new RespuestaDto<FotoFallaMovilDto>(2, mensaje, new FotoFallaMovilDto(EnteroLargo(r, "id_evidencia")));
            }, ct);

    public Task<RespuestaDto<CierreEquipoMovilDto>> ValidarCierreAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<CierreEquipoMovilDto>("SP_ValidarCierreEquipoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<CierreEquipoMovilDto>(1, "Servicio o equipo no encontrado.");
                var puede = Booleano(r, "puede_generar");
                var ya = Booleano(r, "ya_generado");
                var numeroInforme = Texto(r, "numero_informe");
                var conformes = Entero(r, "conformes");
                var total = Entero(r, "total");
                var pendientes = Entero(r, "pendientes");
                var estadoEquipo = Texto(r, "estado_equipo") ?? "en_ejecucion";
                var equipo = Texto(r, "equipo") ?? "Equipo";
                var numeroOs = Texto(r, "numero_os") ?? string.Empty;

                await r.NextResultAsync(ct);
                var etapas = new List<(int Orden, string Codigo, string Nombre, string Estado, string? Detalle)>();
                while (await r.ReadAsync(ct))
                    etapas.Add((Entero(r, "orden"), Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "estado") ?? "pendiente", Texto(r, "detalle")));

                await r.NextResultAsync(ct);
                var textos = new List<(int Orden, string Texto)>();
                while (await r.ReadAsync(ct)) textos.Add((Entero(r, "orden"), Texto(r, "texto") ?? string.Empty));

                var lista = etapas.Select(e => new EtapaCierreMovilDto(e.Orden, e.Codigo, e.Nombre, e.Estado, e.Detalle, textos.Where(t => t.Orden == e.Orden).Select(t => t.Texto).ToList())).ToList();
                return new RespuestaDto<CierreEquipoMovilDto>(2, mensaje, new CierreEquipoMovilDto(puede, ya, numeroInforme, conformes, total, pendientes, estadoEquipo, equipo, numeroOs, lista));
            }, ct);

    public Task<RespuestaDto<InformeGeneradoMovilDto>> GenerarInformeAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<InformeGeneradoMovilDto>("SP_GenerarInformeEquipoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<InformeGeneradoMovilDto>(1, "No se pudo generar el informe técnico.");
                return new RespuestaDto<InformeGeneradoMovilDto>(2, mensaje,
                    new InformeGeneradoMovilDto(EnteroLargo(r, "id_informe"), Texto(r, "numero_informe") ?? string.Empty, Texto(r, "estado_equipo") ?? "completado", Booleano(r, "repetida")));
            }, ct);
}
