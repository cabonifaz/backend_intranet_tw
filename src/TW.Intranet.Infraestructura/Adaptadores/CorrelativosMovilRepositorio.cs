using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Correlativos de Metrología en la app móvil (App Mobile HU-14 técnico / HU-34 Jefe de Metrología). Todo sale de procedimientos almacenados.</summary>
public class CorrelativosMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ICorrelativosMovilRepositorio
{
    public Task<RespuestaDto<SolicitudCorrelativoDto>> ObtenerSolicitudAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<SolicitudCorrelativoDto>("SP_ObtenerSolicitudCorrelativoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                // 2 Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<SolicitudCorrelativoDto>(1, "Servicio o equipo no encontrado.");
                var cabecera = new CabeceraSolicitudCorrelativoDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, EnteroLargo(r, "id_os_equipo"), Texto(r, "equipo") ?? "Equipo", Entero(r, "numero"),
                    Texto(r, "num_serie"), Texto(r, "codigo_cliente"), Texto(r, "codigo_tw"), Texto(r, "clase"), Texto(r, "capacidad"),
                    Texto(r, "tipo_orden") ?? "OS", Texto(r, "numero_rq"), Texto(r, "resultado"),
                    Booleano(r, "puede_solicitar"), Texto(r, "motivo_bloqueo"),
                    EnteroLargoNulo(r, "ticket_abierto_id"), Texto(r, "ticket_abierto_numero"), Texto(r, "ticket_abierto_estado"),
                    Texto(r, "numero_certificado"), Booleano(r, "tecnico_metrologia"));

                // 3 Tipos de certificado
                await r.NextResultAsync(ct);
                var tipos = new List<TipoCertificadoDto>();
                while (await r.ReadAsync(ct)) tipos.Add(new TipoCertificadoDto(Entero(r, "id_tipo"), Texto(r, "nombre") ?? string.Empty));

                // 4 Correlativo asignado sin usar
                await r.NextResultAsync(ct);
                CorrelativoAsignadoDto? asignado = null;
                if (await r.ReadAsync(ct))
                    asignado = new CorrelativoAsignadoDto(EnteroLargo(r, "id_ticket"), Texto(r, "ticket") ?? string.Empty, Texto(r, "correlativo") ?? string.Empty,
                                                          FechaHora(r, "asignado_en"), Texto(r, "asignado_por") is { Length: > 0 } a ? a : null);

                // 5 Reserva libre
                await r.NextResultAsync(ct);
                var reserva = new List<string>();
                while (await r.ReadAsync(ct)) reserva.Add(Texto(r, "correlativo") ?? string.Empty);

