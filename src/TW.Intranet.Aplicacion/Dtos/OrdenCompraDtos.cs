namespace TW.Intranet.Aplicacion.Dtos;

// ═════════════════════════════════════════════════════════════════════════════
// Órdenes de Compra — Sprint 4 (refinamiento HU-22 a HU-28)
//   Estado de la OC (consolidado de sus vinculaciones con propuestas):
//     autogenerada (OC-AUTO sin PDF) · validada · validada_parcial · observada (diferencias aceptadas por TW)
//     · pendiente_reemplazo (corrección solicitada al cliente) · anulada
//   EstadoVisual: igual al estado (se mantiene por compatibilidad).
//   ReemplazadaPor: OC del cliente que reemplazó a esta (autogenerada o pendiente_reemplazo). Las reemplazadas
//     se ocultan de la bandeja salvo con IncluirReemplazadas.
//   Estado de cada vinculación OC ↔ propuesta: pendiente · validada · observada
//     (TipoObservacion: informativa · correccion_cliente · nueva_version)
//   Resultado de la validación (IA + reglas): ok · advertencia · critico
//   Decisión del comercial al guardar la ficha → estado de la OC:
//     validar → validada (validada_parcial si hay varias propuestas y alguna no quedó validada)
//     observar ("Guardar con observaciones") → observada · correccion_cliente → pendiente_reemplazo
//     nueva_version → observada hasta validar contra la versión nueva
// ═════════════════════════════════════════════════════════════════════════════

// ── Datos de la ficha (los extrae la IA del PDF; el comercial puede corregirlos) ──

public class ConceptoOrdenCompraDto
{
    public string   Descripcion    { get; set; } = "";
    public decimal? Cantidad       { get; set; }
    public decimal? PrecioUnitario { get; set; }
    public decimal? Subtotal       { get; set; }
}

/// <summary>Dato extraído por la IA que el comercial corrigió a mano ("corregir manualmente" → ✋ en el timeline).</summary>
public class CampoCorregidoDto
{
    public string  Campo      { get; set; } = "";
    public string? ValorIa    { get; set; }
    public string? ValorNuevo { get; set; }
}

/// <summary>Datos de la orden de compra. Se envían como JSON (campo "solicitud" en los multipart).</summary>
public class DatosOrdenCompraDto
{
    public string?   NumeroOc        { get; set; }
    public DateTime? FechaEmision    { get; set; }
    /// <summary>Fecha en que llegó la OC (siempre editable, no la lee la IA).</summary>
    public DateTime? FechaRecepcion  { get; set; }
    public int?      IdMoneda        { get; set; }
    public decimal?  MontoTotal      { get; set; }
    /// <summary>Num1 del catálogo CONDICION_PAGO (39).</summary>
    public int?      IdCondicionPago { get; set; }
    /// <summary>Forma de pago tal como la dice la OC (texto libre).</summary>
    public string?   FormaPago       { get; set; }
    public bool?     IgvIncluido     { get; set; }
    public decimal?  IgvPct          { get; set; }
    public decimal?  Descuento       { get; set; }
    /// <summary>RUC y razón social del cliente según la OC.</summary>
    public string?   Ruc             { get; set; }
    public string?   RazonSocial     { get; set; }
    /// <summary>N° de propuesta que menciona la OC.</summary>
    public string?   NumeroPropuesta { get; set; }
    public DateTime? VigenciaHasta   { get; set; }
    public string?   Referencia      { get; set; }
    public string?   Observaciones   { get; set; }
    /// <summary>"¿La factura tendrá lo mismo que la OC?" (marcado por defecto).</summary>
    public bool      FacturaIgualOc  { get; set; } = true;
    public List<ConceptoOrdenCompraDto> Conceptos { get; set; } = [];
    /// <summary>Valores que leyó la IA (campo → valor). Los campos presentes se muestran bloqueados con el ícono IA.</summary>
    public Dictionary<string, string?>? CamposIa { get; set; }
    /// <summary>Campos que el comercial corrigió a mano (valor original de la IA y valor nuevo).</summary>
    public List<CampoCorregidoDto> CamposManuales { get; set; } = [];
}

/// <summary>Propuesta vinculada y monto de la OC que se le asigna (reparto del monto).</summary>
public class VinculacionOrdenCompraDto
{
    public long    IdPropuesta   { get; set; }
    public decimal MontoAsignado { get; set; }
}

