namespace TW.Intranet.Aplicacion.Dtos;

// ═══════════════════════════════════════════════════════════════════════════
// Propuestas — Importación masiva del listado de equipos desde Excel con IA.
// Flujo: 1) analizar (lee el Excel, la IA reconoce las columnas y concilia cada fila contra
// los equipos del cliente y el catálogo de suministros; no guarda nada), 2) el comercial revisa
// y corrige en la vista previa, 3) confirmar (crea en el inventario del cliente los equipos nuevos
// y devuelve la lista final para agregarla al listado de equipos de la propuesta).
// ═══════════════════════════════════════════════════════════════════════════

/// <summary>Datos del formulario "analizar" (multipart, además del archivo).</summary>
public record AnalizarImportacionEquiposSolicitudDto(
    long                 IdCliente,
    long?                IdSede,
    IReadOnlyList<long>  IdsEquipoEnPropuesta,
    IReadOnlyList<string> SeriesEnPropuesta);

/// <summary>Resultado del análisis: vista previa de la conciliación (no se guardó nada).</summary>
public class AnalisisImportacionEquiposDto
{
    public string  NombreArchivo  { get; init; } = "";
    public string  Hoja           { get; init; } = "";
    /// <summary>N.° de fila (Excel, base 1) de los encabezados. 0 = el archivo no tiene encabezados.</summary>
    public int     FilaEncabezado { get; init; }
    /// <summary>Filas con datos leídas (sin contar encabezados ni filas vacías).</summary>
    public int     TotalFilas     { get; init; }
    /// <summary>true si la IA reconoció las columnas o concilió filas; false = solo reglas.</summary>
    public bool    IaUtilizada    { get; init; }
    /// <summary>Motor usado (ej. gemini-3.5-flash-lite) o "reglas".</summary>
    public string  Motor          { get; init; } = "reglas";
    /// <summary>Aviso cuando la IA no estuvo disponible o falló (el análisis sigue con reglas).</summary>
    public string? AvisoIa        { get; init; }
    public ResumenImportacionEquiposDto Resumen { get; init; } = new();
    public List<ColumnaDetectadaDto>   Columnas { get; init; } = [];
    public List<FilaImportacionEquipoDto> Filas { get; init; } = [];
    /// <summary>Sedes del cliente (para elegir la sede de los equipos nuevos).</summary>
    public List<OpcionImportacionDto>  Sedes          { get; init; } = [];
    /// <summary>Clasificaciones válidas para un equipo nuevo (equipo / instrumento / pesa).</summary>
    public List<OpcionImportacionDto>  Clasificaciones { get; init; } = [];
}

public class ResumenImportacionEquiposDto
{
    public int Automaticos   { get; set; }
    public int Revision      { get; set; }
    public int Nuevos        { get; set; }
    public int Omitidos      { get; set; }
    public int Seleccionados { get; set; }
}

/// <summary>Columna del Excel asignada a un dato: campo = numSerie, codigoTw, codigoCliente, equipo, marca, modelo, capacidad, ubicacion, sede.</summary>
public record ColumnaDetectadaDto(string Campo, string Columna, string? Encabezado);

/// <summary>Opción simple para listas (sedes, clasificaciones). Id numérico o Codigo de texto.</summary>
public record OpcionImportacionDto(long? Id, string? Codigo, string Nombre);

/// <summary>Una fila del Excel con el resultado de la conciliación.</summary>
public class FilaImportacionEquipoDto
{
    /// <summary>N.° de fila en el Excel (base 1).</summary>
    public int     Fila          { get; init; }
    public DatosLeidosEquipoDto Leido { get; init; } = new();

    /// <summary>automatico | revision | nuevo | omitido.</summary>
    public string  Estado        { get; set; } = "revision";
    /// <summary>
    /// Por qué quedó en ese estado: codigo_tw, num_serie, codigo_cliente (automático); serie_similar, sugerencia_ia,
    /// serie_repetida, sin_serie, faltan_datos (revisión); catalogo, sin_catalogo (nuevo); duplicado_archivo,
    /// ya_en_propuesta, otro_cliente (omitido).
    /// </summary>
    public string  Motivo        { get; set; } = "";
    public string  EstadoLabel   { get; set; } = "";
    /// <summary>0 a 100.</summary>
    public int     Confianza     { get; set; }
    /// <summary>reglas | ia.</summary>
    public string  Origen        { get; set; } = "reglas";
    /// <summary>vincular (equipo ya registrado) | crear (equipo nuevo) | ninguna.</summary>
    public string  Accion        { get; set; } = "ninguna";
    /// <summary>Marcado por defecto para importar.</summary>
    public bool    Seleccionado  { get; set; }
    /// <summary>false = no se puede importar tal cual (falta un dato o está omitido).</summary>
    public bool    Importable    { get; set; }
    public List<string> Observaciones { get; init; } = [];

    /// <summary>Equipo del cliente con el que coincide (accion = vincular).</summary>
    public EquipoConciliadoDto? Equipo { get; set; }
    /// <summary>Otros equipos del cliente parecidos (para resolver a mano). Máx. 5.</summary>
    public List<EquipoConciliadoDto> Candidatos { get; set; } = [];
    /// <summary>Datos con que se creará el equipo (accion = crear).</summary>
    public NuevoEquipoImportacionDto? Nuevo { get; set; }
    /// <summary>Suministros del catálogo parecidos (para elegir a mano). Máx. 5.</summary>
    public List<SuministroConciliadoDto> SuministrosCandidatos { get; set; } = [];
}

