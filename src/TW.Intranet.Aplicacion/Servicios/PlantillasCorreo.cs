using System.Net;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>Plantillas HTML (con estilos en línea, compatibles con Outlook y Gmail) y su versión en texto.</summary>
public static class PlantillasCorreo
{
    private static string H(string? texto) => WebUtility.HtmlEncode(texto ?? "");

    public static MensajeCorreoDto Credenciales(
        string correo, string nombre, string contrasenaTemporal, OpcionesCorreo opciones, bool esReenvio,
        bool forzarCambio = true)
    {
        string asunto = esReenvio
            ? $"{opciones.NombreSistema}: nueva contraseña temporal"
            : $"{opciones.NombreSistema}: tus credenciales de acceso";
        string intro = esReenvio
            ? "Se generó una nueva contraseña temporal para tu cuenta. La anterior ya no es válida."
            : "Se creó tu cuenta en la intranet de Total Weight. Estos son tus datos de acceso:";

        bool hayUrl = !string.IsNullOrWhiteSpace(opciones.UrlIntranet);
        string avisoCambio = forzarCambio
            ? "Por seguridad, el sistema te pedirá cambiar esta contraseña en tu primer ingreso."
            : "Te recomendamos cambiar esta contraseña después de tu primer ingreso.";
        string boton = hayUrl
            ? $"""<p style="margin:0 0 20px"><a href="{H(opciones.UrlIntranet)}" style="background:#2563EB;color:#FFFFFF;text-decoration:none;padding:10px 18px;border-radius:8px;font-weight:bold;display:inline-block">Ingresar a la intranet</a></p>"""
            : "";

        string html = $"""
            <div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#1F2937">
              <div style="background:#0F172A;padding:18px 24px;border-radius:10px 10px 0 0">
                <span style="color:#FFFFFF;font-size:18px;font-weight:bold">{H(opciones.NombreSistema)}</span>
              </div>
              <div style="border:1px solid #E5E7EB;border-top:none;padding:24px;border-radius:0 0 10px 10px">
                <p style="margin:0 0 12px">Hola {H(nombre)},</p>
                <p style="margin:0 0 16px">{H(intro)}</p>
                <table style="border-collapse:collapse;margin:0 0 16px;font-size:14px">
                  <tr><td style="padding:6px 12px 6px 0;color:#6B7280">Usuario</td>
                      <td style="padding:6px 0;font-weight:bold">{H(correo)}</td></tr>
                  <tr><td style="padding:6px 12px 6px 0;color:#6B7280">Contraseña temporal</td>
                      <td style="padding:6px 0;font-family:Consolas,monospace;font-size:15px;font-weight:bold;letter-spacing:1px">{H(contrasenaTemporal)}</td></tr>
                </table>
                {boton}
                <p style="margin:0 0 8px;font-size:13px;color:#6B7280">{H(avisoCambio)}</p>
                <p style="margin:0;font-size:12px;color:#9CA3AF">Si no esperabas este correo, comunícate con el área de TI. No respondas a este mensaje.</p>
              </div>
            </div>
            """;

        string texto =
            $"Hola {nombre},\n\n{intro}\n\nUsuario: {correo}\nContraseña temporal: {contrasenaTemporal}\n\n" +
            (hayUrl ? $"Ingresa en: {opciones.UrlIntranet}\n\n" : "") +
            $"{avisoCambio}\n" +
            "Si no esperabas este correo, comunícate con el área de TI.";

        return new MensajeCorreoDto(correo, nombre, asunto, html, texto);
    }

    public static MensajeCorreoDto Prueba(string para, OpcionesCorreo opciones, DateTime fecha)
    {
        string asunto = $"{opciones.NombreSistema}: correo de prueba";
        string html = $"""
            <div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#1F2937">
              <h2 style="margin:0 0 12px;font-size:18px">{H(opciones.NombreSistema)}</h2>
              <p style="margin:0 0 8px">El servicio de correo está configurado correctamente.</p>
              <p style="margin:0;font-size:13px;color:#6B7280">Enviado el {fecha:dd/MM/yyyy HH:mm}.</p>
            </div>
            """;
        string texto = $"{opciones.NombreSistema}\n\nEl servicio de correo está configurado correctamente.\nEnviado el {fecha:dd/MM/yyyy HH:mm}.";
        return new MensajeCorreoDto(para, null, asunto, html, texto);
    }

