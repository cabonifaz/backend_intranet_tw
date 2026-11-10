using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Registro fotográfico del equipo en la app móvil (App Mobile HU-11 / HU-12 / HU-13).</summary>
public class EvidenciasMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IEvidenciasMovilRepositorio
{
    private static JsonElement? Json(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        try { return JsonDocument.Parse(texto).RootElement.Clone(); }
        catch (JsonException) { return null; }
    }

    public Task<RespuestaDto<EvidenciasMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<EvidenciasMovilDto>("SP_ObtenerEvidenciasMovil",
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
                    return new RespuestaDto<EvidenciasMovilDto>(1, "Servicio o equipo no encontrado.");
                var cabecera = new CabeceraEvidenciasMovilDto(
                    EnteroLargo(r, "id_os"), EnteroLargo(r, "id_os_equipo"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "nombre") ?? "Equipo", Entero(r, "numero"),
                    Texto(r, "servicio_sigla"), Texto(r, "num_serie"), Texto(r, "codigo_cliente"), Texto(r, "codigo_tw"), Texto(r, "marca"), Texto(r, "modelo"),
                    Texto(r, "estado") ?? "por_iniciar", Booleano(r, "puede_registrar"), Texto(r, "numero_rq"), Entero(r, "total"), Entero(r, "completas"),
                    Entero(r, "forzadas"), Entero(r, "rechazadas"), Entero(r, "obligatorias_faltan"), Booleano(r, "puede_guardar"));

                await r.NextResultAsync(ct);
                var lista = new List<EvidenciaMovilDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new EvidenciaMovilDto(
                        Entero(r, "orden"), Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "descripcion") ?? string.Empty,
                        Booleano(r, "obligatoria"), Texto(r, "medio") ?? "foto", Texto(r, "estado") ?? "pendiente", EnteroLargoNulo(r, "id_evidencia"),
                        EnteroNulo(r, "intento"), Booleano(r, "es_video"), DecimalNulo(r, "duracion_seg"), Entero(r, "paginas"), Texto(r, "motivo_rechazo_ia"),
                        Texto(r, "motivo_forzado"), Texto(r, "forzada_por") is { Length: > 0 } fp ? fp : null, FechaHora(r, "forzada_en"), Entero(r, "intentos_previos"),
                        FechaHora(r, "capturada_en"), Json(Texto(r, "resultado_ia")), Booleano(r, "tiene_cuadro")));

                return new RespuestaDto<EvidenciasMovilDto>(2, mensaje, new EvidenciasMovilDto(cabecera, lista));
            }, ct);

    public Task<RespuestaDto<ResultadoEvidenciaMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, long idOsEquipo, string codigo, int pagina, string? rutaArchivo, string? rutaCuadro, decimal? duracionSeg,
        decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, string? qrTexto, ResultadoValidacionEvidenciaIa ia, CancellationToken ct) =>
        EjecutarAsync<ResultadoEvidenciaMovilDto>("SP_RegistrarEvidenciaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_os",         idOs);
                p.AddWithValue("p_id_os_equipo",  idOsEquipo);
                p.AddWithValue("p_codigo",        codigo);
                p.AddWithValue("p_pagina",        pagina);
                p.AddWithValue("p_ruta_archivo",  Valor(rutaArchivo));
                p.AddWithValue("p_ruta_cuadro",   Valor(rutaCuadro));
                p.AddWithValue("p_duracion",      Valor(duracionSeg));
                p.AddWithValue("p_latitud",       Valor(latitud));
                p.AddWithValue("p_longitud",      Valor(longitud));
                p.AddWithValue("p_precision",     Valor(precision));
                p.AddWithValue("p_capturado_utc", Valor(capturadoUtc));
                p.AddWithValue("p_qr_texto",      Valor(qrTexto));
                p.AddWithValue("p_ia_estado",     ia.Estado);
                p.AddWithValue("p_ia_motivo",     Valor(ia.Motivo));
                p.AddWithValue("p_ia_json",       Valor(ia.DatosJson));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoEvidenciaMovilDto>(1, "No se pudo guardar la evidencia.");
                bool? coincide = EsNulo(r, "coincide") ? null : Booleano(r, "coincide");
                return new RespuestaDto<ResultadoEvidenciaMovilDto>(2, mensaje, new ResultadoEvidenciaMovilDto(
                    EnteroLargo(r, "id_evidencia"), Texto(r, "estado") ?? "omitida", Texto(r, "motivo_rechazo"), Entero(r, "intento"), coincide,
                    Texto(r, "numero_rq"), Json(ia.DatosJson), mensaje));
            }, ct);

    public Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> ForzarAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct) =>
        EjecutarAsync<ResultadoForzarEvidenciaMovilDto>("SP_ForzarEvidenciaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_id_evidencia", idEvidencia);
                p.AddWithValue("p_motivo",       motivo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoForzarEvidenciaMovilDto>(1, "No se pudo registrar la evidencia forzada.");
                return new RespuestaDto<ResultadoForzarEvidenciaMovilDto>(2, mensaje, new ResultadoForzarEvidenciaMovilDto(
                    EnteroLargo(r, "id_evidencia"), FechaHora(r, "forzada_en"), Entero(r, "intentos_previos"), Entero(r, "notificados")));
            }, ct);

    public Task<RespuestaDto<ArchivoEvidenciaMovilDto>> ObtenerArchivoAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct) =>
        EjecutarAsync<ArchivoEvidenciaMovilDto>("SP_ObtenerArchivoEvidenciaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_id_evidencia", idEvidencia);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ArchivoEvidenciaMovilDto>(1, "Evidencia no encontrada.");
                return new RespuestaDto<ArchivoEvidenciaMovilDto>(2, mensaje, new ArchivoEvidenciaMovilDto(
                    Texto(r, "ruta") ?? string.Empty, Texto(r, "ruta_cuadro"), Booleano(r, "es_video")));
            }, ct);
}