/// <summary>Datos tal como vienen en el Excel (texto).</summary>
public class DatosLeidosEquipoDto
{
    public string? NumSerie      { get; init; }
    public string? CodigoTw      { get; init; }
    public string? CodigoCliente { get; init; }
    public string? Equipo        { get; init; }
    public string? Marca         { get; init; }
    public string? Modelo        { get; init; }
    public string? Capacidad     { get; init; }
    public string? Ubicacion     { get; init; }
    public string? Sede          { get; init; }
}

public class EquipoConciliadoDto
{
    public long    IdEquipo           { get; init; }
    public string  CodigoTw           { get; init; } = "";
    public string  NumSerie           { get; init; } = "";
    public string? CodigoCliente      { get; init; }
    public string  Clasificacion      { get; init; } = "";
    public string  ClasificacionLabel { get; init; } = "";
    public string  Marca              { get; init; } = "";
    public string  Modelo             { get; init; } = "";
    public long    IdSede             { get; init; }
    public string? SedeNombre         { get; init; }
    public string? Ubicacion          { get; init; }
    public string? AlcanceMaximo      { get; init; }
    /// <summary>activo | inactivo | borrador.</summary>
    public string  Estado             { get; init; } = "activo";
    public string? Tipo               { get; init; }
    public string? Subtipo            { get; init; }
    /// <summary>Parecido con la fila (0 a 100).</summary>
    public int     Puntaje            { get; init; }
}

public class NuevoEquipoImportacionDto
{
    public string  NumSerie           { get; set; } = "";
    public string? Marca              { get; set; }
    public string? Modelo             { get; set; }
    /// <summary>equipo | instrumento | pesa.</summary>
    public string? Clasificacion      { get; set; }
    public long?   IdSuministro       { get; set; }
    public string? SuministroDescripcion { get; set; }
    public long?   IdSede             { get; set; }
    public string? SedeNombre         { get; set; }
    public string? CodigoCliente      { get; set; }
    public string? Ubicacion          { get; set; }
    public string? AlcanceMaximo      { get; set; }
}

public class SuministroConciliadoDto
{
    public long    IdSuministro { get; init; }
    public string  Codigo       { get; init; } = "";
    public string  Descripcion  { get; init; } = "";
    public string? Clase        { get; init; }
    public string? Tipo         { get; init; }
    public string? Subtipo      { get; init; }
    public string? Marca        { get; init; }
    public string? Modelo       { get; init; }
    public int     Puntaje      { get; init; }
}

// ── Confirmar ──────────────────────────────────────────────────────────────

public class ConfirmarImportacionEquiposSolicitudDto
{
    public long IdCliente { get; set; }
    public List<FilaConfirmarImportacionDto> Filas { get; set; } = [];
}

/// <summary>Fila elegida por el comercial. accion: vincular (idEquipo) | crear (datos del equipo nuevo).</summary>
public class FilaConfirmarImportacionDto
{
    public int     Fila          { get; set; }
    public string  Accion        { get; set; } = "";
    public long?   IdEquipo      { get; set; }
    public string? NumSerie      { get; set; }
    public string? Marca         { get; set; }
    public string? Modelo        { get; set; }
    public string? Clasificacion { get; set; }
    public long?   IdSuministro  { get; set; }
    public long?   IdSede        { get; set; }
    public string? CodigoCliente { get; set; }
    public string? Ubicacion     { get; set; }
    public string? AlcanceMaximo { get; set; }
}

public class ResultadoImportacionEquiposDto
{
    public int Vinculados   { get; init; }
    public int Creados      { get; init; }
    /// <summary>Filas "crear" cuyo equipo ya existía en el cliente (misma serie, marca y modelo): se vincularon.</summary>
    public int Reutilizados { get; init; }
    /// <summary>Equipos para agregar al listado de la propuesta, en el orden de las filas.</summary>
    public List<EquipoImportadoDto> Equipos { get; init; } = [];
}

/// <summary>Equipo listo para el listado de la propuesta (mismos datos que PropuestaEquipoDto).</summary>
public class EquipoImportadoDto
{
    public int     Fila               { get; init; }
    public long    IdEquipo           { get; init; }
    public string  CodigoTw           { get; init; } = "";
    public string  NumSerie           { get; init; } = "";
    public string  Marca              { get; init; } = "";
    public string  Modelo             { get; init; } = "";
    public string  Clasificacion      { get; init; } = "";
    public string  ClasificacionLabel { get; init; } = "";
    public string? Tipo               { get; init; }
    public string? Subtipo            { get; init; }
    public long    IdSede             { get; init; }
    public string? SedeNombre         { get; init; }
    public string? CodigoCliente      { get; init; }
    public string? Ubicacion          { get; init; }
    /// <summary>vinculado | creado | reutilizado.</summary>
    public string  Resultado          { get; init; } = "vinculado";
}

// ── Datos de la BD para conciliar ──────────────────────────────────────────

/// <summary>Lo que devuelve SP_ObtenerCandidatosImportacionEquipos.</summary>
public class CandidatosImportacionEquiposDto
{
    public string? RazonSocialCliente { get; init; }
    public List<EquipoConciliadoDto>      Equipos     { get; init; } = [];
    public List<OpcionImportacionDto>     Sedes       { get; init; } = [];
    public List<SuministroConciliadoDto>  Suministros { get; init; } = [];
    public List<EquipoOtroClienteDto>     EnOtrosClientes { get; init; } = [];
    public List<OpcionImportacionDto>     Clasificaciones { get; init; } = [];
}

public record EquipoOtroClienteDto(long IdEquipo, string CodigoTw, string NumSerie, string Marca, string Modelo, string? RazonSocial);