    /// <summary>HU-33 — Aviso al nuevo responsable de un expediente reasignado.</summary>
    /// <summary>HU-33 — Al nuevo responsable: la lista de entidades (y expedientes) que ahora son suyas.</summary>
    public static MensajeCorreoDto ResponsableAsignado(ReasignacionExpedienteDto r, OpcionesCorreo opciones)
    {
        string asunto = $"{opciones.NombreSistema}: te asignaron {r.TotalEntidades} " +
                        (r.TotalEntidades == 1 ? "entidad" : "entidades") +
                        (r.TotalExpedientes > 1 ? $" en {r.TotalExpedientes} expedientes" : $" del expediente {r.NumeroExpediente}");
        string filas = string.Concat(r.Entidades.Select(e =>
            $"""<tr><td style="padding:4px 12px 4px 0">{H(e.NumeroExpediente)}</td><td style="padding:4px 12px 4px 0">{H(Entidad(e.EntidadTipo))}</td><td style="padding:4px 12px 4px 0"><b>{H(e.Codigo)}</b></td><td style="padding:4px 0;color:#6B7280">{H(e.Cliente)}</td></tr>"""));
        string html = $"""
            <div style="font-family:Arial,Helvetica,sans-serif;max-width:640px;margin:0 auto;color:#1F2937">
              <h2 style="margin:0 0 12px;font-size:18px">{H(opciones.NombreSistema)}</h2>
              <p style="margin:0 0 12px">Hola {H(r.Responsable)}, {H(r.ReasignadoPor ?? "un jefe")} te asignó como responsable ({H(r.Alcance)}).</p>
              <table style="border-collapse:collapse;font-size:14px;margin:0 0 12px">
                <tr><td style="padding:4px 12px 4px 0;color:#6B7280">Motivo</td><td style="padding:4px 0">{H(r.Motivo)}</td></tr>
                <tr><td style="padding:4px 12px 4px 0;color:#6B7280">Comentario</td><td style="padding:4px 0">{H(r.Comentario)}</td></tr>
                <tr><td style="padding:4px 12px 4px 0;color:#6B7280">SLA</td><td style="padding:4px 0">{H(r.GestionSla == "reiniciar" ? "Reiniciado desde ahora" : "Se mantiene el plazo restante")}</td></tr>
              </table>
              <table style="border-collapse:collapse;font-size:13px">
                <tr style="color:#6B7280"><td style="padding:4px 12px 4px 0">Expediente</td><td style="padding:4px 12px 4px 0">Entidad</td><td style="padding:4px 12px 4px 0">Código</td><td style="padding:4px 0">Cliente</td></tr>
                {filas}
              </table>
              {Boton(opciones)}
              <p style="margin:16px 0 0;font-size:12px;color:#6B7280">La reasignación quedó registrada en la auditoría de cada expediente.</p>
            </div>
            """;
        string texto = $"{opciones.NombreSistema}\n\nHola {r.Responsable}, {r.ReasignadoPor ?? "un jefe"} te asignó como responsable ({r.Alcance}).\n" +
                       $"Motivo: {r.Motivo}\nComentario: {r.Comentario}\n\n" +
                       string.Join("\n", r.Entidades.Select(e => $"- {e.NumeroExpediente}: {Entidad(e.EntidadTipo)} {e.Codigo} ({e.Cliente})")) +
                       (string.IsNullOrWhiteSpace(opciones.UrlIntranet) ? "" : $"\n\nIngresa en {opciones.UrlIntranet}");
        return new MensajeCorreoDto(r.CorreoResponsable!, r.Responsable, asunto, html, texto);
    }

    /// <summary>HU-33 — Al responsable anterior: aviso informativo de lo que pasó a otro comercial.</summary>
    public static MensajeCorreoDto ResponsableReemplazado(ReasignacionExpedienteDto r, ResponsableAnteriorDto anterior, OpcionesCorreo opciones)
    {
        string asunto = $"{opciones.NombreSistema}: cambio de responsable ({anterior.Cantidad} " +
                        (anterior.Cantidad == 1 ? "entidad)" : "entidades)");
        string html = $"""
            <div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#1F2937">
              <h2 style="margin:0 0 12px;font-size:18px">{H(opciones.NombreSistema)}</h2>
              <p style="margin:0 0 12px">Hola {H(anterior.Nombre)}, {H(r.ReasignadoPor ?? "un jefe")} reasignó a <b>{H(r.Responsable)}</b>: {H(anterior.Codigos)}.</p>
              <table style="border-collapse:collapse;font-size:14px">
                <tr><td style="padding:4px 12px 4px 0;color:#6B7280">Motivo</td><td style="padding:4px 0">{H(r.Motivo)}</td></tr>
                <tr><td style="padding:4px 12px 4px 0;color:#6B7280">Comentario</td><td style="padding:4px 0">{H(r.Comentario)}</td></tr>
              </table>
              <p style="margin:16px 0 0;font-size:12px;color:#6B7280">Es un aviso informativo; no requiere ninguna acción.</p>
            </div>
            """;
        string texto = $"{opciones.NombreSistema}\n\nHola {anterior.Nombre}, {r.ReasignadoPor ?? "un jefe"} reasignó a {r.Responsable}: {anterior.Codigos}.\n" +
                       $"Motivo: {r.Motivo}\nComentario: {r.Comentario}\n\nEs un aviso informativo.";
        return new MensajeCorreoDto(anterior.Correo!, anterior.Nombre, asunto, html, texto);
    }

    private static string Entidad(string tipo) => tipo switch
    {
        "requerimiento"  => "RQ",
        "propuesta"      => "Propuesta",
        "orden_compra"   => "OC",
        "orden_servicio" => "OS",
        _                => tipo,
    };

    private static string Boton(OpcionesCorreo opciones) =>
        string.IsNullOrWhiteSpace(opciones.UrlIntranet)
            ? ""
            : $"""<p style="margin:16px 0 0"><a href="{H(opciones.UrlIntranet)}" style="background:#2563EB;color:#FFFFFF;text-decoration:none;padding:10px 18px;border-radius:8px;font-weight:bold;display:inline-block">Abrir la intranet</a></p>""";
}
