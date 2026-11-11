using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Ensayos y Calibración de la app móvil (App Mobile HU-10).</summary>
public class EnsayosMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IEnsayosMovilRepositorio
{
    public Task<RespuestaDto<EnsayosMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<EnsayosMovilDto>("SP_ObtenerEnsayosMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<EnsayosMovilDto>(1, "Servicio o equipo no encontrado.");
                var cabecera = new CabeceraEnsayosMovilDto(
                    EnteroLargo(r, "id_os"), EnteroLargo(r, "id_os_equipo"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "nombre") ?? "Equipo",
                    Entero(r, "numero"), Texto(r, "unidad") ?? "kg", Texto(r, "clase"), DecimalNulo(r, "cap_maxima"), DecimalNulo(r, "d"), DecimalNulo(r, "e"),
                    Booleano(r, "evaluable"), Texto(r, "forma_plato") ?? "rectangular", Texto(r, "motivo_error_critico"), Booleano(r, "acepta_error"),
                    Booleano(r, "finalizado"), FechaHora(r, "finalizado_en"), Booleano(r, "puede_registrar"), Texto(r, "area_encargado"));

                await r.NextResultAsync(ct);
                var pesaje = new List<LecturaPesajeMovilDto>();
                while (await r.ReadAsync(ct))
                    pesaje.Add(new LecturaPesajeMovilDto(Entero(r, "orden"), DecimalNulo(r, "carga") ?? 0m, DecimalNulo(r, "indicacion"), DecimalNulo(r, "error"),
                        DecimalNulo(r, "emp"), Texto(r, "resultado"), Booleano(r, "critico")));

                await r.NextResultAsync(ct);
                var ecc = new List<LecturaExcentricidadMovilDto>();
                while (await r.ReadAsync(ct))
                    ecc.Add(new LecturaExcentricidadMovilDto(Entero(r, "grupo"), Entero(r, "posicion"), DecimalNulo(r, "carga") ?? 0m, DecimalNulo(r, "indicacion"),
                        DecimalNulo(r, "error"), DecimalNulo(r, "emp"), Texto(r, "resultado"), Booleano(r, "critico")));

                await r.NextResultAsync(ct);
                EncargadoEnsayoMovilDto? encargado = null;
                if (await r.ReadAsync(ct))
                    encargado = new EncargadoEnsayoMovilDto(EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? string.Empty, Texto(r, "cargo"), Texto(r, "telefono"), Texto(r, "area"));

                return new RespuestaDto<EnsayosMovilDto>(2, mensaje, new EnsayosMovilDto(cabecera, pesaje, ecc, encargado));
            }, ct);

    public Task<RespuestaDto<ResultadoGuardarEnsayosMovilDto>> GuardarAsync(
        long idUsuario, long idOs, long idOsEquipo, string formaPlato, string json, string? motivo, bool finalizar, CancellationToken ct) =>
        EjecutarAsync<ResultadoGuardarEnsayosMovilDto>("SP_GuardarEnsayosMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_forma",        formaPlato);
                p.AddWithValue("p_json",         json);
                p.AddWithValue("p_motivo",       Valor(motivo));
                p.AddWithValue("p_finalizar",    Bit(finalizar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoGuardarEnsayosMovilDto>(1, "No se pudieron guardar los ensayos.");
                return new RespuestaDto<ResultadoGuardarEnsayosMovilDto>(2, mensaje, new ResultadoGuardarEnsayosMovilDto(
                    EnteroLargo(r, "id_informe"), Entero(r, "criticos"), Booleano(r, "finalizado"), Entero(r, "notificados")));
            }, ct);

    public Task<RespuestaDto<ResultadoLlamadaEnsayoMovilDto>> RegistrarLlamadaAsync(long idUsuario, long idOs, long idOsEquipo, string? detalle, CancellationToken ct) =>
        EjecutarAsync<ResultadoLlamadaEnsayoMovilDto>("SP_RegistrarLlamadaEnsayoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_detalle",      Valor(detalle));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoLlamadaEnsayoMovilDto>(1, "No se pudo registrar la llamada.");
                return new RespuestaDto<ResultadoLlamadaEnsayoMovilDto>(2, mensaje, new ResultadoLlamadaEnsayoMovilDto(
                    Texto(r, "nombre") ?? string.Empty, Texto(r, "cargo"), Texto(r, "telefono") ?? string.Empty, Texto(r, "area")));
            }, ct);
}