// ── Evaluación de la IA (la arma el back con Gemini; no la envía la pantalla) ──

public class ConceptoEvaluadoDto
{
    public string   Descripcion    { get; set; } = "";
    public decimal? MontoOc        { get; set; }
    public decimal? MontoPropuesta { get; set; }
    /// <summary>coincide · falta_en_oc · adicional_en_oc · monto_distinto</summary>
    public string   Estado         { get; set; } = "coincide";
}

public class InsightIaDto
{
    public string? Campo       { get; set; }
    public string  Titulo      { get; set; } = "";
    public string  Explicacion { get; set; } = "";
    public string? Accion      { get; set; }
    public bool    Recomendado { get; set; }
}

public class EvaluacionIaPropuestaDto
{
    public long    IdPropuesta { get; set; }
    public List<ConceptoEvaluadoDto> Conceptos { get; set; } = [];
    public string? Dictamen   { get; set; }
    public List<InsightIaDto> Insights { get; set; } = [];
    public decimal? Confianza { get; set; }
    public string? Motor      { get; set; }
}

// ── Solicitudes ──

/// <summary>POST /api/crm/ordenes-compra/comparar — validación en vivo de la ficha (no guarda).</summary>
public class CompararOrdenCompraSolicitudDto
{
    /// <summary>OC que se edita (null al registrar).</summary>
    public long?   IdOc          { get; set; }
    /// <summary>Propuesta de origen (al registrar).</summary>
    public long?   IdPropuesta   { get; set; }
    /// <summary>OC que se reemplaza al registrar (autogenerada o pendiente_reemplazo): no cuenta en el saldo de la propuesta.</summary>
    public long?   IdOcReemplaza { get; set; }
    public DatosOrdenCompraDto Datos { get; set; } = new();
    public List<VinculacionOrdenCompraDto> Vinculaciones { get; set; } = [];
    /// <summary>Opcional: valida que la decisión se pueda tomar.</summary>
    public string? Decision      { get; set; }
}

/// <summary>Campo "solicitud" (JSON) del POST multipart de registro.</summary>
public class RegistrarOrdenCompraSolicitudDto
{
    public long?   IdOcReemplaza { get; set; }
    public DatosOrdenCompraDto Datos { get; set; } = new();
    public List<VinculacionOrdenCompraDto> Vinculaciones { get; set; } = [];
    public string? Decision      { get; set; }
}

/// <summary>Campo "solicitud" (JSON) del PUT multipart de edición. El PDF es opcional.</summary>
public class EditarOrdenCompraSolicitudDto
{
    public DatosOrdenCompraDto Datos { get; set; } = new();
    public List<VinculacionOrdenCompraDto> Vinculaciones { get; set; } = [];
    public string? Decision  { get; set; }
    /// <summary>Si llega un PDF: reemplazo | oc_corregida.</summary>
    public string? TipoPdf   { get; set; }
    public string? MotivoPdf { get; set; }
}

public class RevalidarOrdenCompraSolicitudDto
{
    /// <summary>null = todas las propuestas vinculadas.</summary>
    public long? IdPropuesta { get; set; }
}

public class AnularOrdenCompraSolicitudDto
{
    public int?    IdMotivo        { get; set; }
    public string? Justificacion   { get; set; }
    public bool    ConfirmaImpacto { get; set; }
}

public class FiltrosBandejaOrdenesCompraDto
{
    /// <summary>todas (defecto), autogenerada, validada, validada_parcial, observada, pendiente_reemplazo, anulada, sin_asignar</summary>
    public string?   Estado        { get; set; }
    /// <summary>true = incluye las OC ya reemplazadas por la OC del cliente (auditoría).</summary>
    public bool      IncluirReemplazadas { get; set; }
    public long?     IdCliente     { get; set; }
    public long?     IdResponsable { get; set; }
    public long?     IdPropuesta   { get; set; }
    public DateTime? FechaDesde    { get; set; }
    public DateTime? FechaHasta    { get; set; }
    public string?   Busqueda      { get; set; }
    public int       Pagina        { get; set; } = 1;
    public int       PorPagina     { get; set; } = 10;
}

// ── Catálogos y propuestas ──

public record MonedaOrdenCompraDto(int Id, string Nombre, string? Simbolo, string? Codigo);
public record CondicionPagoDto(int Id, string Nombre, string? Codigo);

