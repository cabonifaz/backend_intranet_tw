using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// HU-55 — Registro del informe de un equipo desde la intranet. Llama a los SP de intranet (SP_ContextoRegistroIntranet, SP_IniciarRegistroIntranet, SP_AutorizarRegistroIntranet,
/// SP_LiberarRegistroIntranet, SP_MarcarRegistroInformeIntranet, SP_AjustarTiempoEquipoIntranet, SP_ForzarEvidenciaIntranet y SP_PausarEquipoAbiertoIntranet). Un conflicto de bloqueo llega
/// del SP como IdTipoMensaje 1 con el mensaje prefijado por "[409] ": aquí se deja tal cual y la API lo traduce a HTTP 409.
/// </summary>
public class RegistroInformeIntranetRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IRegistroInformeIntranetRepositorio
{
    public Task<RespuestaDto<ContextoRegistroIntranetDto>> ObtenerContextoAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<ContextoRegistroIntranetDto>("SP_ContextoRegistroIntranet",
            p =>
            {
                p.AddWithValue("p_id_registrador", idRegistrador);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_id_os_equipo",   idOsEquipo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ContextoRegistroIntranetDto>(1, "Servicio o equipo no encontrado.");
                var fila = new ContextoRegistroIntranetFilaDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os"), Texto(r, "tipo_orden"), Texto(r, "numero_rq"), Texto(r, "estado_os"),
                    Texto(r, "cliente"), Texto(r, "ruc"), Texto(r, "planta"), Texto(r, "direccion_planta"),
                    EnteroLargo(r, "id_os_equipo"), EnteroLargoNulo(r, "id_equipo"), Texto(r, "equipo_nombre"), EnteroNulo(r, "numero_equipo"),
                    Texto(r, "numero_serie"), Texto(r, "codigo_cliente"), Texto(r, "codigo_tw"), Texto(r, "marca"), Texto(r, "modelo"),
                    EnteroLargoNulo(r, "id_tecnico"), Texto(r, "tecnico"), Booleano(r, "informe_fisico"), Texto(r, "estado_equipo"),
                    Booleano(r, "iniciado"), Booleano(r, "informe_generado"), Texto(r, "numero_informe"), EnteroLargoNulo(r, "id_informe"),
                    Booleano(r, "puede_iniciar"), Texto(r, "motivo_no_puede"), Booleano(r, "registro_activo"),
                    EnteroLargoNulo(r, "registrador_id"), Texto(r, "registrador_nombre"), Booleano(r, "registro_propio"), FechaHora(r, "registro_ultima_actividad"),
                    Booleano(r, "actividad_previa_tecnico"), Texto(r, "otro_equipo_abierto"));

                await r.NextResultAsync(ct);
                var etapas = new List<EtapaRegistroIntranetDto>();
                while (await r.ReadAsync(ct))
                    etapas.Add(new EtapaRegistroIntranetDto(
                        Entero(r, "orden"), Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "estado") ?? "pendiente", Texto(r, "detalle")));

