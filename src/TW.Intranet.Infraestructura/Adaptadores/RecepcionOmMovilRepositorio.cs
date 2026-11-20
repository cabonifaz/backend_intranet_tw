using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Recepción de instrumentos (OM) en el taller desde la app móvil (App Mobile HU-23).</summary>
public class RecepcionOmMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IRecepcionOmMovilRepositorio
{
    private static JsonElement? Json(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        try { return JsonDocument.Parse(texto).RootElement.Clone(); }
        catch (JsonException) { return null; }
    }

    /// <summary>Los códigos de accesorios guardados como JSON (["caja_original", …]).</summary>
    private static IReadOnlyList<string> Lista(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return [];
        try { return JsonSerializer.Deserialize<List<string>>(texto) ?? []; }
        catch (JsonException) { return []; }
    }

    /// <summary>Los nombres separados por «|» que arma el SP (SP_ObtenerRecepcionesOmMovil).</summary>
    private static IReadOnlyList<string> Nombres(string? texto) =>
        string.IsNullOrWhiteSpace(texto) ? [] : texto.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private static async Task<List<ItemRecepcionOmMovilDto>> LeerItemsAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<ItemRecepcionOmMovilDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new ItemRecepcionOmMovilDto(
                EnteroLargo(r, "id_os"), Texto(r, "numero") ?? string.Empty, Texto(r, "cliente"), Texto(r, "numero_rq"), Texto(r, "servicio"),
                Entero(r, "total_instrumentos"), Entero(r, "recibidos"), Texto(r, "estado") ?? "por_recibir", Texto(r, "hora"), Texto(r, "guia"), Nombres(Texto(r, "pendientes"))));
        return lista;
    }

    public Task<RespuestaDto<ListaRecepcionOmMovilDto>> ObtenerListaAsync(long idUsuario, string? busqueda, CancellationToken ct) =>
        EjecutarAsync<ListaRecepcionOmMovilDto>("SP_ObtenerRecepcionesOmMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_busqueda", Valor(busqueda)); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var porRecibir = await LeerItemsAsync(r, ct);
                await r.NextResultAsync(ct);
                var hoy = await LeerItemsAsync(r, ct);
                return new RespuestaDto<ListaRecepcionOmMovilDto>(2, mensaje, new ListaRecepcionOmMovilDto(porRecibir, hoy));
            }, ct);

    public Task<RespuestaDto<DetalleRecepcionOmMovilDto>> ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<DetalleRecepcionOmMovilDto>("SP_ObtenerRecepcionOmMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DetalleRecepcionOmMovilDto>(1, "Orden de metrología no encontrada o no asignada a tu usuario.");
                var cab = new CabeceraRecepcionOmMovilDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero") ?? string.Empty, Texto(r, "cliente"), Texto(r, "numero_rq"), Texto(r, "servicio"),
                    Entero(r, "total_instrumentos"), Entero(r, "recibidos"), Booleano(r, "puede_recibir"), Texto(r, "estado") ?? "por_recibir");

                await r.NextResultAsync(ct);
                var instrumentos = new List<InstrumentoRecepcionOmMovilDto>();
                while (await r.ReadAsync(ct))
                    instrumentos.Add(new InstrumentoRecepcionOmMovilDto(
                        EnteroLargo(r, "id_os_equipo"), Entero(r, "numero"), Texto(r, "nombre") ?? string.Empty, Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "serie"),
                        Texto(r, "capacidad"), Texto(r, "codigo_cliente"), Texto(r, "codigo_tw"), Booleano(r, "recibido"), Texto(r, "estado_fisico"), Texto(r, "observaciones"),
                        Entero(r, "fotos"), Texto(r, "recibido_en")));

                await r.NextResultAsync(ct);
                var recepciones = new List<RecepcionRegistradaOmMovilDto>();
                while (await r.ReadAsync(ct))
                    recepciones.Add(new RecepcionRegistradaOmMovilDto(
                        EnteroLargo(r, "id_recepcion"), Texto(r, "guia"), Texto(r, "medio"), Texto(r, "entrego"), Texto(r, "entrego_cargo"), Texto(r, "recibio"), Texto(r, "fecha"),
                        Texto(r, "estado") ?? "conforme", Texto(r, "motivo_parcial"), Entero(r, "instrumentos"), Booleano(r, "tiene_constancia")));

                return new RespuestaDto<DetalleRecepcionOmMovilDto>(2, mensaje, new DetalleRecepcionOmMovilDto(cab, instrumentos, recepciones));
            }, ct);

    public Task<RespuestaDto<FotoRecepcionOmMovilDto>> RegistrarFotoAsync(long idUsuario, long idOs, long idOsEquipo, string ruta, CancellationToken ct) =>
        EjecutarAsync<FotoRecepcionOmMovilDto>("SP_RegistrarFotoRecepcionOmMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_ruta", ruta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<FotoRecepcionOmMovilDto>(1, "No se pudo guardar la foto.");
                return new RespuestaDto<FotoRecepcionOmMovilDto>(2, mensaje, new FotoRecepcionOmMovilDto(EnteroLargo(r, "id_foto"), Entero(r, "orden")));
            }, ct);

    public Task<RespuestaDto<string>> QuitarFotoAsync(long idUsuario, long idOs, long idOsEquipo, long idFoto, CancellationToken ct) =>
        EjecutarAsync<string>("SP_QuitarFotoRecepcionOmMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_id_foto", idFoto);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<string>(1, "Foto no encontrada.");
                return new RespuestaDto<string>(2, mensaje, Texto(r, "ruta") ?? string.Empty);
            }, ct);

    public Task<RespuestaDto<List<FotoRecepcionOmMovilDto>>> ObtenerFotosAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<List<FotoRecepcionOmMovilDto>>("SP_ObtenerFotosRecepcionOmMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<FotoRecepcionOmMovilDto>();
                while (await r.ReadAsync(ct)) lista.Add(new FotoRecepcionOmMovilDto(EnteroLargo(r, "id_foto"), Entero(r, "orden")));
                return new RespuestaDto<List<FotoRecepcionOmMovilDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<string>> ObtenerRutaFotoAsync(long idUsuario, long idFoto, CancellationToken ct) =>
        EjecutarAsync<string>("SP_ObtenerArchivoFotoRecepcionOmMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_foto", idFoto); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<string>(1, "Foto no encontrada.");
                return new RespuestaDto<string>(2, mensaje, Texto(r, "ruta") ?? string.Empty);
            }, ct);

    public Task<RespuestaDto<InstrumentoQrRecepcionOmMovilDto>> BuscarQrAsync(long idUsuario, long idOs, string texto, CancellationToken ct) =>
        EjecutarAsync<InstrumentoQrRecepcionOmMovilDto>("SP_BuscarInstrumentoQrRecepcionOmMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); p.AddWithValue("p_texto", texto); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<InstrumentoQrRecepcionOmMovilDto>(1, "El código leído no corresponde a ningún instrumento de esta orden.");
                return new RespuestaDto<InstrumentoQrRecepcionOmMovilDto>(2, mensaje, new InstrumentoQrRecepcionOmMovilDto(EnteroLargo(r, "id_os_equipo"), Texto(r, "nombre") ?? string.Empty));
            }, ct);

    public Task<RespuestaDto<RegistroRecepcionOmMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, string numeroGuia, string medioEntrega, string entregoNombre, string? entregoCargo, string? motivoParcial,
        string instrumentosJson, string firmaJson, CancellationToken ct) =>
        EjecutarAsync<RegistroRecepcionOmMovilDto>("SP_RegistrarRecepcionOmMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_guia", numeroGuia);
                p.AddWithValue("p_medio", medioEntrega);
                p.AddWithValue("p_entrego", entregoNombre);
                p.AddWithValue("p_cargo", Valor(entregoCargo));
                p.AddWithValue("p_motivo", Valor(motivoParcial));
                p.AddWithValue("p_instrumentos", instrumentosJson);
                p.AddWithValue("p_firma", firmaJson);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<RegistroRecepcionOmMovilDto>(1, "No se pudo registrar la recepción.");
                return new RespuestaDto<RegistroRecepcionOmMovilDto>(2, mensaje, new RegistroRecepcionOmMovilDto(
                    EnteroLargo(r, "id_recepcion"), Texto(r, "estado") ?? "conforme", Booleano(r, "parcial"), Entero(r, "instrumentos_recibidos"),
                    Entero(r, "instrumentos_pendientes"), Entero(r, "notificados")));
            }, ct);

    public Task<RespuestaDto<ConstanciaRecepcionOmDto>> ObtenerConstanciaAsync(long idUsuario, long idRecepcion, CancellationToken ct) =>
        EjecutarAsync<ConstanciaRecepcionOmDto>("SP_ObtenerConstanciaRecepcionOmMovil",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_recepcion", idRecepcion); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ConstanciaRecepcionOmDto>(1, "Constancia no encontrada.");
                var cab = new CabeceraConstanciaRecepcionOmDto(
                    EnteroLargo(r, "id_recepcion"), Texto(r, "numero_om") ?? string.Empty, Texto(r, "cliente"), Texto(r, "direccion"), Texto(r, "contacto_nombre"),
                    Texto(r, "contacto_correo"), Texto(r, "numero_rq"), Texto(r, "guia"), Texto(r, "medio"), Texto(r, "entrego"), Texto(r, "entrego_cargo"), Texto(r, "recibio"),
                    Texto(r, "recibido_en"), Texto(r, "estado") ?? "conforme", Texto(r, "motivo_parcial"), Json(Texto(r, "firma_trazos")), Texto(r, "ruta_constancia"),
                    Booleano(r, "correo_enviado"), Booleano(r, "envio_activo"));

                await r.NextResultAsync(ct);
                var instrumentos = new List<InstrumentoConstanciaRecepcionOmDto>();
                while (await r.ReadAsync(ct))
                    instrumentos.Add(new InstrumentoConstanciaRecepcionOmDto(
                        Texto(r, "nombre") ?? string.Empty, Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "serie"), Texto(r, "codigo"), Texto(r, "estado_fisico"),
                        Texto(r, "observaciones"), Lista(Texto(r, "accesorios")), Entero(r, "fotos")));

                await r.NextResultAsync(ct);
                var pendientes = new List<PendienteConstanciaRecepcionOmDto>();
                while (await r.ReadAsync(ct))
                    pendientes.Add(new PendienteConstanciaRecepcionOmDto(Texto(r, "nombre") ?? string.Empty, Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "serie"), Texto(r, "codigo")));

                return new RespuestaDto<ConstanciaRecepcionOmDto>(2, mensaje, new ConstanciaRecepcionOmDto(cab, instrumentos, pendientes));
            }, ct);

    public Task<RespuestaDto<string?>> GuardarConstanciaAsync(long idUsuario, long idRecepcion, string ruta, bool correoEnviado, CancellationToken ct) =>
        EjecutarAsync<string?>("SP_GuardarConstanciaRecepcionOmMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_recepcion", idRecepcion);
                p.AddWithValue("p_ruta", ruta);
                p.AddWithValue("p_correo_enviado", Bit(correoEnviado));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var anterior = await r.ReadAsync(ct) ? Texto(r, "ruta_anterior") : null;
                return new RespuestaDto<string?>(2, mensaje, anterior);
            }, ct);
}
