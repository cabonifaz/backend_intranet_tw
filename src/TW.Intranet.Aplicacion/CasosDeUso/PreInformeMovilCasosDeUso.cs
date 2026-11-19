using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile — Pre-informe (PDF de la cabecera del informe del equipo, para imprimir y que lo firme el encargado de planta) ─────────────

/// <summary>
/// Regla de "cabecera completa" (una sola vez, la misma de las 6 etapas que muestra el avance de la cabecera): quién atiende en planta, Detalle Serv. guardado,
/// Recomendaciones (o "sin recomendaciones"), Fallas con su prueba (o "sin fallas"), Pruebas generales finalizadas y Diagnóstico final.
/// </summary>
public static class ReglasPreInformeMovil
{
    /// <summary>Lo que falta para poder generar el pre-informe (vacío = cabecera completa).</summary>
    public static IReadOnlyList<string> Pendientes(CabeceraInformeMovilDto c)
    {
        var faltan = new List<string>();
        if (string.IsNullOrWhiteSpace(c.Datos.ResponsableNombre)) faltan.Add("Quién atiende en planta");
        if (!c.Detalle.Guardado) faltan.Add("Detalle Serv.");
        if (c.Recomendaciones.Count == 0 && !c.SinRecomendaciones) faltan.Add("Recomendaciones inmediatas");
        var fallasCompletas = c.Fallas.Count > 0 ? c.Fallas.All(f => f.Pruebas.Count > 0) : c.SinFallas;
        if (!fallasCompletas) faltan.Add("Fallas y su prueba");
        if (!c.PruebasGenerales.Finalizado) faltan.Add("Pruebas generales (finalizar Ensayos y Calibración)");
        if (string.IsNullOrWhiteSpace(c.Diagnostico.SeveridadGeneral) || string.IsNullOrWhiteSpace(c.Diagnostico.EstadoEquipo)) faltan.Add("Diagnóstico final");
        return faltan;
    }
}

/// <summary>
/// Genera el PDF del pre-informe con lo YA GUARDADO de la cabecera del informe del equipo. Solo si la cabecera está completa; con acceso del técnico al equipo
/// (SP_ObtenerCabeceraInformeMovil). No escribe nada ni asigna el N° de informe: el informe oficial se genera al finalizar el trabajo en el equipo.
/// </summary>
public class GenerarPreInformeMovilCasoDeUso(IInformeEquipoMovilRepositorio repositorio, IGeneradorPreInformePdf pdf)
{
    /// <summary>Hora de Lima (UTC-5, sin horario de verano).</summary>
    private static DateTime AhoraLima() => DateTime.UtcNow.AddHours(-5);

    public async Task<RespuestaDto<byte[]>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Servicio o equipo no encontrado.");
        var r = await repositorio.ObtenerCabeceraAsync(idUsuario, idOs, idOsEquipo, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var faltan = ReglasPreInformeMovil.Pendientes(r.Datos);
        if (faltan.Count > 0) return new(1, $"El pre-informe se descarga cuando la cabecera está completa. Falta: {string.Join(", ", faltan)}.");

        return new(2, "Éxito.", pdf.Generar(new DatosPreInformePdf(r.Datos, AhoraLima())));
    }
}
