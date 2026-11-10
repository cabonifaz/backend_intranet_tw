using System.Text.Json;

namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-11 / HU-12 / HU-13 — Registro fotográfico, evidencia forzada y microvideo de encendido ──────────

/// <summary>
/// Cabecera del registro fotográfico. Completas = evidencias aprobadas por la IA, forzadas u "omitidas" (sin IA); PuedeGuardar = las 9 completas
/// ("Guardar y volver"). ObligatoriasFaltan = cuántas de las marcadas con (*) —placa e inicial— faltan.
/// </summary>
public record CabeceraEvidenciasMovilDto(
    long    IdOs,
    long    IdOsEquipo,
    string  NumeroOs,
    string  Nombre,
    int     Numero,
    string? ServicioSigla,
    string? NumeroSerie,
    string? CodigoCliente,
    string? CodigoTw,
    string? Marca,
    string? Modelo,
    string  Estado,
    bool    PuedeRegistrar,
    string? NumeroRq,
    int     Total,
    int     Completas,
    int     Forzadas,
    int     Rechazadas,
    int     ObligatoriasFaltan,
    bool    PuedeGuardar);

/// <summary>
/// Una de las 9 evidencias. Codigo: placa | inicial | encendido | desmontaje | abierto | prueba | final | informe | qr. Medio: foto | video | qr.
/// Estado: pendiente | aprobada | rechazada | forzada | omitida. Los datos de "Ver detalles" (motivo del técnico, rechazo de la IA, quién y cuándo,
/// intentos previos) vienen en las forzadas. ResultadoIa = lo que leyó la IA (JSON). Horas de Lima.
/// </summary>
public record EvidenciaMovilDto(
    int          Orden,
    string       Codigo,
    string       Nombre,
    string       Descripcion,
    bool         Obligatoria,
    string       Medio,
    string       Estado,
    long?        IdEvidencia,
    int?         Intento,
    bool         EsVideo,
    decimal?     DuracionSeg,
    int          Paginas,
    string?      MotivoRechazoIa,
    string?      MotivoForzado,
    string?      ForzadaPor,
    DateTime?    ForzadaEn,
    int          IntentosPrevios,
    DateTime?    CapturadaEn,
    JsonElement? ResultadoIa,
    bool         TieneCuadro);

public record EvidenciasMovilDto(CabeceraEvidenciasMovilDto Cabecera, List<EvidenciaMovilDto> Evidencias);

/// <summary>Resultado de una captura. Estado: aprobada | rechazada | omitida. Coincide = la placa o el QR corresponden al equipo (null si no se pudo comparar).</summary>
public record ResultadoEvidenciaMovilDto(
    long         IdEvidencia,
    string       Estado,
    string?      MotivoRechazo,
    int          Intento,
    bool?        Coincide,
    string?      NumeroRq,
    JsonElement? DatosIa,
    string       Mensaje);

/// <summary>Motivo escrito con el que el técnico acepta una foto rechazada por la IA (HU-12).</summary>
public class PeticionForzarEvidenciaMovilDto
{
    public string? Motivo { get; set; }
}

public record ResultadoForzarEvidenciaMovilDto(long IdEvidencia, DateTime? ForzadaEn, int IntentosPrevios, int Notificados);

/// <summary>Dónde está guardado el archivo de una evidencia.</summary>
public record ArchivoEvidenciaMovilDto(string Ruta, string? RutaCuadro, bool EsVideo);

/// <summary>Lo que la IA necesita para validar una captura (la imagen ya es JPEG; para un video es un cuadro de la grabación).</summary>
public record SolicitudValidacionEvidenciaIa(string Codigo, byte[] Imagen, string? Marca, string? Modelo, string? NumeroSerie);

/// <summary>Estado: aprobada | rechazada | omitida (la IA no estuvo disponible: no bloquea al técnico). DatosJson = lo que leyó, o null.</summary>
public record ResultadoValidacionEvidenciaIa(string Estado, string? Motivo, string? DatosJson);
