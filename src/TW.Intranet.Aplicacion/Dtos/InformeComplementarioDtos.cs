namespace TW.Intranet.Aplicacion.Dtos;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Revisión Técnica — Informe Complementario (cambio del 23/11/2026, HU-56 a HU-60).
// El informe que genera el técnico desde la app es inmutable. El Supervisor Técnico, si lo necesita, genera un informe complementario
// (fila de informe_tecnico con id_informe_padre = original) con observaciones, recomendaciones, fotos / videos y la precotización.
// Estados del complementario: borrador (generado, sin guardar) · complementario (guardado).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// <summary>Respuesta de "Generar Informe Complementario". Creado = false si ya existía (se devuelve el mismo).</summary>
public class InformeComplementarioCreadoDto
{
    public long    IdInformeComplementario { get; init; }
    public string? Numero                  { get; init; }
    public string? Estado                  { get; init; }
    public bool    Creado                  { get; init; }
    /// <summary>Fotos, observaciones y recomendaciones precargadas del original.</summary>
    public int     Fotos                   { get; init; }
    public int     Observaciones           { get; init; }
    public int     Recomendaciones         { get; init; }
}

/// <summary>Cabecera del complementario: sus datos, los del informe original (solo lectura), la precotización y las acciones.</summary>
public class CabeceraInformeComplementarioDto
{
    public long      IdInformeComplementario     { get; init; }
    public string?   NumeroComplementario        { get; init; }
    /// <summary>borrador · complementario.</summary>
    public string?   Estado                      { get; init; }
    public string?   EstadoLabel                 { get; init; }
    public string?   ObservacionesGenerales      { get; init; }
    public long?     IdSupervisor                { get; init; }
    public string?   Supervisor                  { get; init; }
    public DateTime? FechaCreacion               { get; init; }
    public DateTime? FechaActualizacion          { get; init; }
    /// <summary>Cuándo se cerró (al revisar el original).</summary>
    public DateTime? FechaCierre                 { get; init; }

    // Informe original (solo lectura)
    public long      IdInformeOriginal           { get; init; }
    public string?   NumeroInformeOriginal       { get; init; }
    /// <summary>N° del informe que asignó la app al generarlo (NNNN-AAAA).</summary>
    public string?   NumeroInformeTecnico        { get; init; }
    public DateTime? InformeGeneradoEn           { get; init; }
    public string?   EstadoOriginal              { get; init; }
    public string?   GrupoEstadoOriginal         { get; init; }
    public string?   PdfInformeOriginalUrl       { get; init; }
    public string?   PdfInformeComplementarioUrl { get; init; }
    public long?     IdOs                        { get; init; }
    public string?   NumeroOs                    { get; init; }
    public string?   TipoOs                      { get; init; }
    public long?     IdCliente                   { get; init; }
    public string?   RazonSocial                 { get; init; }
    public string?   Ruc                         { get; init; }
    public long?     IdSede                      { get; init; }
    public string?   Sede                        { get; init; }
    public long?     IdEquipo                    { get; init; }
    public string?   Equipo                      { get; init; }
    public string?   CodigoTw                    { get; init; }
    public string?   NumeroSerie                 { get; init; }
    public string?   Marca                       { get; init; }
    public string?   Modelo                      { get; init; }
    public string?   TipoEquipo                  { get; init; }
    public int?      IdTipoServicio              { get; init; }
    public string?   TipoServicio                { get; init; }
    public long?     IdTecnico                   { get; init; }
    public string?   Tecnico                     { get; init; }
    public DateTime? FechaEjecucion              { get; init; }
    public string?   HoraInicio                  { get; init; }
    public string?   HoraFin                     { get; init; }
    public int?      DuracionMin                 { get; init; }
    public long?     IdPropuesta                 { get; init; }
    public string?   NumeroPropuesta             { get; init; }
    public int?      VersionPropuesta            { get; init; }
    public long?     IdRequerimiento             { get; init; }
    public string?   NumeroRq                    { get; init; }
    public string?   Contacto                    { get; init; }
    public string?   Diagnostico                 { get; init; }
    public string?   Normativa                   { get; init; }
    public string?   PatronEnsayo                { get; init; }
    public decimal?  ToleranciaExcentricidad     { get; init; }
    /// <summary>dentro · fuera (de tolerancia). Lo calcula el servidor al guardar los ensayos del técnico.</summary>
    public string?   ResultadoGlobal             { get; init; }
    public decimal?  ErrorMaximo                 { get; init; }
    public string?   ErrorMaximoDetalle          { get; init; }
    public decimal?  Incertidumbre               { get; init; }
    public decimal?  FactorK                     { get; init; }
    public string?   DecisionTecnica             { get; init; }

