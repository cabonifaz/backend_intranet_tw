using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ══════════════════════ HU-13 — Bandeja de Visto Bueno ══════════════════════

public class ObtenerBandejaVistoBuenoCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    private static readonly string[] Estados = ["", "pendiente", "aprobado", "devuelto", "rechazado"];
    private static readonly string[] Slas    = ["", "en_plazo", "proximo", "vencido", "cumplido", "fuera_de_plazo"];

    public Task<RespuestaDto<BandejaVistoBuenoDto>> EjecutarAsync(FiltrosBandejaVistoBuenoDto f, long idUsuario, CancellationToken ct = default)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        var sla    = f.Sla?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return Task.FromResult(new RespuestaDto<BandejaVistoBuenoDto>(1, "Estado no válido. Use pendiente, aprobado, devuelto o rechazado."));
        if (!Slas.Contains(sla))
            return Task.FromResult(new RespuestaDto<BandejaVistoBuenoDto>(1, "Filtro de SLA no válido."));

        var filtros = f with
        {
            Estado    = estado,
            Sla       = sla,
            Dias      = Math.Max(f.Dias, 0),
            Pagina    = Math.Max(f.Pagina, 1),
            PorPagina = Math.Clamp(f.PorPagina, 1, 100),
        };
        return repositorio.ObtenerBandejaAsync(filtros, idUsuario, ct);
    }
}

public class ResolverVistoBuenoCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    private static readonly string[] Acciones = ["aprobar", "corregir", "rechazar"];

    public Task<RespuestaDto<ResultadoResolverVistoBuenoDto>> EjecutarAsync(
        long idPropuesta, ResolverVistoBuenoDto dto, long idUsuario, CancellationToken ct = default)
    {
        var accion = dto.Accion?.Trim().ToLowerInvariant() ?? "";
        if (!Acciones.Contains(accion))
            return Task.FromResult(new RespuestaDto<ResultadoResolverVistoBuenoDto>(1, "Acción no válida. Use aprobar, corregir o rechazar."));
        if (accion != "aprobar" && (dto.Comentario?.Trim().Length ?? 0) < 10)
            return Task.FromResult(new RespuestaDto<ResultadoResolverVistoBuenoDto>(1,
                accion == "corregir" ? "Indique qué debe corregir el comercial (mínimo 10 caracteres)."
                                     : "Indique el motivo del rechazo (mínimo 10 caracteres)."));

        // HU-15 — requisitos de cada decisión (el SP vuelve a validarlos contra los catálogos)
        if (accion == "rechazar" && (dto.IdMotivoRechazo is null or <= 0))
            return Task.FromResult(new RespuestaDto<ResultadoResolverVistoBuenoDto>(1, "Seleccione el motivo del rechazo."));
        if (accion == "corregir")
        {
            if (dto.Areas is null || dto.Areas.Count(a => !string.IsNullOrWhiteSpace(a)) == 0)
                return Task.FromResult(new RespuestaDto<ResultadoResolverVistoBuenoDto>(1, "Seleccione al menos un área a corregir."));
            if (dto.FechaLimite is null)
                return Task.FromResult(new RespuestaDto<ResultadoResolverVistoBuenoDto>(1, "Indique la fecha y hora límite de corrección."));
        }

        var normalizado = dto with
        {
            Accion                  = accion,
            Comentario              = dto.Comentario?.Trim(),
            ValidacionesConfirmadas = Limpiar(dto.ValidacionesConfirmadas),
            Areas                   = Limpiar(dto.Areas),
        };
        return repositorio.ResolverAsync(idPropuesta, normalizado, idUsuario, ct);
    }

    private static List<string> Limpiar(List<string>? valores)
        => (valores ?? []).Where(v => !string.IsNullOrWhiteSpace(v))
                          .Select(v => v.Trim().ToLowerInvariant()).Distinct().ToList();
}

/// <summary>HU-15 — Datos de los modales Aprobar / Rechazar / Solicitar Corrección.</summary>
public class PrepararDecisionVistoBuenoCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public Task<RespuestaDto<DecisionVistoBuenoDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<DecisionVistoBuenoDto>(1, "Indique la propuesta."))
            : repositorio.PrepararDecisionAsync(idPropuesta, idUsuario, ct);
}

/// <summary>HU-15 — Última solicitud de corrección de la propuesta.</summary>
public class ObtenerCorreccionPropuestaCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public Task<RespuestaDto<CorreccionPropuestaDto?>> EjecutarAsync(long idPropuesta, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<CorreccionPropuestaDto?>(1, "Indique la propuesta."))
            : repositorio.ObtenerCorreccionAsync(idPropuesta, ct);
}

