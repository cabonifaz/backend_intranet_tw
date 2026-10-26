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
                Revision(f, "serie_distinta", Con(porTw, 100), seleccionar: true, confianza: 80);
                f.Observaciones.Add($"El código TW {porTw.CodigoTw} está registrado con la serie {porTw.NumSerie}, no con {d.NumSerie}.");
            }
            else Automatico(f, porTw, "codigo_tw", 100);
            return f;
        }

        // 2. N.° de serie exacto en el cliente.
        if (ns.Length > 0 && porSerie.Contains(ns))
        {
            var mismos = porSerie[ns].ToList();
            if (mismos.Count == 1)
            {
                var e = mismos[0];
                var marcaDistinta = !string.IsNullOrWhiteSpace(d.Marca) && Parecido(d.Marca, e.Marca) < Similitud.UmbralParecido
                                    && !e.Marca.Equals("Genérico", StringComparison.OrdinalIgnoreCase);
                Automatico(f, e, "num_serie", marcaDistinta ? 90 : 100);
                if (marcaDistinta) f.Observaciones.Add($"La marca del archivo ({d.Marca}) no coincide con la registrada ({e.Marca}).");
                return f;
            }

            // Misma serie en varios equipos del cliente (de distinta marca/modelo): se elige por marca y modelo.
            var puntuados = mismos
                .Select(e => (e, p: Math.Max(Parecido($"{d.Marca} {d.Modelo}", $"{e.Marca} {e.Modelo}"), Parecido(d.Modelo, e.Modelo))))
                .OrderByDescending(x => x.p).ToList();
            if (puntuados[0].p >= Similitud.UmbralDuplicado && puntuados[0].p - puntuados[1].p >= 15)
                Automatico(f, puntuados[0].e, "num_serie", 95);
            else
            {
                f.Candidatos = puntuados.Take(5).Select(x => Con(x.e, 100)).ToList();
                Revision(f, "serie_repetida", f.Candidatos[0], seleccionar: false, confianza: 50);
                f.Observaciones.Add($"El cliente tiene {mismos.Count} equipos con la serie {d.NumSerie}: elija cuál es.");
            }
            return f;
        }

        // 3. Código del cliente (tag / código interno).
        var cc = NormalizarSerie(d.CodigoCliente);
        if (cc.Length > 0 && porCodigoCliente.Contains(cc) && porCodigoCliente[cc].Count() == 1)
        {
            var e = porCodigoCliente[cc].First();
            if (ns.Length == 0 || PuntajeSerie(ns, NormalizarSerie(e.NumSerie)) >= UmbralSerieParecida)
                Automatico(f, e, "codigo_cliente", 95);
            else
            {
                Revision(f, "codigo_cliente", Con(e, 70), seleccionar: false, confianza: 60);
                f.Observaciones.Add($"El código del cliente {d.CodigoCliente} corresponde al equipo {e.CodigoTw} (serie {e.NumSerie}), pero el archivo indica la serie {d.NumSerie}.");
                PrepararNuevo(f, d, ns);
            }
            return f;
        }

        // 4. La serie es de un equipo de OTRO cliente: no se puede vincular ni duplicar.
        if (ns.Length > 0 && otrosPorSerie.Contains(ns))
        {
            var o = otrosPorSerie[ns].First();
            Omitir(f, "otro_cliente");
            f.Observaciones.Add($"La serie {d.NumSerie} está registrada como equipo de {o.RazonSocial ?? "otro cliente"} ({o.CodigoTw}, {o.Marca} {o.Modelo}). Coordine su traslado con el área de equipos.");
            return f;
        }

        // 5. Serie parecida (error de tipeo) en el cliente.
        if (ns.Length > 0)
        {
            var parecidos = bd.Equipos
                .Select(e => (e, p: PuntajeSerie(ns, NormalizarSerie(e.NumSerie))))
                .Where(x => x.p >= UmbralSerieParecida)
                .OrderByDescending(x => x.p).ThenByDescending(x => Parecido($"{d.Marca} {d.Modelo}", $"{x.e.Marca} {x.e.Modelo}"))
                .Take(5).ToList();
            if (parecidos.Count > 0)
            {
                f.Candidatos = parecidos.Select(x => Con(x.e, x.p)).ToList();
                Revision(f, "serie_similar", f.Candidatos[0], seleccionar: false, confianza: parecidos[0].p - 20);
                f.Observaciones.Add($"No hay un equipo con la serie {d.NumSerie}; el más parecido es {parecidos[0].e.NumSerie} ({parecidos[0].e.CodigoTw}).");
                PrepararNuevo(f, d, ns);
                return f;
            }
        }

        // 6. Equipo nuevo para el cliente.
        if (ns.Length == 0)
        {
            Revision(f, "sin_serie", null, seleccionar: false, confianza: 0);
            f.Importable = false;
            f.Observaciones.Add("La fila no tiene número de serie (obligatorio para registrar el equipo).");
            return f;
        }
        PrepararNuevo(f, d, ns);
        EvaluarNuevo(f);
        return f;
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

    /// <summary>Estado de una fila cuyo destino es crear el equipo: nuevo si tiene todo, revisión si falta algo.</summary>
    public void EvaluarNuevo(FilaImportacionEquipoDto f)
    {
        var n = f.Nuevo!;
        var faltan = new List<string>();
        if (string.IsNullOrWhiteSpace(n.Marca) || string.IsNullOrWhiteSpace(n.Modelo)) faltan.Add("marca y modelo (o el suministro del catálogo)");
        if (!EsClasificacionValida(n.Clasificacion)) faltan.Add("la clasificación");
        if (n.IdSede is null) faltan.Add("la sede");

        f.Equipo = null;
        f.Accion = "crear";
        if (faltan.Count > 0)
        {
            f.Estado = "revision"; f.Motivo = "faltan_datos"; f.Importable = false; f.Seleccionado = false;
            f.Confianza = 0;
            f.Observaciones.RemoveAll(o => o.StartsWith("Para registrar el equipo indique"));
            f.Observaciones.Add("Para registrar el equipo indique " + string.Join(", ", faltan) + ".");
        }
        else
        {
            f.Estado = "nuevo"; f.Importable = true; f.Seleccionado = true;
            f.Motivo = n.IdSuministro is null ? "sin_catalogo" : "catalogo";
            f.Confianza = Math.Max(f.Confianza, n.IdSuministro is null ? 70 : 90);
            f.Observaciones.RemoveAll(o => o.StartsWith("Para registrar el equipo indique"));
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

    /// <summary>Elegido por la IA entre los candidatos: queda en revisión (el comercial confirma), marcado si la confianza es alta.</summary>
    public void SugerenciaIa(FilaImportacionEquipoDto f, EquipoConciliadoDto e, int confianza, string? motivo)
    {
        Revision(f, "sugerencia_ia", e, seleccionar: confianza >= 85, confianza: confianza);
        f.Origen = "ia";
        if (!string.IsNullOrWhiteSpace(motivo)) f.Observaciones.Add("IA: " + Recortar(motivo, 300));
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
        "nuevo"      => f.Motivo == "catalogo" ? "Nuevo registro en sede (modelo del catálogo)" : "Nuevo registro en sede",
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
            "codigo_cliente"  => "Revisar: código del cliente con otra serie",
            "equipo_inactivo" => "Revisar: equipo inactivo",
            "sin_serie"       => "Falta el N/S",
            "faltan_datos"    => "Faltan datos para registrar",
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
