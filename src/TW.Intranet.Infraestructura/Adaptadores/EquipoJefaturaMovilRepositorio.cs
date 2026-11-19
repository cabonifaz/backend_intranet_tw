using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Mi equipo y horas contabilizadas del Jefe de Área en la app móvil (App Mobile HU-36). Todo sale de procedimientos almacenados.</summary>
public class EquipoJefaturaMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IEquipoJefaturaMovilRepositorio
{
    /// <summary>Las columnas del técnico son las mismas en la lista, la ficha y las horas (SP_ArmarEquipoJefaturaMovil).</summary>
    private static EquipoTecnicoDto LeerTecnico(MySqlDataReader r) =>
        new(EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? string.Empty, Texto(r, "iniciales") ?? string.Empty, Texto(r, "cargo"), Texto(r, "estado") ?? "sin_marcar",
            Texto(r, "detalle") ?? string.Empty, Texto(r, "hora_inicio"), EnteroNulo(r, "minutos_tardanza"), EnteroLargoNulo(r, "id_os"), Texto(r, "numero_os"), Texto(r, "tipo_os"),
            Texto(r, "estado_servicio"), Texto(r, "lugar"), Texto(r, "motivo_sin_servicio"), DecimalNulo(r, "latitud"), DecimalNulo(r, "longitud"), EnteroNulo(r, "minutos_ubicacion"));