// ══════════════════════ HU-16 — Reasignación de aprobador ══════════════════════

public class PrepararReasignacionVistoBuenoCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public Task<RespuestaDto<ReasignacionVistoBuenoDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<ReasignacionVistoBuenoDto>(1, "Indique la propuesta."))
            : repositorio.PrepararReasignacionAsync(idPropuesta, idUsuario, ct);
}

public class ObtenerCandidatosReasignacionVbCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public Task<RespuestaDto<List<CandidatoAprobadorDto>>> EjecutarAsync(long idPropuesta, string? buscar, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<List<CandidatoAprobadorDto>>(1, "Indique la propuesta."))
            : repositorio.ObtenerCandidatosReasignacionAsync(idPropuesta, buscar?.Trim(), ct);
}

public class ReasignarVistoBuenoCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    private const int MaxComentario = 1000;

    public Task<RespuestaDto<ResultadoReasignacionVbDto>> EjecutarAsync(
        long idPropuesta, ReasignarVistoBuenoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<ResultadoReasignacionVbDto>(1, "Indique la propuesta."));
        if (dto is null || dto.IdNuevoAprobador <= 0)
            return Task.FromResult(new RespuestaDto<ResultadoReasignacionVbDto>(1, "Seleccione el nuevo aprobador."));
        if (dto.IdMotivo is null or <= 0)
            return Task.FromResult(new RespuestaDto<ResultadoReasignacionVbDto>(1, "Seleccione el motivo de la reasignación."));
        if ((dto.Comentario?.Trim().Length ?? 0) > MaxComentario)
            return Task.FromResult(new RespuestaDto<ResultadoReasignacionVbDto>(1, $"El comentario no puede superar los {MaxComentario} caracteres."));

        return repositorio.ReasignarAsync(idPropuesta, dto with { Comentario = dto.Comentario?.Trim() }, idUsuario, ct);
    }
}

// ══════════════════════ HU-14 — Validaciones previas ══════════════════════

public class ObtenerValidacionesVistoBuenoCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public async Task<RespuestaDto<ValidacionesVistoBuenoDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        var r = await repositorio.ObtenerValidacionesAsync(idPropuesta, idUsuario, ct);
        if (r.IdTipoMensaje != 2)
            return new RespuestaDto<ValidacionesVistoBuenoDto>(r.IdTipoMensaje, r.Mensaje);

        var (validaciones, resumen) = r.Datos;
        return new RespuestaDto<ValidacionesVistoBuenoDto>(2, r.Mensaje,
            new ValidacionesVistoBuenoDto(validaciones, resumen, Riesgo.Calcular(validaciones).Nivel));
    }
}

/// <summary>Riesgo financiero: ALTO si alguna validación de crédito o margen está en error,
/// MODERADO si hay alertas (o el margen no se puede calcular), BAJO en otro caso.</summary>
public static class Riesgo
{
    private static readonly string[] Financieras = ["credito", "margen", "descuento"];

    public static (string Nivel, List<string> Motivos) Calcular(List<ValidacionPreviaDto> v)
    {
        var relevantes = v.Where(x => Financieras.Contains(x.Codigo)).ToList();
        var motivos = relevantes.Where(x => x.Nivel is "error" or "alerta").Select(x => $"{x.Etiqueta}: {x.Detalle}").ToList();

        if (relevantes.Any(x => x.Nivel == "error"))  return ("ALTO", motivos);
        if (relevantes.Any(x => x.Nivel == "alerta")) return ("MODERADO", motivos);
        if (relevantes.Any(x => x.Codigo == "margen" && x.Nivel == "no_disponible"))
            return ("MODERADO", ["Margen de utilidad: sin precios de costo para evaluarlo."]);
        return ("BAJO", motivos);
    }
}

// ══════════════════════ HU-14 — Comparar versiones ══════════════════════

public class CompararVersionesPropuestaCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    private static readonly CultureInfo Pe = CultureInfo.GetCultureInfo("es-PE");

    public async Task<RespuestaDto<ComparacionVersionesDto>> EjecutarAsync(
        long idBase, long idDestino, long idUsuario, CancellationToken ct = default)
    {
        if (idBase <= 0 || idDestino <= 0)
            return new RespuestaDto<ComparacionVersionesDto>(1, "Indique la versión base y la versión destino.");
        if (idBase == idDestino)
            return new RespuestaDto<ComparacionVersionesDto>(1, "Elija dos versiones distintas.");

        var datos = await repositorio.ObtenerDatosComparacionAsync(idBase, idDestino, ct);
        if (datos.IdTipoMensaje != 2 || datos.Datos is null)
            return new RespuestaDto<ComparacionVersionesDto>(datos.IdTipoMensaje, datos.Mensaje);

        var d = datos.Datos;
        var b = d.Base with { FormaPago = FormaPago(d.FormasPago, "base") };
        var t = d.Destino with { FormaPago = FormaPago(d.FormasPago, "destino") };

        var items       = CompararItems(d.Items);
        var financiero  = CompararFinanciero(b, t);
        var condiciones = CompararCondiciones(b, t);
        var equipos     = CompararElementos(
            d.Equipos.Where(e => e.Rol == "base").Select(Equipo).ToList(),
            d.Equipos.Where(e => e.Rol == "destino").Select(Equipo).ToList());
        var textos      = CompararElementos(
            d.Textos.Where(x => x.Rol == "base").Select(Texto).ToList(),
            d.Textos.Where(x => x.Rol == "destino").Select(Texto).ToList());

        var val = await repositorio.ObtenerValidacionesAsync(t.IdPropuesta, idUsuario, ct);
        var validaciones = val.IdTipoMensaje == 2 ? val.Datos.Validaciones : [];
        var (riesgo, motivos) = Riesgo.Calcular(validaciones);

        var difTotal = t.Total - b.Total;
        var resumen = new ResumenComparacionDto(
            difTotal,
            b.Total == 0 ? 0 : Math.Round(difTotal * 100 / b.Total, 1),
            d.Items.Count(i => i.Rol == "base"),
            d.Items.Count(i => i.Rol == "destino"),
            items.Count(i => i.Estado == "agregado"),
            items.Count(i => i.Estado == "modificado"),
            items.Count(i => i.Estado == "eliminado"),
            riesgo,
            motivos);

        return new RespuestaDto<ComparacionVersionesDto>(2, datos.Mensaje,
            new ComparacionVersionesDto(b, t, resumen, financiero, items, condiciones, equipos, textos, validaciones, d.Versiones));
    }

    // ── Ítems: se emparejan por suministro (o por descripción si no tiene) y sección ──
    private static List<DiferenciaItemDto> CompararItems(List<ItemVersionDto> todos)
    {
        static string Clave(ItemVersionDto i) =>
            $"{i.Seccion}|{(i.IdCatalogoItem is > 0 ? "s" + i.IdCatalogoItem : "d" + Similitud.Normalizar(i.Descripcion))}";

        var bases    = todos.Where(i => i.Rol == "base").GroupBy(Clave).ToDictionary(g => g.Key, g => new Queue<ItemVersionDto>(g));
        var destinos = todos.Where(i => i.Rol == "destino").ToList();
        var resultado = new List<DiferenciaItemDto>();

        foreach (var nuevo in destinos)
        {
            if (bases.TryGetValue(Clave(nuevo), out var cola) && cola.Count > 0)
            {
                var viejo = cola.Dequeue();
                var campos = new List<string>();
                if (viejo.Cantidad       != nuevo.Cantidad)       campos.Add("cantidad");
                if (viejo.PrecioUnitario != nuevo.PrecioUnitario) campos.Add("precio_unitario");
                if (viejo.Descuento      != nuevo.Descuento)      campos.Add("descuento");
                if (viejo.Subtotal       != nuevo.Subtotal)       campos.Add("subtotal");
                if (!Igual(viejo.Descripcion, nuevo.Descripcion)) campos.Add("descripcion");
                if (!Igual(viejo.Alcance, nuevo.Alcance))         campos.Add("alcance");
                if (!Igual(viejo.PuntosCalibracion, nuevo.PuntosCalibracion)) campos.Add("puntos_calibracion");
                if (viejo.Frecuencia     != nuevo.Frecuencia)     campos.Add("frecuencia");

                resultado.Add(new DiferenciaItemDto(campos.Count == 0 ? "igual" : "modificado", nuevo.Seccion, nuevo.Descripcion,
                    viejo.Cantidad, nuevo.Cantidad, viejo.PrecioUnitario, nuevo.PrecioUnitario, viejo.Subtotal, nuevo.Subtotal, campos));
            }
            else
            {
                resultado.Add(new DiferenciaItemDto("agregado", nuevo.Seccion, nuevo.Descripcion,
                    null, nuevo.Cantidad, null, nuevo.PrecioUnitario, null, nuevo.Subtotal, []));
            }
        }

        foreach (var viejo in bases.Values.SelectMany(c => c))
            resultado.Add(new DiferenciaItemDto("eliminado", viejo.Seccion, viejo.Descripcion,
                viejo.Cantidad, null, viejo.PrecioUnitario, null, viejo.Subtotal, null, []));

        return resultado;
    }

    private static List<DiferenciaCampoDto> CompararFinanciero(CabeceraVersionDto b, CabeceraVersionDto t)
    {
        string M(decimal v, CabeceraVersionDto c) => $"{c.MonedaSimbolo} {v.ToString("N2", Pe)}".Trim();
        return
        [
            Campo("subtotal",  "Sub-total",            M(b.Subtotal, b),        M(t.Subtotal, t)),
            Campo("descuento", "Descuento",            M(b.DescuentoMonto, b) + $" ({b.DescuentoPct:0.#} %)",
                                                       M(t.DescuentoMonto, t) + $" ({t.DescuentoPct:0.#} %)"),
            Campo("igv",       $"IGV ({t.IgvPct:0.#} %)", M(b.IgvMonto, b),     M(t.IgvMonto, t)),
            Campo("total",     "Monto total",          M(b.Total, b),           M(t.Total, t)),
        ];
    }

    private static List<DiferenciaCampoDto> CompararCondiciones(CabeceraVersionDto b, CabeceraVersionDto t)
    {
        static string? Dias(int? d) => d is null ? null : $"{d} días calendario";
        return
        [
            Campo("moneda",          "Moneda",             b.Moneda,          t.Moneda),
            Campo("condicion_pago",  "Condición de pago",  b.CondicionPago,   t.CondicionPago),
            Campo("forma_pago",      "Forma de pago",      b.FormaPago,       t.FormaPago),
            Campo("vigencia",        "Validez de oferta",  Dias(b.VigenciaDias),     Dias(t.VigenciaDias)),
            Campo("plazo_entrega",   "Plazo de entrega",   Dias(b.PlazoEntregaDias), Dias(t.PlazoEntregaDias)),
            Campo("aplica_igv",      "Aplica IGV",         b.AplicaIgv ? "Sí" : "No", t.AplicaIgv ? "Sí" : "No"),
        ];
    }

    private static List<DiferenciaElementoDto> CompararElementos(List<(string Clave, string Texto)> b, List<(string Clave, string Texto)> t)
    {
        var lista = new List<DiferenciaElementoDto>();
        var restantes = b.ToList();
        foreach (var x in t)
        {
            var i = restantes.FindIndex(y => y.Clave == x.Clave);
            if (i >= 0) { lista.Add(new DiferenciaElementoDto("igual", x.Texto)); restantes.RemoveAt(i); }
            else          lista.Add(new DiferenciaElementoDto("agregado", x.Texto));
        }
        lista.AddRange(restantes.Select(y => new DiferenciaElementoDto("eliminado", y.Texto)));
        return lista;
    }

    private static (string, string) Equipo(EquipoVersionDto e) =>
        (e.IdEquipo is > 0 ? "id" + e.IdEquipo : "s" + Similitud.Normalizar(e.NumSerie ?? e.CodigoTw ?? ""),
         string.Join(" · ", new[] { e.CodigoTw, e.Tipo, e.Marca, e.Modelo, e.NumSerie is null ? null : "Serie " + e.NumSerie }
                                .Where(x => !string.IsNullOrWhiteSpace(x))));

    private static (string, string) Texto(TextoVersionDto x) =>
        (x.Seccion + "|" + Similitud.Normalizar(x.Texto), $"[{x.Seccion}] {x.Texto}");

    private static string? FormaPago(List<FormaPagoVersionDto> f, string rol)
    {
        var l = f.Where(x => x.Rol == rol).Select(x => $"{x.Porcentaje:0.##} % {x.Condicion}").ToList();
        return l.Count == 0 ? null : string.Join(" + ", l);
    }

    private static DiferenciaCampoDto Campo(string campo, string etiqueta, string? b, string? t) =>
        new(campo, etiqueta, b, t, Igual(b, t) ? "igual" : "modificado");

    private static bool Igual(string? a, string? b) =>
        string.Equals((a ?? "").Trim(), (b ?? "").Trim(), StringComparison.OrdinalIgnoreCase);
}

// ══════════════════════ HU-14 — Precio de costo ══════════════════════

public class ObtenerCostoSuministroCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public Task<RespuestaDto<CostoSuministroDto>> EjecutarAsync(long idSuministro, CancellationToken ct = default)
        => repositorio.ObtenerCostoSuministroAsync(idSuministro, ct);
}

public class GuardarCostoSuministroCasoDeUso(IVistoBuenoRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idSuministro, GuardarCostoSuministroDto dto, long idUsuario, CancellationToken ct = default)
        => dto.PrecioCosto is < 0
            ? Task.FromResult(new RespuestaDto<bool>(1, "El precio de costo no puede ser negativo."))
            : repositorio.GuardarCostoSuministroAsync(idSuministro, dto.PrecioCosto, idUsuario, ct);
}
