using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════
// Propuestas — Importación masiva del listado de equipos desde Excel con IA (Sprint 4).
// ═══════════════════════════════════════════════════════════════════════════

internal static class LimitesImportacionEquipos
{
    public const long TamanoMaximo   = 5 * 1024 * 1024;
    public const int  MaxFilas       = 500;
    /// <summary>Filas que se envían a la IA para conciliar (las demás quedan con el resultado de las reglas).</summary>
    public const int  MaxFilasIa     = 150;
    public const int  FilasPorLlamadaIa = 25;
    public const string TipoXlsx     = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public static readonly string[] Encabezados =
    [
        "N/S (número de serie)", "Código TW (si ya está registrado)", "Código del cliente", "Equipo / instrumento",
        "Marca", "Modelo", "Capacidad / alcance", "Sede", "Ubicación en sede",
    ];
}

/// <summary>
/// Lee el Excel, reconoce las columnas (IA + reglas) y concilia cada fila contra los equipos del cliente y el
/// catálogo de suministros. No guarda nada: devuelve la vista previa para que el comercial revise.
/// </summary>
public class AnalizarImportacionEquiposCasoDeUso(
    ILectorHojaCalculo             lector,
    IAsistenteIaEquipos            ia,
    IImportacionEquiposRepositorio repositorio)
{
    private static readonly string[] MotivosParaIa = ["serie_similar", "serie_repetida", "codigo_cliente", "faltan_datos", "sin_suministro"];

    public async Task<RespuestaDto<AnalisisImportacionEquiposDto>> EjecutarAsync(
        Stream contenido, string nombreArchivo, long tamano, AnalizarImportacionEquiposSolicitudDto solicitud,
        long idUsuario, CancellationToken ct = default)
    {
        if (solicitud.IdCliente <= 0) return new(1, "Indique el cliente de la propuesta.");
        if (tamano <= 0) return new(1, "Adjunte el archivo Excel con el listado de equipos.");
        if (tamano > LimitesImportacionEquipos.TamanoMaximo) return new(1, "El archivo supera el máximo de 5 MB.");

        var lectura = lector.Leer(contenido, nombreArchivo, LimitesImportacionEquipos.MaxFilas + ReconocedorColumnasEquipos.FilasMuestra);
        if (lectura.ExcedeMaximo)
            return new(1, $"El archivo tiene más de {LimitesImportacionEquipos.MaxFilas} equipos; el máximo por importación es {LimitesImportacionEquipos.MaxFilas}. Divídalo en varios archivos.");
        if (lectura.Hoja is null) return new(1, lectura.Error ?? "No se pudo leer el archivo.");
        var hoja = lectura.Hoja;
        if (hoja.Filas.Count == 0) return new(1, "El archivo no tiene datos.");

        // ── 1. Columnas ──
        // Lo que el encabezado nombra sin ambigüedad ("N/S", "Código TW", "Código del cliente"…) manda; la IA reconoce
        // el resto (encabezados con otros nombres, archivos sin encabezado) y las reglas completan lo que falte.
        var (filaEncabezado, columnas) = ReconocedorColumnasEquipos.Reconocer(hoja.Filas);
        var porEncabezado = filaEncabezado > 0
            ? ReconocedorColumnasEquipos.CamposPorEncabezado(hoja.Filas.First(f => f.Numero == filaEncabezado).Celdas)
            : [];
        var iaUsada = false;
        string? aviso = null;
        if (ia.Disponible)
        {
            var r = await ia.ReconocerColumnasAsync(hoja.Filas.Take(ReconocedorColumnasEquipos.FilasMuestra).ToList(), ct);
            if (r.Datos is { } mapeo && mapeo.Columnas.Keys.Any(k => k is "numSerie" or "codigoTw" or "codigoCliente"))
            {
                iaUsada = true;
                var deIa = mapeo.Columnas.Where(c => ReconocedorColumnasEquipos.Campos.Contains(c.Key))
                                         .GroupBy(c => c.Value).Select(g => g.First())
                                         .ToDictionary(c => c.Key, c => c.Value);
                if (porEncabezado.Keys.Any(k => k is "numSerie" or "codigoTw" or "codigoCliente") && porEncabezado.Count >= 2)
                {
                    // El encabezado es claro: se respeta y la IA solo agrega columnas que el encabezado no nombró.
                    var deReglas = columnas;
                    columnas = new Dictionary<string, int>(porEncabezado);
                    foreach (var (campo, col) in deReglas.Concat(deIa))
                        if (!columnas.ContainsKey(campo) && !columnas.ContainsValue(col)) columnas[campo] = col;
                }
                else
                {
                    var deReglas = columnas;
                    columnas = deIa;
                    if (mapeo.FilaEncabezado == filaEncabezado || filaEncabezado == 0)
                        foreach (var (campo, col) in deReglas)
                            if (!columnas.ContainsKey(campo) && !columnas.ContainsValue(col)) columnas[campo] = col;
                    filaEncabezado = mapeo.FilaEncabezado;
                }
            }
            else aviso = r.Error is null
                ? "La IA no reconoció las columnas del archivo; se usaron las reglas."
                : r.Error + " Se usaron las reglas.";
        }
        else aviso = "La IA no está configurada: el archivo se analizó solo con reglas.";

        // Una columna es código TW solo si el encabezado lo dice o si sus valores tienen el formato EQ-TW-AAAA-NNNN.
        if (columnas.TryGetValue("codigoTw", out var colTw)
            && !(porEncabezado.TryGetValue("codigoTw", out var colTwEnc) && colTwEnc == colTw)
            && !ReconocedorColumnasEquipos.TraeCodigosTw(hoja.Filas, filaEncabezado, colTw))
        {
            columnas.Remove("codigoTw");
            if (!columnas.ContainsKey("numSerie") && !columnas.ContainsValue(colTw)) columnas["numSerie"] = colTw;
        }

        if (!columnas.Keys.Any(k => k is "numSerie" or "codigoTw" or "codigoCliente"))
            return new(1, "No se reconoció la columna del número de serie (N/S). Revise que el archivo tenga encabezados o descargue la plantilla.");

        // ── 2. Filas de datos ──
        var encabezados = hoja.Filas.FirstOrDefault(f => f.Numero == filaEncabezado)?.Celdas ?? [];
        string? Celda(FilaLeida f, string campo) =>
            columnas.TryGetValue(campo, out var c) && c < f.Celdas.Count && !string.IsNullOrWhiteSpace(f.Celdas[c]) ? f.Celdas[c].Trim() : null;

        var datos = hoja.Filas
            .Where(f => f.Numero > filaEncabezado)
            .Select(f => (f.Numero, d: new DatosLeidosEquipoDto
            {
                NumSerie      = ConciliadorEquiposImportacion.Recortar(Celda(f, "numSerie"), 80),
                CodigoTw      = ConciliadorEquiposImportacion.Recortar(Celda(f, "codigoTw"), 30),
                CodigoCliente = ConciliadorEquiposImportacion.Recortar(Celda(f, "codigoCliente"), 80),
                Equipo        = ConciliadorEquiposImportacion.Recortar(Celda(f, "equipo"), 200),
                Marca         = ConciliadorEquiposImportacion.Recortar(Celda(f, "marca"), 80),
                Modelo        = ConciliadorEquiposImportacion.Recortar(Celda(f, "modelo"), 80),
                Capacidad     = ConciliadorEquiposImportacion.Recortar(Celda(f, "capacidad"), 100),
                Ubicacion     = ConciliadorEquiposImportacion.Recortar(Celda(f, "ubicacion"), 200),
                Sede          = ConciliadorEquiposImportacion.Recortar(Celda(f, "sede"), 200),
            }))
            .Where(x => new[] { x.d.NumSerie, x.d.CodigoTw, x.d.CodigoCliente, x.d.Equipo, x.d.Marca, x.d.Modelo }
                        .Any(v => v is not null))
            .ToList();

        if (datos.Count == 0) return new(1, "El archivo no tiene equipos debajo de los encabezados.");
        if (datos.Count > LimitesImportacionEquipos.MaxFilas)
            return new(1, $"El archivo tiene {datos.Count} equipos; el máximo por importación es {LimitesImportacionEquipos.MaxFilas}. Divídalo en varios archivos.");

        // ── 3. Candidatos de la BD ──
        var series = datos.Select(x => ConciliadorEquiposImportacion.NormalizarSerie(x.d.NumSerie))
                          .Where(s => s.Length > 0).Distinct().ToList();
        var bd = await repositorio.ObtenerCandidatosAsync(solicitud.IdCliente, series, idUsuario, ct);
        if (bd.IdTipoMensaje != 2 || bd.Datos is null) return new(bd.IdTipoMensaje, bd.Mensaje);

        // ── 4. Conciliación por reglas ──
        var conciliador = new ConciliadorEquiposImportacion(bd.Datos, solicitud);
        var filas = datos.Select(x => conciliador.Conciliar(x.Numero, x.d)).ToList();

        // ── 5. La IA sugiere en lo que las reglas no resolvieron ──
        if (ia.Disponible)
        {
            var (usada, avisoConciliacion) = await ConciliarConIaAsync(filas, conciliador, ct);
            iaUsada |= usada;
            aviso ??= avisoConciliacion;
        }

        // ── 6. Duplicados en el archivo y equipos que ya están en la propuesta ──
        conciliador.MarcarDuplicados(filas);

        var resumen = new ResumenImportacionEquiposDto
        {
            Automaticos   = filas.Count(f => f.Estado == "automatico"),
            Revision      = filas.Count(f => f.Estado == "revision"),
            Nuevos        = filas.Count(f => f.Estado == "nuevo"),
            Omitidos      = filas.Count(f => f.Estado == "omitido"),
            Seleccionados = filas.Count(f => f.Seleccionado),
        };

        return new(2, $"Archivo analizado: {filas.Count} equipos ({resumen.Automaticos} automáticos, {resumen.Revision} por revisar, {resumen.Nuevos} nuevos, {resumen.Omitidos} omitidos).",
            new AnalisisImportacionEquiposDto
            {
                NombreArchivo  = Path.GetFileName(nombreArchivo),
                Hoja           = hoja.Nombre,
                FilaEncabezado = filaEncabezado,
                TotalFilas     = filas.Count,
                IaUtilizada    = iaUsada,
                Motor          = iaUsada ? ia.Motor : "reglas",
                AvisoIa        = aviso,
                Resumen        = resumen,
                Columnas       = ReconocedorColumnasEquipos.Campos
                                    .Where(columnas.ContainsKey)
                                    .Select(c => new ColumnaDetectadaDto(c, ReconocedorColumnasEquipos.Letra(columnas[c]),
                                        columnas[c] < encabezados.Count && encabezados[columnas[c]].Length > 0 ? encabezados[columnas[c]] : null))
                                    .ToList(),
                Filas          = filas,
                Sedes          = bd.Datos.Sedes,
                Clasificaciones = bd.Datos.Clasificaciones,
            });
    }

    private async Task<(bool Usada, string? Aviso)> ConciliarConIaAsync(
        List<FilaImportacionEquipoDto> filas, ConciliadorEquiposImportacion conciliador, CancellationToken ct)
    {
        var pendientes = filas
            .Where(f => f.Estado is "revision" or "nuevo" && MotivosParaIa.Contains(f.Motivo) && (f.Nuevo is not null || f.Candidatos.Count > 0))
            .Take(LimitesImportacionEquipos.MaxFilasIa)
            .Select(f => (f, consulta: new ConsultaConciliacionIaDto(f.Fila, f.Leido, f.Candidatos, conciliador.CandidatosSuministro(f.Leido, 8))))
            // Sin candidatos solo vale la pena si la IA puede deducir marca / modelo / clasificación del texto.
            .Where(x => x.consulta.Equipos.Count > 0 || x.consulta.Suministros.Count > 0 || x.f.Motivo == "faltan_datos"
                        || !string.IsNullOrWhiteSpace(x.f.Leido.Equipo))
            .ToList();
        if (pendientes.Count == 0) return (false, null);

        var usada = false;
        string? aviso = null;
        foreach (var lote in pendientes.Chunk(LimitesImportacionEquipos.FilasPorLlamadaIa))
        {
            var r = await ia.ConciliarAsync(lote.Select(x => x.consulta).ToList(), ct);
            if (r.Datos is null)
            {
                aviso = (r.Error ?? "La IA no respondió.") + " Las filas sin resolver quedaron con el resultado de las reglas.";
                break;
            }
            usada = true;
            var porFila = r.Datos.GroupBy(x => x.Fila).ToDictionary(g => g.Key, g => g.First());
            foreach (var (f, consulta) in lote)
                if (porFila.TryGetValue(f.Fila, out var res)) Aplicar(f, consulta, res, conciliador);
        }
        if (filas.Count(f => f.Estado is "revision" or "nuevo" && MotivosParaIa.Contains(f.Motivo)) > LimitesImportacionEquipos.MaxFilasIa)
            aviso ??= $"La IA revisó las primeras {LimitesImportacionEquipos.MaxFilasIa} filas pendientes; el resto quedó con el resultado de las reglas.";
        return (usada, aviso);
    }

    private static void Aplicar(FilaImportacionEquipoDto f, ConsultaConciliacionIaDto consulta, ConciliacionIaDto res,
                                ConciliadorEquiposImportacion conciliador)
    {
        var confianza = Math.Clamp(res.Confianza, 0, 100);

        // La IA eligió uno de los equipos parecidos del cliente (solo se acepta un candidato que se le envió).
        var equipo = res.IdEquipo is long idEq ? consulta.Equipos.FirstOrDefault(e => e.IdEquipo == idEq) : null;
        if (equipo is not null && confianza >= 60)
        {
            conciliador.SugerenciaIa(f, equipo, confianza, res.Motivo);
            return;
        }

        if (f.Nuevo is not { } nuevo) return;
        var cambio = false;
        var suministro = res.IdSuministro is long idSum ? consulta.Suministros.FirstOrDefault(s => s.IdSuministro == idSum) : null;
        if (suministro is not null && nuevo.IdSuministro is null && confianza >= 60)
        {
            conciliador.AsignarSuministro(nuevo, suministro);
            if (f.SuministrosCandidatos.All(s => s.IdSuministro != suministro.IdSuministro))
                f.SuministrosCandidatos.Insert(0, suministro);
            cambio = true;
        }
        if (string.IsNullOrWhiteSpace(nuevo.Marca) && !string.IsNullOrWhiteSpace(res.Marca))
        { nuevo.Marca = ConciliadorEquiposImportacion.Recortar(res.Marca, 80); cambio = true; }
        if (string.IsNullOrWhiteSpace(nuevo.Modelo) && !string.IsNullOrWhiteSpace(res.Modelo))
        { nuevo.Modelo = ConciliadorEquiposImportacion.Recortar(res.Modelo, 80); cambio = true; }
        if (nuevo.IdSuministro is null && conciliador.EsClasificacionValida(res.Clasificacion)
            && !string.Equals(nuevo.Clasificacion, res.Clasificacion, StringComparison.OrdinalIgnoreCase))
        { nuevo.Clasificacion = res.Clasificacion!.ToLowerInvariant(); cambio = true; }

        if (f.Motivo is "faltan_datos" or "sin_suministro")
        {
            conciliador.EvaluarNuevo(f);
            if (cambio) { f.Origen = "ia"; f.Confianza = Math.Max(f.Confianza, confianza); }
        }
        else if (f.Motivo == "serie_similar" && res.IdEquipo is null && confianza >= 80)
        {
            // La IA indica que ninguno de los equipos parecidos es el mismo: se propone registrarlo.
            conciliador.EvaluarNuevo(f);
            f.Origen = "ia";
            if (f.Estado == "nuevo") f.Seleccionado = confianza >= 90;
            f.Observaciones.Add("IA: ninguno de los equipos con serie parecida es este equipo"
                                + (string.IsNullOrWhiteSpace(res.Motivo) ? "." : " — " + ConciliadorEquiposImportacion.Recortar(res.Motivo, 300)));
        }
        else if (cambio) f.Origen = "ia";
        f.EstadoLabel = ConciliadorEquiposImportacion.Etiqueta(f);
    }
}