/// <summary>Propuesta aceptada con saldo por cubrir ("+ Nueva OC" y "Agregar propuesta vinculada").</summary>
public record PropuestaDisponibleOcDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    long?     IdCliente,
    string?   RazonSocial,
    string?   Ruc,
    long?     IdRequerimiento,
    string?   NumeroRq,
    long?     IdContacto,
    string?   Contacto,
    decimal   Total,
    decimal   Saldo,
    int       IdMoneda,
    string?   Moneda,
    string?   MonedaSimbolo,
    DateTime? FechaAceptacion,
    string?   Responsable,
    string?   TipoServicio,
    bool      TieneOc);

/// <summary>Propuesta de origen de la ficha de registro.</summary>
public record PropuestaOrigenOcDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    long      IdCliente,
    string    RazonSocial,
    string?   Ruc,
    long?     IdRequerimiento,
    string?   NumeroRq,
    long?     IdContacto,
    string?   Contacto,
    string?   CargoContacto,
    decimal   Total,
    decimal   Saldo,
    int       IdMoneda,
    string?   Moneda,
    string?   MonedaSimbolo,
    int?      IdCondicionPago,
    string?   CondicionPago,
    bool      AplicaIgv,
    decimal?  IgvPct,
    DateTime? FechaExpiracion,
    DateTime? FechaAceptacion,
    long?     IdResponsable,
    string?   Responsable,
    string?   TipoServicio,
    int       Items,
    DateTime? FechaServidor);

/// <summary>OC que se reemplaza al registrar: autogenerada o pendiente_reemplazo.</summary>
public record OcAReemplazarDto(long IdOc, string NumeroOc, decimal MontoTotal, DateTime? FechaRegistro, bool EsAutogenerada, string Estado);

/// <summary>GET /api/crm/propuestas/{id}/orden-compra/preparar — ficha de registro.</summary>
public record PreparacionOrdenCompraDto(
    PropuestaOrigenOcDto            Propuesta,
    OcAReemplazarDto?               OcAReemplazar,
    List<PropuestaDisponibleOcDto>  OtrasPropuestas,
    List<MonedaOrdenCompraDto>      Monedas,
    List<CondicionPagoDto>          CondicionesPago,
    bool                            ExtraccionIaDisponible);

/// <summary>Propuesta vinculada en la ficha de edición.</summary>
public record VinculacionEdicionOcDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    decimal   Total,
    decimal   Saldo,
    int       IdMoneda,
    decimal   MontoAsignado,
    string    EstadoValidacion,
    string?   TipoObservacion,
    string?   ResultadoIa,
    long?     IdContacto,
    string?   Contacto,
    long?     IdRequerimiento,
    string?   NumeroRq,
    long?     IdPropuestaNuevaVersion,
    string?   NumeroNuevaVersion,
    int?      VersionNuevaVersion,
    string?   EstadoNuevaVersion,
    bool      NuevaVersionAceptada);

/// <summary>Datos de la OC en la ficha de edición.</summary>
public record OrdenCompraEdicionDto(
    long      IdOc,
    string    NumeroOc,
    string    Estado,
    long      IdCliente,
    string    RazonSocial,
    string?   Ruc,
    long?     IdPropuesta,
    DatosOrdenCompraDto Datos,
    string?   NombreArchivoPdf,
    long?     TamanoPdfBytes,
    bool      TienePdf,
    string?   UrlPdf,
    bool      PendienteCorreccion,
    DateTime? FechaRegistro);

/// <summary>GET /api/crm/ordenes-compra/{id}/edicion — ficha en modo edición.</summary>
public record PreparacionEdicionOrdenCompraDto(
    OrdenCompraEdicionDto           Oc,
    List<VinculacionEdicionOcDto>   Vinculaciones,
    List<PropuestaDisponibleOcDto>  OtrasPropuestas,
    List<MonedaOrdenCompraDto>      Monedas,
    List<CondicionPagoDto>          CondicionesPago,
    bool                            ExtraccionIaDisponible);

// ── Extracción con IA ──

/// <summary>POST /api/crm/ordenes-compra/extraer — datos leídos del PDF por la IA (para precargar la ficha).</summary>
public record ExtraccionOrdenCompraDto(
    DatosOrdenCompraDto Datos,
    string?  MonedaLeida,
    decimal? Confianza,
    string   Motor,
    List<string> Advertencias);

// ── Comparación / validación ──