                return new RespuestaDto<SolicitudCorrelativoDto>(2, mensaje, new SolicitudCorrelativoDto(cabecera, tipos, asignado, reserva));
            }, ct);

    public Task<RespuestaDto<TicketCreadoDto>> SolicitarAsync(long idUsuario, long idOs, long idOsEquipo, int idTipo, string? observacion, CancellationToken ct) =>
        EjecutarAsync<TicketCreadoDto>("SP_SolicitarCorrelativoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_id_tipo",      idTipo);
                p.AddWithValue("p_observacion",  Valor(observacion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<TicketCreadoDto>(1, "No se pudo registrar la solicitud.");
                return new RespuestaDto<TicketCreadoDto>(2, mensaje, new TicketCreadoDto(
                    EnteroLargo(r, "id_ticket"), Texto(r, "numero") ?? string.Empty, Texto(r, "estado") ?? "solicitado", FechaHora(r, "solicitado_en"), Entero(r, "notificados")));
            }, ct);

    public Task<RespuestaDto<IReadOnlyList<TicketCorrelativoDto>>> ObtenerTicketsAsync(long idUsuario, string filtro, long? idOs, CancellationToken ct) =>
        EjecutarAsync<IReadOnlyList<TicketCorrelativoDto>>("SP_ObtenerTicketsCorrelativoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_filtro",     filtro);
                p.AddWithValue("p_id_os",      Valor(idOs));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<TicketCorrelativoDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new TicketCorrelativoDto(
                        EnteroLargo(r, "id_ticket"), Texto(r, "numero") ?? string.Empty, Texto(r, "estado") ?? "solicitado", Booleano(r, "usado"),
                        EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, EnteroLargoNulo(r, "id_os_equipo"), Texto(r, "equipo"), Texto(r, "codigo_equipo"), Texto(r, "num_serie"),
                        EnteroNulo(r, "id_tipo"), Texto(r, "tipo_certificado"), Texto(r, "observacion"),
                        FechaHora(r, "solicitado_en"), Texto(r, "solicitante"),
                        Texto(r, "correlativo"), FechaHora(r, "asignado_en"), Texto(r, "asignado_por") is { Length: > 0 } a ? a : null,
                        Booleano(r, "puede_usar")));
                return new RespuestaDto<IReadOnlyList<TicketCorrelativoDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<CertificadoGuardadoDto>> GuardarCertificadoAsync(long idUsuario, long idOs, long idOsEquipo, string certificado, CancellationToken ct) =>
        EjecutarAsync<CertificadoGuardadoDto>("SP_GuardarCertificadoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_certificado",  certificado);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<CertificadoGuardadoDto>(1, "No se pudo guardar el certificado.");
                return new RespuestaDto<CertificadoGuardadoDto>(2, mensaje, new CertificadoGuardadoDto(Texto(r, "numero_certificado") ?? certificado, Texto(r, "origen"), Texto(r, "ticket")));
            }, ct);

    public Task<RespuestaDto<ReservaGeneradaDto>> GenerarReservaAsync(long idUsuario, string modo, CancellationToken ct) =>
        EjecutarAsync<ReservaGeneradaDto>("SP_GenerarReservaCorrelativosMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_modo",       modo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<ReservaGeneradaDto>(2, mensaje, new ReservaGeneradaDto(Entero(r, "generados"), Entero(r, "tecnicos")))
                    : new RespuestaDto<ReservaGeneradaDto>(2, mensaje, new ReservaGeneradaDto(0, 0));
            }, ct);

    public Task<RespuestaDto<CorrelativosJefaturaDto>> ObtenerPanelJefaturaAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<CorrelativosJefaturaDto>("SP_ObtenerCorrelativosJefaturaMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2 KPIs
                await r.NextResultAsync(ct);
                var kpis = await r.ReadAsync(ct)
                    ? new KpisCorrelativosDto(Entero(r, "pendientes"), Entero(r, "asignados_hoy"), Entero(r, "reservados"), Texto(r, "siguiente_sugerido"), Entero(r, "reserva_diaria"))
                    : new KpisCorrelativosDto(0, 0, 0, null, 2);

                // 3 Tickets
                await r.NextResultAsync(ct);
                var tickets = new List<TicketJefaturaDto>();
                while (await r.ReadAsync(ct))
                    tickets.Add(new TicketJefaturaDto(
                        EnteroLargo(r, "id_ticket"), Texto(r, "numero") ?? string.Empty, Texto(r, "estado") ?? "solicitado", Texto(r, "tecnico"), Texto(r, "numero_os") ?? string.Empty,
                        Texto(r, "equipo"), Texto(r, "codigo_equipo"), Texto(r, "capacidad"), Texto(r, "tipo_certificado"), Texto(r, "observacion"), Texto(r, "patron"), Texto(r, "resultado"),
                        FechaHora(r, "solicitado_en"), Entero(r, "minutos"),
                        Texto(r, "correlativo"), FechaHora(r, "asignado_en"), Texto(r, "asignado_por") is { Length: > 0 } a ? a : null));

                // 4 Reserva por técnico
                await r.NextResultAsync(ct);
                var reserva = new List<ReservaTecnicoDto>();
                while (await r.ReadAsync(ct))
                    reserva.Add(new ReservaTecnicoDto(EnteroLargo(r, "id_usuario"), Texto(r, "tecnico") ?? string.Empty, Entero(r, "libres"), Texto(r, "codigos_libres") ?? string.Empty,
                                                      Entero(r, "usados"), Texto(r, "usados_texto") ?? string.Empty));

                return new RespuestaDto<CorrelativosJefaturaDto>(2, mensaje, new CorrelativosJefaturaDto(kpis, tickets, reserva));
            }, ct);

    public Task<RespuestaDto<AsignacionCorrelativoDto>> AsignarAsync(long idUsuario, long idTicket, string? correlativo, CancellationToken ct) =>
        EjecutarAsync<AsignacionCorrelativoDto>("SP_AsignarCorrelativoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_ticket",   idTicket);
                p.AddWithValue("p_correlativo", Valor(correlativo));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<AsignacionCorrelativoDto>(1, "No se pudo asignar el correlativo.");
                return new RespuestaDto<AsignacionCorrelativoDto>(2, mensaje, new AsignacionCorrelativoDto(
                    EnteroLargo(r, "id_ticket"), Texto(r, "numero") ?? string.Empty, Texto(r, "estado") ?? "asignado", Texto(r, "correlativo") ?? string.Empty,
                    FechaHora(r, "asignado_en"), Texto(r, "asignado_por"), Texto(r, "tecnico"), Texto(r, "siguiente_sugerido")));
            }, ct);
}
