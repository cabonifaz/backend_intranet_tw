using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Detalle del servicio y checklist de pre-salida de la app móvil (App Mobile HU-04).</summary>
public class PresalidaMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IPresalidaMovilRepositorio
{
    public Task<RespuestaDto<DetalleServicioMovilDto>> ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<DetalleServicioMovilDto>("SP_ObtenerDetalleServicioMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleServicioMovilDto>(1, "Servicio no encontrado o no asignado a tu usuario.");

                var servicio = new ServicioDetalleMovilDto(
                    EnteroLargo(r, "id_os"),
                    Texto(r, "numero_os") ?? string.Empty,
                    Texto(r, "numero_rq"),
                    Texto(r, "numero_om"),
                    Texto(r, "cliente"),
                    Entero(r, "id_tipo_servicio"),
                    Texto(r, "tipo_servicio"),
                    Fecha(r, "fecha_ejecucion"),
                    Texto(r, "hora_inicio"),
                    Texto(r, "estado_os") ?? string.Empty,
                    Texto(r, "sede"),
                    Texto(r, "direccion"),
                    Texto(r, "contacto_nombre"),
                    Texto(r, "contacto_cargo"),
                    Texto(r, "contacto_telefono"),
                    Texto(r, "responsable"),
                    Booleano(r, "cliente_confirmado"),
                    Texto(r, "estado_ssoma") ?? "pendiente",
                    Entero(r, "objetivos_total"),
                    Texto(r, "notas_operativas"));

                var alertas = new List<AlertaServicioMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    alertas.Add(new AlertaServicioMovilDto(EnteroLargo(r, "id_alerta"), Texto(r, "tipo"),
                        Texto(r, "descripcion") ?? string.Empty, Texto(r, "prioridad"), Texto(r, "equipo"), FechaHora(r, "fecha_generacion")));

                var riesgos = new List<RiesgoServicioMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    riesgos.Add(new RiesgoServicioMovilDto(Entero(r, "id_riesgo"), Texto(r, "nombre"), Texto(r, "codigo"),
                        Texto(r, "icono"), Texto(r, "observacion")));

                var repuestos = new List<RepuestoServicioMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    repuestos.Add(new RepuestoServicioMovilDto(EnteroLargo(r, "id_item"), Texto(r, "descripcion") ?? string.Empty,
                        Booleano(r, "asignado")));

                var historial = new List<HistorialServicioMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    historial.Add(new HistorialServicioMovilDto(FechaHora(r, "fecha"), Texto(r, "origen") ?? "servicio",
                        Texto(r, "titulo"), Texto(r, "referencia"), Texto(r, "valor_anterior"), Texto(r, "valor_nuevo"),
                        Texto(r, "detalle"), Texto(r, "usuario")));

                var documentos = new List<DocumentoServicioMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    documentos.Add(new DocumentoServicioMovilDto(EnteroLargo(r, "id_documento"), Texto(r, "nombre_archivo") ?? string.Empty,
                        Texto(r, "tipo"), Entero(r, "version"), FechaHora(r, "fecha_carga")));

                return new RespuestaDto<DetalleServicioMovilDto>(2, mensaje,
                    new DetalleServicioMovilDto(servicio, alertas, riesgos, repuestos, historial, documentos));
            }, ct);

    public Task<RespuestaDto<HechosChecklistSalidaDto>> ObtenerHechosChecklistAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<HechosChecklistSalidaDto>("SP_ObtenerChecklistSalidaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<HechosChecklistSalidaDto>(1, "Servicio no encontrado o no asignado a tu usuario.");

                return new RespuestaDto<HechosChecklistSalidaDto>(2, mensaje, new HechosChecklistSalidaDto(
                    EnteroLargo(r, "id_os"),
                    Texto(r, "numero_os") ?? string.Empty,
                    Texto(r, "cliente"),
                    Fecha(r, "fecha_ejecucion"),
                    Texto(r, "hora_inicio"),
                    Texto(r, "tecnico"),
                    Texto(r, "estado_os") ?? string.Empty,
                    Entero(r, "id_tipo_servicio"),
                    Booleano(r, "cliente_confirmado"),
                    Texto(r, "estado_ssoma") ?? "pendiente",
                    Booleano(r, "tiene_oc"),
                    Entero(r, "repuestos_total"),
                    Entero(r, "repuestos_pendientes"),
                    Entero(r, "alertas_pendientes"),
                    Booleano(r, "chk_expediente"),
                    Booleano(r, "chk_epp"),
                    Booleano(r, "chk_materiales"),
                    Booleano(r, "chk_herramientas"),
                    Booleano(r, "chk_pesas_patron"),
                    Texto(r, "aut_estado"),
                    Texto(r, "aut_comentario"),
                    FechaHora(r, "aut_solicitado_en"),
                    FechaHora(r, "aut_resuelto_en"),
                    Texto(r, "aut_jefe"),
                    Texto(r, "area_autoriza_codigo"),
                    Texto(r, "area_autoriza"),
                    Texto(r, "cargo_encargado"),
                    Texto(r, "encargado_area")));
            }, ct);

    public Task<RespuestaDto<bool>> MarcarItemAsync(long idUsuario, long idOs, string codigo, bool confirmado, CancellationToken ct) =>
        EjecutarAsync("SP_MarcarChecklistSalidaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_codigo",     codigo);
                p.AddWithValue("p_confirmado", Bit(confirmado));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<bool>> SolicitarAutorizacionAsync(long idUsuario, long idOs, string? motivo, string pendientes, CancellationToken ct) =>
        EjecutarAsync("SP_SolicitarAutorizacionSalidaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_motivo",     Valor(motivo));
                p.AddWithValue("p_pendientes", Valor(pendientes));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<bool>> IniciarTrasladoAsync(long idUsuario, long idOs, bool conVistoBueno, CancellationToken ct) =>
        EjecutarAsync("SP_IniciarTrasladoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_os",           idOs);
                p.AddWithValue("p_con_visto_bueno", Bit(conVistoBueno));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);
}