public record ResumenComparacionOcDto(
    string Resultado,
    string Sugerencia,
    int    Criticas,
    int    Advertencias,
    bool   PuedeValidar,
    bool   PuedeObservar,
    bool   PuedeSolicitarCorreccion,
    bool   PuedeNuevaVersion);

public record ComparacionPropuestaOcDto(
    int     Orden,
    long    IdPropuesta,
    string  Numero,
    decimal MontoAsignado,
    string  Resultado,
    int     Coincidencias,
    int     Advertencias,
    int     Criticas,
    int     TotalCampos,
    string  Sugerencia);

/// <summary>Fila de la comparación campo por campo. Severidad: ok · advertencia · critico · sin_dato.</summary>
public record CampoComparadoOcDto(
    long    IdPropuesta,
    int     Orden,
    string  Campo,
    string  Etiqueta,
    string? ValorOc,
    string? ValorPropuesta,
    string  Severidad,
    string? Mensaje,
    string? Accion);

public record ComparacionOrdenCompraDto(
    ResumenComparacionOcDto          Resumen,
    List<ComparacionPropuestaOcDto>  Propuestas,
    List<CampoComparadoOcDto>        Campos,
    List<EvaluacionIaPropuestaDto>   EvaluacionesIa);

// ── Resultado de registrar / editar / reemplazar PDF ──

public record OrdenCompraGuardadaDto(
    long    IdOc,
    string  NumeroOc,
    string  Estado,
    decimal MontoTotal,
    long?   IdOcReemplazada,
    string? NumeroOcReemplazada,
    int     Notificados);

public record VinculacionGuardadaOcDto(
    long    IdPropuesta,
    string  Numero,
    int     Version,
    decimal MontoAsignado,
    string  EstadoValidacion,
    string? TipoObservacion,
    string? ResultadoIa,
    long?   IdPropuestaNuevaVersion,
    string? Sugerencia,
    int?    Coincidencias,
    int?    Advertencias,
    int?    Criticas);

/// <summary>Versión nueva generada para una propuesta observada ("Generar nueva versión de propuesta").</summary>
public record NuevaVersionGeneradaOcDto(long IdPropuesta, long? IdPropuestaNueva, string? Numero, int? Version, string? Error);

public record ResultadoGuardarOrdenCompraDto(
    OrdenCompraGuardadaDto          Oc,
    List<VinculacionGuardadaOcDto>  Vinculaciones,
    List<NuevaVersionGeneradaOcDto> NuevasVersiones,
    string?                         AvisoIa);

public record OcAutogeneradaDto(long IdOc, string NumeroOc, string Estado, decimal MontoTotal, int IdMoneda);

public record RevalidacionOrdenCompraDto(
    long     IdValidacion,
    long     IdPropuesta,
    string   Numero,
    int      Corrida,
    string   Resultado,
    int      Coincidencias,
    int      Advertencias,
    int      Criticas,
    int      TotalCampos,
    string?  Sugerencia,
    DateTime? FechaValidacion);

// ── Bandeja ──

public record TarjetasOrdenesCompraDto(
    int Total,
    int RegistradasMes,
    int Validadas,
    int ValidadasParcial,
    int Observadas,
    int ParcialUObservadas,
    int AutogeneradasPendientes,
    int PendientesReemplazo,
    int SinAsignar,
    int Anuladas);

public record MontoMonedaDto(int IdMoneda, string? Moneda, string? MonedaSimbolo, decimal Monto);

public record ItemBandejaOrdenCompraDto(
    long      IdOc,
    string    NumeroOc,
    bool      EsAutogenerada,
    long?     ReemplazadaPor,
    string?   NumeroOcReemplazo,
    string?   FechaOc,
    string?   FechaRecepcion,
    DateTime? FechaRegistro,
    long      IdCliente,
    string    RazonSocial,
    string?   Ruc,
    long?     IdRequerimiento,
    string?   NumeroRq,
    long?     IdPropuesta,
    string?   NumeroPropuesta,
    int?      VersionPropuesta,
    int       PropuestasVinculadas,
    int       PropuestasAdicionales,
    int       IdMoneda,
    string?   Moneda,
    string?   MonedaSimbolo,
    decimal   MontoOc,
    decimal   MontoAsignado,
    decimal   SaldoOc,
    decimal   AsignadoPct,
    string    Estado,
    string    EstadoVisual,
    string?   ResultadoIa,
    int       AlertasIa,
    long?     IdResponsable,
    string?   Responsable,
    bool      TienePdf,
    string?   UrlPdf,
    bool      PuedeAnular,
    /// <summary>Se puede registrar la OC del cliente que la reemplaza (autogenerada o pendiente_reemplazo).</summary>
    bool      PuedeReemplazar);

