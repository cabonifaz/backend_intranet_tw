using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Trabajo en el equipo y variables ambientales de la app móvil (App Mobile HU-08 / HU-09).</summary>
public class TrabajoEquipoMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ITrabajoEquipoMovilRepositorio
{
    public Task<RespuestaDto<TrabajoEquipoMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<TrabajoEquipoMovilDto>("SP_ObtenerTrabajoEquipoMovil",
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
                    return new RespuestaDto<TrabajoEquipoMovilDto>(1, "Servicio o equipo no encontrado.");
                var cabecera = new CabeceraTrabajoEquipoMovilDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "cliente"), Texto(r, "tipo_orden") ?? "OS", Texto(r, "numero_rq"),
                    Texto(r, "servicio_sigla"), Texto(r, "servicio"), EnteroLargo(r, "id_os_equipo"), Texto(r, "nombre") ?? "Equipo",
                    Texto(r, "num_serie"), Texto(r, "codigo_cliente"), Texto(r, "codigo_tw"), Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "ubicacion"),
                    Texto(r, "estado") ?? "por_iniciar", EnteroNulo(r, "tiempo_estimado_min"), Entero(r, "tiempo_real_min"), FechaHora(r, "iniciado_en"),
                    Booleano(r, "puede_registrar"), Entero(r, "etapas_conformes"), Entero(r, "etapas_total"), Booleano(r, "puede_finalizar"));

                await r.NextResultAsync(ct);
                VariablesAmbientalesMovilDto? variables = null;
                if (await r.ReadAsync(ct))
                    variables = new VariablesAmbientalesMovilDto(
                        DecimalNulo(r, "temperatura_c") ?? 0m, DecimalNulo(r, "humedad_pct") ?? 0m, Texto(r, "procedencia") ?? "N.I", FechaHora(r, "registrado_en"));

                await r.NextResultAsync(ct);
                var etapas = new List<EtapaTrabajoMovilDto>();
                while (await r.ReadAsync(ct))
                    etapas.Add(new EtapaTrabajoMovilDto(
                        Entero(r, "orden"), Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "estado") ?? "pendiente",
                        Texto(r, "detalle"), Booleano(r, "disponible")));

                return new RespuestaDto<TrabajoEquipoMovilDto>(2, mensaje, new TrabajoEquipoMovilDto(cabecera, variables, etapas));
            }, ct);

    public Task<RespuestaDto<ResultadoVariablesAmbientalesMovilDto>> GuardarVariablesAsync(
        long idUsuario, long idOs, long idOsEquipo, decimal temperatura, decimal humedad, string? procedencia, DateTime? capturadoUtc, CancellationToken ct) =>
        EjecutarAsync<ResultadoVariablesAmbientalesMovilDto>("SP_GuardarVariablesAmbientalesMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_os",         idOs);
                p.AddWithValue("p_id_os_equipo",  idOsEquipo);
                p.AddWithValue("p_temperatura",   temperatura);
                p.AddWithValue("p_humedad",       humedad);
                p.AddWithValue("p_procedencia",   Valor(procedencia));
                p.AddWithValue("p_capturado_utc", Valor(capturadoUtc));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoVariablesAmbientalesMovilDto>(1, "No se pudieron guardar las variables ambientales.");
                return new RespuestaDto<ResultadoVariablesAmbientalesMovilDto>(2, mensaje, new ResultadoVariablesAmbientalesMovilDto(
                    DecimalNulo(r, "temperatura_c") ?? temperatura, DecimalNulo(r, "humedad_pct") ?? humedad, Texto(r, "procedencia") ?? "N.I",
                    FechaHora(r, "registrado_en"), Booleano(r, "actualizada"), Booleano(r, "repetida")));
            }, ct);
}
