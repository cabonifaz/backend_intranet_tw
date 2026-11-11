using System.Text.Json;

namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-17 — Firma de informes y constancia de servicio ─────────────────────────────────────────────────

/// <summary>Cuerpo de "Confirmar firma" / "Cliente ausente" de un responsable. Modo: dispositivo | ausente (el formato físico llega por multipart).</summary>
public record PeticionFirmaResponsableMovilDto(string? Modo, JsonElement? Trazos, string? Motivo);

/// <summary>Cuerpo de la firma del cliente en la constancia.</summary>
public record PeticionFirmaConstanciaMovilDto(JsonElement? Trazos, string? Nombre);

/// <summary>Cabecera de la lista de informes: plazo de aceptación tácita (segundos que quedan) y avance de firmas.</summary>
public record CabeceraFirmasMovilDto(
    long IdOs, string NumeroOs, string? Cliente, int PlazoHoras, int? SegundosRestantes, bool TacitaActiva,
    int Informes, int Completos, int Firmados, int Responsables, int Resueltos, bool Listo, bool ConstanciaFirmada, bool ConstanciaGenerada, bool Cerrado);

/// <summary>Un informe técnico (uno por equipo). Firma: incompleto | pendiente | ausente | firmado.</summary>
public record InformeFirmaMovilDto(
    long IdOsEquipo, long? IdInforme, string? NumeroInforme, string? Equipo, string? CodigoEquipo, bool Completo, string? Motivo,
    string? Responsable, string? Cargo, string? Telefono, string? Clave, string Firma, DateTime? FirmadoEn);

/// <summary>Un responsable ("Quién atiende en planta") con sus informes y su firma (trazos normalizados de 0 a 1).</summary>
public record ResponsableFirmaMovilDto(
    string Clave, string Nombre, string? Cargo, string? Telefono, int NInformes, string? Informes, string Firma, string? Modo, bool Resuelto,
    DateTime? FirmadoEn, string? Firmante, string? Motivo, JsonElement? Trazos);

public record FirmasMovilDto(CabeceraFirmasMovilDto Cabecera, List<InformeFirmaMovilDto> Informes, List<ResponsableFirmaMovilDto> Responsables);

public record ResumenFirmasMovilDto(int Informes, int Completos, int Firmados, int Resueltos, int Responsables, bool Cerrado);

/// <summary>Lo que necesita el servicio de similitud: el umbral y las firmas por dispositivo de OTROS responsables de la misma OS.</summary>
public record FirmaComparableMovilDto(string Nombre, string Trazos);
public record ComparablesFirmaMovilDto(int UmbralPct, List<FirmaComparableMovilDto> Firmas);

public record RegistroFirmaMovilDto(string Firma, int Responsables, int Resueltos, int Firmados, bool Listo, bool CierreListo, string? RutaFotoAnterior);
public record RegistroConstanciaMovilDto(bool Generada, bool Listo, bool CierreListo, string? RutaFotoAnterior);
public record CierreConstanciaMovilDto(bool Cerrado, DateTime? CerradaEn);

public record CabeceraConstanciaMovilDto(
    long IdOs, string NumeroOs, string? Cliente, string? Direccion, string? ContactoNombre, string? ContactoCargo, string? ContactoTelefono, string? ContactoCorreo,
    string? NumeroRq, string? Fecha, int Informes, int Completos, int Firmados, int Responsables, int Resueltos,
    string? Modo, string? Firmante, DateTime? FirmadoEn, JsonElement? Trazos, bool TieneFoto, bool Firmada, DateTime? GeneradaEn, DateTime? CerradaEn,
    string EnvioEstado, string? EnvioDestino, DateTime? EnvioEn, string? EnvioDetalle, bool PuedeGenerar, bool EnvioActivo);

public record EquipoConstanciaMovilDto(
    string? Equipo, string? Marca, string? Modelo, string? Serie, string? Capacidad, string? D, string? E, string? Ubicacion, string? Codigo, string? Procedencia, string? Certificado);

public record FaltaFirmaMovilDto(string Nombre, string? Cargo, string? Informes);

public record ConstanciaMovilDto(CabeceraConstanciaMovilDto Cabecera, List<EquipoConstanciaMovilDto> Equipos, List<FaltaFirmaMovilDto> Faltan);

/// <summary>Datos con los que se arma el PDF de la constancia.</summary>
public record DatosConstanciaPdf(ConstanciaMovilDto Constancia, FirmasMovilDto Firmas);
