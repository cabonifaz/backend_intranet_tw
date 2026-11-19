using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Agenda y carga del área del Jefe de Área en la app móvil (App Mobile HU-37). Todo sale de procedimientos almacenados que envuelven la Programación de la intranet (HU-35 a HU-39).</summary>
public class AgendaAreaMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IAgendaAreaMovilRepositorio
{
    private static object Nulo(object? v) => v ?? DBNull.Value;

    public Task<RespuestaDto<AgendaAreaDto>> ObtenerAsync(long idUsuario, string? desde, CancellationToken ct) =>
        EjecutarAsync<AgendaAreaDto>("SP_ObtenerAgendaAreaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_desde", Nulo(desde is null ? null : DateTime.ParseExact(desde, "yyyy-MM-dd", CultureInfo.InvariantCulture)));
            },
            async (r, mensaje) =>
            {
                // 2 Cabecera y KPIs
                await r.NextResultAsync(ct);
                string lunes = desde ?? string.Empty, hasta = string.Empty;
                var kpis = new AgendaKpisDto(0, 0, 0, null, 30);
                if (await r.ReadAsync(ct))
                {
                    lunes = Texto(r, "desde") ?? lunes;
                    hasta = Texto(r, "hasta") ?? string.Empty;
                    kpis = new AgendaKpisDto(Entero(r, "conflictos"), Entero(r, "servicios"), Entero(r, "sobrecargados"), Texto(r, "actualizado"), Math.Max(Entero(r, "refresco_segundos"), 10));
                }

                // 3 Técnicos
                await r.NextResultAsync(ct);
                var tecnicos = new List<(long Id, string Nombre, string Corto, string Iniciales, decimal Horas, int Util, string Nivel)>();
                while (await r.ReadAsync(ct))
                    tecnicos.Add((EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? string.Empty, Texto(r, "nombre_corto") ?? string.Empty, Texto(r, "iniciales") ?? string.Empty,
                                  DecimalNulo(r, "horas_semana") ?? 0m, Entero(r, "utilizacion_pct"), Texto(r, "nivel") ?? "libre"));

                // 4 Días (técnico × día)
                await r.NextResultAsync(ct);
                var dias = new List<(long Id, string Fecha, decimal Horas, string Nivel, bool Conflicto)>();
                while (await r.ReadAsync(ct))
                    dias.Add((EnteroLargo(r, "id_usuario"), Texto(r, "fecha") ?? string.Empty, DecimalNulo(r, "horas") ?? 0m, Texto(r, "nivel") ?? "libre", Booleano(r, "conflicto")));

                // 5 Servicios (técnico × día)
                await r.NextResultAsync(ct);
                var servicios = new Dictionary<(long, string), List<AgendaServicioDto>>();
                while (await r.ReadAsync(ct))
                {
                    var clave = (EnteroLargo(r, "id_usuario"), Texto(r, "fecha") ?? string.Empty);
                    if (!servicios.TryGetValue(clave, out var lista)) servicios[clave] = lista = [];
                    lista.Add(new AgendaServicioDto(EnteroLargo(r, "id_os"), EnteroLargoNulo(r, "id_programacion"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "tipo") ?? "OS",
                                                    Texto(r, "codigo") ?? string.Empty, Texto(r, "cliente"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"), Texto(r, "tipo_servicio"),
                                                    Texto(r, "estado") ?? "pendiente", Booleano(r, "conflicto")));
                }

                // 6 Conflictos
                await r.NextResultAsync(ct);
                var conflictos = new List<AgendaConflictoDto>();
                while (await r.ReadAsync(ct)) conflictos.Add(LeerConflicto(r));

                var lista2 = tecnicos
                    .Select(t => new AgendaTecnicoDto(t.Id, t.Nombre, t.Corto, t.Iniciales,
                        dias.Where(d => d.Id == t.Id).Select(d => new AgendaDiaDto(d.Fecha, d.Horas, d.Nivel, d.Conflicto, servicios.TryGetValue((t.Id, d.Fecha), out var s) ? s : [])).ToList(),
                        t.Horas, t.Util, t.Nivel))
                    .ToList();

                return new RespuestaDto<AgendaAreaDto>(2, mensaje, new AgendaAreaDto(lunes, hasta, kpis, lista2, conflictos));
            }, ct);

    private static AgendaConflictoDto LeerConflicto(MySqlConnector.MySqlDataReader r) =>
        new(Texto(r, "clave") ?? string.Empty, Texto(r, "tipo") ?? string.Empty, Texto(r, "titulo") ?? string.Empty, Texto(r, "detalle"), Texto(r, "fecha"), EnteroLargo(r, "id_tecnico"),
            Texto(r, "tecnico") ?? string.Empty, EnteroLargoNulo(r, "id_os_a"), Texto(r, "numero_os_a"), EnteroLargoNulo(r, "id_os_b"), Texto(r, "numero_os_b"),
            Booleano(r, "puede_resolver"), Texto(r, "modo") ?? "solo_lectura");

    public Task<RespuestaDto<AgendaConflictoDetalleDto>> ObtenerConflictoAsync(long idUsuario, string tipo, long idTecnico, long idOsA, long? idOsB, CancellationToken ct) =>
        EjecutarAsync<AgendaConflictoDetalleDto>("SP_ObtenerConflictoAgendaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_tipo",       tipo);
                p.AddWithValue("p_id_tecnico", idTecnico);
                p.AddWithValue("p_id_os_a",    idOsA);
                p.AddWithValue("p_id_os_b",    Nulo(idOsB));
            },
            async (r, mensaje) =>
            {
                // 2 Conflicto (el de la intranet)
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AgendaConflictoDetalleDto>(1, "El conflicto ya no existe o cambió: actualiza la lista de alertas.");
                var clave = Texto(r, "clave") ?? string.Empty;
                var titulo = Texto(r, "titulo") ?? string.Empty;
                var detalle = Texto(r, "detalle");
                var fechaConflicto = Fecha(r, "fecha");
                var tecnico = Texto(r, "tecnico") ?? string.Empty;
                var motivoSugerido = Texto(r, "motivo_sugerido");
                var modo = Texto(r, "modo") ?? "solo_lectura";
                var puedeResolver = Booleano(r, "puede_resolver");

                // 3 Servicios
                await r.NextResultAsync(ct);
                var servicios = new List<(long IdOs, long? IdProg, string Numero, string Tipo, string? Cliente, string? Fecha, string? Ini, string? Fin, string? TipoServicio, string? EstadoProg, bool Resoluble)>();
                while (await r.ReadAsync(ct))
                    servicios.Add((EnteroLargo(r, "id_os"), EnteroLargoNulo(r, "id_programacion"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "tipo") ?? "OS", Texto(r, "razon_social"),
                                   Fecha(r, "fecha"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"), Texto(r, "tipo_servicio"), Texto(r, "estado_programacion"), Booleano(r, "resoluble")));

                // 4 Opciones de la intranet (no se usan: la app ofrece sus tres acciones)
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct)) { }

                // 5 Recursos sugeridos por servicio
                await r.NextResultAsync(ct);
                var candidatos = new List<(long ParaOs, long IdTecnico, string Nombre, string? Ssoma, int Util, int Score)>();
                while (await r.ReadAsync(ct))
                    candidatos.Add((EnteroLargo(r, "para_id_os"), EnteroLargo(r, "id_tecnico"), Texto(r, "nombre") ?? string.Empty, Texto(r, "ssoma_estado"), Entero(r, "utilizacion_pct"), Entero(r, "score")));

                // 6 Técnicos del alcance del jefe
                await r.NextResultAsync(ct);
                var alcance = new HashSet<long>();
                while (await r.ReadAsync(ct)) alcance.Add(EnteroLargo(r, "id_tecnico"));

                // 7 Motivos de reprogramación
                await r.NextResultAsync(ct);
                var motivos = new List<OpcionAgendaDto>();
                while (await r.ReadAsync(ct)) motivos.Add(new OpcionAgendaDto(Entero(r, "id_motivo"), Texto(r, "nombre") ?? string.Empty));

                // El servicio que conviene mover: entre los resolubles, el menos avanzado (pendiente de confirmación antes que confirmado) y, a igualdad, el más reciente
                var objetivo = servicios
                    .Where(s => s.Resoluble)
                    .OrderBy(s => s.EstadoProg == "pendiente_confirmacion" ? 0 : 1)
                    .ThenByDescending(s => s.IdOs)
                    .Select(s => (long?)s.IdOs)
                    .FirstOrDefault();

                // El técnico sugerido: el mejor candidato (menos carga) para el servicio objetivo, y solo si el jefe puede asignarlo
                var sugerido = candidatos
                    .Where(c => alcance.Contains(c.IdTecnico))
                    .OrderBy(c => objetivo is not null && c.ParaOs == objetivo ? 0 : 1)
                    .ThenByDescending(c => c.Score)
                    .ThenBy(c => c.Nombre, StringComparer.Ordinal)
                    .Select(c => new TecnicoSugeridoDto(c.IdTecnico, c.Nombre, $"carga {c.Util} % · SSOMA {TextoSsoma(c.Ssoma)}"))
                    .FirstOrDefault();

                var detalleServicios = servicios
                    .Select(s => new AgendaConflictoServicioDto(s.IdOs, s.IdProg, s.Numero, s.Tipo, s.Cliente, s.Fecha, s.Ini, s.Fin, s.TipoServicio, objetivo == s.IdOs))
                    .ToList();
                string? NumeroDe(long? id) => id is null ? null : servicios.Where(s => s.IdOs == id).Select(s => s.Numero).FirstOrDefault();

                var conflicto = new AgendaConflictoDto(clave, TipoDeClave(clave), titulo, detalle, fechaConflicto, idTecnico, tecnico, idOsA, NumeroDe(idOsA), idOsB, NumeroDe(idOsB), puedeResolver, modo);
                return new RespuestaDto<AgendaConflictoDetalleDto>(2, mensaje, new AgendaConflictoDetalleDto(conflicto, detalleServicios, sugerido, motivos, modo, motivoSugerido));
            }, ct);

    /// <summary>El tipo de conflicto es el prefijo de su clave («solapamiento:12:100:101»).</summary>
    private static string TipoDeClave(string clave) => clave.Split(':')[0];

    private static string TextoSsoma(string? estado) => estado switch
    {
        "por_vencer" => "por vencer",
        "incompleto" => "incompleto",
        _            => "conforme",
    };

    public Task<RespuestaDto<ResolucionConflictoAgendaDto>> ResolverAsync(long idUsuario, ResolucionConflictoDatos d, CancellationToken ct) =>
        EjecutarAsync<ResolucionConflictoAgendaDto>("SP_ResolverConflictoAgendaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_tipo",             d.Tipo);
                p.AddWithValue("p_id_tecnico",       d.IdTecnico);
                p.AddWithValue("p_id_os_a",          d.IdOsA);
                p.AddWithValue("p_id_os_b",          Nulo(d.IdOsB));
                p.AddWithValue("p_opcion",           d.Opcion);
                p.AddWithValue("p_id_os_objetivo",   Nulo(d.IdOsObjetivo));
                p.AddWithValue("p_id_nuevo_tecnico", Nulo(d.IdNuevoTecnico));
                p.AddWithValue("p_fecha",            Nulo(d.Fecha?.ToDateTime(TimeOnly.MinValue)));
                p.AddWithValue("p_hora_inicio",      Nulo(d.HoraInicio?.ToTimeSpan()));
                p.AddWithValue("p_hora_fin",         Nulo(d.HoraFin?.ToTimeSpan()));
                p.AddWithValue("p_id_motivo",        Nulo(d.IdMotivo));
                p.AddWithValue("p_comentario",       Valor(d.Comentario));
            },
            async (r, mensaje) =>
            {
                // 2 Resultado (los de SP_ReprogramarProgramacion): modo directa | solicitud
                await r.NextResultAsync(ct);
                var modo = await r.ReadAsync(ct) ? Texto(r, "modo") ?? "directa" : "directa";
                return new RespuestaDto<ResolucionConflictoAgendaDto>(2, mensaje, new ResolucionConflictoAgendaDto(modo, mensaje));
            }, ct);
}
