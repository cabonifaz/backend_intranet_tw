namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-90 Centro de Notificaciones del Usuario (Sprint 5, Módulo 16) ─────────────────────────────────────────────

/// <summary>Quien envió la notificación. IdUsuario null = "Sistema TotalWeight".</summary>
public record RemitenteNotificacionDto(long? IdUsuario, string Nombre, string Iniciales);

/// <summary>
/// Link profundo ("Ir al elemento origen"). Accion es un nombre estable que el front traduce a su ruta/modal:
/// os.detalle · programacion.os · seguimiento.servicio (Tab "mapa" en alertas operativas) · propuesta.detalle · vb.detalle ·
/// seguimiento.propuesta · propuesta.precotizacion · oc.detalle · expediente.detalle · programacion.detalle · informe.detalle ·
/// equipo.detalle · cliente.detalle. Null en la fila = la notificación no tiene elemento asociado.
/// </summary>
public record DestinoNotificacionDto(string Accion, string EntidadTipo, long IdEntidad, string? Tab);

/// <summary>Fila de la campana y de la lista izquierda de la bandeja.</summary>
public record FilaNotificacionDto(
    long                     IdNotificacion,
    string                   Titulo,
    string                   Resumen,
    string                   Modulo,
    string                   ModuloLabel,
    string                   Tipo,
    string                   TipoLabel,
    string                   Prioridad,
    bool                     EsAlertaOperativa,
    bool                     Leida,
    bool                     Archivada,
    RemitenteNotificacionDto Remitente,
    DateTime                 FechaCreacion,
    string                   Grupo,          // hoy · ayer · semana · antiguas
    DestinoNotificacionDto?  Destino);

/// <summary>Campana: badge + popover con las 5 últimas no leídas.</summary>
public record ResumenNotificacionesDto(int NoLeidas, List<FilaNotificacionDto> Ultimas);

/// <summary>Query de GET api/notificaciones/bandeja.</summary>
public class FiltrosBandejaNotificacionesDto
{
    /// <summary>activas (defecto, no archivadas) · no_leida · leida · archivada · todas.</summary>
    public string?   Estado     { get; set; }
    /// <summary>Módulos separados por coma (multi-select). Vacío = todos.</summary>
    public string?   Modulos    { get; set; }
    /// <summary>Tipos separados por coma. Vacío = todos.</summary>
    public string?   Tipos      { get; set; }
    /// <summary>hoy · semana · mes · custom (usa FechaDesde/FechaHasta). Vacío = sin límite.</summary>
    public string?   Rango      { get; set; }
    public DateTime? FechaDesde { get; set; }
    public DateTime? FechaHasta { get; set; }
    /// <summary>Vacío = todos · 0 = Sistema · id de usuario.</summary>
    public long?     Remitente  { get; set; }
    /// <summary>N° de documento, cliente, usuario o palabra clave.</summary>
    public string?   Busqueda   { get; set; }
    public int       Pagina     { get; set; } = 1;
    public int       PorPagina  { get; set; } = 30;
}

public record BandejaNotificacionesDto(int Total, int NoLeidas, int Pagina, int PorPagina, List<FilaNotificacionDto> Items);

/// <summary>Panel de detalle derecho. Al pedirlo, la notificación queda leída.</summary>
public record DetalleNotificacionDto(
    FilaNotificacionDto Notificacion,
    string              Mensaje,
    DateTime?           FechaLectura,
    DateTime?           FechaArchivado,
    bool                PuedeArchivar,  // leída y aún no archivada
    int                 NoLeidas);

/// <summary>Body de POST api/notificaciones/marcar-leidas: { "ids": [..] } o { "todas": true }.</summary>
public class MarcarNotificacionesLeidasDto
{
    public List<long>? Ids   { get; set; }
    public bool        Todas { get; set; }
}

public record ResultadoMarcadoNotificacionesDto(int Marcadas, int NoLeidas);

public record ResultadoArchivadoNotificacionDto(long IdNotificacion, int NoLeidas);

public record OpcionFiltroNotificacionDto(string Valor, string Etiqueta, int Total, int NoLeidas);

/// <summary>IdUsuario 0 = Sistema.</summary>
public record RemitenteFiltroNotificacionDto(long IdUsuario, string Nombre, int Total);

public record FiltrosNotificacionesDto(
    List<OpcionFiltroNotificacionDto>    Modulos,
    List<OpcionFiltroNotificacionDto>    Tipos,
    List<OpcionFiltroNotificacionDto>    Estados,
    List<OpcionFiltroNotificacionDto>    Rangos,
    List<RemitenteFiltroNotificacionDto> Remitentes);

/// <summary>Conteos crudos que devuelve el SP de filtros (el caso de uso los completa con el catálogo).</summary>
public record ConteoFiltroNotificacionDto(string Valor, int Total, int NoLeidas);

public record ConteosFiltrosNotificacionesDto(
    List<ConteoFiltroNotificacionDto>    Modulos,
    List<ConteoFiltroNotificacionDto>    Tipos,
    List<RemitenteFiltroNotificacionDto> Remitentes);

/// <summary>Resultado de una pasada del worker de alertas operativas del Módulo 11.</summary>
public record ResultadoAlertasOperativasDto(int Generadas, int Alertas);

/// <summary>Catálogo fijo del Centro de Notificaciones (valores que deduce la migración 102 y sus etiquetas).</summary>
public static class CatalogoNotificaciones
{
    public static readonly IReadOnlyList<(string Valor, string Etiqueta)> Modulos =
    [
        ("propuestas",       "Propuestas"),
        ("visto_bueno",      "Visto Bueno"),
        ("seguimiento",      "Seguimiento Comercial"),
        ("ordenes_compra",   "Órdenes de Compra"),
        ("ordenes_servicio", "Órdenes de Servicio"),
        ("expedientes",      "Expedientes Digitales"),
        ("programacion",     "Programación Operativa"),
        ("control_campo",    "Control de Campo"),
        ("ssoma",            "SSOMA"),
        ("revision_tecnica", "Revisión Técnica"),
        ("maestros",         "Maestros"),
        ("sistema",          "Sistema"),
    ];

    public static readonly IReadOnlyList<(string Valor, string Etiqueta)> Tipos =
    [
        ("alerta_operativa",     "Alerta operativa"),
        ("aprobacion_pendiente", "Aprobación pendiente"),
        ("recordatorio",         "Recordatorio"),
        ("asignacion",           "Asignación"),
        ("cambio_estado",        "Cambio de estado"),
        ("ssoma",                "SSOMA"),
        ("informativo",          "Informativo"),
    ];

    public static readonly IReadOnlyList<(string Valor, string Etiqueta)> Estados =
    [
        ("activas",   "Activas"),
        ("no_leida",  "No leídas"),
        ("leida",     "Leídas"),
        ("archivada", "Archivadas"),
        ("todas",     "Todas"),
    ];

    public static readonly IReadOnlyList<(string Valor, string Etiqueta)> Rangos =
    [
        ("hoy",    "Hoy"),
        ("semana", "Esta semana"),
        ("mes",    "Este mes"),
        ("custom", "Personalizado"),
    ];

    public static string EtiquetaModulo(string? valor) => Buscar(Modulos, valor);
    public static string EtiquetaTipo(string? valor)   => Buscar(Tipos, valor);

    private static string Buscar(IReadOnlyList<(string Valor, string Etiqueta)> lista, string? valor)
    {
        foreach (var (v, e) in lista)
            if (string.Equals(v, valor, StringComparison.OrdinalIgnoreCase)) return e;
        return valor ?? "";
    }
}