public record BandejaOrdenesCompraDto(
    TarjetasOrdenesCompraDto        Tarjetas,
    List<MontoMonedaDto>            MontoValidadoMes,
    List<ItemBandejaOrdenCompraDto> Items,
    int                             Total,
    int                             Pagina,
    int                             PorPagina,
    List<OpcionFiltroDto>           Clientes,
    List<OpcionFiltroDto>           Responsables);

// ── Detalle (HU-25) ──

public record CabeceraDetalleOcDto
{
    public long      IdOc                    { get; init; }
    public string    NumeroOc                { get; init; } = "";
    public string    Estado                  { get; init; } = "";
    public string    EstadoVisual            { get; init; } = "";
    public bool      EsAutogenerada          { get; init; }
    public bool      PendienteReemplazo      { get; init; }
    public long?     ReemplazadaPor          { get; init; }
    public string?   NumeroOcReemplazo       { get; init; }
    public DateTime? FechaReemplazo          { get; init; }
    public long?     IdOcReemplazada         { get; init; }
    public string?   NumeroOcReemplazada     { get; init; }
    public long      IdCliente               { get; init; }
    public string    RazonSocial             { get; init; } = "";
    public string?   Ruc                     { get; init; }
    public DateTime? FechaRegistro           { get; init; }
    public string?   RegistradoPor           { get; init; }
    public long?     IdResponsable           { get; init; }
    public string?   Responsable             { get; init; }
    public int       IdMoneda                { get; init; }
    public string?   MonedaNombre            { get; init; }
    public string?   MonedaSimbolo           { get; init; }
    public string?   Moneda                  { get; init; }
    public decimal   MontoOc                 { get; init; }
    public int       PropuestasVinculadas    { get; init; }
    public decimal   MontoAsignado           { get; init; }
    public decimal   SaldoOc                 { get; init; }
    public decimal   AsignadoPct             { get; init; }
    public string?   ResultadoIa             { get; init; }
    public int       AlertasIa               { get; init; }
    public int       VinculacionesValidadas  { get; init; }
    public int       VinculacionesObservadas { get; init; }
    public int       PendientesCorreccion    { get; init; }
    public string?   RucClienteOc            { get; init; }
    public string?   RazonSocialOc           { get; init; }
    public string?   NumeroPropuestaRef      { get; init; }
    public int?      IdCondicionPago         { get; init; }
    public string?   CondicionPago           { get; init; }
    public string?   FormaPago               { get; init; }
    public bool?     IgvIncluido             { get; init; }
    public decimal?  IgvPct                  { get; init; }
    public decimal?  DescuentoMonto          { get; init; }
    public string?   FechaOc                 { get; init; }
    public string?   FechaRecepcion          { get; init; }
    public string?   VigenciaHasta           { get; init; }
    public bool      FacturaIgualOc          { get; init; }
    public string?   Referencia              { get; init; }
    public string?   Observaciones           { get; init; }
    public List<ConceptoOrdenCompraDto> Conceptos { get; init; } = [];
    public Dictionary<string, string?>? CamposIa  { get; init; }
    public List<CampoCorregidoDto> CamposManuales { get; init; } = [];
    public bool      TienePdf                { get; init; }
    public string?   NombreArchivoPdf        { get; init; }
    public long?     TamanoPdfBytes          { get; init; }
    public string?   UrlPdf                  { get; init; }
    public int?      IdMotivoAnulacion       { get; init; }
    public string?   MotivoAnulacion         { get; init; }
    public string?   JustificacionAnulacion  { get; init; }
    public DateTime? FechaAnulacion          { get; init; }
    public string?   AnuladoPor              { get; init; }
    public long?     IdExpediente            { get; init; }
    public string?   NumeroExpediente        { get; init; }
    public bool      PuedeEditar             { get; init; }
    public bool      PuedeReemplazarPdf      { get; init; }
    public bool      PuedeSubirCorregida     { get; init; }
    public bool      PuedeAgregarPropuesta   { get; init; }
    public bool      PuedeRevalidar          { get; init; }
    public bool      PuedeAnular             { get; init; }
    /// <summary>Igual a PuedeReemplazar (nombre anterior, se mantiene por compatibilidad).</summary>
    public bool      PuedeReemplazarAuto     { get; init; }
    /// <summary>"Registrar OC del cliente" en reemplazo de esta (autogenerada o pendiente_reemplazo).</summary>
    public bool      PuedeReemplazar         { get; init; }
}

