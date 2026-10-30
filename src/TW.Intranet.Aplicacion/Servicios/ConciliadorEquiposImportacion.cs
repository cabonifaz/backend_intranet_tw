using System.Text;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// Importación de equipos de una propuesta: reglas de conciliación de cada fila del Excel contra los equipos del
/// cliente, los de otros clientes y el catálogo de suministros. Las filas que las reglas no resuelven quedan en
/// revisión con candidatos; la IA (si está disponible) sugiere después cuál corresponde.
/// </summary>
public sealed class ConciliadorEquiposImportacion
{
    private readonly CandidatosImportacionEquiposDto bd;
    private readonly AnalizarImportacionEquiposSolicitudDto solicitud;
    private readonly ILookup<string, EquipoConciliadoDto> porSerie;
    private readonly ILookup<string, EquipoConciliadoDto> porCodigoCliente;
    private readonly Dictionary<string, EquipoConciliadoDto> porCodigoTw;
    private readonly ILookup<string, EquipoOtroClienteDto> otrosPorSerie;
    private readonly HashSet<string> clasificacionesValidas;

    public ConciliadorEquiposImportacion(CandidatosImportacionEquiposDto bd, AnalizarImportacionEquiposSolicitudDto solicitud)
    {
        this.bd        = bd;
        this.solicitud = solicitud;
        porSerie          = bd.Equipos.ToLookup(e => NormalizarSerie(e.NumSerie));
        porCodigoCliente  = bd.Equipos.Where(e => !string.IsNullOrWhiteSpace(e.CodigoCliente))
                                      .ToLookup(e => NormalizarSerie(e.CodigoCliente));
        porCodigoTw       = bd.Equipos.GroupBy(e => e.CodigoTw.Trim().ToUpperInvariant())
                                      .ToDictionary(g => g.Key, g => g.First());
        otrosPorSerie     = bd.EnOtrosClientes.ToLookup(e => NormalizarSerie(e.NumSerie));
        clasificacionesValidas = bd.Clasificaciones.Where(c => c.Codigo is not null)
                                                   .Select(c => c.Codigo!).ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    // ══════════════════════ Normalización y parecido ══════════════════════

    /// <summary>Serie o código para comparar: solo letras y dígitos, en mayúsculas ("mt-8644 29" → "MT864429").</summary>
    public static string NormalizarSerie(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var sb = new StringBuilder(s.Length);
        foreach (var c in Similitud.Normalizar(s)) if (char.IsLetterOrDigit(c)) sb.Append(char.ToUpperInvariant(c));
        return sb.ToString();
    }

    /// <summary>Parecido de dos series normalizadas (0 a 100): errores de tipeo, un carácter de más o de menos.</summary>
    public static int PuntajeSerie(string a, string b)
    {
        if (a.Length == 0 || b.Length == 0) return 0;
        if (a == b) return 100;
        if (Math.Min(a.Length, b.Length) < 4) return 0;
        var puntaje = (int)Math.Round(100.0 * (1 - (double)Levenshtein(a, b) / Math.Max(a.Length, b.Length)));
        if (Math.Min(a.Length, b.Length) >= 5 && (a.Contains(b) || b.Contains(a))) puntaje = Math.Max(puntaje, 85);
        return puntaje;
    }

    /// <summary>Umbral para mostrar un equipo del cliente como "serie parecida".</summary>
    public const int UmbralSerieParecida = 75;

    private static int Levenshtein(string a, string b)
    {
        var d = new int[b.Length + 1];
        for (int j = 0; j <= b.Length; j++) d[j] = j;
        for (int i = 1; i <= a.Length; i++)
        {
            int prev = d[0]; d[0] = i;
            for (int j = 1; j <= b.Length; j++)
            {
                int tmp = d[j];
                d[j] = Math.Min(Math.Min(d[j] + 1, d[j - 1] + 1), prev + (a[i - 1] == b[j - 1] ? 0 : 1));
                prev = tmp;
            }
        }
        return d[b.Length];
    }

    private static bool MismoTexto(string? a, string? b) =>
        !string.IsNullOrWhiteSpace(a) && !string.IsNullOrWhiteSpace(b) && Similitud.Normalizar(a) == Similitud.Normalizar(b);

    private static int Parecido(string? a, string? b) =>
        string.IsNullOrWhiteSpace(a) || string.IsNullOrWhiteSpace(b) ? 0 : Similitud.Puntaje(a, b);

    // ══════════════════════ Puntaje ponderado ══════════════════════
    //
    // Matriz acordada con el equipo (suma 100):
    //   N/S exacto 55 (ancla: identifica al equipo físico; N/S parecido, hasta 2 caracteres de diferencia: 25)
    //   Suministro 25 (marca + modelo + capacidad; confirma el tipo de equipo)
    //   Código del cliente 10 · Sede 5 · Ubicación 5 (refuerzos mutables: el cliente puede cambiarlos)
    // Estado por puntaje: ≥ 80 automático · 40 a 79 revisión (sin preseleccionar) · < 40 equipo nuevo.
    // Solo el N/S exacto llega a automático: un N/S parecido o una fila sin N/S quedan como máximo en revisión.

    public const int PesoSerie          = 55;
    public const int PesoSerieParecida  = 25;
    public const int PesoSuministro     = 25;
    public const int PesoCodigoCliente  = 10;
    public const int PesoSede           = 5;
    public const int PesoUbicacion      = 5;
    public const int UmbralAutomatico   = 80;
    public const int UmbralRevision     = 40;
    /// <summary>Diferencia máxima (Levenshtein) para considerar parecido un N/S.</summary>
    public const int MaxDiferenciaSerie = 2;

    /// <summary>Señales que coinciden entre la fila y un equipo del cliente.</summary>
    public sealed record Puntaje(int Total, bool SerieExacta, bool SerieParecida, int Suministro, bool SuministroDistinto,
                                 bool CodigoCliente, bool Sede, bool Ubicacion);

    public static bool SerieParecida(string a, string b) =>
        a.Length > 0 && b.Length > 0 && a != b && Math.Min(a.Length, b.Length) >= 5 && Levenshtein(a, b) <= MaxDiferenciaSerie;

    private static bool Coincide(string? a, string? b) =>
        !string.IsNullOrWhiteSpace(a) && !string.IsNullOrWhiteSpace(b)
        && (NormalizarSerie(a) == NormalizarSerie(b) || Parecido(a, b) >= Similitud.UmbralDuplicado);

    private static bool Vacio(string? s) => string.IsNullOrWhiteSpace(s);

    public Puntaje Puntuar(DatosLeidosEquipoDto d, EquipoConciliadoDto e)
    {
        var ns = NormalizarSerie(d.NumSerie);
        var nsBd = NormalizarSerie(e.NumSerie);
        bool exacta = ns.Length > 0 && ns == nsBd;
        bool parecida = !exacta && SerieParecida(ns, nsBd);

        // Suministro: marca + modelo (+ capacidad). Si el archivo no trae marca ni modelo, no contradice: con el N/S
        // exacto basta (el comercial ve la observación). Si los trae y no coinciden, el suministro es distinto.
        int suministro = 0; bool distinto = false;
        bool hayMarca = !Vacio(d.Marca), hayModelo = !Vacio(d.Modelo);
        bool marca  = hayMarca && (Coincide(d.Marca, e.Marca) || e.Marca.Equals("Genérico", StringComparison.OrdinalIgnoreCase));
        bool modelo = hayModelo && Coincide(d.Modelo, e.Modelo);
        bool capacidadDistinta = !Vacio(d.Capacidad) && !Vacio(e.AlcanceMaximo)
                                 && NormalizarSerie(d.Capacidad) != NormalizarSerie(e.AlcanceMaximo);
        if (!hayMarca && !hayModelo) suministro = exacta ? PesoSuministro : 0;
        else if ((marca || !hayMarca) && (modelo || !hayModelo)) suministro = capacidadDistinta ? 15 : PesoSuministro;
        else if (marca || modelo) { suministro = 10; distinto = true; }
        else distinto = true;

        bool codigo    = Coincide(d.CodigoCliente, e.CodigoCliente);
        bool sede      = !Vacio(d.Sede) && !Vacio(e.SedeNombre) && Parecido(d.Sede, e.SedeNombre) >= Similitud.UmbralDuplicado;
        bool ubicacion = !Vacio(d.Ubicacion) && !Vacio(e.Ubicacion) && Parecido(d.Ubicacion, e.Ubicacion) >= Similitud.UmbralDuplicado;

        int total = (exacta ? PesoSerie : parecida ? PesoSerieParecida : 0) + suministro
                    + (codigo ? PesoCodigoCliente : 0) + (sede ? PesoSede : 0) + (ubicacion ? PesoUbicacion : 0);
        return new Puntaje(Math.Min(total, 100), exacta, parecida, suministro, distinto, codigo, sede, ubicacion);
    }

    // ══════════════════════ Conciliación por reglas ══════════════════════

    public FilaImportacionEquipoDto Conciliar(int fila, DatosLeidosEquipoDto d)
    {
        var f  = new FilaImportacionEquipoDto { Fila = fila, Leido = d };
        var ns = NormalizarSerie(d.NumSerie);

        // 1. Código TW: identifica al equipo sin ambigüedad.
        if (!string.IsNullOrWhiteSpace(d.CodigoTw) && porCodigoTw.TryGetValue(d.CodigoTw.Trim().ToUpperInvariant(), out var porTw))
        {
            if (ns.Length > 0 && NormalizarSerie(porTw.NumSerie) != ns)
            {
                Revision(f, "serie_distinta", Con(porTw, 100), seleccionar: false, confianza: Math.Min(Puntuar(d, porTw).Total + PesoSerie, 79));
                f.Observaciones.Add($"El código TW {porTw.CodigoTw} está registrado con la serie {porTw.NumSerie}, no con {d.NumSerie}.");
            }
            else
            {
                Automatico(f, porTw, "codigo_tw", 100);
                AvisarCambios(f, d, porTw);
            }
            return f;
        }

        // 2. La serie es de un equipo de OTRO cliente (y no del cliente): no se puede vincular ni duplicar.
        if (ns.Length > 0 && !porSerie.Contains(ns) && otrosPorSerie.Contains(ns))
        {
            var o = otrosPorSerie[ns].First();
            Omitir(f, "otro_cliente");
            f.Observaciones.Add($"La serie {d.NumSerie} está registrada como equipo de {o.RazonSocial ?? "otro cliente"} ({o.CodigoTw}, {o.Marca} {o.Modelo}). Coordine su traslado con el área de equipos.");
            return f;
        }

        // 3. Candidatos: N/S exacto o parecido, código del cliente y, sin N/S, misma marca y modelo. Se puntúa cada uno.
        var cc = NormalizarSerie(d.CodigoCliente);
        var puntuados = bd.Equipos
            .Where(e =>
            {
                var nsBd = NormalizarSerie(e.NumSerie);
                return (ns.Length > 0 && (nsBd == ns || SerieParecida(ns, nsBd)))
                    || (cc.Length > 0 && NormalizarSerie(e.CodigoCliente) == cc)
                    || (ns.Length == 0 && Coincide(d.Marca, e.Marca) && Coincide(d.Modelo, e.Modelo));
            })
            .Select(e => (e, p: Puntuar(d, e)))
            .OrderByDescending(x => x.p.Total).ThenByDescending(x => x.p.SerieExacta)
            .Take(5).ToList();
        f.Candidatos = puntuados.Select(x => Con(x.e, x.p.Total)).ToList();
        var mejor = puntuados.FirstOrDefault();

        // 4. Sin coincidencia suficiente (< 40): equipo nuevo para el cliente.
        if (mejor.e is null || mejor.p.Total < UmbralRevision)
        {
            if (mejor.e is not null)
                f.Observaciones.Add($"Coincidencia débil ({mejor.p.Total}%) con {mejor.e.CodigoTw} ({mejor.e.Marca} {mejor.e.Modelo}, serie {mejor.e.NumSerie}): "
                                    + (ns.Length == 0 ? "no alcanza para vincularlo al inventario." : "se propone como equipo nuevo."));
            if (ns.Length == 0)
            {
                Revision(f, "sin_serie", null, seleccionar: false, confianza: mejor.e is null ? 0 : mejor.p.Total);
                f.Importable = false;
                f.Observaciones.Add("La fila no tiene número de serie (obligatorio para registrar el equipo).");
                return f;
            }
            PrepararNuevo(f, d, ns);
            EvaluarNuevo(f);
            f.Confianza = mejor.e is null ? 0 : mejor.p.Total;
            return f;
        }

        var exactos = puntuados.Where(x => x.p.SerieExacta).ToList();

        // 5. Automático: solo con N/S exacto y ≥ 80, sin otro equipo del cliente con la misma serie que compita.
        if (mejor.p.SerieExacta && mejor.p.Total >= UmbralAutomatico
            && (exactos.Count == 1 || exactos[1].p.Total < UmbralAutomatico))
        {
            Automatico(f, mejor.e, "num_serie", mejor.p.Total);
            f.Candidatos = [];
            if (Vacio(d.Marca) && Vacio(d.Modelo))
                f.Observaciones.Add("ⓘ El archivo no trae marca ni modelo: se identificó solo por el N/S.");
            AvisarCambios(f, d, mejor.e);
            return f;
        }

        // 6. Revisión (40 a 79, o N/S repetido en el cliente): el comercial confirma.
        string motivo; string observacion;
        if (exactos.Count > 1)
        {
            motivo = "serie_repetida";
            observacion = $"El cliente tiene {exactos.Count} equipos con la serie {d.NumSerie}: elija cuál es.";
        }
        else if (mejor.p.SerieExacta)
        {
            motivo = mejor.p.SuministroDistinto ? "suministro_distinto" : "coincidencia_parcial";
            observacion = mejor.p.SuministroDistinto
                ? $"La serie coincide con {mejor.e.CodigoTw}, pero está registrado como {mejor.e.Marca} {mejor.e.Modelo} y el archivo indica {d.Marca} {d.Modelo}."
                : $"La serie coincide con {mejor.e.CodigoTw}, pero los demás datos no lo confirman.";
        }
        else if (mejor.p.SerieParecida)
        {
            motivo = "serie_similar";
            observacion = $"No hay un equipo con la serie {d.NumSerie}; el más parecido es {mejor.e.NumSerie} ({mejor.e.CodigoTw}). Puede ser un error de tipeo o un equipo distinto.";
        }
        else
        {
            motivo = "codigo_cliente";
            observacion = ns.Length == 0
                ? $"Sin N/S en el archivo: coincide con {mejor.e.CodigoTw} por el código del cliente y otros datos. Confirme que es el mismo equipo."
                : $"El código del cliente {d.CodigoCliente} corresponde al equipo {mejor.e.CodigoTw} (serie {mejor.e.NumSerie}), pero el archivo indica la serie {d.NumSerie}.";
        }
        Revision(f, motivo, Con(mejor.e, mejor.p.Total), seleccionar: false, confianza: Math.Min(mejor.p.Total, UmbralAutomatico - 1));
        f.Observaciones.Add(observacion);
        if (ns.Length > 0 && !mejor.p.SerieExacta) PrepararNuevo(f, d, ns);
        return f;
    }

    /// <summary>Match automático con datos mutables distintos: avisa sin forzar la revisión.</summary>
    private void AvisarCambios(FilaImportacionEquipoDto f, DatosLeidosEquipoDto d, EquipoConciliadoDto e)
    {
        if (!Vacio(d.CodigoCliente) && !Vacio(e.CodigoCliente) && !Coincide(d.CodigoCliente, e.CodigoCliente))
            f.Observaciones.Add($"ⓘ Código cliente cambió: {e.CodigoCliente} → {d.CodigoCliente}");
        if (!Vacio(d.Sede) && !Vacio(e.SedeNombre) && Parecido(d.Sede, e.SedeNombre) < Similitud.UmbralDuplicado)
            f.Observaciones.Add($"ⓘ Sede cambió: {e.SedeNombre} → {d.Sede}");
        if (!Vacio(d.Ubicacion) && !Vacio(e.Ubicacion) && Parecido(d.Ubicacion, e.Ubicacion) < Similitud.UmbralDuplicado)
            f.Observaciones.Add($"ⓘ Ubicación cambió: {e.Ubicacion} → {d.Ubicacion}");
        if (!Vacio(d.Marca) && !Vacio(e.Marca) && !Coincide(d.Marca, e.Marca) && !e.Marca.Equals("Genérico", StringComparison.OrdinalIgnoreCase))
            f.Observaciones.Add($"ⓘ Marca distinta: registrada {e.Marca}, archivo {d.Marca}");
    }

    // ══════════════════════ Equipo nuevo ══════════════════════

    private void PrepararNuevo(FilaImportacionEquipoDto f, DatosLeidosEquipoDto d, string ns)
    {
        var (idSede, sedeNombre) = ResolverSede(d.Sede);
        f.Nuevo = new NuevoEquipoImportacionDto
        {
            NumSerie      = Recortar(d.NumSerie!.Trim(), 80)!,
            Marca         = Recortar(d.Marca, 80),
            Modelo        = Recortar(d.Modelo, 80),
            IdSede        = idSede,
            SedeNombre    = sedeNombre,
            CodigoCliente = Recortar(d.CodigoCliente, 80),
            Ubicacion     = Recortar(d.Ubicacion, 200),
            AlcanceMaximo = Recortar(d.Capacidad, 40),
            Clasificacion = ClasificacionPorTexto(d.Equipo),
        };

        // Suministro del catálogo: misma marca y modelo.
        var exactos = bd.Suministros.Where(s => MismoTexto(s.Marca, d.Marca) && MismoTexto(s.Modelo, d.Modelo)).ToList();
        if (exactos.Count == 1) AsignarSuministro(f.Nuevo, exactos[0]);

        f.SuministrosCandidatos = CandidatosSuministro(d, 5);
        if (f.Nuevo.IdSuministro is null && exactos.Count > 1)
            f.SuministrosCandidatos = exactos.Take(5).Select(s => ConPuntaje(s, 100)).ToList();
    }

    /// <summary>Suministros más parecidos a la fila (marca + modelo, o la descripción del equipo).</summary>
    public List<SuministroConciliadoDto> CandidatosSuministro(DatosLeidosEquipoDto d, int maximo)
    {
        var marcaModelo = $"{d.Marca} {d.Modelo}".Trim();
        var texto       = $"{d.Equipo} {d.Marca} {d.Modelo}".Trim();
        var palabras    = Palabras(texto);
        if (palabras.Count == 0) return [];

        return bd.Suministros
            .Select(s =>
            {
                var p = Math.Max(Math.Max(Parecido(marcaModelo, $"{s.Marca} {s.Modelo}"), Parecido(d.Modelo, s.Modelo)),
                                 Parecido(texto, s.Descripcion));
                var comunes = Palabras($"{s.Descripcion} {s.Marca} {s.Modelo} {s.Tipo} {s.Subtipo}").Count(palabras.Contains);
                return (s, p, comunes);
            })
            .Where(x => x.p >= 60 || x.comunes >= 2)
            .OrderByDescending(x => x.p).ThenByDescending(x => x.comunes)
            .Take(maximo)
            .Select(x => ConPuntaje(x.s, Math.Max(x.p, Math.Min(59, x.comunes * 20))))
            .ToList();
    }

    private static HashSet<string> Palabras(string texto) =>
        Similitud.Normalizar(texto).Split(' ', StringSplitOptions.RemoveEmptyEntries)
                 .Where(p => p.Length >= 3 || p.Any(char.IsDigit)).ToHashSet();

    public void AsignarSuministro(NuevoEquipoImportacionDto n, SuministroConciliadoDto s)
    {
        n.IdSuministro          = s.IdSuministro;
        n.SuministroDescripcion = s.Descripcion;
        if (string.IsNullOrWhiteSpace(n.Marca))  n.Marca  = Recortar(s.Marca, 80);
        if (string.IsNullOrWhiteSpace(n.Modelo)) n.Modelo = Recortar(s.Modelo, 80);
        if (s.Clase is not null && clasificacionesValidas.Contains(s.Clase)) n.Clasificacion = s.Clase.ToLowerInvariant();
    }

    /// <summary>Clasificación por el texto del equipo (la IA o el comercial la corrigen).</summary>
    private string? ClasificacionPorTexto(string? equipo)
    {
        var t = Similitud.Normalizar(equipo ?? "");
        string c = t.Contains("pesa") || t.Contains("patron") ? "pesa"
                 : t.Contains("termometro") || t.Contains("manometro") || t.Contains("dinamometro") || t.Contains("higrometro")
                   || t.Contains("calibrador") || t.Contains("cronometro") || t.Contains("humedad") || t.Contains("determinador")
                   || t.Contains("estufa") || t.Contains("mufla") ? "instrumento"
                 : "equipo";
        return clasificacionesValidas.Contains(c) ? c : clasificacionesValidas.FirstOrDefault();
    }

    public bool EsClasificacionValida(string? c) => c is not null && clasificacionesValidas.Contains(c);

    private (long? Id, string? Nombre) ResolverSede(string? sedeArchivo)
    {
        if (!string.IsNullOrWhiteSpace(sedeArchivo))
        {
            var mejor = bd.Sedes.Select(s => (s, p: Parecido(sedeArchivo, s.Nombre))).OrderByDescending(x => x.p).FirstOrDefault();
            if (mejor.s is not null && mejor.p >= Similitud.UmbralDuplicado) return (mejor.s.Id, mejor.s.Nombre);
        }
        var porDefecto = solicitud.IdSede is > 0 ? bd.Sedes.FirstOrDefault(s => s.Id == solicitud.IdSede) : null;
        if (porDefecto is not null) return (porDefecto.Id, porDefecto.Nombre);
        return bd.Sedes.Count == 1 ? (bd.Sedes[0].Id, bd.Sedes[0].Nombre) : (null, null);
    }

    /// <summary>
    /// Estado de una fila cuyo destino es crear el equipo. Un equipo del cliente no se registra sin su ficha técnica
    /// (suministro del catálogo): sin suministro queda en revisión "sin_suministro" y no se puede importar hasta que el
    /// comercial elija uno (si el modelo no existe, se crea antes en el maestro de Suministros, HU-86).
    /// Con suministro, nuevo si también tiene clasificación y sede; si no, revisión "faltan_datos".
    /// </summary>
    public void EvaluarNuevo(FilaImportacionEquipoDto f)
    {
        var n = f.Nuevo!;
        f.Equipo = null;
        f.Accion = "crear";
        f.Observaciones.RemoveAll(o => o.StartsWith("Para registrar el equipo"));

        var faltan = new List<string>();
        if (!EsClasificacionValida(n.Clasificacion)) faltan.Add("la clasificación");
        if (n.IdSede is null) faltan.Add("la sede");

        if (n.IdSuministro is null)
        {
            f.Estado = "revision"; f.Motivo = "sin_suministro"; f.Importable = false; f.Seleccionado = false;
            f.Observaciones.Add("Para registrar el equipo elija el suministro del catálogo"
                + (faltan.Count > 0 ? " e indique " + string.Join(" y ", faltan) : "")
                + ". Si el modelo no está en el catálogo, créelo primero en el maestro de Suministros.");
        }
        else if (faltan.Count > 0)
        {
            f.Estado = "revision"; f.Motivo = "faltan_datos"; f.Importable = false; f.Seleccionado = false;
            f.Observaciones.Add("Para registrar el equipo indique " + string.Join(" y ", faltan) + ".");
        }
        else
        {
            f.Estado = "nuevo"; f.Motivo = "catalogo"; f.Importable = true; f.Seleccionado = true;
        }
        f.EstadoLabel = Etiqueta(f);
    }

    // ══════════════════════ Duplicados ══════════════════════

    /// <summary>
    /// Después de conciliar (reglas + IA): omite las filas que repiten un equipo de otra fila del archivo o que ya
    /// están en el listado de la propuesta.
    /// </summary>
    public void MarcarDuplicados(IReadOnlyList<FilaImportacionEquipoDto> filas)
    {
        var enPropuestaIds    = solicitud.IdsEquipoEnPropuesta.ToHashSet();
        var enPropuestaSeries = solicitud.SeriesEnPropuesta.Select(NormalizarSerie).Where(s => s.Length > 0).ToHashSet();
        var vistos = new Dictionary<string, int>();

        foreach (var f in filas)
        {
            if (f.Estado == "omitido") continue;
            var serie = NormalizarSerie(f.Equipo?.NumSerie ?? f.Nuevo?.NumSerie ?? f.Leido.NumSerie);

            if ((f.Equipo is not null && f.Accion == "vincular" && enPropuestaIds.Contains(f.Equipo.IdEquipo))
                || (serie.Length > 0 && enPropuestaSeries.Contains(serie)))
            {
                Omitir(f, "ya_en_propuesta");
                f.Observaciones.Add("El equipo ya está en el listado de la propuesta.");
                continue;
            }

            var clave = f.Accion == "vincular" && f.Equipo is not null ? "E" + f.Equipo.IdEquipo : serie.Length > 0 ? "S" + serie : null;
            if (clave is null) continue;
            if (vistos.TryGetValue(clave, out var primera))
            {
                Omitir(f, "duplicado_archivo");
                f.Observaciones.Add($"Repite el equipo de la fila {primera}.");
            }
            else vistos[clave] = f.Fila;
        }
    }

    // ══════════════════════ Estados ══════════════════════

    private void Automatico(FilaImportacionEquipoDto f, EquipoConciliadoDto e, string motivo, int confianza)
    {
        f.Equipo = Con(e, 100); f.Accion = "vincular"; f.Motivo = motivo; f.Confianza = confianza;
        f.Estado = "automatico"; f.Importable = true; f.Seleccionado = true;
        if (e.Estado == "inactivo")
        {
            f.Estado = "revision"; f.Motivo = "equipo_inactivo"; f.Seleccionado = false;
            f.Observaciones.Add($"El equipo {e.CodigoTw} está inactivo en el inventario del cliente.");
        }
        else if (e.Estado == "borrador")
            f.Observaciones.Add($"El equipo {e.CodigoTw} está en borrador en el inventario del cliente.");
        f.EstadoLabel = Etiqueta(f);
    }

    private void Revision(FilaImportacionEquipoDto f, string motivo, EquipoConciliadoDto? e, bool seleccionar, int confianza)
    {
        f.Estado = "revision"; f.Motivo = motivo; f.Equipo = e; f.Accion = e is null ? "ninguna" : "vincular";
        f.Importable = e is not null; f.Seleccionado = seleccionar && e is not null; f.Confianza = Math.Clamp(confianza, 0, 100);
        f.EstadoLabel = Etiqueta(f);
    }

    /// <summary>
    /// Elegido por la IA entre los candidatos: queda en revisión sin preseleccionar (el comercial confirma). La confianza
    /// es la de la matriz de pesos (la IA no la sube: un N/S parecido o una fila sin N/S nunca llegan a automático).
    /// </summary>
    public void SugerenciaIa(FilaImportacionEquipoDto f, EquipoConciliadoDto e, int confianzaIa, string? motivo)
    {
        var puntaje = Math.Min(Puntuar(f.Leido, e).Total, UmbralAutomatico - 1);
        Revision(f, "sugerencia_ia", Con(e, puntaje), seleccionar: false, confianza: puntaje);
        f.Origen = "ia";
        f.Observaciones.Add($"IA ({confianzaIa}%): " + (Recortar(motivo, 300) ?? "es el equipo más probable."));
        f.EstadoLabel = Etiqueta(f);
    }

    private static void Omitir(FilaImportacionEquipoDto f, string motivo)
    {
        f.Estado = "omitido"; f.Motivo = motivo; f.Accion = "ninguna"; f.Importable = false; f.Seleccionado = false;
        f.EstadoLabel = Etiqueta(f);
    }

    public static string Etiqueta(FilaImportacionEquipoDto f) => f.Estado switch
    {
        "automatico" => $"Match {f.Confianza}% automático",
        "nuevo"      => "Nuevo registro en sede",
        "omitido"    => f.Motivo switch
        {
            "duplicado_archivo" => "Duplicado en el archivo",
            "ya_en_propuesta"   => "Ya está en la propuesta",
            "otro_cliente"      => "Registrado en otro cliente",
            _                   => "Omitido",
        },
        _ => f.Motivo switch
        {
            "sugerencia_ia"   => $"Sugerencia IA ({f.Confianza}%) — revisar",
            "serie_similar"   => "Revisar: serie parecida",
            "serie_repetida"  => "Revisar: serie repetida en el cliente",
            "serie_distinta"  => "Revisar: código TW con otra serie",
            "codigo_cliente"  => "Revisar: coincide el código del cliente",
            "suministro_distinto"  => "Revisar: misma serie, otra marca o modelo",
            "coincidencia_parcial" => "Revisar: coincidencia parcial",
            "equipo_inactivo" => "Revisar: equipo inactivo",
            "sin_serie"       => "Falta el N/S",
            "faltan_datos"    => "Faltan datos para registrar",
            "sin_suministro"  => "Falta el suministro del catálogo",
            _                 => "Revisión manual",
        },
    };

    private static EquipoConciliadoDto Con(EquipoConciliadoDto e, int puntaje) => new()
    {
        IdEquipo = e.IdEquipo, CodigoTw = e.CodigoTw, NumSerie = e.NumSerie, CodigoCliente = e.CodigoCliente,
        Clasificacion = e.Clasificacion, ClasificacionLabel = e.ClasificacionLabel, Marca = e.Marca, Modelo = e.Modelo,
        IdSede = e.IdSede, SedeNombre = e.SedeNombre, Ubicacion = e.Ubicacion, AlcanceMaximo = e.AlcanceMaximo,
        Estado = e.Estado, Tipo = e.Tipo, Subtipo = e.Subtipo, Puntaje = puntaje,
    };

    private static SuministroConciliadoDto ConPuntaje(SuministroConciliadoDto s, int puntaje) => new()
    {
        IdSuministro = s.IdSuministro, Codigo = s.Codigo, Descripcion = s.Descripcion, Clase = s.Clase,
        Tipo = s.Tipo, Subtipo = s.Subtipo, Marca = s.Marca, Modelo = s.Modelo, Puntaje = puntaje,
    };

    public static string? Recortar(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        return s.Length > max ? s[..max] : s;
    }
}
