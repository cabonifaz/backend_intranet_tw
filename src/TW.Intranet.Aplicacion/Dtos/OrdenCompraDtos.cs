namespace TW.Intranet.Aplicacion.Dtos;

// ══════════════════════ HU-22 — Registro de Orden de Compra recibida ══════════════════════

/// <summary>Propuesta aceptada a la que se vincula la OC (base del indicador de cobertura).</summary>
public record PropuestaOrdenCompraDto
{
    public long      IdPropuesta         { get; init; }
    public string    Numero              { get; init; } = "";
    public int       Version             { get; init; }
    public long      IdCliente           { get; init; }
    public string    RazonSocial         { get; init; } = "";
    public string?   Ruc                 { get; init; }
    public long?     IdRequerimiento     { get; init; }
    public string?   NumeroRq            { get; init; }
    /// <summary>Monto de la propuesta aprobada (se compara con el monto de la OC).</summary>
    public decimal   Total               { get; init; }
    public int       IdMoneda            { get; init; }
    public string?   Moneda              { get; init; }
    public string?   MonedaSimbolo       { get; init; }
    public string?   MonedaNombre        { get; init; }
    public DateTime? FechaAceptacion     { get; init; }
    public string?   TipoAceptacion      { get; init; }
    public long      IdResponsable       { get; init; }
    public string?   Responsable         { get; init; }
    public DateTime? FechaServidor       { get; init; }
    public int       VigenciaDiasDefecto { get; init; }
}

public record MonedaOrdenCompraDto(int Id, string Nombre, string? Simbolo, string? Codigo);

public record PreparacionOrdenCompraDto(PropuestaOrdenCompraDto Propuesta, List<MonedaOrdenCompraDto> Monedas);

/// <summary>Datos de la OC (N° OC, fechas, moneda, monto, vigencia en días y observaciones).</summary>
public record DatosOrdenCompraDto
{
    public string?   NumeroOc       { get; init; }
    public DateTime? FechaOc        { get; init; }
    public DateTime? FechaRecepcion { get; init; }
    public int?      IdMoneda       { get; init; }
    public decimal?  Monto          { get; init; }
    public int?      VigenciaDias   { get; init; }
    public string?   Observaciones  { get; init; }
    /// <summary>HU-24 — Referencia / glosa de la OC (opcional, hasta 200 caracteres).</summary>
    public string?   Referencia     { get; init; }
}

/// <summary>Datos que el caso de uso envía al SP (incluye el PDF ya guardado).</summary>
public record ComandoOrdenCompra(
    DatosOrdenCompraDto Datos,
    string?             RutaPdf,
    string?             NombrePdf,
    long?               TamanoPdf,
    string?             HashPdf);

/// <summary>
/// Indicador de cobertura. EstadoCobertura: completa | parcial | excede | moneda_diferente.
/// Diferencia = monto OC − monto propuesta (null si las monedas son distintas).
/// </summary>
public record CoberturaOrdenCompraDto(
    string   EstadoCobertura,
    decimal  CoberturaPct,
    decimal? Diferencia,
    decimal  MontoPropuesta,
    int      IdMonedaPropuesta,
    string?  MonedaSimboloPropuesta,
    decimal  MontoOc,
    int      IdMonedaOc,
    string?  MonedaSimboloOc);

/// <summary>OC registrada. Estado: pendiente_validacion. SiguienteEtapa: validacion_oc.</summary>
public record OrdenCompraRegistradaDto(
    long      IdOc,
    string    NumeroOc,
    string    Estado,
    string    EstadoCobertura,
    decimal   CoberturaPct,
    decimal?  Diferencia,
    DateTime? VigenciaHasta,
    string    SiguienteEtapa,
    int       Notificados);

public record RutaPdfOrdenCompraDto(string Ruta, string NombreArchivo);

// ══════════════════════ HU-23 — Bandeja y Detalle de Órdenes de Compra ══════════════════════

