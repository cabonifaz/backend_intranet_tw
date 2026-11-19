namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-35 — Viáticos y gastos del equipo (Jefe de Área) ────────────────────────────────────────────────────

/// <summary>
/// KPIs de "Viáticos y gastos del equipo" sobre los servicios de la lista: asignado (viáticos), rendido (gastos no rechazados) y por revisar (gastos pendientes de la decisión del jefe).
/// Los montos son en soles.
/// </summary>
public record ViaticosEquipoKpisDto(decimal Asignado, decimal Rendido, decimal PorRevisar, string? Actualizado, int RefrescoSegundos);

/// <summary>
/// Un servicio de la lista. Tecnicos = nombres separados por ", " (el principal primero). Depositado = lo asignado ya depositado; PorRevisar = monto de los gastos pendientes de revisión
/// (GastosPorRevisar = cuántos). Avance = rendido / asignado en % (0 sin asignado; tope 100). Estado: por_revisar | por_depositar | al_dia | cerrado.
/// PuedeAsignar = prog_aprobar_reprogramacion, programación confirmada, rendición abierta y servicio sin salir a campo.
/// </summary>
public record ViaticoEquipoServicioDto(long IdOs, string NumeroOs, string? Cliente, long IdProgramacion, string Tecnicos, int NTecnicos, decimal Asignado, decimal Depositado,
                                       decimal Rendido, decimal PorRevisar, int GastosPorRevisar, int Avance, string Estado, bool PuedeAsignar);

public record ViaticosEquipoDto(ViaticosEquipoKpisDto Kpis, List<ViaticoEquipoServicioDto> Servicios);

/// <summary>
/// Cabecera del detalle de un servicio. Version = huella de la asignación: debe enviarse al asignar (si cambió mientras tanto, se rechaza y hay que recargar).
/// MotivoNoAsignar explica por qué PuedeAsignar es false.
/// </summary>
public record ViaticoServicioCabeceraDto(long IdOs, string NumeroOs, string? Cliente, long IdProgramacion, bool Cerrada, bool PuedeAsignar, string? MotivoNoAsignar, string Version,
                                         decimal Asignado, decimal Depositado, decimal Rendido, decimal PorRevisar);

/// <summary>Línea asignada a un técnico. Clave: movilidad | alimentacion | alojamiento (conceptos fijos) | otros. Depositado: ya no se puede modificar ni quitar.</summary>
public record ViaticoLineaDto(long IdGasto, string Concepto, string? Clave, decimal Monto, bool Depositado);

/// <summary>Un técnico del servicio con lo asignado, depositado, rendido y por revisar, y sus líneas de viáticos.</summary>
public record ViaticoTecnicoDto(long IdTecnico, string Nombre, bool Principal, decimal Asignado, decimal Depositado, decimal Rendido, decimal PorRevisar, List<ViaticoLineaDto> Lineas);

/// <summary>
/// Gasto rendido. Estado: pendiente | observado | aprobado | rechazado. Fecha "yyyy-MM-dd". MontoIa / CoincideIa = lectura de la IA del comprobante y si coincide con lo declarado (null si no se leyó).
/// La foto del comprobante y la decisión (aprobar, observar, rechazar) están en GET/PUT api/movil/aprobaciones/gastos/{id}.
/// </summary>
public record ViaticoGastoDto(long IdGasto, long IdTecnico, string Tecnico, string Concepto, decimal Monto, string Estado, string? Fecha, bool TieneComprobante, decimal? MontoIa, bool? CoincideIa);

public record ViaticoServicioDto(ViaticoServicioCabeceraDto Cabecera, List<ViaticoTecnicoDto> Tecnicos, List<ViaticoGastoDto> Gastos);

/// <summary>
/// Asignar viático a un técnico del servicio: un monto por concepto fijo (0 o vacío = quitar esa línea si no está depositada), si queda ya depositado y la versión con la que se abrió
/// el servicio. Montos con hasta 2 decimales y hasta el tope de la intranet (VIATICOS_MONTO_MAXIMO, lo valida el SP).
/// </summary>
public record AsignarViaticoEquipoDto(long? IdTecnico, decimal? Movilidad, decimal? Alimentacion, decimal? Alojamiento, decimal? Otros, bool? Depositado, string? Version);

/// <summary>Resultado de asignar. Total = lo asignado a ese técnico en el servicio; Depositado = todo lo suyo está depositado; Notificados = Contabilidad (lo pendiente) + el técnico; Version = la nueva huella.</summary>
public record AsignacionViaticoResultadoDto(decimal Total, bool Depositado, int Notificados, string Version);
