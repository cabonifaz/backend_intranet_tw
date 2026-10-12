using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;
using MySqlConnector;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-17 — Seguimiento comercial de propuestas enviadas.</summary>
public class SeguimientoComercialRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ISeguimientoComercialRepositorio
{
    private static decimal Dec(MySqlDataReader r, string c) => DecimalNulo(r, c) ?? 0m;
    private static int Ent(MySqlDataReader r, string c) => (int)(DecimalNulo(r, c) ?? 0m);
    private static int? EntNulo(MySqlDataReader r, string c) => DecimalNulo(r, c) is { } v ? (int)v : null;

    // ── HU-17 Bandeja ─────────────────────────────────────────────────────────
    public Task<RespuestaDto<BandejaSeguimientoDto>> ObtenerBandejaAsync(FiltrosBandejaSeguimientoDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_responsable", Valor(f.IdResponsable));
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
            },
            async (r, mensaje) =>
            {
                // 2. KPIs
                await r.NextResultAsync(ct);
                var kpis = new KpisSeguimientoDto(0, 0, 0, 0, 0, 0, 0, 0, "estable", 0);
                if (await r.ReadAsync(ct))
                {
                    int rechazadas = Ent(r, "rechazadas_mes"), rechazadasAnt = Ent(r, "rechazadas_mes_anterior");
                    kpis = new KpisSeguimientoDto(
                        Ent(r, "en_seguimiento"),
                        Dec(r, "variacion_en_seguimiento_pct"),
                        Ent(r, "sin_respuesta"),
                        Ent(r, "seguimientos_vencidos"),
                        Ent(r, "aceptadas_mes"),
                        Ent(r, "meta_aceptadas_mes"),
                        rechazadas,
                        rechazadasAnt,
                        rechazadas > rechazadasAnt ? "alza" : rechazadas < rechazadasAnt ? "baja" : "estable",
                        Ent(r, "oc_pendientes"));
                }

                // 3. Filas
                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaSeguimientoDto
                    {
                        IdPropuesta            = EnteroLargo(r, "id_propuesta"),
                        Numero                 = Texto(r, "numero") ?? "",
                        Version                = Ent(r, "version"),
                        IdRequerimiento        = EnteroLargoNulo(r, "id_requerimiento"),
                        NumeroRq               = Texto(r, "numero_rq"),
                        IdCliente              = EnteroLargo(r, "id_cliente"),
                        RazonSocial            = Texto(r, "razon_social") ?? "",
                        Ruc                    = Texto(r, "ruc"),
                        IdContacto             = EnteroLargoNulo(r, "id_contacto"),
                        Contacto               = Texto(r, "contacto"),
                        CargoContacto          = Texto(r, "cargo_contacto"),
                        TelefonoContacto       = Texto(r, "telefono_contacto"),
                        CorreoContacto         = Texto(r, "correo_contacto"),
                        Total                  = Dec(r, "total"),
                        IdMoneda               = Ent(r, "id_moneda"),
                        Moneda                 = Texto(r, "moneda"),
                        MonedaSimbolo          = Texto(r, "moneda_simbolo"),
                        FechaEnvio             = FechaHora(r, "fecha_envio"),
                        DiasTranscurridos      = Ent(r, "dias_transcurridos"),
                        DiasSinRespuesta       = Ent(r, "dias_sin_respuesta"),
                        IdResponsable          = EnteroLargo(r, "id_responsable"),
                        Responsable            = Texto(r, "responsable"),
                        Interacciones          = Ent(r, "interacciones"),
                        FechaUltimaInteraccion = FechaHora(r, "fecha_ult_interaccion"),
                        CanalUltimo            = Texto(r, "canal_ult"),
                        ResultadoUltimoCodigo  = Texto(r, "resultado_ult_codigo"),
                        ResultadoUltimo        = Texto(r, "resultado_ult"),
                        ProximaAccionCodigo    = Texto(r, "proxima_accion_codigo"),
                        ProximaAccion          = Texto(r, "proxima_accion"),
                        ProximaAccionDetalle   = Texto(r, "proxima_accion_detalle"),
                        ProximaAccionFecha     = FechaHora(r, "proxima_accion_fecha"),
                        DiasParaAccion         = EntNulo(r, "dias_para_accion"),
                        HorasParaAccion        = EntNulo(r, "horas_para_accion"),
                        PrioridadAccion        = Texto(r, "prioridad_accion"),
                        PrioridadAccionCodigo  = Texto(r, "prioridad_accion_codigo"),
                        EstadoSeguimiento      = Texto(r, "estado_seguimiento") ?? "",
                        EstadoPropuesta        = Texto(r, "estado_propuesta") ?? "",
                        SlaEstado              = Texto(r, "sla_estado") ?? "",
                        SlaPct                 = EntNulo(r, "sla_pct"),
                        FechaAceptacion        = FechaHora(r, "fecha_aceptacion"),
                        FechaRechazo           = FechaHora(r, "fecha_rechazo"),
                        TieneOc                = Booleano(r, "tiene_oc"),
                        OcPorValidar           = Ent(r, "oc_por_validar"),
                    });

                // 4. Total
                int total = await LeerTotalAsync(r, ct);

                // 5. Responsables
                await r.NextResultAsync(ct);
                var responsables = new List<OpcionFiltroDto>();
                while (await r.ReadAsync(ct))
                    responsables.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? ""));

                // 6. Parámetros
                await r.NextResultAsync(ct);
                var parametros = new ParametrosSeguimientoDto(7, 48, 24, 8);
                if (await r.ReadAsync(ct))
                    parametros = new ParametrosSeguimientoDto(
                        Ent(r, "dias_sin_respuesta"), Ent(r, "sla_horas"),
                        Ent(r, "alerta_horas"), Ent(r, "meta_aceptadas_mes"));

                return new RespuestaDto<BandejaSeguimientoDto>(2, mensaje,
                    new BandejaSeguimientoDto(kpis, items, total, f.Pagina, f.PorPagina, responsables, parametros));
            },
            ct);
}