    // Contadores del complementario
    public int       NFotos                      { get; init; }
    /// <summary>Fotos y videos que subió el supervisor (no copiados del original).</summary>
    public int       NFotosAgregadas             { get; init; }
    public int       NObservaciones              { get; init; }
    public int       NRecomendaciones            { get; init; }

    // Precotización
    public long?     IdPrecotizacion             { get; init; }
    public string?   NumeroPrecot                { get; init; }
    public string?   EstadoPrecot                { get; init; }
    public DateTime? FechaPrecot                 { get; init; }
    public string?   NotaPrecotizacion           { get; init; }
    public int       NItemsPrecot                { get; init; }
    public long?     IdPropuestaDerivada         { get; init; }
    public string?   NumeroPropuestaDerivada     { get; init; }
    public int?      VersionPropuestaDerivada    { get; init; }
    public string?   EstadoPropuestaDerivada     { get; init; }

    // Acciones
    /// <summary>Se edita mientras el informe original no esté revisado (con rt_editar).</summary>
    public bool      PuedeEditar                 { get; init; }
    /// <summary>false si la precotización ya se convirtió en propuesta.</summary>
    public bool      PuedeEditarPrecotizacion    { get; init; }
    /// <summary>Solo un complementario en borrador (nunca guardado).</summary>
    public bool      PuedeDescartar              { get; init; }
}

public class ObservacionComplementarioDto : ObservacionInformeDto
{
    /// <summary>true = precargada del informe del técnico.</summary>
    public bool    Copiada             { get; init; }
    /// <summary>Clasificación y componente de la falla (catálogos CLASIFICACION_FALLA / COMPONENTE_FALLA); solo las que vienen de la app.</summary>
    public string? Clasificacion       { get; init; }
    public string? ClasificacionNombre { get; init; }
    public string? Componente          { get; init; }
    public string? ComponenteNombre    { get; init; }
}

/// <summary>Quién atendió al técnico en planta (lo que cargó en "Datos" del informe; si no, el contacto de la OS).</summary>
public record ResponsableClienteDto(string? Nombre, string? Cargo, string? Telefono);

/// <summary>Diagnóstico final que marcó el técnico en la app (severidadGeneral: baja · media · alta · critica; estadoEquipo: operativo · con_observaciones · inoperativo).</summary>
public record DiagnosticoFinalDto(string? SeveridadGeneral, string? EstadoEquipo, bool RevisionJefatura, bool Precotizacion, bool SegundaVisita, bool AplicaGarantia);

/// <summary>"Detalle Serv." del informe en la app: tipo de equipo, celdas (mV, hasta 12), pruebas por sumatoria / comparación y anillos de fijación.</summary>
public record DetalleServicioInformeDto(string? TipoEquipo, IReadOnlyList<decimal> Celdas, decimal? SumatoriaHasta, decimal? ComparacionHasta, bool? AnillosFijacion);

/// <summary>Resultado global de los ensayos del técnico (dentro · fuera), calculado por el servidor.</summary>
public record ResultadoOriginalDto(string? ResultadoGlobal, decimal? ErrorMaximo, string? DecisionTecnica, string? ErrorCritico);

/// <summary>Precotización del complementario: nota para Comercial e ítems.</summary>
public record PrecotizacionComplementarioDetalleDto(long? IdPrecotizacion, string? Numero, string? Estado, string? Nota, List<ItemPrecotizacionDto> Items);

public record OpcionFichaComplementarioDto(string Codigo, string Nombre, string? Padre = null);

/// <summary>Catálogos de la ficha: tipos de equipo, clasificación y componente de falla (padre = clasificación), niveles y prioridades.</summary>
public record OpcionesInformeComplementarioDto(
    List<OpcionFichaComplementarioDto> TiposEquipo,
    List<OpcionFichaComplementarioDto> ClasificacionesFalla,
    List<OpcionFichaComplementarioDto> ComponentesFalla,
    List<OpcionFichaComplementarioDto> SeveridadesObservacion,
    List<OpcionFichaComplementarioDto> PrioridadesRecomendacion,
    List<OpcionFichaComplementarioDto> PrioridadesItemPrecotizacion);