/// <summary>
/// Confirma la importación: vincula los equipos ya registrados y crea en el inventario del cliente los nuevos
/// (todo o nada). Devuelve la lista para agregar al listado de equipos de la propuesta (se guarda con la propuesta).
/// </summary>
public class ConfirmarImportacionEquiposCasoDeUso(IImportacionEquiposRepositorio repositorio)
{
    public async Task<RespuestaDto<ResultadoImportacionEquiposDto>> EjecutarAsync(
        ConfirmarImportacionEquiposSolicitudDto? s, long idUsuario, CancellationToken ct = default)
    {
        if (s is null || s.IdCliente <= 0) return new(1, "Indique el cliente de la propuesta.");
        if (s.Filas.Count == 0) return new(1, "Seleccione al menos un equipo para importar.");
        if (s.Filas.Count > LimitesImportacionEquipos.MaxFilas)
            return new(1, $"El máximo por importación es {LimitesImportacionEquipos.MaxFilas} equipos.");

        var ids    = new HashSet<long>();
        var series = new HashSet<string>();
        foreach (var f in s.Filas)
        {
            var fila = f.Fila > 0 ? $"Fila {f.Fila}: " : "";
            f.Accion = (f.Accion ?? "").Trim().ToLowerInvariant();
            switch (f.Accion)
            {
                case "vincular":
                    if (f.IdEquipo is not > 0) return new(1, fila + "indique el equipo a vincular.");
                    if (!ids.Add(f.IdEquipo.Value)) return new(1, fila + "el equipo está repetido en la importación.");
                    break;
                case "crear":
                    var serie = ConciliadorEquiposImportacion.NormalizarSerie(f.NumSerie);
                    if (serie.Length == 0) return new(1, fila + "el número de serie es obligatorio.");
                    if (!series.Add(serie)) return new(1, fila + $"la serie {f.NumSerie!.Trim()} está repetida en la importación.");
                    if (f.IdSede is not > 0) return new(1, fila + "indique la sede del equipo.");
                    if (string.IsNullOrWhiteSpace(f.Clasificacion)) return new(1, fila + "indique la clasificación (equipo, instrumento o pesa).");
                    if (f.IdSuministro is not > 0)
                        return new(1, fila + "elija el suministro del catálogo para registrar el equipo.");
                    f.NumSerie      = ConciliadorEquiposImportacion.Recortar(f.NumSerie, 80);
                    f.Marca         = ConciliadorEquiposImportacion.Recortar(f.Marca, 80);
                    f.Modelo        = ConciliadorEquiposImportacion.Recortar(f.Modelo, 80);
                    f.CodigoCliente = ConciliadorEquiposImportacion.Recortar(f.CodigoCliente, 80);
                    f.Ubicacion     = ConciliadorEquiposImportacion.Recortar(f.Ubicacion, 200);
                    f.AlcanceMaximo = ConciliadorEquiposImportacion.Recortar(f.AlcanceMaximo, 40);
                    f.Clasificacion = f.Clasificacion.Trim().ToLowerInvariant();
                    break;
                default:
                    return new(1, fila + "la acción debe ser vincular o crear.");
            }
        }

        return await repositorio.ImportarAsync(s, idUsuario, ct);
    }
}

