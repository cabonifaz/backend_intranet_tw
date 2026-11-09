using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Lista de objetivos y selección de equipos de la app móvil (App Mobile HU-07).</summary>
public class ObjetivosMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IObjetivosMovilRepositorio
{
    /// <summary>Cambios que se muestran por equipo en "Ver detalles" (los más recientes).</summary>
    private const int CambiosPorEquipo = 5;

    public Task<RespuestaDto<ObjetivosMovilDto>> ObtenerAsync(long idUsuario, long idOs, string buscar, CancellationToken ct) =>
        EjecutarAsync<ObjetivosMovilDto>("SP_ObtenerObjetivosMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_buscar",     Valor(buscar));
            },
            async (r, mensaje) =>
            {
                // 2. Resumen
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ObjetivosMovilDto>(1, "Servicio no encontrado o no asignado a tu usuario.");
                var resumen = new ResumenObjetivosMovilDto(
                    EnteroLargo(r, "id_os"),
                    Texto(r, "numero_os") ?? string.Empty,
                    Texto(r, "estado_os") ?? string.Empty,
                    Texto(r, "cliente"),
                    Texto(r, "sede"),
                    true,                       // sin llegada el SP no entrega objetivos (Hard Stop)
                    FechaHora(r, "salida_en"),
                    FechaHora(r, "llegada_en"),
                    EnteroNulo(r, "traslado_min"),
                    Entero(r, "en_planta_min"),
                    Entero(r, "estimado_min"));

                // 3. Contadores
                await r.NextResultAsync(ct);
                var contadores = await r.ReadAsync(ct)
                    ? new ContadoresObjetivosMovilDto(Entero(r, "completados"), Entero(r, "pendientes"), Entero(r, "observados"), Entero(r, "total"))
                    : new ContadoresObjetivosMovilDto(0, 0, 0, 0);

                // 4. Equipos
                await r.NextResultAsync(ct);
                var equipos = new List<ObjetivoEquipoMovilDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(LeerEquipo(r, []));

                // 5. Cambios (el más reciente primero): se reparten por equipo
                await r.NextResultAsync(ct);
                var cambios = new Dictionary<long, List<CambioEquipoMovilDto>>();
                while (await r.ReadAsync(ct))
                {
                    var id = EnteroLargo(r, "id_os_equipo");
                    if (!cambios.TryGetValue(id, out var lista)) cambios[id] = lista = [];
                    if (lista.Count < CambiosPorEquipo)
                        lista.Add(new CambioEquipoMovilDto(
                            FechaHora(r, "fecha"), Texto(r, "campo") ?? string.Empty, Texto(r, "valor_anterior"), Texto(r, "valor_nuevo"),
                            Texto(r, "detalle"), Texto(r, "usuario")));
                }

                var conCambios = equipos.Select(e => cambios.TryGetValue(e.IdOsEquipo, out var c) ? e with { Cambios = c } : e).ToList();
                return new RespuestaDto<ObjetivosMovilDto>(2, mensaje, new ObjetivosMovilDto(resumen, contadores, conCambios));
            }, ct);

    public Task<RespuestaDto<ObjetivoEquipoMovilDto>> BuscarPorQrAsync(long idUsuario, long idOs, string codigo, CancellationToken ct) =>
        EjecutarAsync<ObjetivoEquipoMovilDto>("SP_BuscarEquipoQrMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_codigo",     Valor(codigo));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ObjetivoEquipoMovilDto>(1, "El código escaneado no corresponde a ningún equipo de esta O/S.");
                return new RespuestaDto<ObjetivoEquipoMovilDto>(2, mensaje, LeerEquipo(r, []));
            }, ct);

    public Task<RespuestaDto<ResultadoCambioEstadoEquipoMovilDto>> CambiarEstadoAsync(
        long idUsuario, long idOs, long idOsEquipo, string accion, string? motivo, DateTime? capturadoUtc, CancellationToken ct) =>
        EjecutarAsync<ResultadoCambioEstadoEquipoMovilDto>("SP_CambiarEstadoEquipoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_os",         idOs);
                p.AddWithValue("p_id_os_equipo",  idOsEquipo);
                p.AddWithValue("p_accion",        accion);
                p.AddWithValue("p_motivo",        Valor(motivo));
                p.AddWithValue("p_capturado_utc", Valor(capturadoUtc));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoCambioEstadoEquipoMovilDto>(1, "No se pudo cambiar el estado del equipo.");
                return new RespuestaDto<ResultadoCambioEstadoEquipoMovilDto>(2, mensaje, new ResultadoCambioEstadoEquipoMovilDto(
                    EnteroLargo(r, "id_os_equipo"), Texto(r, "accion") ?? accion, Texto(r, "estado") ?? string.Empty,
                    Booleano(r, "repetida"), Booleano(r, "diferida")));
            }, ct);

    public Task<RespuestaDto<OpcionesEquipoNuevoMovilDto>> ObtenerOpcionesEquipoNuevoAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<OpcionesEquipoNuevoMovilDto>("SP_ObtenerOpcionesEquipoNuevoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var marcas = new List<string>();
                while (await r.ReadAsync(ct))
                    if (Texto(r, "marca") is { Length: > 0 } m) marcas.Add(m);

                await r.NextResultAsync(ct);
                var tipos = new List<TipoEquipoNuevoMovilDto>();
                while (await r.ReadAsync(ct))
                    tipos.Add(new TipoEquipoNuevoMovilDto(
                        EnteroLargo(r, "id_suministro"), Texto(r, "descripcion") ?? string.Empty, Texto(r, "clase") ?? string.Empty,
                        Texto(r, "marca"), Texto(r, "modelo")));

                return new RespuestaDto<OpcionesEquipoNuevoMovilDto>(2, mensaje, new OpcionesEquipoNuevoMovilDto(marcas, tipos));
            }, ct);

    public Task<RespuestaDto<ResultadoEquipoNuevoMovilDto>> RegistrarEquipoNuevoAsync(
        long idUsuario, long idOs, NuevoEquipoMovilDto e, string rutaFoto, CancellationToken ct) =>
        EjecutarAsync<ResultadoEquipoNuevoMovilDto>("SP_RegistrarEquipoNuevoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_num_serie",      Valor(e.NumeroSerie));
                p.AddWithValue("p_codigo_cliente", Valor(e.Codigo));
                p.AddWithValue("p_marca",          Valor(e.Marca));
                p.AddWithValue("p_modelo",         Valor(e.Modelo));
                p.AddWithValue("p_id_suministro",  e.IdSuministro);
                p.AddWithValue("p_ubicacion",      Valor(e.Ubicacion));
                p.AddWithValue("p_foto_placa",     Valor(rutaFoto));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoEquipoNuevoMovilDto>(1, "No se pudo registrar el equipo.");
                return new RespuestaDto<ResultadoEquipoNuevoMovilDto>(2, mensaje, new ResultadoEquipoNuevoMovilDto(
                    EnteroLargo(r, "id_os_equipo"), EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw") ?? string.Empty,
                    Booleano(r, "ya_existia"), Booleano(r, "ya_registrado"), Booleano(r, "foto_guardada"), Entero(r, "notificados")));
            }, ct);

    /// <summary>Una fila de equipo (mismas columnas en la lista y en la búsqueda por QR).</summary>
    private static ObjetivoEquipoMovilDto LeerEquipo(MySqlDataReader r, List<CambioEquipoMovilDto> cambios) => new(
        EnteroLargo(r, "id_os_equipo"),
        EnteroLargo(r, "id_equipo"),
        Entero(r, "numero"),
        Texto(r, "tipo_intervencion"),
        Texto(r, "tipo_corto"),
        Texto(r, "nombre") ?? "Equipo",
        Texto(r, "codigo_tw"),
        Texto(r, "codigo_cliente"),
        Texto(r, "marca"),
        Texto(r, "modelo"),
        Texto(r, "num_serie"),
        Texto(r, "ubicacion"),
        Texto(r, "estado_equipo"),
        Booleano(r, "bloqueado"),
        Booleano(r, "en_campo"),
        Booleano(r, "falta_equipo"),
        Texto(r, "estado") ?? "por_iniciar",
        EnteroNulo(r, "tiempo_estimado_min"),
        Entero(r, "tiempo_real_min"),
        FechaHora(r, "iniciado_en"),
        Texto(r, "motivo_pausa"),
        Booleano(r, "requiere_aprobacion"),
        Fecha(r, "ultima_intervencion"),
        Texto(r, "ultima_parte"),
        Entero(r, "alertas_pendientes"),
        Booleano(r, "puede_iniciar"),
        Booleano(r, "puede_pausar"),
        Booleano(r, "puede_reanudar"),
        cambios);
}