/// <summary>
/// Filtros de la bandeja. Estado: activas (default) | vigentes | pendiente_validacion | validada | validada_parcial |
/// observada | bloqueada | listas_programacion | vencida | anulada | todas.
/// Cobertura: completa | con_saldo | insuficiente | moneda_diferente | pendiente. Fechas sobre la fecha de la OC.
/// </summary>
public record FiltrosBandejaOrdenesCompraDto
{
    public string?   Estado        { get; init; }
    public string?   Cobertura     { get; init; }
    public long?     IdCliente     { get; init; }
    public long?     IdResponsable { get; init; }
    public DateTime? FechaDesde    { get; init; }
    public DateTime? FechaHasta    { get; init; }
    /// <summary>Filtro "Archivo": true con PDF, false sin PDF, null todas.</summary>
    public bool?     ConPdf        { get; init; }
    public string?   Busqueda      { get; init; }
    public int       Pagina        { get; init; } = 1;
    public int       PorPagina     { get; init; } = 10;
}

/// <summary>Tarjetas superiores de la bandeja.</summary>
public record KpisOrdenesCompraDto(
    int Vigentes,
    int CoberturaParcial,
    int SaldoInsuficiente,
    int PendientesValidacion,
    int ListasProgramacion,
    int Observadas,
    int Vencidas,
    /// <summary>Pendientes de validación cuyo monto no alcanza o están en otra moneda.</summary>
    int PendientesConAlerta);

/// <summary>
/// Fila de la bandeja. MontoAplicado = monto de la propuesta ya aplicado a la OC (0 mientras no se valida);
/// Saldo = MontoOc − MontoAplicado (negativo = saldo insuficiente).
/// CoberturaCodigo: pendiente | completa | con_saldo ("Parcial") | insuficiente | moneda_diferente.
/// CoberturaProyectada: cómo quedará la cobertura al validar. EstadoVisual: pendiente_validacion | observada |
/// validada | validada_parcial | bloqueada | vencida | anulada.
/// </summary>
public record ItemBandejaOrdenCompraDto
{
    public long     IdOc                { get; init; }
    public string   NumeroOc            { get; init; } = "";
    public string?  FechaOc             { get; init; }
    public string?  FechaRecepcion      { get; init; }
    public long     IdCliente           { get; init; }
    public string   RazonSocial         { get; init; } = "";
    public string?  Ruc                 { get; init; }
    public long?    IdRequerimiento     { get; init; }
    public string?  NumeroRq            { get; init; }
    public long?    IdPropuesta         { get; init; }
    public string?  NumeroPropuesta     { get; init; }
    public int?     VersionPropuesta    { get; init; }
    public int      IdMoneda            { get; init; }
    public string?  Moneda              { get; init; }
    public string?  MonedaSimbolo       { get; init; }
    public decimal  MontoOc             { get; init; }
    public decimal  MontoPropuesta      { get; init; }
    public decimal  MontoAplicado       { get; init; }
    public decimal  Saldo               { get; init; }
    public decimal? CoberturaPct        { get; init; }
    public decimal  UtilizacionPct      { get; init; }
    public string   CoberturaCodigo     { get; init; } = "";
    public string   CoberturaProyectada { get; init; } = "";
    public string   Estado              { get; init; } = "";
    public string   EstadoVisual        { get; init; } = "";
    public string?  VigenciaHasta       { get; init; }
    public int?     DiasParaVencer      { get; init; }
    public long     IdResponsable       { get; init; }
    public string?  Responsable         { get; init; }
    public bool     TienePdf            { get; init; }
    public string?  UrlPdf              { get; init; }
    public bool     ListaProgramacion   { get; init; }
    public DateTime? FechaRegistro      { get; init; }
}

public record BandejaOrdenesCompraDto(
    KpisOrdenesCompraDto            Kpis,
    List<ItemBandejaOrdenCompraDto> Items,
    int                             Total,
    int                             Pagina,
    int                             PorPagina,
    List<OpcionFiltroDto>           Clientes,
    List<OpcionFiltroDto>           Responsables);