/// <summary>Plantilla .xlsx sugerida (el archivo puede tener otro formato: la IA reconoce las columnas).</summary>
public class DescargarPlantillaImportacionEquiposCasoDeUso(IGeneradorExcel excel)
{
    public ArchivoGeneradoDto Ejecutar()
    {
        var equipos = new HojaExcel("Equipos", LimitesImportacionEquipos.Encabezados, []);
        var instrucciones = new HojaExcel("Instrucciones", ["Columna", "Obligatorio", "Descripción"],
        [
            ["N/S (número de serie)", "Sí", "Número de serie de la placa del equipo. Se usa para encontrar el equipo en el inventario del cliente."],
            ["Código TW", "No", "Código EQ-TW-AAAA-NNNN si el equipo ya está registrado (identifica al equipo sin dudas)."],
            ["Código del cliente", "No", "Tag o código interno del cliente."],
            ["Equipo / instrumento", "Recomendado", "Descripción del equipo (ej. Báscula camionera 80 t). Ayuda a la IA a reconocer el modelo del catálogo."],
            ["Marca / Modelo", "Para equipos nuevos", "Obligatorios para registrar un equipo nuevo si no se elige el modelo del catálogo."],
            ["Capacidad / alcance", "No", "Capacidad máxima (ej. 80 000 kg). Se registra como alcance máximo."],
            ["Sede", "No", "Sede del cliente; si no se indica se usa la sede del requerimiento."],
            ["Ubicación en sede", "No", "Área o lugar dentro de la sede."],
            ["Límites", "", $"Archivos .xlsx o .csv de hasta 5 MB y {LimitesImportacionEquipos.MaxFilas} equipos. El formato es libre: la IA reconoce las columnas aunque tengan otros nombres."],
        ]);
        return new ArchivoGeneradoDto(excel.Generar([equipos, instrucciones]), "Plantilla_Importacion_Equipos.xlsx", LimitesImportacionEquipos.TipoXlsx);
    }
}

