using System.Text.Json;

namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-23 — Recepción de instrumentos (OM) en el taller ─────────────────────────────────────────────

/// <summary>
/// Una OM de la lista. Estado: por_recibir | parcial (ya recibió algunos, faltan otros) | conforme | observado (en «Recibidos hoy»: el de la última recepción de hoy;
/// parcial si esa recepción dejó instrumentos pendientes). Hora = HH:mm de Lima de la última recepción; Guia = su N° de guía. Pendientes = nombres de los instrumentos sin recibir (hasta 5).
/// </summary>
public record ItemRecepcionOmMovilDto(
    long IdOs, string Numero, string? Cliente, string? NumeroRq, string? Servicio, int TotalInstrumentos, int Recibidos,
    string Estado, string? Hora, string? Guia, IReadOnlyList<string> Pendientes);

/// <summary>Las dos listas de la pantalla: «Por recibir» y «Recibidos hoy» (máximo 50 cada una).</summary>
public record ListaRecepcionOmMovilDto(List<ItemRecepcionOmMovilDto> PorRecibir, List<ItemRecepcionOmMovilDto> RecibidosHoy);

/// <summary>Resumen de la OM. PuedeRecibir = está activa y quedan instrumentos pendientes. Estado: por_recibir | parcial | observado | conforme.</summary>
public record CabeceraRecepcionOmMovilDto(
    long IdOs, string Numero, string? Cliente, string? NumeroRq, string? Servicio, int TotalInstrumentos, int Recibidos, bool PuedeRecibir, string Estado);

/// <summary>Un instrumento de la OM. Si ya se recibió trae su estado físico, observaciones, fotos y cuándo (hora de Lima «yyyy-MM-dd HH:mm»).</summary>
public record InstrumentoRecepcionOmMovilDto(
    long IdOsEquipo, int Numero, string Nombre, string? Marca, string? Modelo, string? Serie, string? Capacidad, string? CodigoCliente, string? CodigoTw,
    bool Recibido, string? EstadoFisico, string? Observaciones, int Fotos, string? RecibidoEn);

/// <summary>Una recepción ya registrada. Medio: cliente_taller | courier | traslado_tw. Fecha de Lima «yyyy-MM-dd HH:mm».</summary>
public record RecepcionRegistradaOmMovilDto(
    long IdRecepcion, string? Guia, string? Medio, string? Entrego, string? EntregoCargo, string? Recibio, string? Fecha, string Estado, string? MotivoParcial,
    int Instrumentos, bool TieneConstancia);

public record DetalleRecepcionOmMovilDto(
    CabeceraRecepcionOmMovilDto Cabecera, List<InstrumentoRecepcionOmMovilDto> Instrumentos, List<RecepcionRegistradaOmMovilDto> Recepciones);

/// <summary>Una foto de recepción subida y aún no ligada a una recepción registrada. Orden = 1 a 8 (siempre correlativo).</summary>
public record FotoRecepcionOmMovilDto(long IdFoto, int Orden);

/// <summary>El instrumento de la OM al que corresponde el código leído.</summary>
public record InstrumentoQrRecepcionOmMovilDto(long IdOsEquipo, string Nombre);

// ── Lo que envía la app al registrar la recepción ──────────────────────────────────────────────────────────────

/// <summary>Un instrumento recibido: estado físico (conforme | observado), observaciones (10 a 500), accesorios (códigos del catálogo) y los ids de sus fotos (3 a 8).</summary>
public record InstrumentoPeticionRecepcionOmMovilDto(long IdOsEquipo, string? EstadoFisico, string? Observaciones, List<string>? Accesorios, List<long>? Fotos);

/// <summary>Firma = { "trazos": [[[x,y],…],…] } de quien entrega (trazos normalizados 0 a 1, igual que la firma de la HU-17).</summary>
public record PeticionRecepcionOmMovilDto(
    string? NumeroGuia, string? MedioEntrega, string? EntregoNombre, string? EntregoCargo, string? MotivoParcial,
    List<InstrumentoPeticionRecepcionOmMovilDto>? Instrumentos, JsonElement? Firma);

/// <summary>Lo que devuelve el SP al registrar (la recepción ya está guardada).</summary>
public record RegistroRecepcionOmMovilDto(long IdRecepcion, string Estado, bool Parcial, int InstrumentosRecibidos, int InstrumentosPendientes, int Notificados);

/// <summary>Respuesta de «Registrar recepción». CorreoEnviado = la constancia se envió al contacto del cliente (best-effort: si falla, la recepción igual queda registrada).</summary>
public record ResultadoRecepcionOmMovilDto(
    long IdRecepcion, string Estado, bool Parcial, int InstrumentosRecibidos, int InstrumentosPendientes, bool CorreoEnviado, string Mensaje);

// ── Constancia de recepción ────────────────────────────────────────────────────────────────────────────────────

public record CabeceraConstanciaRecepcionOmDto(
    long IdRecepcion, string NumeroOm, string? Cliente, string? Direccion, string? ContactoNombre, string? ContactoCorreo, string? NumeroRq,
    string? Guia, string? Medio, string? Entrego, string? EntregoCargo, string? Recibio, string? RecibidoEn, string Estado, string? MotivoParcial,
    JsonElement? FirmaTrazos, string? RutaConstancia, bool CorreoEnviado, bool EnvioActivo);

/// <summary>Un instrumento recibido en la recepción (Accesorios = códigos del catálogo).</summary>
public record InstrumentoConstanciaRecepcionOmDto(
    string Nombre, string? Marca, string? Modelo, string? Serie, string? Codigo, string? EstadoFisico, string? Observaciones, IReadOnlyList<string> Accesorios, int Fotos);

public record PendienteConstanciaRecepcionOmDto(string Nombre, string? Marca, string? Modelo, string? Serie, string? Codigo);

public record ConstanciaRecepcionOmDto(
    CabeceraConstanciaRecepcionOmDto Cabecera, List<InstrumentoConstanciaRecepcionOmDto> Instrumentos, List<PendienteConstanciaRecepcionOmDto> Pendientes);