/// <summary>Datos generales y cobertura económica (propuesta aprobada vs. OC recibida).</summary>
public record ResumenOrdenCompraDto
{
    public long      IdOc                 { get; init; }
    public string    NumeroOc             { get; init; } = "";
    public string?   Referencia           { get; init; }
    public string    Estado               { get; init; } = "";
    public string    EstadoVisual         { get; init; } = "";
    public string?   FechaOc              { get; init; }
    public string?   FechaRecepcion       { get; init; }
    public string?   VigenciaDesde        { get; init; }
    public string?   VigenciaHasta        { get; init; }
    public int?      VigenciaDias         { get; init; }
    public int?      DiasParaVencer       { get; init; }
    public string?   Observaciones        { get; init; }
    public long      IdCliente            { get; init; }
    public string    RazonSocial          { get; init; } = "";
    public string?   Ruc                  { get; init; }
    public long?     IdRequerimiento      { get; init; }
    public string?   NumeroRq             { get; init; }
    /// <summary>Descripción del requerimiento (referencia del servicio).</summary>
    public string?   ReferenciaServicio   { get; init; }
    public long?     IdPropuesta          { get; init; }
    public string?   NumeroPropuesta      { get; init; }
    public int?      VersionPropuesta     { get; init; }
    public int       IdMoneda             { get; init; }
    public string?   Moneda               { get; init; }
    public string?   MonedaSimbolo        { get; init; }
    public string?   MonedaNombre         { get; init; }
    public decimal   MontoOc              { get; init; }
    public decimal   MontoPropuesta       { get; init; }
    /// <summary>Monto OC − monto propuesta (negativo = la OC no alcanza).</summary>
    public decimal   Diferencia           { get; init; }
    public decimal   MontoAplicado        { get; init; }
    public decimal   Saldo                { get; init; }
    public decimal?  CoberturaPct         { get; init; }
    public decimal   UtilizacionPct       { get; init; }
    public string    CoberturaCodigo      { get; init; } = "";
    public string    CoberturaProyectada  { get; init; } = "";
    public long      IdResponsable        { get; init; }
    public string?   Responsable          { get; init; }
    public long?     IdRegistradoPor      { get; init; }
    public string?   RegistradoPor        { get; init; }
    public DateTime? FechaRegistro        { get; init; }
    public long?     IdValidadoPor        { get; init; }
    public string?   ValidadoPor          { get; init; }
    public DateTime? FechaValidacion      { get; init; }
    public int?      IdMotivoObservacion  { get; init; }
    public string?   MotivoObservacion    { get; init; }
    public string?   NombreArchivoPdf     { get; init; }
    public long?     TamanoPdfBytes       { get; init; }
    public string?   UrlPdf               { get; init; }
    public bool      ListaProgramacion    { get; init; }
    public int       OrdenesServicio      { get; init; }
}

/// <summary>Propuesta vinculada a la OC (pestaña Aplicaciones).</summary>
public record AplicacionOrdenCompraDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    string    Estado,
    decimal   MontoPropuesta,
    int       IdMoneda,
    string?   Moneda,
    string?   MonedaSimbolo,
    decimal?  MontoAsignado,
    DateTime? FechaAsignacion,
    DateTime? FechaAceptacion,
    bool      EsPrincipal);

/// <summary>Ítem del checklist: cliente_coincide, moneda_coincide, propuesta_vigente, monto_suficiente, pdf_adjunto, numero_unico, oc_vigente.</summary>
public record ItemChecklistOrdenCompraDto(string Codigo, string Descripcion, bool Cumple, string? Detalle);

/// <summary>Vinculación del proceso: requerimiento | propuesta | expediente | orden_servicio (Disponible = false si aún no existe).</summary>
public record VinculacionOrdenCompraDto(
    string Tipo, long? IdEntidad, string? Codigo, string Descripcion, string? Estado, bool Disponible, string? Url);