public class FotoInformeComplementarioDto
{
    public long      IdEvidencia       { get; init; }
    public string?   UrlArchivo        { get; init; }
    public string?   Descripcion       { get; init; }
    /// <summary>Solo en las fotos copiadas del técnico: etapa de la app (placa, inicial, prueba…) con su nombre y descripción como en el móvil.</summary>
    public string?   Etapa             { get; init; }
    public string?   EtapaNombre       { get; init; }
    public string?   EtapaDescripcion  { get; init; }
    /// <summary>ANTES · DURANTE · DESPUES…</summary>
    public string?   Momento           { get; init; }
    public string?   MomentoLabel      { get; init; }
    public DateTime? FechaCaptura      { get; init; }
    public decimal?  Latitud           { get; init; }
    public decimal?  Longitud          { get; init; }
    public bool      Georreferenciada  { get; init; }
    public string?   ValidacionIa      { get; init; }
    public bool      EsVideo           { get; init; }
    public bool      Forzada           { get; init; }
    public string?   MotivoForzado     { get; init; }
    public string?   MotivoRechazoIa   { get; init; }
    /// <summary>true = copiada del informe del técnico; false = la subió el supervisor.</summary>
    public bool      Copiada           { get; init; }
    /// <summary>tecnico (copiada del informe del técnico) · supervisor (subida al complementario).</summary>
    public string?   Origen            { get; init; }
    public string?   SubidaPor         { get; init; }
    public long?     IdObservacion     { get; init; }
    public string?   CodigoObservacion { get; init; }
}

/// <summary>
/// Ficha del complementario (5 pestañas). Cabecera = datos del servicio y del complementario; ResponsableCliente, DiagnosticoFinal,
/// ComentarioPruebas, DetalleServicio, Procedimiento, Ensayos y ResultadoOriginal = lo del técnico (solo lectura); Fotos, Observaciones,
/// Recomendaciones y PrecotizacionDetalle = lo editable. Precotizacion (solo los ítems) se mantiene por compatibilidad.
/// </summary>
public record DetalleInformeComplementarioDto(
    CabeceraInformeComplementarioDto      Cabecera,
    List<PasoInformeDto>                  Procedimiento,
    List<EnsayoInformeDto>                Ensayos,
    List<ObservacionComplementarioDto>    Observaciones,
    List<RecomendacionInformeDto>         Recomendaciones,
    List<FotoInformeComplementarioDto>    Fotos,
    List<ItemPrecotizacionDto>            Precotizacion,
    ResponsableClienteDto?                ResponsableCliente      = null,
    DiagnosticoFinalDto?                  DiagnosticoFinal        = null,
    string?                               ComentarioPruebas       = null,
    DetalleServicioInformeDto?            DetalleServicio         = null,
    ResultadoOriginalDto?                 ResultadoOriginal       = null,
    PrecotizacionComplementarioDetalleDto? PrecotizacionDetalle   = null,
    OpcionesInformeComplementarioDto?     Opciones                = null);

/// <summary>
/// "Guardar" del complementario. Cada sección es opcional (null = no cambia). Una lista enviada es la lista COMPLETA de esa sección
/// (con Id = se actualiza, sin Id = se agrega, las que faltan se eliminan). ObservacionesGenerales: null = no cambia, "" = se borra.
/// Precotizacion con Items vacío = se quita (si aún no se convirtió en propuesta). Las fotos van por su propio endpoint.
/// </summary>
public class GuardarInformeComplementarioDto
{
    public string?                            ObservacionesGenerales { get; set; }
    public List<ObservacionGuardarDto>?       Observaciones          { get; set; }
    public List<RecomendacionGuardarDto>?     Recomendaciones        { get; set; }
    public PrecotizacionComplementarioDto?    Precotizacion          { get; set; }
}

public class PrecotizacionComplementarioDto
{
    /// <summary>Observaciones del supervisor para Comercial (se copian como nota en la nueva propuesta).</summary>
    public string?                                  Nota  { get; set; }
    public List<ItemPrecotizacionComplementarioDto> Items { get; set; } = [];
}

public class ItemPrecotizacionComplementarioDto : ItemPrecotizacionGuardarDto
{
    /// <summary>Para vincular una observación NUEVA de este mismo guardado: su posición (desde 0) en Observaciones.</summary>
    public int? IndiceObservacion { get; set; }
}

public class InformeComplementarioGuardadoDto
{
    public long    IdInformeComplementario { get; init; }
    public string? Estado                  { get; init; }
    public int     CambiosRegistrados      { get; init; }
    public long?   IdPrecotizacion         { get; init; }
    public string? NumeroPrecotizacion     { get; init; }
    public int     ItemsPrecotizacion      { get; init; }
    public bool    PrecotizacionNueva      { get; init; }
}

public class FotoComplementarioSubidaDto
{
    public long IdEvidencia { get; init; }
    public bool EsVideo     { get; init; }
    public int  TotalFotos  { get; init; }
}

/// <summary>Archivo que ya nadie usa tras quitar una foto o descartar el complementario (el back lo borra del almacenamiento).</summary>
public record ArchivoBorrableDto(string Ruta, string? RutaCuadro);

/// <summary>Lo que necesita el PDF del complementario: el detalle y las imágenes (id de evidencia → JPEG/PNG).</summary>
public record DatosInformeComplementarioPdf(
    DetalleInformeComplementarioDto     Detalle,
    IReadOnlyDictionary<long, byte[]>   Imagenes,
    DateTime                            GeneradoEn);