/// <summary>Reporte .xlsx de la conciliación (con lo que el comercial tenga en pantalla, incluidas sus correcciones).</summary>
public class ExportarReporteImportacionEquiposCasoDeUso(IGeneradorExcel excel)
{
    public RespuestaDto<ArchivoGeneradoDto> Ejecutar(List<FilaImportacionEquipoDto>? filas)
    {
        if (filas is null || filas.Count == 0) return new(1, "No hay filas para el reporte.");
        if (filas.Count > LimitesImportacionEquipos.MaxFilas) return new(1, "Demasiadas filas para el reporte.");

        var hoja = new HojaExcel("Conciliación",
            ["Fila", "N/S (archivo)", "Equipo (archivo)", "Marca (archivo)", "Modelo (archivo)", "Capacidad", "Ubicación",
             "Estado", "Acción", "Código TW asignado", "N/S registrado", "Marca / modelo registrados", "Sede", "Confianza %",
             "Origen", "Seleccionado", "Observaciones"],
            filas.OrderBy(f => f.Fila).Select(f => (IReadOnlyList<object?>)
            [
                f.Fila, f.Leido.NumSerie, f.Leido.Equipo, f.Leido.Marca, f.Leido.Modelo, f.Leido.Capacidad, f.Leido.Ubicacion,
                string.IsNullOrWhiteSpace(f.EstadoLabel) ? f.Estado : f.EstadoLabel,
                f.Accion switch { "vincular" => "Vincular", "crear" => "Crear equipo", _ => "—" },
                f.Accion == "vincular" ? f.Equipo?.CodigoTw : f.Accion == "crear" ? "(nuevo)" : null,
                f.Accion == "vincular" ? f.Equipo?.NumSerie : f.Nuevo?.NumSerie,
                f.Accion == "vincular" ? $"{f.Equipo?.Marca} {f.Equipo?.Modelo}".Trim() : $"{f.Nuevo?.Marca} {f.Nuevo?.Modelo}".Trim(),
                f.Accion == "vincular" ? f.Equipo?.SedeNombre : f.Nuevo?.SedeNombre,
                f.Confianza, f.Origen == "ia" ? "IA" : "Reglas", f.Seleccionado ? "Sí" : "No",
                string.Join(" | ", f.Observaciones),
            ]).ToList());

        return new(2, "Reporte generado.",
            new ArchivoGeneradoDto(excel.Generar([hoja]), $"Conciliacion_Equipos_{DateTime.Now:yyyyMMdd-HHmm}.xlsx", LimitesImportacionEquipos.TipoXlsx));
    }
}