    public Task<RespuestaDto<EquipoJefaturaDto>> ObtenerAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<EquipoJefaturaDto>("SP_ObtenerEquipoJefaturaMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2 KPIs
                await r.NextResultAsync(ct);
                var kpis = await r.ReadAsync(ct)
                    ? new EquipoKpisDto(Entero(r, "en_labores"), Entero(r, "refrigerio"), Entero(r, "tardanza"), Entero(r, "sin_marcar"), Entero(r, "finalizaron"), Entero(r, "total"),
                                        Texto(r, "actualizado"), Math.Max(Entero(r, "refresco_segundos"), 10), Entero(r, "en_jornada"))
                    : new EquipoKpisDto(0, 0, 0, 0, 0, 0, null, 30);

                // 3 Técnicos
                await r.NextResultAsync(ct);
                var tecnicos = new List<EquipoTecnicoDto>();
                while (await r.ReadAsync(ct)) tecnicos.Add(LeerTecnico(r));

                return new RespuestaDto<EquipoJefaturaDto>(2, mensaje, new EquipoJefaturaDto(kpis, tecnicos));
            }, ct);

    public Task<RespuestaDto<FichaEquipoTecnicoDto>> ObtenerFichaAsync(long idUsuario, long idTecnico, CancellationToken ct) =>
        EjecutarAsync<FichaEquipoTecnicoDto>("SP_ObtenerFichaEquipoTecnicoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_tecnico", idTecnico);
            },
            async (r, mensaje) =>
            {
                // 2 Técnico (+ teléfono, área y SSOMA)
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<FichaEquipoTecnicoDto>(1, "El técnico no pertenece a tu equipo.");
                var tecnico = LeerTecnico(r);
                var telefono = Texto(r, "telefono");
                var area = Texto(r, "area");
                var ssoma = new SsomaTecnicoDto(Texto(r, "ssoma_estado"), Texto(r, "ssoma_detalle"));

                // 3 Marcaciones del día
                await r.NextResultAsync(ct);
                var marcaciones = new List<MarcacionEquipoDto>();
                while (await r.ReadAsync(ct))
                    marcaciones.Add(new MarcacionEquipoDto(Texto(r, "tipo") ?? string.Empty, Texto(r, "titulo") ?? string.Empty, Texto(r, "hora"), Texto(r, "detalle"),
                                                           Texto(r, "estado") ?? "hecho", Texto(r, "tono") ?? "gris"));

                // 4 Carga por día
                await r.NextResultAsync(ct);
                var dias = new List<CargaDiaEquipoDto>();
                while (await r.ReadAsync(ct))
                    dias.Add(new CargaDiaEquipoDto(Texto(r, "fecha") ?? string.Empty, Texto(r, "etiqueta") ?? string.Empty, DecimalNulo(r, "horas") ?? 0m, Entero(r, "porcentaje")));

                // 5 Resumen de la carga
                await r.NextResultAsync(ct);
                var carga = await r.ReadAsync(ct)
                    ? new CargaSemanaDto(Texto(r, "desde") ?? string.Empty, Texto(r, "hasta") ?? string.Empty, dias, Entero(r, "utilizacion_pct"), Texto(r, "nivel") ?? "baja",
                                         DecimalNulo(r, "horas_planificadas") ?? 0m, DecimalNulo(r, "horas_capacidad") ?? 0m)
                    : new CargaSemanaDto(string.Empty, string.Empty, dias, 0, "baja", 0m, 0m);

                return new RespuestaDto<FichaEquipoTecnicoDto>(2, mensaje, new FichaEquipoTecnicoDto(tecnico, telefono, area, ssoma, marcaciones, carga));
            }, ct);

    public Task<RespuestaDto<HorasTecnicoLecturaDto>> ObtenerHorasAsync(long idUsuario, long idTecnico, string? mes, CancellationToken ct) =>
        EjecutarAsync<HorasTecnicoLecturaDto>("SP_ObtenerHorasTecnicoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_tecnico", idTecnico);
                p.AddWithValue("p_mes",        Valor(mes));
            },
            async (r, mensaje) =>
            {
                // 2 Técnico
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<HorasTecnicoLecturaDto>(1, "El técnico no pertenece a tu equipo.");
                var tecnico = LeerTecnico(r);

                // 3 Resumen del mes
                await r.NextResultAsync(ct);
                string mesLeido = mes ?? string.Empty;
                int total = 0, diasTrabajados = 0, servicios = 0;
                var cerrado = false;
                if (await r.ReadAsync(ct))
                {
                    mesLeido = Texto(r, "mes") ?? mesLeido;
                    total = Entero(r, "total_minutos");
                    diasTrabajados = Entero(r, "dias_trabajados");
                    servicios = Entero(r, "servicios");
                    cerrado = Booleano(r, "cerrado");
                }

                // 4 Días con datos
                await r.NextResultAsync(ct);
                var dias = new List<(string Fecha, int Minutos, int Servicios, string? Inicio, string? Fin, bool SinCierre)>();
                while (await r.ReadAsync(ct))
                    dias.Add((Texto(r, "fecha") ?? string.Empty, Entero(r, "minutos"), Entero(r, "servicios"), Texto(r, "inicio"), Texto(r, "fin"), Booleano(r, "sin_cierre")));

                // 5 Detalle por servicio
                await r.NextResultAsync(ct);
                var detalle = new Dictionary<string, List<HoraServicioDto>>();
                while (await r.ReadAsync(ct))
                {
                    var fecha = Texto(r, "fecha") ?? string.Empty;
                    if (!detalle.TryGetValue(fecha, out var lista)) detalle[fecha] = lista = [];
                    lista.Add(new HoraServicioDto(EnteroLargo(r, "id_os"), Texto(r, "numero") ?? string.Empty, Texto(r, "inicio") ?? string.Empty, Texto(r, "fin"), Entero(r, "minutos")));
                }

                // 6 Historial de meses
                await r.NextResultAsync(ct);
                var historial = new List<HoraMesDto>();
                while (await r.ReadAsync(ct))
                    historial.Add(new HoraMesDto(Texto(r, "mes") ?? string.Empty, Entero(r, "minutos"), Entero(r, "dias_trabajados"), Entero(r, "servicios"), Booleano(r, "cerrado")));

                var listaDias = dias
                    .Select(d => new HoraDiaDto(d.Fecha, d.Minutos, d.Servicios, d.Inicio, d.Fin, d.SinCierre, detalle.TryGetValue(d.Fecha, out var s) ? s : []))
                    .ToList();

                return new RespuestaDto<HorasTecnicoLecturaDto>(2, mensaje, new HorasTecnicoLecturaDto(tecnico, mesLeido, listaDias, total, diasTrabajados, servicios, cerrado, historial));
            }, ct);
}