                await r.NextResultAsync(ct);
                var porCatalogo = new Dictionary<string, List<CatalogoItemRegistroIntranetDto>>(StringComparer.Ordinal);
                while (await r.ReadAsync(ct))
                {
                    var catalogo = Texto(r, "catalogo") ?? string.Empty;
                    if (!porCatalogo.TryGetValue(catalogo, out var lista)) porCatalogo[catalogo] = lista = [];
                    lista.Add(new CatalogoItemRegistroIntranetDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "clasificacion"), Entero(r, "orden")));
                }
                var catalogos = porCatalogo.ToDictionary(k => k.Key, k => (IReadOnlyList<CatalogoItemRegistroIntranetDto>)k.Value);

                return new RespuestaDto<ContextoRegistroIntranetDto>(2, mensaje, new ContextoRegistroIntranetDto(fila, etapas, catalogos));
            }, ct);

    public Task<RespuestaDto<ResultadoIniciarRegistroIntranetDto>> IniciarAsync(
        long idRegistrador, long idOs, long idOsEquipo, DateTime inicioUtc, DateTime finUtc, string motivo, string? comentario, CancellationToken ct) =>
        EjecutarAsync<ResultadoIniciarRegistroIntranetDto>("SP_IniciarRegistroIntranet",
            p =>
            {
                p.AddWithValue("p_id_registrador", idRegistrador);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_id_os_equipo",   idOsEquipo);
                p.AddWithValue("p_inicio_utc",     inicioUtc);
                p.AddWithValue("p_fin_utc",        finUtc);
                p.AddWithValue("p_motivo",         motivo);
                p.AddWithValue("p_comentario",     Valor(comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoIniciarRegistroIntranetDto>(1, "No se pudo iniciar el registro.");
                return new RespuestaDto<ResultadoIniciarRegistroIntranetDto>(2, mensaje, new ResultadoIniciarRegistroIntranetDto(
                    EnteroLargo(r, "id_registro"), Booleano(r, "idempotente"), Texto(r, "estado_os"), Texto(r, "estado_equipo"), EnteroLargo(r, "id_tecnico"),
                    Entero(r, "tiempo_aplicado_min")));
            }, ct);

    public Task<RespuestaDto<AutorizacionRegistroIntranetDto>> AutorizarAsync(long idRegistrador, long idOs, long? idOsEquipo, string modo, CancellationToken ct) =>
        EjecutarAsync<AutorizacionRegistroIntranetDto>("SP_AutorizarRegistroIntranet",
            p =>
            {
                p.AddWithValue("p_id_registrador", idRegistrador);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_id_os_equipo",   Valor(idOsEquipo));
                p.AddWithValue("p_modo",           modo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AutorizacionRegistroIntranetDto>(1, "No se pudo autorizar el registro.");
                return new RespuestaDto<AutorizacionRegistroIntranetDto>(2, mensaje, new AutorizacionRegistroIntranetDto(
                    EnteroLargo(r, "id_tecnico"), EnteroLargoNulo(r, "id_registro"), Booleano(r, "informe_fisico")));
            }, ct);

    public Task<RespuestaDto<object>> LiberarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct) =>
        SoloEncabezadoAsync("SP_LiberarRegistroIntranet", idRegistrador, idOs, idOsEquipo, ct);

    public Task<RespuestaDto<object>> MarcarInformeAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct) =>
        SoloEncabezadoAsync("SP_MarcarRegistroInformeIntranet", idRegistrador, idOs, idOsEquipo, ct);

    public Task<RespuestaDto<object>> AjustarTiempoAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct) =>
        SoloEncabezadoAsync("SP_AjustarTiempoEquipoIntranet", idRegistrador, idOs, idOsEquipo, ct);

    public Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> ForzarEvidenciaAsync(
        long idRegistrador, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct) =>
        EjecutarAsync<ResultadoForzarEvidenciaMovilDto>("SP_ForzarEvidenciaIntranet",
            p =>
            {
                p.AddWithValue("p_id_registrador", idRegistrador);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_id_os_equipo",   idOsEquipo);
                p.AddWithValue("p_id_evidencia",   idEvidencia);
                p.AddWithValue("p_motivo",         motivo);
            },
            async (r, mensaje) =>
            {
                // Mismos result sets que SP_ForzarEvidenciaMovil después del encabezado
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoForzarEvidenciaMovilDto>(1, "No se pudo registrar la evidencia forzada.");
                return new RespuestaDto<ResultadoForzarEvidenciaMovilDto>(2, mensaje, new ResultadoForzarEvidenciaMovilDto(
                    EnteroLargo(r, "id_evidencia"), FechaHora(r, "forzada_en"), Entero(r, "intentos_previos"), Entero(r, "notificados")));
            }, ct);

    public Task<RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>> PausarEquipoAbiertoAsync(
        long idRegistrador, long idOs, long idOsEquipo, string? motivo, CancellationToken ct) =>
        EjecutarAsync<ResultadoPausarEquipoAbiertoIntranetDto>("SP_PausarEquipoAbiertoIntranet",
            p =>
            {
                p.AddWithValue("p_id_registrador", idRegistrador);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_id_os_equipo",   idOsEquipo);
                p.AddWithValue("p_motivo",         Valor(motivo));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>(1, "No hay otro equipo en ejecución.");
                // El contrato nombra la tercera columna "nombre del equipo pausado": se acepta "equipo" o "nombre"
                var equipo = Existe(r, "equipo") ? Texto(r, "equipo") : Existe(r, "nombre") ? Texto(r, "nombre") : null;
                return new RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>(2, mensaje, new ResultadoPausarEquipoAbiertoIntranetDto(
                    EnteroLargo(r, "id_os"), EnteroLargo(r, "id_os_equipo"), equipo));
            }, ct);

    private Task<RespuestaDto<object>> SoloEncabezadoAsync(string sp, long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<object>(sp,
            p =>
            {
                p.AddWithValue("p_id_registrador", idRegistrador);
                p.AddWithValue("p_id_os",          idOs);
                p.AddWithValue("p_id_os_equipo",   idOsEquipo);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    private static bool Existe(MySqlConnector.MySqlDataReader r, string columna)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), columna, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }
}
