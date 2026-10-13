using System.Text.Json;
using System.Text.Json.Serialization;

namespace TW.Intranet.API.Configuracion;

/// <summary>
/// Todo el sistema trabaja en hora de Lima (UTC-5, Perú no usa horario de verano).
///   - Contenedor: ENV TZ=America/Lima en el Dockerfile (DateTime.Now / Today).
///   - MySQL: time_zone = '-05:00' (migración 63) para NOW(), CURDATE() y CURRENT_TIMESTAMP.
///   - JSON: las fechas viajan sin zona ("2026-10-13T09:15:00") y se entienden como hora de Lima.
/// </summary>
public static class ZonaHorariaLima
{
    public static readonly TimeZoneInfo Zona = Resolver();

    private static TimeZoneInfo Resolver()
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById("America/Lima"); }
        catch (TimeZoneNotFoundException) { }
        catch (InvalidTimeZoneException) { }
        // Imagen sin tzdata: Lima es UTC-5 fijo todo el año.
        return TimeZoneInfo.CreateCustomTimeZone("America/Lima", TimeSpan.FromHours(-5), "Lima", "Lima");
    }

    /// <summary>Lleva una fecha con zona (UTC u otra) a hora de Lima, sin zona.</summary>
    public static DateTime AHoraLima(DateTime valor) => valor.Kind switch
    {
        DateTimeKind.Utc   => TimeZoneInfo.ConvertTimeFromUtc(valor, Zona),
        DateTimeKind.Local => DateTime.SpecifyKind(TimeZoneInfo.ConvertTime(valor, Zona), DateTimeKind.Unspecified),
        _                  => valor,
    };
}

/// <summary>
/// Si un cliente envía una fecha con zona ("...Z" o "-05:00"), se convierte a hora de Lima
/// antes de llegar al caso de uso, para que se guarde igual que NOW() en MySQL.
/// Al responder, las fechas salen sin zona (hora de Lima). También aplica a DateTime?.
/// </summary>
public sealed class FechaHoraLimaJsonConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => ZonaHorariaLima.AHoraLima(reader.GetDateTime());

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
        => writer.WriteStringValue(DateTime.SpecifyKind(ZonaHorariaLima.AHoraLima(value), DateTimeKind.Unspecified));
}