/// <summary>Documento: orden_compra_pdf | propuesta_pdf | evidencia_aceptacion.</summary>
public record DocumentoOrdenCompraDto(string Tipo, string Nombre, long? TamanoBytes, DateTime? Fecha, string? Url);

/// <summary>Etapa del flujo. Estado: completado | actual | observado | bloqueado | pendiente.</summary>
public record EtapaWorkflowOrdenCompraDto(int Orden, string Codigo, string Etapa, string Estado, DateTime? Fecha);

public record EventoHistorialOrdenCompraDto(
    DateTime? Fecha, string Tipo, string Titulo, string? Descripcion, long? IdUsuario, string? Usuario);

public record DetalleOrdenCompraDto(
    ResumenOrdenCompraDto                Resumen,
    List<AplicacionOrdenCompraDto>       Aplicaciones,
    List<ItemChecklistOrdenCompraDto>    Checklist,
    int                                  ChecklistCumplidos,
    List<VinculacionOrdenCompraDto>      Vinculaciones,
    List<DocumentoOrdenCompraDto>        Documentos,
    List<EtapaWorkflowOrdenCompraDto>    Workflow,
    List<EventoHistorialOrdenCompraDto>  Historial);

/// <summary>Propuesta aceptada sin OC (selector del botón "+ Nueva Orden de Compra").</summary>
public record PropuestaSinOrdenCompraDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    long      IdCliente,
    string    RazonSocial,
    string?   Ruc,
    long?     IdRequerimiento,
    string?   NumeroRq,
    decimal   Total,
    int       IdMoneda,
    string?   Moneda,
    string?   MonedaSimbolo,
    DateTime? FechaAceptacion,
    long      IdResponsable,
    string?   Responsable);

// ══════════════════════ HU-24 — Registro y Edición de Orden de Compra ══════════════════════

/// <summary>Datos que se van escribiendo en el formulario (panel en tiempo real). Todos opcionales.</summary>
public record EvaluacionOrdenCompraSolicitudDto
{
    public string?  NumeroOc     { get; init; }
    public int?     IdMoneda     { get; init; }
    public decimal? Monto        { get; init; }
    /// <summary>true si el usuario ya seleccionó el PDF (aún no subido).</summary>
    public bool     TieneArchivo { get; init; }
}

/// <summary>
/// Panel "Validación de Cobertura" + "Checklist de negocio".
/// EstadoCobertura: sin_monto | completa | con_saldo | insuficiente | moneda_diferente.
/// En edición: CambiaMontoMoneda, RequiereRevalidacion (la OC validada vuelve a validación) y
/// CambioBloqueado (la OC ya tiene órdenes de servicio).
/// </summary>
public record EvaluacionOrdenCompraDto
{
    public string   EstadoCobertura         { get; init; } = "";
    public string   EtiquetaCobertura       { get; init; } = "";
    public decimal  CoberturaPct            { get; init; }
    public decimal? Diferencia              { get; init; }
    public decimal  MontoPropuesta          { get; init; }
    public int      IdMonedaPropuesta       { get; init; }
    public string?  MonedaSimboloPropuesta  { get; init; }
    public decimal? MontoOc                 { get; init; }
    public int?     IdMonedaOc              { get; init; }
    public string?  MonedaSimboloOc         { get; init; }
    public decimal  ToleranciaPct           { get; init; }
    public bool     DentroTolerancia        { get; init; }
    public bool     EsEdicion               { get; init; }
    public decimal? MontoOcActual           { get; init; }
    public int?     IdMonedaActual          { get; init; }
    public bool     CambiaMontoMoneda       { get; init; }
    public bool     RequiereRevalidacion    { get; init; }
    public bool     CambioBloqueado         { get; init; }
    public decimal  MontoAplicadoProyectado { get; init; }
    public decimal  SaldoProyectado         { get; init; }
    public List<ItemChecklistOrdenCompraDto> Checklist { get; init; } = [];
    public int      ChecklistCumplidos      { get; init; }
    public bool     TodoConforme            { get; init; }
}