public record PropuestaVinculadaOcDto
{
    public long      IdPropuesta             { get; init; }
    public string    Numero                  { get; init; } = "";
    public int       Version                 { get; init; }
    public string?   EstadoPropuesta         { get; init; }
    public bool      Aceptada                { get; init; }
    public decimal   MontoPropuesta          { get; init; }
    public decimal   MontoAsignado           { get; init; }
    public decimal   PctOc                   { get; init; }
    public decimal   SaldoPropuesta          { get; init; }
    public long?     IdContacto              { get; init; }
    public string?   Contacto                { get; init; }
    public string?   CargoContacto           { get; init; }
    public long?     IdRequerimiento         { get; init; }
    public string?   NumeroRq                { get; init; }
    public int       Servicios               { get; init; }
    public string?   ServiciosDetalle        { get; init; }
    public string    EstadoValidacion        { get; init; } = "";
    public string?   TipoObservacion         { get; init; }
    public string?   ResultadoIa             { get; init; }
    public DateTime? FechaDecision           { get; init; }
    public long?     IdValidacion            { get; init; }
    public int?      Corrida                 { get; init; }
    public int?      Coincidencias           { get; init; }
    public int?      Advertencias            { get; init; }
    public int?      Criticas                { get; init; }
    public int?      TotalCampos             { get; init; }
    public string?   Sugerencia              { get; init; }
    public string?   Dictamen                { get; init; }
    public DateTime? FechaValidacion         { get; init; }
    public long?     IdPropuestaNuevaVersion { get; init; }
    public string?   NumeroNuevaVersion      { get; init; }
    public int?      VersionNuevaVersion     { get; init; }
    public string?   EstadoNuevaVersion      { get; init; }
    public bool      NuevaVersionAceptada    { get; init; }
    public bool      FacturacionHabilitada   { get; init; }
}

public record DetalleOrdenCompraDto(
    CabeceraDetalleOcDto          Cabecera,
    List<PropuestaVinculadaOcDto> Propuestas,
    List<CampoComparadoOcDto>     Diferencias);

// ── Modal "Detalle de Validación IA" (HU-24) ──

public record CabeceraValidacionOcDto
{
    public long      IdOc                 { get; init; }
    public string    NumeroOc             { get; init; } = "";
    public string?   FechaOc              { get; init; }
    public string?   RazonSocial          { get; init; }
    public string?   Ruc                  { get; init; }
    public string?   NombreArchivoPdf     { get; init; }
    public long?     TamanoPdfBytes       { get; init; }
    public bool      TienePdf             { get; init; }
    public long      IdPropuesta          { get; init; }
    public string    NumeroPropuesta      { get; init; } = "";
    public int       VersionPropuesta     { get; init; }
    public string?   EstadoPropuesta      { get; init; }
    public DateTime? FechaAceptacion      { get; init; }
    public string?   NumeroExpediente     { get; init; }
    public string    EstadoValidacion     { get; init; } = "";
    public string?   TipoObservacion      { get; init; }
    public long?     IdValidacion         { get; init; }
    public int?      Corrida              { get; init; }
    public string?   Origen               { get; init; }
    public string?   Resultado            { get; init; }
    public int?      Coincidencias        { get; init; }
    public int?      Advertencias         { get; init; }
    public int?      Criticas             { get; init; }
    public int?      TotalCampos          { get; init; }
    public int       ValidacionesCorridas { get; init; }
    public string?   Dictamen             { get; init; }
    public decimal?  Confianza            { get; init; }
    public string?   Motor                { get; init; }
    public string?   Sugerencia           { get; init; }
    public DateTime? FechaValidacion      { get; init; }
}

public record HistorialValidacionOcDto(
    DateTime? Fecha,
    string    Tipo,
    string    Titulo,
    string?   Descripcion,
    string?   Resultado,
    int?      Coincidencias,
    int?      Advertencias,
    int?      Criticas,
    string?   Usuario);

public record PropuestaPillOcDto(long IdPropuesta, string Numero, int Version, string? ResultadoIa, string EstadoValidacion, bool Seleccionada);

