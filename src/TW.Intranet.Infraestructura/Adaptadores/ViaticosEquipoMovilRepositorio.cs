using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Viáticos y gastos del equipo del Jefe de Área en la app móvil (App Mobile HU-35). Todo sale de procedimientos almacenados.</summary>
public class ViaticosEquipoMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IViaticosEquipoMovilRepositorio
{
    private static decimal Monto(MySqlConnector.MySqlDataReader r, string col) => DecimalNulo(r, col) ?? 0m;

    public Task<RespuestaDto<ViaticosEquipoDto>> ObtenerAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<ViaticosEquipoDto>("SP_ObtenerViaticosEquipoMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2 KPIs
                await r.NextResultAsync(ct);
                var kpis = await r.ReadAsync(ct)
                    ? new ViaticosEquipoKpisDto(Monto(r, "asignado"), Monto(r, "rendido"), Monto(r, "por_revisar"), Texto(r, "actualizado"), Math.Max(Entero(r, "refresco_segundos"), 10))
                    : new ViaticosEquipoKpisDto(0, 0, 0, null, 30);

                // 3 Servicios
                await r.NextResultAsync(ct);
                var servicios = new List<ViaticoEquipoServicioDto>();
                while (await r.ReadAsync(ct))
                    servicios.Add(new ViaticoEquipoServicioDto(
                        EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "cliente"), EnteroLargo(r, "id_programacion"), Texto(r, "tecnicos") ?? string.Empty,
                        Entero(r, "n_tecnicos"), Monto(r, "asignado"), Monto(r, "depositado"), Monto(r, "rendido"), Monto(r, "por_revisar"), Entero(r, "gastos_por_revisar"),
                        Entero(r, "avance"), Texto(r, "estado") ?? "al_dia", Booleano(r, "puede_asignar")));

                return new RespuestaDto<ViaticosEquipoDto>(2, mensaje, new ViaticosEquipoDto(kpis, servicios));
            }, ct);

    public Task<RespuestaDto<ViaticoServicioDto>> ObtenerServicioAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<ViaticoServicioDto>("SP_ObtenerViaticoServicioEquipoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                // 2 Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ViaticoServicioDto>(1, "El servicio no existe, no tiene programación o no pertenece a tu alcance.");
                var cabecera = new ViaticoServicioCabeceraDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "cliente"), EnteroLargo(r, "id_programacion"), Booleano(r, "cerrada"),
                    Booleano(r, "puede_asignar"), Texto(r, "motivo_no_asignar"), Texto(r, "version") ?? string.Empty,
                    Monto(r, "asignado"), Monto(r, "depositado"), Monto(r, "rendido"), Monto(r, "por_revisar"));

                // 3 Técnicos (sin líneas todavía)
                await r.NextResultAsync(ct);
                var tecnicos = new List<(long IdTecnico, string Nombre, bool Principal, decimal Asignado, decimal Depositado, decimal Rendido, decimal PorRevisar)>();
                while (await r.ReadAsync(ct))
                    tecnicos.Add((EnteroLargo(r, "id_tecnico"), Texto(r, "nombre") ?? string.Empty, Booleano(r, "principal"), Monto(r, "asignado"), Monto(r, "depositado"),
                                  Monto(r, "rendido"), Monto(r, "por_revisar")));

                // 4 Líneas asignadas (se reparten por técnico)
                await r.NextResultAsync(ct);
                var lineas = new Dictionary<long, List<ViaticoLineaDto>>();
                while (await r.ReadAsync(ct))
                {
                    var idTecnico = EnteroLargo(r, "id_tecnico");
                    if (!lineas.TryGetValue(idTecnico, out var lista)) lineas[idTecnico] = lista = [];
                    lista.Add(new ViaticoLineaDto(EnteroLargo(r, "id_gasto"), Texto(r, "concepto") ?? "Concepto", Texto(r, "clave"), Monto(r, "monto"), Booleano(r, "depositado")));
                }

                // 5 Gastos rendidos
                await r.NextResultAsync(ct);
                var gastos = new List<ViaticoGastoDto>();
                while (await r.ReadAsync(ct))
                    gastos.Add(new ViaticoGastoDto(EnteroLargo(r, "id_gasto"), EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? string.Empty, Texto(r, "concepto") ?? "Concepto",
                                                   Monto(r, "monto"), Texto(r, "estado") ?? "pendiente", Texto(r, "fecha"), Booleano(r, "tiene_comprobante"), DecimalNulo(r, "monto_ia"),
                                                   EsNulo(r, "coincide_ia") ? null : Booleano(r, "coincide_ia")));

                var porTecnico = tecnicos
                    .Select(t => new ViaticoTecnicoDto(t.IdTecnico, t.Nombre, t.Principal, t.Asignado, t.Depositado, t.Rendido, t.PorRevisar,
                                                       lineas.TryGetValue(t.IdTecnico, out var l) ? l : []))
                    .ToList();

                return new RespuestaDto<ViaticoServicioDto>(2, mensaje, new ViaticoServicioDto(cabecera, porTecnico, gastos));
            }, ct);

    public Task<RespuestaDto<AsignacionViaticoResultadoDto>> AsignarAsync(long idUsuario, long idOs, long idTecnico, decimal movilidad, decimal alimentacion, decimal alojamiento, decimal otros,
                                                                          bool depositado, string version, CancellationToken ct) =>
        EjecutarAsync<AsignacionViaticoResultadoDto>("SP_AsignarViaticoEquipoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_tecnico",   idTecnico);
                p.AddWithValue("p_movilidad",    movilidad);
                p.AddWithValue("p_alimentacion", alimentacion);
                p.AddWithValue("p_alojamiento",  alojamiento);
                p.AddWithValue("p_otros",        otros);
                p.AddWithValue("p_depositado",   Bit(depositado));
                p.AddWithValue("p_version",      version);
            },
            async (r, mensaje) =>
            {
                // 2 Resultado de SP_GuardarViaticosProgramacion (intranet): notificados_contabilidad, sin_cambios, version…
                await r.NextResultAsync(ct);
                var notificadosContabilidad = 0;
                var versionNueva = version;
                var totalProgramacion = 0m;
                if (await r.ReadAsync(ct))
                {
                    notificadosContabilidad = Entero(r, "notificados_contabilidad");
                    versionNueva = Texto(r, "version") ?? version;
                    totalProgramacion = Monto(r, "total_asignado");
                }

                // 3 Lo asignado a ese técnico y el aviso que se le dio (el SP lo agrega solo si guardó)
                var total = totalProgramacion;
                var depositadoTecnico = false;
                var tecnicoNotificado = 0;
                if (await r.NextResultAsync(ct) && await r.ReadAsync(ct))
                {
                    total = Monto(r, "total_tecnico");
                    depositadoTecnico = Booleano(r, "depositado");
                    tecnicoNotificado = Entero(r, "tecnico_notificado");
                    versionNueva = Texto(r, "version") ?? versionNueva;
                }

                return new RespuestaDto<AsignacionViaticoResultadoDto>(2, mensaje,
                    new AsignacionViaticoResultadoDto(total, depositadoTecnico, notificadosContabilidad + tecnicoNotificado, versionNueva));
            }, ct);
}
