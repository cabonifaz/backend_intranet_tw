using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Propuestas comerciales (HU-07).</summary>
public class PropuestasRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IPropuestasRepositorio
{
    // ── Datos heredados del RQ ────────────────────────────────────────────────
    public Task<RespuestaDto<DatosNuevaPropuestaDto>> ObtenerDatosNuevaPropuestaAsync(long idRequerimiento, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDatosNuevaPropuesta",
            p => p.AddWithValue("p_id_requerimiento", idRequerimiento),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DatosNuevaPropuestaDto>(1, "Requerimiento no encontrado.");

                var idRq        = EnteroLargo(r, "id_requerimiento");
                var numeroRq    = Texto(r, "numero_requerimiento") ?? "";
                var estadoRq    = Texto(r, "estado_requerimiento") ?? "";
                var idCliente   = EnteroLargo(r, "id_cliente");
                var razonSocial = Texto(r, "razon_social") ?? "";
                var ruc         = Texto(r, "ruc") ?? "";
                var idSede      = EnteroLargoNulo(r, "id_sede");
                var nombreSede  = Texto(r, "nombre_sede");
                var idContacto  = EnteroLargoNulo(r, "id_contacto");
                var nombreCont  = Texto(r, "nombre_contacto");
                var cargoCont   = Texto(r, "cargo_contacto");
                var idArea      = EnteroNulo(r, "id_area");
                var areaLabel   = Texto(r, "area_label");
                var idPrioridad = EnteroNulo(r, "id_prioridad");
                var prioLabel   = Texto(r, "prioridad_label");
                var descripcion = Texto(r, "descripcion") ?? "";

                PropuestaExistenteDto? existente = null;
                await r.NextResultAsync(ct);
                if (await r.ReadAsync(ct))
                    existente = new PropuestaExistenteDto(
                        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "",
                        Entero(r, "version"), Texto(r, "estado") ?? "");

                return new RespuestaDto<DatosNuevaPropuestaDto>(2, mensaje, new DatosNuevaPropuestaDto(
                    idRq, numeroRq, estadoRq, idCliente, razonSocial, ruc, idSede, nombreSede,
                    idContacto, nombreCont, cargoCont, idArea, areaLabel, idPrioridad, prioLabel,
                    descripcion, existente));
            }, ct);

    // ── Listado (bandeja HU-08) ───────────────────────────────────────────────
    public Task<RespuestaDto<PropuestasPaginadoDto>> ObtenerPropuestasAsync(FiltrosPropuestasDto f, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPropuestas",
            p =>
            {
                p.AddWithValue("p_id_requerimiento",    Valor(f.IdRequerimiento));
                p.AddWithValue("p_estado",              Valor(f.Estado));
                p.AddWithValue("p_busqueda",            Valor(f.Busqueda));
                p.AddWithValue("p_pagina",              f.Pagina);
                p.AddWithValue("p_por_pagina",          f.PorPagina);
                p.AddWithValue("p_grupo_estado",        Valor(f.GrupoEstado));
                p.AddWithValue("p_anio",                Valor(f.Anio));
                p.AddWithValue("p_id_comercial",        Valor(f.IdComercial));
                p.AddWithValue("p_solo_ultima_version", Bit(f.SoloUltimaVersion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<PropuestaResumenDto>();
                while (await r.ReadAsync(ct))
                {
                    items.Add(new PropuestaResumenDto(
                        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Entero(r, "version"),
                        EnteroLargo(r, "id_requerimiento"), Texto(r, "numero_requerimiento") ?? "",
                        EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "referencia"),
                        Texto(r, "moneda"), DecimalNulo(r, "total") ?? 0, DecimalNulo(r, "total_opcionales") ?? 0,
                        Texto(r, "estado") ?? "", FechaHora(r, "fecha_creacion"), Texto(r, "responsable"),
                        Texto(r, "ruc"),
                        Texto(r, "estado_grupo") ?? "",
                        Texto(r, "accion") ?? "ver_detalle",
                        EnteroNulo(r, "sla_dias_restantes"),
                        FechaHora(r, "fecha_modificacion"),
                        EnteroLargoNulo(r, "id_responsable")));
                }
                int total = await LeerTotalAsync(r, ct);
                return new RespuestaDto<PropuestasPaginadoDto>(2, mensaje,
                    new PropuestasPaginadoDto(items, total, f.Pagina, f.PorPagina));
            }, ct);

    // ── KPIs (bandeja HU-08) ──────────────────────────────────────────────────
    public Task<RespuestaDto<KpisPropuestasDto>> ObtenerKpisAsync(int? anio, long? idComercial, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerKpisPropuestas",
            p =>
            {
                p.AddWithValue("p_anio",         Valor(anio));
                p.AddWithValue("p_id_comercial", Valor(idComercial));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<KpisPropuestasDto>(2, mensaje, new KpisPropuestasDto(0, 0, 0, 0, 0, 0));

                return new RespuestaDto<KpisPropuestasDto>(2, mensaje, new KpisPropuestasDto(
                    (int)(DecimalNulo(r, "pendientes")      ?? 0),
                    DecimalNulo(r, "variacion_pendientes")  ?? 0,
                    (int)(DecimalNulo(r, "por_visto_bueno") ?? 0),
                    (int)(DecimalNulo(r, "por_enviar")      ?? 0),
                    (int)(DecimalNulo(r, "en_seguimiento")  ?? 0),
                    (int)(DecimalNulo(r, "sla_vencidos")    ?? 0)));
            }, ct);

    // ── Propuesta completa ────────────────────────────────────────────────────
    public Task<RespuestaDto<PropuestaDetalleDto>> ObtenerPropuestaPorIdAsync(long idPropuesta, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPropuestaPorId",
            p => p.AddWithValue("p_id_propuesta", idPropuesta),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PropuestaDetalleDto>(1, "Propuesta no encontrada.");

                var d = new PropuestaDetalleDto
                {
                    IdPropuesta           = EnteroLargo(r, "id_propuesta"),
                    Numero                = Texto(r, "numero") ?? "",
                    Version               = Entero(r, "version"),
                    Estado                = Texto(r, "estado") ?? "",
                    IdPropuestaPadre      = EnteroLargoNulo(r, "id_propuesta_padre"),
                    IdRequerimiento       = EnteroLargo(r, "id_requerimiento"),
                    NumeroRequerimiento   = Texto(r, "numero_requerimiento") ?? "",
                    IdCliente             = EnteroLargo(r, "id_cliente"),
                    RazonSocial           = Texto(r, "razon_social") ?? "",
                    Ruc                   = Texto(r, "ruc") ?? "",
                    IdSede                = EnteroLargoNulo(r, "id_sede"),
                    NombreSede            = Texto(r, "nombre_sede"),
                    IdContacto            = EnteroLargoNulo(r, "id_contacto"),
                    NombreContacto        = Texto(r, "nombre_contacto"),
                    CargoContacto         = Texto(r, "cargo_contacto"),
                    IdResponsable         = EnteroLargoNulo(r, "id_responsable"),
                    NombreResponsable     = Texto(r, "nombre_responsable"),
                    TipoServicio          = Texto(r, "tipo_servicio"),
                    Referencia            = Texto(r, "referencia"),
                    Introduccion          = Texto(r, "introduccion"),
                    NotasGenerales        = Texto(r, "notas_generales"),
                    SeccionesActivas      = LeerListaJson(Texto(r, "secciones_activas")),
                    EsTercerizado         = Booleano(r, "es_tercerizado"),
                    TerceroRuc            = Texto(r, "tercero_ruc"),
                    TerceroRazonSocial    = Texto(r, "tercero_razon_social"),
                    TerceroDireccion      = Texto(r, "tercero_direccion"),
                    IdMoneda              = Entero(r, "id_moneda"),
                    Moneda                = Texto(r, "moneda"),
                    MonedaSimbolo         = Texto(r, "moneda_simbolo"),
                    TipoCambio            = DecimalNulo(r, "tipo_cambio"),
                    GarantiaMeses         = EnteroNulo(r, "garantia_meses"),
                    MostrarGarantia       = Booleano(r, "mostrar_garantia"),
                    PlazoEntregaDias      = EnteroNulo(r, "plazo_entrega_dias"),
                    PlazoEntregaUnidad    = Texto(r, "plazo_entrega_unidad"),
                    PlazoEntregaCondicion = Texto(r, "plazo_entrega_condicion"),
                    VigenciaDias          = EnteroNulo(r, "vigencia_dias"),
                    AplicaIgv             = Booleano(r, "aplica_igv"),
                    PreciosIncluyenIgv    = Booleano(r, "precios_incluyen_igv"),
                    IgvPct                = DecimalNulo(r, "igv_pct") ?? 18,
                    Subtotal              = DecimalNulo(r, "subtotal") ?? 0,
                    DescuentoPct          = DecimalNulo(r, "descuento_pct"),
                    DescuentoMonto        = DecimalNulo(r, "descuento_monto") ?? 0,
                    IdMotivoDescuento     = EnteroNulo(r, "id_motivo_descuento"),
                    MotivoDescuento       = Texto(r, "motivo_descuento"),
                    IgvMonto              = DecimalNulo(r, "igv_monto") ?? 0,
                    Total                 = DecimalNulo(r, "total") ?? 0,
                    SubtotalOpcionales    = DecimalNulo(r, "subtotal_opcionales") ?? 0,
                    DescuentoOpcionales   = DecimalNulo(r, "descuento_opcionales") ?? 0,
                    TotalOpcionales       = DecimalNulo(r, "total_opcionales") ?? 0,
                    NombreCreador         = Texto(r, "nombre_creador"),
                    FechaCreacion         = FechaHora(r, "fecha_creacion"),
                    FechaEnvio            = FechaHora(r, "fecha_envio"),
                    FechaExpiracion       = Fecha(r, "fecha_expiracion"),
                    IdMotivoNuevaVersion  = EnteroNulo(r, "id_motivo_nueva_version"),
                    MotivoNuevaVersion    = Texto(r, "motivo_nueva_version"),
                    DescripcionCambios    = Texto(r, "descripcion_cambios"),
                    UltimaEdicionEn       = FechaHora(r, "ultima_edicion_en"),
                    UltimaEdicionPor      = Texto(r, "ultima_edicion_por"),
                };
                d.EsEditable = d.Estado == "borrador";

                // Ítems
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    d.Items.Add(new PropuestaItemDto
                    {
                        IdItem            = EnteroLargo(r, "id_item"),
                        Seccion           = Texto(r, "seccion"),
                        IdCatalogoItem    = EnteroLargoNulo(r, "id_catalogo_item"),
                        Descripcion       = Texto(r, "descripcion"),
                        Alcance           = Texto(r, "alcance"),
                        PuntosCalibracion = Texto(r, "puntos_calibracion"),
                        Cantidad          = DecimalNulo(r, "cantidad") ?? 0,
                        Frecuencia        = DecimalNulo(r, "frecuencia") ?? 1,
                        PrecioUnitario    = DecimalNulo(r, "precio_unitario") ?? 0,
                        Descuento         = DecimalNulo(r, "descuento") ?? 0,
                        Subtotal          = DecimalNulo(r, "subtotal") ?? 0,
                        EsEspaciado       = Booleano(r, "es_espaciado"),
                        Orden             = Entero(r, "orden"),
                    });

                // Textos
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    d.Textos.Add(new PropuestaTextoDto
                    {
                        Id          = EnteroLargo(r, "id"),
                        Seccion     = Texto(r, "seccion"),
                        Tipo        = Texto(r, "tipo"),
                        Texto       = Texto(r, "texto"),
                        IdTextoBase = EnteroLargoNulo(r, "id_texto_base"),
                        Orden       = Entero(r, "orden"),
                    });

                // Formas de pago
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    d.FormasPago.Add(new PropuestaFormaPagoDto
                    {
                        Id             = EnteroLargo(r, "id"),
                        Porcentaje     = DecimalNulo(r, "porcentaje") ?? 0,
                        Condicion      = Texto(r, "condicion"),
                        CondicionLabel = Texto(r, "condicion_label"),
                        Orden          = Entero(r, "orden"),
                    });

                // Equipos
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    d.Equipos.Add(new PropuestaEquipoDto
                    {
                        Id            = EnteroLargo(r, "id"),
                        IdEquipo      = EnteroLargoNulo(r, "id_equipo"),
                        LocalSede     = Texto(r, "local_sede"),
                        Tipo          = Texto(r, "tipo"),
                        Subtipo       = Texto(r, "subtipo"),
                        NumSerie      = Texto(r, "num_serie"),
                        Marca         = Texto(r, "marca"),
                        Modelo        = Texto(r, "modelo"),
                        CodigoCliente = Texto(r, "codigo_cliente"),
                        CodigoTw      = Texto(r, "codigo_tw"),
                        Orden         = Entero(r, "orden"),
                    });

                return new RespuestaDto<PropuestaDetalleDto>(2, mensaje, d);
            }, ct);

    // ── Guardar (crear / actualizar / nueva versión) ──────────────────────────
    public Task<RespuestaDto<GuardarPropuestaResultadoDto>> GuardarPropuestaAsync(
        GuardarPropuestaDto dto, long idUsuario, CancellationToken ct)
    {
        // Arreglos JSON con las claves que lee el SP (JSON_TABLE)
        var items = dto.Items.Select((i, n) => new
        {
            seccion            = i.Seccion,
            id_catalogo_item   = i.IdCatalogoItem,
            descripcion        = i.Descripcion?.Trim(),
            alcance            = i.Alcance,
            puntos_calibracion = i.PuntosCalibracion,
            cantidad           = i.EsEspaciado ? 0 : i.Cantidad,
            frecuencia         = i.Frecuencia <= 0 ? 1 : i.Frecuencia,
            precio_unitario    = i.EsEspaciado ? 0 : i.PrecioUnitario,
            descuento          = i.EsEspaciado ? 0 : i.Descuento,
            es_espaciado       = i.EsEspaciado ? 1 : 0,
            orden              = i.Orden > 0 ? i.Orden : n + 1,
        });
        var textos = dto.Textos.Select((t, n) => new
        {
            seccion       = t.Seccion,
            tipo          = t.Tipo,
            texto         = t.Texto,
            id_texto_base = t.IdTextoBase,
            orden         = t.Orden > 0 ? t.Orden : n + 1,
        });
        var pagos = dto.FormasPago.Select((f, n) => new
        {
            porcentaje = f.Porcentaje,
            condicion  = f.Condicion?.Trim(),
            orden      = f.Orden > 0 ? f.Orden : n + 1,
        });
        var equipos = dto.Equipos.Select((e, n) => new
        {
            id             = e.Id,
            id_equipo      = e.IdEquipo,
            local_sede     = e.LocalSede,
            tipo           = e.Tipo,
            subtipo        = e.Subtipo,
            num_serie      = e.NumSerie?.Trim(),
            marca          = e.Marca?.Trim(),
            modelo         = e.Modelo?.Trim(),
            codigo_cliente = e.CodigoCliente,
            codigo_tw      = e.CodigoTw,
            orden          = e.Orden > 0 ? e.Orden : n + 1,
        });

        return EjecutarAsync("SP_GuardarPropuesta",
            p =>
            {
                p.AddWithValue("p_id_propuesta",            dto.IdPropuesta);
                p.AddWithValue("p_id_propuesta_base",       Valor(dto.IdPropuestaBase));
                p.AddWithValue("p_id_requerimiento",        dto.IdRequerimiento);
                p.AddWithValue("p_id_sede",                 Valor(dto.IdSede));
                p.AddWithValue("p_id_contacto",             Valor(dto.IdContacto));
                p.AddWithValue("p_id_responsable",          Valor(dto.IdResponsable));
                p.AddWithValue("p_tipo_servicio",           Valor(dto.TipoServicio));
                p.AddWithValue("p_referencia",              Valor(dto.Referencia));
                p.AddWithValue("p_introduccion",            Valor(dto.Introduccion));
                p.AddWithValue("p_notas_generales",         Valor(dto.NotasGenerales));
                p.AddWithValue("p_secciones_activas",       dto.SeccionesActivas is null ? DBNull.Value : JsonSerializer.Serialize(dto.SeccionesActivas));
                p.AddWithValue("p_es_tercerizado",          Bit(dto.EsTercerizado));
                p.AddWithValue("p_tercero_ruc",             dto.EsTercerizado ? Valor(dto.TerceroRuc) : DBNull.Value);
                p.AddWithValue("p_tercero_razon_social",    dto.EsTercerizado ? Valor(dto.TerceroRazonSocial) : DBNull.Value);
                p.AddWithValue("p_tercero_direccion",       dto.EsTercerizado ? Valor(dto.TerceroDireccion) : DBNull.Value);
                p.AddWithValue("p_id_moneda",               dto.IdMoneda);
                p.AddWithValue("p_tipo_cambio",             Valor(dto.TipoCambio));
                p.AddWithValue("p_garantia_meses",          Valor(dto.GarantiaMeses));
                p.AddWithValue("p_mostrar_garantia",        Bit(dto.MostrarGarantia));
                p.AddWithValue("p_plazo_entrega_dias",      Valor(dto.PlazoEntregaDias));
                p.AddWithValue("p_plazo_entrega_unidad",    Valor(dto.PlazoEntregaUnidad));
                p.AddWithValue("p_plazo_entrega_condicion", Valor(dto.PlazoEntregaCondicion));
                p.AddWithValue("p_vigencia_dias",           Valor(dto.VigenciaDias));
                p.AddWithValue("p_aplica_igv",              Bit(dto.AplicaIgv));
                p.AddWithValue("p_precios_incluyen_igv",    Bit(dto.PreciosIncluyenIgv));
                p.AddWithValue("p_descuento_pct",           Valor(dto.DescuentoPct));
                p.AddWithValue("p_descuento_monto",         Valor(dto.DescuentoMonto));
                p.AddWithValue("p_id_motivo_descuento",     Valor(dto.IdMotivoDescuento));
                p.AddWithValue("p_descuento_opcionales",    Valor(dto.DescuentoOpcionales));
                p.AddWithValue("p_items_json",              JsonSerializer.Serialize(items));
                p.AddWithValue("p_textos_json",             JsonSerializer.Serialize(textos));
                p.AddWithValue("p_pagos_json",              JsonSerializer.Serialize(pagos));
                p.AddWithValue("p_equipos_json",            JsonSerializer.Serialize(equipos));
                p.AddWithValue("p_id_usuario",              idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<GuardarPropuestaResultadoDto>(3, "El procedimiento no devolvió el resultado.");

                return new RespuestaDto<GuardarPropuestaResultadoDto>(2, mensaje, new GuardarPropuestaResultadoDto(
                    EnteroLargo(r, "id_propuesta"),
                    Texto(r, "numero") ?? "",
                    Entero(r, "version"),
                    DecimalNulo(r, "subtotal") ?? 0,
                    DecimalNulo(r, "descuento_monto") ?? 0,
                    DecimalNulo(r, "igv_monto") ?? 0,
                    DecimalNulo(r, "total") ?? 0,
                    DecimalNulo(r, "subtotal_opcionales") ?? 0,
                    DecimalNulo(r, "descuento_opcionales") ?? 0,
                    DecimalNulo(r, "total_opcionales") ?? 0));
            }, ct);
    }

    // ── HU-09: contexto del detalle ──────────────────────────────────────────
    public Task<RespuestaDto<PropuestaContextoDto>> ObtenerContextoPropuestaAsync(long idPropuesta, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerContextoPropuesta",
            p => p.AddWithValue("p_id_propuesta", idPropuesta),
            async (r, mensaje) =>
            {
                // Situación
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PropuestaContextoDto>(1, "Propuesta no encontrada.");

                var c = new PropuestaContextoDto
                {
                    Estado              = Texto(r, "estado") ?? "",
                    FechaPdf            = FechaHora(r, "fecha_pdf"),
                    FechaEnvio          = FechaHora(r, "fecha_envio"),
                    FechaExpiracion     = FechaHora(r, "fecha_expiracion"),
                    EsUltimaVersion     = Booleano(r, "es_ultima_version"),
                    TieneOc             = Booleano(r, "tiene_oc"),
                    SlaTipo             = Texto(r, "sla_tipo"),
                    SlaVenceEn          = FechaHora(r, "sla_vence_en"),
                    NumeroContratoMarco = Texto(r, "numero_contrato_marco"),
                    Ahora               = FechaHora(r, "ahora") ?? DateTime.Now,
                };

                // Documentos vinculados
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    c.Documentos.Add(new DocumentoVinculadoDto
                    {
                        Tipo        = Texto(r, "tipo") ?? "",
                        IdEntidad   = EnteroLargoNulo(r, "id_entidad"),
                        Codigo      = Texto(r, "codigo"),
                        Descripcion = Texto(r, "descripcion"),
                        Estado      = Texto(r, "estado"),
                        Url         = Texto(r, "url"),
                        Fecha       = FechaHora(r, "fecha"),
                    });

                // Versiones
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    c.Versiones.Add(new VersionPropuestaDto
                    {
                        IdPropuesta        = EnteroLargo(r, "id_propuesta"),
                        Version            = Entero(r, "version"),
                        Estado             = Texto(r, "estado") ?? "",
                        Total              = DecimalNulo(r, "total") ?? 0,
                        FechaCreacion      = FechaHora(r, "fecha_creacion"),
                        FechaEnvio         = FechaHora(r, "fecha_envio"),
                        NombreCreador      = Texto(r, "nombre_creador"),
                        MotivoNuevaVersion = Texto(r, "motivo_nueva_version"),
                    });

                // Actividad
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    c.Actividad.Add(new ActividadPropuestaDto
                    {
                        IdAuditoria    = EnteroLargo(r, "id_auditoria"),
                        Accion         = Texto(r, "accion") ?? "",
                        EstadoAnterior = Texto(r, "estado_anterior"),
                        EstadoNuevo    = Texto(r, "estado_nuevo"),
                        Descripcion    = Texto(r, "descripcion"),
                        RegistradoEn   = FechaHora(r, "registrado_en"),
                        NombreUsuario  = Texto(r, "nombre_usuario"),
                    });

                return new RespuestaDto<PropuestaContextoDto>(2, mensaje, c);
            }, ct);

    // ── HU-10: nueva versión ────────────────────────────────────────────────
    public Task<RespuestaDto<NuevaVersionPropuestaResultadoDto>> CrearNuevaVersionAsync(
        long idPropuestaOrigen, CrearNuevaVersionPropuestaDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CrearNuevaVersionPropuesta",
            p =>
            {
                p.AddWithValue("p_id_propuesta_origen",  idPropuestaOrigen);
                p.AddWithValue("p_id_motivo",            dto.IdMotivoNuevaVersion);
                p.AddWithValue("p_descripcion_cambios",  dto.DescripcionCambios.Trim());
                p.AddWithValue("p_copiar_configuracion", Bit(dto.Copiar.Configuracion));
                p.AddWithValue("p_copiar_detalle",       Bit(dto.Copiar.DetalleDescriptivo));
                p.AddWithValue("p_copiar_condiciones",   Bit(dto.Copiar.Condiciones));
                p.AddWithValue("p_copiar_items",         Bit(dto.Copiar.Items));
                p.AddWithValue("p_copiar_forma_pago",    Bit(dto.Copiar.FormaPago));
                p.AddWithValue("p_copiar_equipos",       Bit(dto.Copiar.Equipos));
                p.AddWithValue("p_id_usuario",           idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<NuevaVersionPropuestaResultadoDto>(3, "El procedimiento no devolvió el resultado.");

                return new RespuestaDto<NuevaVersionPropuestaResultadoDto>(2, mensaje, new NuevaVersionPropuestaResultadoDto(
                    EnteroLargo(r, "id_propuesta"),
                    Texto(r, "numero") ?? "",
                    Entero(r, "version"),
                    Booleano(r, "version_anterior_anulada")));
            }, ct);

    // ── HU-11: descuento global ──────────────────────────────────────────────
    public Task<RespuestaDto<DescuentoPropuestaResultadoDto>> AplicarDescuentoAsync(
        long idPropuesta, string tipo, decimal valor, int? idMotivo, bool soloPrevisualizar,
        long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AplicarDescuentoPropuesta",
            p =>
            {
                p.AddWithValue("p_id_propuesta",       idPropuesta);
                p.AddWithValue("p_tipo",               tipo);
                p.AddWithValue("p_valor",              valor);
                p.AddWithValue("p_id_motivo",          Valor(idMotivo));
                p.AddWithValue("p_solo_previsualizar", Bit(soloPrevisualizar));
                p.AddWithValue("p_id_usuario",         idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DescuentoPropuestaResultadoDto>(3, "El procedimiento no devolvió el resultado.");

                return new RespuestaDto<DescuentoPropuestaResultadoDto>(2, mensaje, new DescuentoPropuestaResultadoDto
                {
                    SubtotalActual     = DecimalNulo(r, "subtotal_actual") ?? 0,
                    DescuentoActual    = DecimalNulo(r, "descuento_actual") ?? 0,
                    PorcentajeActual   = DecimalNulo(r, "porcentaje_actual"),
                    IgvActual          = DecimalNulo(r, "igv_actual") ?? 0,
                    TotalActual        = DecimalNulo(r, "total_actual") ?? 0,
                    Tipo               = Texto(r, "tipo") ?? tipo,
                    Porcentaje         = DecimalNulo(r, "porcentaje"),
                    DescuentoNuevo     = DecimalNulo(r, "descuento_nuevo") ?? 0,
                    SubtotalNuevo      = DecimalNulo(r, "subtotal_nuevo") ?? 0,
                    IgvNuevo           = DecimalNulo(r, "igv_nuevo") ?? 0,
                    TotalNuevo         = DecimalNulo(r, "total_nuevo") ?? 0,
                    IgvPct             = DecimalNulo(r, "igv_pct") ?? 0,
                    IdMotivoDescuento  = EnteroNulo(r, "id_motivo_descuento"),
                    MotivoDescuento    = Texto(r, "motivo_descuento"),
                    Guardado           = Booleano(r, "guardado"),
                });
            }, ct);

    // ── HU-12: envío a visto bueno ───────────────────────────────────────────
    public Task<RespuestaDto<VistoBuenoPropuestaDto>> EnviarVistoBuenoAsync(
        long idPropuesta, string? comentario, bool soloPreparar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_EnviarVistoBuenoPropuesta",
            p =>
            {
                p.AddWithValue("p_id_propuesta",  idPropuesta);
                p.AddWithValue("p_comentario",    Valor(comentario));
                p.AddWithValue("p_solo_preparar", Bit(soloPreparar));
                p.AddWithValue("p_id_usuario",    idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<VistoBuenoPropuestaDto>(3, "El procedimiento no devolvió el resultado.");

                var vb = new VistoBuenoPropuestaDto
                {
                    IdPropuesta                = EnteroLargo(r, "id_propuesta"),
                    Numero                     = Texto(r, "numero") ?? "",
                    Version                    = Entero(r, "version"),
                    Estado                     = Texto(r, "estado") ?? "",
                    Cliente                    = Texto(r, "cliente"),
                    NumeroRequerimiento        = Texto(r, "numero_requerimiento"),
                    Total                      = DecimalNulo(r, "total") ?? 0,
                    MonedaSimbolo              = Texto(r, "moneda_simbolo"),
                    IdAprobador                = EnteroLargoNulo(r, "id_aprobador"),
                    NombreAprobador            = Texto(r, "nombre_aprobador"),
                    CargoAprobador             = Texto(r, "cargo_aprobador"),
                    EsSuplente                 = Booleano(r, "es_suplente"),
                    IdJefeDirecto              = EnteroLargoNulo(r, "id_jefe_directo"),
                    NombreJefeDirecto          = Texto(r, "nombre_jefe_directo"),
                    SlaHoras                   = Entero(r, "sla_horas"),
                    FechaLimite                = FechaHora(r, "fecha_limite"),
                    RequiereAprobacionEspecial = Booleano(r, "requiere_aprobacion_especial"),
                    MotivoAlerta               = Texto(r, "motivo_alerta"),
                    DescuentoPct               = DecimalNulo(r, "descuento_pct") ?? 0,
                    UmbralDescuentoPct         = DecimalNulo(r, "umbral_descuento_pct") ?? 0,
                    PuedeEnviar                = Booleano(r, "puede_enviar"),
                    IdVistoBueno               = EnteroLargoNulo(r, "id_visto_bueno"),
                };

                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    vb.Validaciones.Add(new ValidacionVistoBuenoDto
                    {
                        Codigo      = Texto(r, "codigo") ?? "",
                        Etiqueta    = Texto(r, "etiqueta") ?? "",
                        Cumple      = Booleano(r, "cumple"),
                        Obligatoria = Booleano(r, "obligatoria"),
                        Detalle     = Texto(r, "detalle"),
                    });

                return new RespuestaDto<VistoBuenoPropuestaDto>(2, mensaje, vb);
            }, ct);

    // ── HU-12: anulación ─────────────────────────────────────────────────────
    public Task<RespuestaDto<AnulacionPropuestaDto>> AnularPropuestaAsync(
        long idPropuesta, int? idMotivo, string? justificacion, bool confirmacion, bool soloPreparar,
        long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AnularPropuesta",
            p =>
            {
                p.AddWithValue("p_id_propuesta",  idPropuesta);
                p.AddWithValue("p_id_motivo",     Valor(idMotivo));
                p.AddWithValue("p_justificacion", Valor(justificacion));
                p.AddWithValue("p_confirmacion",  Bit(confirmacion));
                p.AddWithValue("p_solo_preparar", Bit(soloPreparar));
                p.AddWithValue("p_id_usuario",    idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AnulacionPropuestaDto>(3, "El procedimiento no devolvió el resultado.");

                var a = new AnulacionPropuestaDto
                {
                    IdPropuesta            = EnteroLargo(r, "id_propuesta"),
                    Numero                 = Texto(r, "numero") ?? "",
                    Version                = Entero(r, "version"),
                    Estado                 = Texto(r, "estado") ?? "",
                    Cliente                = Texto(r, "cliente"),
                    NumeroRequerimiento    = Texto(r, "numero_requerimiento"),
                    NumeroExpediente       = Texto(r, "numero_expediente"),
                    TieneVbPendiente       = Booleano(r, "tiene_vb_pendiente"),
                    PuedeAnular            = Booleano(r, "puede_anular"),
                    MotivoBloqueo          = Texto(r, "motivo_bloqueo"),
                    Impacto                = Texto(r, "impacto"),
                    MotivoAnulacion        = Texto(r, "motivo_anulacion"),
                    JustificacionAnulacion = Texto(r, "justificacion_anulacion"),
                    FechaAnulacion         = FechaHora(r, "fecha_anulacion"),
                };

                if (soloPreparar && await r.NextResultAsync(ct))
                    while (await r.ReadAsync(ct))
                        a.Motivos.Add(new OpcionMotivoDto
                        {
                            Id     = Entero(r, "id"),
                            Nombre = Texto(r, "nombre") ?? "",
                        });

                return new RespuestaDto<AnulacionPropuestaDto>(2, mensaje, a);
            }, ct);

    private static List<string> LeerListaJson(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new();
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? new(); }
        catch (JsonException) { return new(); }
    }
}