public record ValidacionOrdenCompraDto(
    CabeceraValidacionOcDto        Cabecera,
    List<CampoComparadoOcDto>      Campos,
    List<ConceptoEvaluadoDto>      Conceptos,
    List<InsightIaDto>             Insights,
    List<HistorialValidacionOcDto> Historial,
    List<PropuestaPillOcDto>       Propuestas);

// ── Timeline (HU-26) ──

public record CabeceraTimelineOcDto(
    long      IdOc,
    string    NumeroOc,
    string    Estado,
    string?   EstadoVisual,
    bool      EsAutogenerada,
    long?     IdCliente,
    string?   RazonSocial,
    string?   Ruc,
    long?     IdPropuesta,
    string?   NumeroPropuesta,
    int?      VersionPropuesta,
    DateTime? GeneradoEn,
    string?   GeneradoPor);

/// <summary>Evento del timeline. Categoria: validacion_ia · comercial · documental. Nivel: exito · alerta · critico · info · neutro.</summary>
public record EventoTimelineOcDto(
    long      IdEvento,
    DateTime? Fecha,
    string    Accion,
    string    Titulo,
    string?   Descripcion,
    string    Categoria,
    string    Nivel,
    string?   EstadoAnterior,
    string?   EstadoNuevo,
    string?   Metadata,
    string?   Url,
    long?     IdUsuario,
    string?   Usuario,
    string?   Area,
    string?   Rol,
    bool      AutomaticoIa);

public record TimelineOrdenCompraDto(CabeceraTimelineOcDto Cabecera, List<EventoTimelineOcDto> Eventos);

// ── Anulación (HU-28) ──

public record ImpactoAnulacionOcDto(
    long     IdOc,
    string   NumeroOc,
    bool     EsAutogenerada,
    string?  RazonSocial,
    int      IdMoneda,
    string?  MonedaSimbolo,
    decimal  MontoOc,
    decimal  MontoAsignado,
    int      PropuestasVinculadas,
    int      OsEnEjecucion,
    bool     ImpactoCritico,
    DateTime? FechaServidor);

/// <summary>GeneraraOcAutogenerada: la propuesta aceptada queda sin OC vigente y al anular se le generará una OC-AUTO.</summary>
public record PropuestaAfectadaOcDto(long IdPropuesta, string Numero, int Version, decimal MontoAsignado,
                                     string? EstadoValidacion, decimal SaldoActual, decimal SaldoDespues,
                                     bool GeneraraOcAutogenerada);

public record OsEnEjecucionDto(long IdOs, string Numero, string Estado, DateTime? FechaEjecucion, string? NumeroExpediente);

public record PreparacionAnulacionOcDto(
    ImpactoAnulacionOcDto        Impacto,
    List<PropuestaAfectadaOcDto> Propuestas,
    List<OsEnEjecucionDto>       OrdenesServicio,
    List<OpcionFiltroDto>        Motivos);

/// <summary>IdOcAutogenerada / NumeroOcAutogenerada: OC-AUTO generada al anular para mantener la cobertura (si aplica).</summary>
public record PropuestaSaldoOcDto(long IdPropuesta, string Numero, int Version, decimal MontoAsignado, decimal Saldo,
                                  long? IdOcAutogenerada, string? NumeroOcAutogenerada);

public record AnulacionOrdenCompraDto(
    long      IdOc,
    string    NumeroOc,
    string    Estado,
    DateTime? FechaAnulacion,
    string?   Motivo,
    string?   Justificacion,
    List<PropuestaSaldoOcDto> Propuestas);

// ── PDF ──

public record RutaPdfOrdenCompraDto(string Ruta, string NombreArchivo);

// ── Comandos internos (de los casos de uso al repositorio) ──

/// <summary>PDF ya guardado en el almacenamiento.</summary>
public record ArchivoPdfOcDto(string Ruta, string Nombre, long Tamano, string Hash);

/// <summary>Datos de apoyo para la IA: monedas, condiciones, ítems de las propuestas y motivo de nueva versión.</summary>
public record ItemPropuestaIaDto(long IdPropuesta, string Numero, int Version, string Descripcion, decimal Cantidad,
                                 decimal PrecioUnitario, decimal Subtotal);

public record DatosIaOrdenCompraDto(
    List<MonedaOrdenCompraDto> Monedas,
    List<CondicionPagoDto>     CondicionesPago,
    List<ItemPropuestaIaDto>   Items,
    int?                       IdMotivoNuevaVersion);