/// <summary>Visto bueno de salida desde la intranet (encargado del área · App Mobile HU-04).</summary>
public class AutorizacionSalidaRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IAutorizacionSalidaRepositorio
{
    public Task<RespuestaDto<List<AutorizacionSalidaBandejaDto>>> ObtenerAsync(long idUsuario, string? estado, CancellationToken ct) =>
        EjecutarAsync<List<AutorizacionSalidaBandejaDto>>("SP_ObtenerAutorizacionesSalida",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_estado",     Valor(estado));
            },
            async (r, mensaje) =>
            {
                var lista = new List<AutorizacionSalidaBandejaDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new AutorizacionSalidaBandejaDto(
                        EnteroLargo(r, "id_autorizacion"),
                        EnteroLargo(r, "id_os"),
                        Texto(r, "numero_os") ?? string.Empty,
                        Texto(r, "cliente"),
                        Fecha(r, "fecha_ejecucion"),
                        Texto(r, "hora_inicio"),
                        Texto(r, "estado_os") ?? string.Empty,
                        Texto(r, "tecnico"),
                        Texto(r, "motivo"),
                        Texto(r, "pendientes"),
                        Texto(r, "estado") ?? string.Empty,
                        Texto(r, "area_destino"),
                        Texto(r, "area"),
                        FechaHora(r, "solicitado_en"),
                        Texto(r, "jefe"),
                        FechaHora(r, "resuelto_en"),
                        Texto(r, "comentario")));
                return new RespuestaDto<List<AutorizacionSalidaBandejaDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<bool>> ResolverAsync(long idJefe, long idOs, bool aprobar, string? comentario, CancellationToken ct) =>
        EjecutarAsync("SP_ResolverAutorizacionSalida",
            p =>
            {
                p.AddWithValue("p_id_jefe",    idJefe);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_aprobar",    Bit(aprobar));
                p.AddWithValue("p_comentario", Valor(comentario));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);
}