/// <summary>OC a editar: datos editables, datos bloqueados (propuesta, RQ, cliente) y resumen de situación.</summary>
public record OrdenCompraEdicionDto
{
    public long      IdOc                          { get; init; }
    public string    NumeroOc                      { get; init; } = "";
    public string?   Referencia                    { get; init; }
    public string?   FechaOc                       { get; init; }
    public string?   FechaRecepcion                { get; init; }
    public int?      VigenciaDias                  { get; init; }
    public string?   VigenciaHasta                 { get; init; }
    public int       IdMoneda                      { get; init; }
    public string?   Moneda                        { get; init; }
    public string?   MonedaSimbolo                 { get; init; }
    public string?   MonedaNombre                  { get; init; }
    public decimal   MontoOc                       { get; init; }
    public string?   Observaciones                 { get; init; }
    public string?   NombreArchivoPdf              { get; init; }
    public long?     TamanoPdfBytes                { get; init; }
    public string?   UrlPdf                        { get; init; }
    public long?     IdPropuesta                   { get; init; }
    public string?   NumeroPropuesta               { get; init; }
    public int?      VersionPropuesta              { get; init; }
    public long?     IdRequerimiento               { get; init; }
    public string?   NumeroRq                      { get; init; }
    public long      IdCliente                     { get; init; }
    public string    RazonSocial                   { get; init; } = "";
    public string?   Ruc                           { get; init; }
    public int?      IdMonedaPropuesta             { get; init; }
    public string?   MonedaSimboloPropuesta        { get; init; }
    public decimal   MontoPropuesta                { get; init; }
    public decimal   MontoAplicado                 { get; init; }
    public decimal   Saldo                         { get; init; }
    public decimal?  CoberturaPct                  { get; init; }
    public decimal   UtilizacionPct                { get; init; }
    public string    CoberturaCodigo               { get; init; } = "";
    public string    CoberturaProyectada           { get; init; } = "";
    public string    Estado                        { get; init; } = "";
    public string    EstadoVisual                  { get; init; } = "";
    public int?      IdMotivoObservacion           { get; init; }
    public string?   MotivoObservacion             { get; init; }
    /// <summary>true si la OC está validada: cambiar monto o moneda la regresa a validación (alerta "Revalidación necesaria").</summary>
    public bool      RequiereRevalidacionAlCambiar { get; init; }
    /// <summary>false si la OC ya tiene órdenes de servicio (no se puede cambiar monto ni moneda).</summary>
    public bool      PuedeCambiarMonto             { get; init; }
    public int       OrdenesServicio               { get; init; }
    public string?   FechaServidor                 { get; init; }
}

public record EdicionOrdenCompraDto(OrdenCompraEdicionDto OrdenCompra, List<MonedaOrdenCompraDto> Monedas);

/// <summary>Formulario de edición: los datos de la OC + Revalidar ("Guardar y revalidar").</summary>
public record EditarOrdenCompraSolicitudDto : DatosOrdenCompraDto
{
    public bool Revalidar { get; init; }
}

public record ComandoEdicionOrdenCompra(
    DatosOrdenCompraDto Datos,
    bool                Revalidar,
    string?             RutaPdf,
    string?             NombrePdf,
    long?               TamanoPdf,
    string?             HashPdf);

/// <summary>Resultado de la edición. RequiereRevalidacion = la OC volvió a 'pendiente_validacion'.</summary>
public record OrdenCompraEditadaDto(
    long     IdOc,
    string   NumeroOc,
    string   Estado,
    string   EstadoCobertura,
    decimal  CoberturaPct,
    decimal? Diferencia,
    bool     RequiereRevalidacion,
    string?  Cambios,
    int      Notificados);
