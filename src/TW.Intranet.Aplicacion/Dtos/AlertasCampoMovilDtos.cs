namespace TW.Intranet.Aplicacion.Dtos;

// App Mobile HU-32 — Alertas y apoyo en campo

/// <summary>Una lectura del ensayo: carga L, indicación I, error E, EMP y si es crítica (supera el EMP). <c>Grupo</c> solo en excentricidad.</summary>
public record LecturaAlertaMovilDto(int? Grupo, int Orden, decimal? Carga, decimal? Indicacion, decimal? Error, decimal? Emp, string? Resultado, bool Critico);

/// <summary>Pedido de apoyo del técnico ante un error crítico en un ensayo (aviso «Ensayo con error crítico»).</summary>
public record AlertaCampoMovilDto(
    long IdNotificacion, string Titulo, string Cuerpo, string? CreadaEn, int HaceMin,
    long IdOs, string NumeroOs, string? Cliente, string? Sede,
    long? IdTecnico, string? Tecnico, string? Telefono,
    long? IdOsEquipo, string? EquipoCodigo, string? EquipoDescripcion, string? EquipoUbicacion,
    IReadOnlyList<LecturaAlertaMovilDto> Pesaje, IReadOnlyList<LecturaAlertaMovilDto> Excentricidad);

public record ContactoAlertaMovilDto(string Nombre, string? Telefono);

public record TecnicoReasignacionMovilDto(
    long IdUsuario, string Nombre, string Iniciales, decimal? DistanciaKm, int? LlegaMin,
    int ServiciosHoy, int CargaPct, string Ssoma, bool Disponible, string? MotivoNo);

public record ReasignacionOsMovilDto(
    long IdOs, string NumeroOs, string? Cliente, long? IdTecnicoActual, string? TecnicoActual,
    decimal? PlantaLatitud, decimal? PlantaLongitud, IReadOnlyList<TecnicoReasignacionMovilDto> Tecnicos);

public record IncidenciaRegistradaMovilDto(long IdIncidencia, string Estado, int Notificados);

public record ReasignadoMovilDto(long IdOs, long IdTecnico, string Tecnico, int Notificados);

public record AccionAlertaSolicitud(string? Accion, string? Mensaje);

public record ReasignarSolicitud(long IdTecnico);
