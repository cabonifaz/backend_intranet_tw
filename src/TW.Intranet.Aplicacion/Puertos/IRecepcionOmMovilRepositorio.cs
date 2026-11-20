using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>App Mobile HU-23 — Recepción de instrumentos (OM) en el taller (todo por procedimientos almacenados). El técnico siempre sale del token.</summary>
public interface IRecepcionOmMovilRepositorio
{
    Task<RespuestaDto<ListaRecepcionOmMovilDto>> ObtenerListaAsync(long idUsuario, string? busqueda, CancellationToken ct);

    Task<RespuestaDto<DetalleRecepcionOmMovilDto>> ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct);

    Task<RespuestaDto<FotoRecepcionOmMovilDto>> RegistrarFotoAsync(long idUsuario, long idOs, long idOsEquipo, string ruta, CancellationToken ct);

    /// <summary>Quita una foto aún no registrada; devuelve la ruta del archivo para borrarlo del almacén.</summary>
    Task<RespuestaDto<string>> QuitarFotoAsync(long idUsuario, long idOs, long idOsEquipo, long idFoto, CancellationToken ct);

    Task<RespuestaDto<List<FotoRecepcionOmMovilDto>>> ObtenerFotosAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);

    Task<RespuestaDto<string>> ObtenerRutaFotoAsync(long idUsuario, long idFoto, CancellationToken ct);

    Task<RespuestaDto<InstrumentoQrRecepcionOmMovilDto>> BuscarQrAsync(long idUsuario, long idOs, string texto, CancellationToken ct);

    /// <summary>instrumentosJson y firmaJson ya validados por el caso de uso (el SP vuelve a validar todo y decide el estado).</summary>
    Task<RespuestaDto<RegistroRecepcionOmMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, string numeroGuia, string medioEntrega, string entregoNombre, string? entregoCargo, string? motivoParcial,
        string instrumentosJson, string firmaJson, CancellationToken ct);

    Task<RespuestaDto<ConstanciaRecepcionOmDto>> ObtenerConstanciaAsync(long idUsuario, long idRecepcion, CancellationToken ct);

    /// <summary>Guarda la ruta del PDF y si se envió por correo; devuelve la ruta del PDF que reemplaza (null si no había).</summary>
    Task<RespuestaDto<string?>> GuardarConstanciaAsync(long idUsuario, long idRecepcion, string ruta, bool correoEnviado, CancellationToken ct);
}

/// <summary>Arma el PDF de la constancia de recepción de instrumentos (con la firma de quien entrega dibujada como vector).</summary>
public interface IGeneradorConstanciaRecepcionOmPdf
{
    byte[] Generar(ConstanciaRecepcionOmDto datos);
}
