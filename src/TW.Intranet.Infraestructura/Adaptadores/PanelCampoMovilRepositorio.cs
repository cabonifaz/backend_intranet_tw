using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Panel de campo y seguimiento del servicio del Jefe de Área en la app móvil (App Mobile HU-29 / HU-30). Todo sale de procedimientos almacenados.</summary>
public class PanelCampoMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IPanelCampoMovilRepositorio
{
    public Task<RespuestaDto<PanelCampoDto>> ObtenerPanelAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<PanelCampoDto>("SP_ObtenerPanelCampoMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2 KPIs
                await r.NextResultAsync(ct);
                var kpis = await r.ReadAsync(ct)
                    ? new PanelCampoKpisDto(Entero(r, "programados"), Entero(r, "en_ruta"), Entero(r, "ejecucion"), Entero(r, "demora"), Entero(r, "incidencia"),
                                            Entero(r, "finalizados"), Texto(r, "actualizado"), Math.Max(Entero(r, "refresco_segundos"), 10))
                    : new PanelCampoKpisDto(0, 0, 0, 0, 0, 0, null, 30);

                // 3 Pines
                await r.NextResultAsync(ct);
                var pines = new List<PanelCampoPinDto>();
                while (await r.ReadAsync(ct))
                    pines.Add(new PanelCampoPinDto(EnteroLargo(r, "id_usuario"), Texto(r, "tecnico") ?? string.Empty, Texto(r, "iniciales") ?? string.Empty,
                                                   Texto(r, "estado") ?? "sin_salir", DecimalNulo(r, "latitud"), DecimalNulo(r, "longitud"), EnteroNulo(r, "minutos_ubicacion"),
                                                   EnteroLargoNulo(r, "id_os"), Texto(r, "numero_os"), Texto(r, "cliente")));

                // 4 Alertas
                await r.NextResultAsync(ct);
                var alertas = new List<PanelCampoAlertaDto>();
                while (await r.ReadAsync(ct))
                    alertas.Add(new PanelCampoAlertaDto(Texto(r, "clave") ?? string.Empty, Texto(r, "tipo") ?? string.Empty, Texto(r, "severidad") ?? "advertencia",
                                                        Texto(r, "titulo") ?? string.Empty, Texto(r, "detalle"), EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty,
                                                        Texto(r, "cliente"), Texto(r, "tecnico"), Texto(r, "equipo"), Entero(r, "minutos")));

                return new RespuestaDto<PanelCampoDto>(2, mensaje, new PanelCampoDto(kpis, pines, alertas));
            }, ct);

    public Task<RespuestaDto<ServiciosJefaturaDto>> ObtenerServiciosAsync(long idUsuario, string filtro, string? busqueda, CancellationToken ct) =>
        EjecutarAsync<ServiciosJefaturaDto>("SP_ObtenerServiciosJefaturaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_filtro",     filtro);
                p.AddWithValue("p_busqueda",   Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var chips = await r.ReadAsync(ct)
                    ? new ChipsServiciosDto(Entero(r, "activos"), Entero(r, "con_demora"), Entero(r, "incidencias"), Entero(r, "finalizados"), Texto(r, "actualizado"),
                                            Math.Max(Entero(r, "refresco_segundos"), 10))
                    : new ChipsServiciosDto(0, 0, 0, 0, null, 30);

                await r.NextResultAsync(ct);
                var lista = new List<ServicioActivoDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new ServicioActivoDto(EnteroLargo(r, "id_os"), Texto(r, "numero") ?? string.Empty, Texto(r, "cliente"), Texto(r, "estado") ?? "sin_salir",
                                                    EnteroLargoNulo(r, "id_tecnico"), Texto(r, "tecnico"), Texto(r, "iniciales") ?? string.Empty, Texto(r, "lugar"),
                                                    Texto(r, "hora_programada"), Texto(r, "llegada"), Texto(r, "eta"), Entero(r, "avance_pct"), EnteroNulo(r, "minutos_ubicacion")));

                return new RespuestaDto<ServiciosJefaturaDto>(2, mensaje, new ServiciosJefaturaDto(chips, lista));
            }, ct);

    public Task<RespuestaDto<ServicioJefaturaDto>> ObtenerServicioAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<ServicioJefaturaDto>("SP_ObtenerServicioJefaturaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ServicioJefaturaDto>(1, "El servicio no existe, no es de hoy o no pertenece a tu área.");
                var cabecera = new ServicioCabeceraDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero") ?? string.Empty, Texto(r, "tipo"), Texto(r, "cliente"), Texto(r, "lugar"), Texto(r, "estado") ?? "sin_salir",
                    Texto(r, "estado_os") ?? string.Empty, EnteroLargoNulo(r, "id_tecnico"), Texto(r, "tecnico"), Texto(r, "cargo_tecnico"), Texto(r, "telefono_tecnico"),
                    Texto(r, "hora_programada"), Texto(r, "llegada"), EnteroNulo(r, "sla_pct"), Entero(r, "avance_pct"), Entero(r, "equipos"), Entero(r, "ejecutados"),
                    Texto(r, "contacto_nombre"), Texto(r, "contacto_telefono"), Booleano(r, "puede_cambiar_estado"), Texto(r, "actualizado"));

                await r.NextResultAsync(ct);
                var hitos = new List<HitoServicioDto>();
                while (await r.ReadAsync(ct))
                    hitos.Add(new HitoServicioDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "titulo") ?? string.Empty, Texto(r, "detalle"), Texto(r, "hora"),
                                                  Texto(r, "estado") ?? "pendiente", Texto(r, "tono") ?? "gris"));

                await r.NextResultAsync(ct);
                var estados = new List<EstadoPermitidoDto>();
                while (await r.ReadAsync(ct))
                    estados.Add(new EstadoPermitidoDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty));

                await r.NextResultAsync(ct);
                var motivos = new List<MotivoCambioDto>();
                while (await r.ReadAsync(ct))
                    motivos.Add(new MotivoCambioDto(Entero(r, "id_motivo"), Texto(r, "nombre") ?? string.Empty));

                return new RespuestaDto<ServicioJefaturaDto>(2, mensaje, new ServicioJefaturaDto(cabecera, hitos, estados, motivos));
            }, ct);

    public Task<RespuestaDto<RutaServicioDto>> ObtenerRutaAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<RutaServicioDto>("SP_ObtenerRutaServicioJefaturaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RutaServicioDto>(1, "El servicio no existe, no es de hoy o no pertenece a tu área.");
                var resumen = new RutaResumenDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero") ?? string.Empty, Texto(r, "cliente"), Texto(r, "estado") ?? "sin_salir", EnteroLargoNulo(r, "id_tecnico"),
                    Texto(r, "tecnico"), Texto(r, "telefono_tecnico"), DecimalNulo(r, "latitud"), DecimalNulo(r, "longitud"), EnteroNulo(r, "minutos_ubicacion"),
                    DecimalNulo(r, "velocidad_kmh"), EnteroNulo(r, "distancia_m"), DecimalNulo(r, "destino_latitud"), DecimalNulo(r, "destino_longitud"),
                    Texto(r, "destino_nombre"), DecimalNulo(r, "origen_latitud"), DecimalNulo(r, "origen_longitud"), Texto(r, "eta"), Texto(r, "eta_programada"),
                    Texto(r, "demora_texto"), Texto(r, "demora_origen"), Texto(r, "contacto_nombre"), Texto(r, "contacto_telefono"), Texto(r, "actualizado"),
                    EnteroNulo(r, "eta_minutos"), Texto(r, "eta_estimada"), Texto(r, "destino_direccion"));

                await r.NextResultAsync(ct);
                var recorrido = new List<PuntoGpsServicioDto>();
                while (await r.ReadAsync(ct))
                    recorrido.Add(new PuntoGpsServicioDto(DecimalNulo(r, "latitud") ?? 0m, DecimalNulo(r, "longitud") ?? 0m, Texto(r, "hora")));

                await r.NextResultAsync(ct);
                var eventos = new List<EventoRutaDto>();
                while (await r.ReadAsync(ct))
                    eventos.Add(new EventoRutaDto(Texto(r, "hora"), Texto(r, "titulo") ?? string.Empty, Texto(r, "detalle"), Texto(r, "badge") ?? string.Empty, Texto(r, "tono") ?? "verde"));

                return new RespuestaDto<RutaServicioDto>(2, mensaje, new RutaServicioDto(resumen, recorrido, eventos));
            }, ct);

    public Task<RespuestaDto<RegistroSeguimientoResultadoDto>> RegistrarAsync(long idUsuario, long idOs, string modo, string? nuevoEstado, int? idMotivo, string texto, CancellationToken ct) =>
        EjecutarAsync<RegistroSeguimientoResultadoDto>("SP_RegistrarSeguimientoJefaturaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_modo",         modo);
                p.AddWithValue("p_nuevo_estado", Valor(nuevoEstado));
                p.AddWithValue("p_id_motivo",    Valor(idMotivo));
                p.AddWithValue("p_texto",        texto);
            },
            async (r, mensaje) =>
            {
                // Resultado de SP_RegistrarAsistenteServicioRuta: IdRegistro, Modo, Notificados, EstadoNuevo
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RegistroSeguimientoResultadoDto>(2, mensaje, new RegistroSeguimientoResultadoDto(0, modo, 0, nuevoEstado));
                return new RespuestaDto<RegistroSeguimientoResultadoDto>(2, mensaje,
                    new RegistroSeguimientoResultadoDto(EnteroLargo(r, "IdRegistro"), Texto(r, "Modo") ?? modo, Entero(r, "Notificados"), Texto(r, "EstadoNuevo")));
            }, ct);
}
