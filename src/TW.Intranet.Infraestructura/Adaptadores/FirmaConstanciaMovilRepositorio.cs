using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Firma de informes y constancia de servicio en la app móvil (App Mobile HU-17).</summary>
public class FirmaConstanciaMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IFirmaConstanciaMovilRepositorio
{
    private static JsonElement? Json(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        try { return JsonDocument.Parse(texto).RootElement.Clone(); }
        catch (JsonException) { return null; }
    }

    public Task<RespuestaDto<FirmasMovilDto>> ObtenerFirmasAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<FirmasMovilDto>("SP_ObtenerFirmasMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<FirmasMovilDto>(1, "Servicio no encontrado.");
                var cab = new CabeceraFirmasMovilDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "cliente"), Entero(r, "plazo_horas"), EnteroNulo(r, "segundos_restantes"),
                    Booleano(r, "tacita_activa"), Entero(r, "informes"), Entero(r, "completos"), Entero(r, "firmados"), Entero(r, "responsables"), Entero(r, "resueltos"),
                    Booleano(r, "listo"), Booleano(r, "constancia_firmada"), Booleano(r, "constancia_generada"), Booleano(r, "cerrado"));

                await r.NextResultAsync(ct);
                var informes = new List<InformeFirmaMovilDto>();
                while (await r.ReadAsync(ct))
                    informes.Add(new InformeFirmaMovilDto(
                        EnteroLargo(r, "id_os_equipo"), EnteroLargoNulo(r, "id_informe"), Texto(r, "numero_informe"), Texto(r, "equipo"), Texto(r, "codigo_equipo"),
                        Booleano(r, "completo"), Texto(r, "motivo"), Texto(r, "responsable"), Texto(r, "cargo"), Texto(r, "telefono"), Texto(r, "clave"),
                        Texto(r, "firma") ?? "pendiente", FechaHora(r, "firmado_en")));

                await r.NextResultAsync(ct);
                var resp = new List<ResponsableFirmaMovilDto>();
                while (await r.ReadAsync(ct))
                    resp.Add(new ResponsableFirmaMovilDto(
                        Texto(r, "clave") ?? string.Empty, Texto(r, "nombre") ?? string.Empty, Texto(r, "cargo"), Texto(r, "telefono"), Entero(r, "n_informes"), Texto(r, "informes"),
                        Texto(r, "firma") ?? "pendiente", Texto(r, "modo"), Booleano(r, "resuelto"), FechaHora(r, "firmado_en"), Texto(r, "firmante"), Texto(r, "motivo"),
                        Json(Texto(r, "trazos"))));
                return new RespuestaDto<FirmasMovilDto>(2, mensaje, new FirmasMovilDto(cab, informes, resp));
            }, ct);

    public Task<RespuestaDto<ResumenFirmasMovilDto>> ObtenerResumenAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<ResumenFirmasMovilDto>("SP_ResumenFirmasOsMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ResumenFirmasMovilDto>(1, "Servicio no encontrado.");
                return new RespuestaDto<ResumenFirmasMovilDto>(2, mensaje, new ResumenFirmasMovilDto(
                    Entero(r, "informes"), Entero(r, "completos"), Entero(r, "firmados"), Entero(r, "resueltos"), Entero(r, "responsables"), Booleano(r, "cerrado")));
            }, ct);

    public Task<RespuestaDto<ComparablesFirmaMovilDto>> ObtenerComparablesAsync(long idUsuario, long idOs, string clave, CancellationToken ct) =>
        EjecutarAsync<ComparablesFirmaMovilDto>("SP_ObtenerFirmasComparablesMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); p.AddWithValue("p_clave", clave); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var umbral = 90;
                if (await r.ReadAsync(ct)) umbral = Entero(r, "umbral_pct");
                await r.NextResultAsync(ct);
                var lista = new List<FirmaComparableMovilDto>();
                while (await r.ReadAsync(ct))
                    if (Texto(r, "trazos") is { Length: > 0 } t) lista.Add(new FirmaComparableMovilDto(Texto(r, "nombre") ?? "otro responsable", t));
                return new RespuestaDto<ComparablesFirmaMovilDto>(2, mensaje, new ComparablesFirmaMovilDto(umbral, lista));
            }, ct);

    public Task<RespuestaDto<RegistroFirmaMovilDto>> GuardarFirmaAsync(long idUsuario, long idOs, string clave, string modo, string? trazos, string? hash, string? nombre, string? rutaFoto, string? motivo, CancellationToken ct) =>
        EjecutarAsync<RegistroFirmaMovilDto>("SP_GuardarFirmaResponsableMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_clave",      clave);
                p.AddWithValue("p_modo",       modo);
                p.AddWithValue("p_trazos",     Valor(trazos));
                p.AddWithValue("p_hash",       Valor(hash));
                p.AddWithValue("p_nombre",     Valor(nombre));
                p.AddWithValue("p_ruta_foto",  Valor(rutaFoto));
                p.AddWithValue("p_motivo",     Valor(motivo));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<RegistroFirmaMovilDto>(1, "No se pudo registrar la firma.");
                return new RespuestaDto<RegistroFirmaMovilDto>(2, mensaje, new RegistroFirmaMovilDto(
                    Texto(r, "firma") ?? "firmado", Entero(r, "responsables"), Entero(r, "resueltos"), Entero(r, "firmados"), Booleano(r, "listo"), Booleano(r, "cierre_listo"),
                    Texto(r, "ruta_foto_anterior")));
            }, ct);

    public Task<RespuestaDto<ConstanciaMovilDto>> ObtenerConstanciaAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<ConstanciaMovilDto>("SP_ObtenerConstanciaMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ConstanciaMovilDto>(1, "Servicio no encontrado.");
                var cab = new CabeceraConstanciaMovilDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, Texto(r, "cliente"), Texto(r, "direccion"), Texto(r, "contacto_nombre"), Texto(r, "contacto_cargo"),
                    Texto(r, "contacto_telefono"), Texto(r, "contacto_correo"), Texto(r, "numero_rq"), Texto(r, "fecha"), Entero(r, "informes"), Entero(r, "completos"),
                    Entero(r, "firmados"), Entero(r, "responsables"), Entero(r, "resueltos"), Texto(r, "modo"), Texto(r, "firmante"), FechaHora(r, "firmado_en"),
                    Json(Texto(r, "trazos")), Booleano(r, "tiene_foto"), Booleano(r, "firmada"), FechaHora(r, "generada_en"), FechaHora(r, "cerrada_en"),
                    Texto(r, "envio_estado") ?? "en_espera", Texto(r, "envio_destino"), FechaHora(r, "envio_en"), Texto(r, "envio_detalle"), Booleano(r, "puede_generar"), Booleano(r, "envio_activo"));

                await r.NextResultAsync(ct);
                var equipos = new List<EquipoConstanciaMovilDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(new EquipoConstanciaMovilDto(Texto(r, "equipo"), Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "serie"), Texto(r, "capacidad"), Texto(r, "d"), Texto(r, "e"),
                        Texto(r, "ubicacion"), Texto(r, "codigo"), Texto(r, "procedencia"), Texto(r, "certificado")));

                await r.NextResultAsync(ct);
                var faltan = new List<FaltaFirmaMovilDto>();
                while (await r.ReadAsync(ct))
                    faltan.Add(new FaltaFirmaMovilDto(Texto(r, "nombre") ?? string.Empty, Texto(r, "cargo"), Texto(r, "informes")));
                return new RespuestaDto<ConstanciaMovilDto>(2, mensaje, new ConstanciaMovilDto(cab, equipos, faltan));
            }, ct);

    public Task<RespuestaDto<RegistroConstanciaMovilDto>> GuardarConstanciaAsync(long idUsuario, long idOs, string accion, string? trazos, string? hash, string? nombre, string? rutaFoto, CancellationToken ct) =>
        EjecutarAsync<RegistroConstanciaMovilDto>("SP_GuardarConstanciaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_accion",     accion);
                p.AddWithValue("p_trazos",     Valor(trazos));
                p.AddWithValue("p_hash",       Valor(hash));
                p.AddWithValue("p_nombre",     Valor(nombre));
                p.AddWithValue("p_ruta_foto",  Valor(rutaFoto));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<RegistroConstanciaMovilDto>(1, "No se pudo registrar la constancia.");
                return new RespuestaDto<RegistroConstanciaMovilDto>(2, mensaje, new RegistroConstanciaMovilDto(
                    Booleano(r, "generada"), Booleano(r, "listo"), Booleano(r, "cierre_listo"), Texto(r, "ruta_foto_anterior")));
            }, ct);

    public Task<RespuestaDto<CierreConstanciaMovilDto>> RegistrarCierreAsync(long idUsuario, long idOs, string? rutaPdf, string envioEstado, string? envioDestino, string? envioDetalle, CancellationToken ct) =>
        EjecutarAsync<CierreConstanciaMovilDto>("SP_RegistrarCierreConstanciaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_os",         idOs);
                p.AddWithValue("p_ruta_pdf",      Valor(rutaPdf));
                p.AddWithValue("p_envio_estado",  envioEstado);
                p.AddWithValue("p_envio_destino", Valor(envioDestino));
                p.AddWithValue("p_envio_detalle", Valor(envioDetalle));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<CierreConstanciaMovilDto>(1, "No se pudo cerrar el servicio.");
                return new RespuestaDto<CierreConstanciaMovilDto>(2, mensaje, new CierreConstanciaMovilDto(Booleano(r, "cerrado"), FechaHora(r, "cerrada_en")));
            }, ct);

    public Task<RespuestaDto<string>> ObtenerRutaArchivoAsync(long idUsuario, long idOs, string tipo, CancellationToken ct) =>
        EjecutarAsync<string>("SP_ObtenerArchivoConstanciaMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); p.AddWithValue("p_tipo", tipo); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<string>(1, "Archivo no encontrado.");
                return new RespuestaDto<string>(2, mensaje, Texto(r, "ruta") ?? string.Empty);
            }, ct);
}
