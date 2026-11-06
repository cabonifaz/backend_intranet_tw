using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-51 Bandeja de Seguimiento Operativo (Sprint 5). Solo lectura: todo pasa por SPs parametrizados.</summary>
public class SeguimientoOperativoRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), ISeguimientoOperativoRepositorio
{
    private static readonly OpcionCodigoSeguimientoDto[] EstadosCatalogo =
    [
        new("sin_salir", "Sin salir"), new("en_ruta", "En ruta"), new("en_planta", "En planta"), new("en_ejecucion", "En ejecución"),
        new("con_demora", "Con demora"), new("con_incidente", "Con incidente"), new("finalizado", "Finalizado"),
    ];

    private static void Filtros(MySqlParameterCollection p, ConsultaSeguimientoNormalizada q, long idUsuario)
    {
        p.AddWithValue("p_id_usuario", idUsuario);
        p.AddWithValue("p_id_tecnico", Valor(q.IdTecnico));
        p.AddWithValue("p_id_cliente", Valor(q.IdCliente));
        p.AddWithValue("p_estado",     Valor(q.Estado));
        p.AddWithValue("p_zona",       Valor(q.Zona));
        p.AddWithValue("p_busqueda",   Valor(q.Busqueda));
    }

    public Task<RespuestaDto<ResumenSeguimientoDto>> ObtenerResumenAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerResumenSeguimiento",
            p => Filtros(p, q, idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResumenSeguimientoDto>(3, "El procedimiento no devolvió los indicadores.");
                var kpis = new KpisBandejaSeguimientoDto(Entero(r, "Programados"), Entero(r, "TecnicosEnRuta"), Entero(r, "EnPlanta"), Entero(r, "EnEjecucion"),
                    Entero(r, "ConDemoraIncidente"), Entero(r, "Finalizados"), Entero(r, "SinSalir"), Entero(r, "ServiciosFiltrados"),
                    Entero(r, "TecnicosActivos"), Entero(r, "IncidenciasDelDia"), Texto(r, "Actualizado") ?? "", Entero(r, "RefrescoSegundos"));

                await r.NextResultAsync(ct);
                var pines = new List<PinMapaDto>();
                while (await r.ReadAsync(ct))
                    pines.Add(new PinMapaDto(EnteroLargo(r, "IdUsuario"), Texto(r, "Tecnico") ?? "", Texto(r, "Iniciales") ?? "", Texto(r, "Estado") ?? "",
                        DecimalNulo(r, "Latitud"), DecimalNulo(r, "Longitud"), Texto(r, "Direccion") ?? "", EnteroNulo(r, "MinutosUbicacion"),
                        EnteroLargoNulo(r, "IdOs"), Texto(r, "NumeroOs"), Texto(r, "Cliente")));

                await r.NextResultAsync(ct);
                var alertas = new List<AlertaSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    alertas.Add(new AlertaSeguimientoDto(Texto(r, "Clave") ?? "", Texto(r, "Tipo") ?? "", Texto(r, "Severidad") ?? "", Texto(r, "Titulo") ?? "",
                        Texto(r, "Detalle") ?? "", Entero(r, "Minutos"), Booleano(r, "Nueva"), EnteroLargo(r, "IdUsuario"), Texto(r, "Tecnico") ?? "",
                        EnteroLargo(r, "IdOs"), Texto(r, "NumeroOs") ?? ""));

                await r.NextResultAsync(ct);
                var totales = new TotalesAlertasDto(0, 0, 0);
                if (await r.ReadAsync(ct))
                    totales = new TotalesAlertasDto(Entero(r, "Total"), Entero(r, "Nuevas"), Entero(r, "Criticas"));

                await r.NextResultAsync(ct);
                var hitos = new List<HitoEsperadoDto>();
                while (await r.ReadAsync(ct))
                    hitos.Add(new HitoEsperadoDto(EnteroLargo(r, "IdOs"), Texto(r, "NumeroOs") ?? "", Texto(r, "Tipo") ?? "", Texto(r, "Hora") ?? "",
                        Texto(r, "Texto") ?? "", Texto(r, "Detalle") ?? "", Booleano(r, "Atrasado"), EnteroLargoNulo(r, "IdTecnico")));

                await r.NextResultAsync(ct);
                var resumenHitos = new ResumenHitosDto(true, 0);
                if (await r.ReadAsync(ct))
                    resumenHitos = new ResumenHitosDto(Booleano(r, "TodosOcurrieron"), Entero(r, "Pendientes"));

                return new RespuestaDto<ResumenSeguimientoDto>(2, mensaje, new ResumenSeguimientoDto(kpis, pines, alertas, totales, hitos, resumenHitos));
            },
            ct);

    public Task<RespuestaDto<ServiciosSeguimientoDto>> ObtenerServiciosAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerServiciosSeguimiento",
            p =>
            {
                Filtros(p, q, idUsuario);
                p.AddWithValue("p_rango",  Valor(q.Rango));
                p.AddWithValue("p_pagina", q.Pagina);
                p.AddWithValue("p_tamano", q.Tamano);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ServiciosSeguimientoDto>(3, "El procedimiento no devolvió los totales.");
                int total = Entero(r, "Total"), pagina = Entero(r, "Pagina"), tamano = Entero(r, "Tamano"), paginas = Entero(r, "TotalPaginas");
                var actualizado = Texto(r, "Actualizado");

                await r.NextResultAsync(ct);
                var filas = new List<ServicioSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    filas.Add(new ServicioSeguimientoDto(EnteroLargo(r, "IdOs"), Texto(r, "Numero") ?? "", Texto(r, "Tipo") ?? "OS", Texto(r, "Propuesta"),
                        Texto(r, "Cliente") ?? "", Texto(r, "Ruc"), EnteroLargoNulo(r, "IdTecnico"), Texto(r, "Tecnico"), Texto(r, "Iniciales"),
                        Texto(r, "Estado") ?? "", Texto(r, "Zona"), Texto(r, "HoraInicio"), Texto(r, "UltimaUbicacion"), EnteroNulo(r, "MinutosUbicacion"),
                        Entero(r, "Equipos"), Entero(r, "Ejecutados"), Entero(r, "AvancePct")));

                return new RespuestaDto<ServiciosSeguimientoDto>(2, mensaje, new ServiciosSeguimientoDto(total, pagina, tamano, paginas, actualizado, filas));
            },
            ct);

    public Task<RespuestaDto<TecnicosSeguimientoDto>> ObtenerTecnicosAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerTecnicosSeguimiento",
            p => Filtros(p, q, idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<TecnicosSeguimientoDto>(3, "El procedimiento no devolvió el resumen.");
                int total = Entero(r, "Total"), adicionales = Entero(r, "AdicionalesSinIniciar");
                var actualizado = Texto(r, "Actualizado");

                await r.NextResultAsync(ct);
                var cabeceras = new List<(long Id, Func<IReadOnlyList<ServicioDeTecnicoDto>, TecnicoSeguimientoDto> Crear)>();
                while (await r.ReadAsync(ct))
                {
                    long id = EnteroLargo(r, "IdUsuario");
                    string nombre = Texto(r, "Tecnico") ?? "", iniciales = Texto(r, "Iniciales") ?? "", estado = Texto(r, "Estado") ?? "";
                    string? cargo = Texto(r, "Cargo"), zona = Texto(r, "Zona"), ssoma = Texto(r, "Ssoma"), real = Texto(r, "SalidaReal"),
                            prog = Texto(r, "SalidaProgramada"), ubic = Texto(r, "UltimaUbicacion");
                    int servicios = Entero(r, "Servicios"), completados = Entero(r, "Completados"), enCurso = Entero(r, "EnCurso");
                    int? dif = EnteroNulo(r, "DiferenciaSalidaMin"), minUbic = EnteroNulo(r, "MinutosUbicacion");
                    cabeceras.Add((id, s => new TecnicoSeguimientoDto(id, nombre, iniciales, cargo, zona, estado, ssoma, servicios, completados, enCurso,
                        real, prog, dif, ubic, minUbic, s)));
                }

                await r.NextResultAsync(ct);
                var porTecnico = new Dictionary<long, List<ServicioDeTecnicoDto>>();
                while (await r.ReadAsync(ct))
                {
                    var id = EnteroLargo(r, "IdUsuario");
                    if (!porTecnico.TryGetValue(id, out var lista))
                        porTecnico[id] = lista = [];
                    lista.Add(new ServicioDeTecnicoDto(EnteroLargo(r, "IdOs"), Texto(r, "Numero") ?? "", Texto(r, "Cliente") ?? "", Texto(r, "Estado") ?? "",
                        Texto(r, "HoraInicio"), Texto(r, "HoraFin"), Texto(r, "Rol") ?? "principal", Entero(r, "Equipos"), Entero(r, "Ejecutados")));
                }

                var tecnicos = cabeceras.Select(c => c.Crear(porTecnico.TryGetValue(c.Id, out var l) ? l : [])).ToList();
                return new RespuestaDto<TecnicosSeguimientoDto>(2, mensaje, new TecnicosSeguimientoDto(total, adicionales, actualizado, tecnicos));
            },
            ct);

    public Task<RespuestaDto<IncidenciasSeguimientoDto>> ObtenerIncidenciasAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerIncidenciasSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_tecnico", Valor(q.IdTecnico));
                p.AddWithValue("p_id_cliente", Valor(q.IdCliente));
                p.AddWithValue("p_zona",       Valor(q.Zona));
                p.AddWithValue("p_busqueda",   Valor(q.Busqueda));
                p.AddWithValue("p_tipo",       Valor(q.Tipo));
                p.AddWithValue("p_impacto",    Valor(q.Impacto));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = new TarjetasIncidenciasDto(0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    tarjetas = new TarjetasIncidenciasDto(Entero(r, "Retrasan"), Entero(r, "Detienen"), Entero(r, "RegistradasTecnico"),
                        Entero(r, "RegistradasAsistente"), Entero(r, "Total"));

                await r.NextResultAsync(ct);
                var filas = new List<IncidenciaSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    filas.Add(new IncidenciaSeguimientoDto(Texto(r, "Clave") ?? "", Texto(r, "Hora") ?? "", EnteroLargo(r, "IdUsuario"), Texto(r, "Tecnico") ?? "",
                        Texto(r, "Iniciales") ?? "", EnteroLargo(r, "IdOs"), Texto(r, "Numero") ?? "", Texto(r, "Cliente") ?? "", Texto(r, "TipoCodigo") ?? "",
                        Texto(r, "Tipo") ?? "", Texto(r, "Descripcion"), EnteroNulo(r, "DuracionMin"), Texto(r, "Impacto") ?? "retrasa", Texto(r, "Origen") ?? "tecnico",
                        Texto(r, "Momento")));

                return new RespuestaDto<IncidenciasSeguimientoDto>(2, mensaje, new IncidenciasSeguimientoDto(tarjetas, filas));
            },
            ct);

    public Task<RespuestaDto<OpcionesFiltrosSeguimientoDto>> ObtenerFiltrosAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerFiltrosSeguimiento",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tecnicos = new List<OpcionFiltroSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    tecnicos.Add(new OpcionFiltroSeguimientoDto(EnteroLargo(r, "Id"), Texto(r, "Nombre") ?? ""));
                await r.NextResultAsync(ct);
                var clientes = new List<OpcionFiltroSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    clientes.Add(new OpcionFiltroSeguimientoDto(EnteroLargo(r, "Id"), Texto(r, "Nombre") ?? ""));
                await r.NextResultAsync(ct);
                var zonas = new List<string>();
                while (await r.ReadAsync(ct))
                    zonas.Add(Texto(r, "Nombre") ?? "");
                await r.NextResultAsync(ct);
                var tipos = new List<OpcionCodigoSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    tipos.Add(new OpcionCodigoSeguimientoDto(Texto(r, "Codigo") ?? "", Texto(r, "Nombre") ?? ""));
                return new RespuestaDto<OpcionesFiltrosSeguimientoDto>(2, mensaje, new OpcionesFiltrosSeguimientoDto(tecnicos, clientes, zonas, tipos, EstadosCatalogo));
            },
            ct);

    public Task<RespuestaDto<UbicacionRegistradaDto>> RegistrarUbicacionAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal? precisionMetros, decimal? velocidadKmh, decimal? altitudM, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarUbicacionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_latitud",    latitud);
                p.AddWithValue("p_longitud",   longitud);
                p.AddWithValue("p_precision",  Valor(precisionMetros));
                p.AddWithValue("p_velocidad",  Valor(velocidadKmh));
                p.AddWithValue("p_altitud",    Valor(altitudM));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<UbicacionRegistradaDto>(2, mensaje, new UbicacionRegistradaDto(await r.ReadAsync(ct) && Booleano(r, "Guardada")));
            },
            ct);
}
