using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>HU-07 — Validaciones de forma; las de negocio (estado, totales, equipos) están en el SP.</summary>
public class GuardarPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    private static readonly string[] SeccionesItem   = ["principal", "opcional"];
    private static readonly string[] SeccionesTexto  = ["detalle", "recomendaciones", "suministros_cliente", "condiciones"];
    private static readonly string[] TiposTexto      = ["titulo", "vineta"];
    private static readonly string[] UnidadesPlazo   = ["dias_habiles", "dias_calendario"];

    public async Task<RespuestaDto<GuardarPropuestaResultadoDto>> EjecutarAsync(
        GuardarPropuestaDto dto, long idUsuario, CancellationToken ct = default)
    {
        string? error = Validar(dto);
        if (error is not null)
            return new RespuestaDto<GuardarPropuestaResultadoDto>(1, error);

        // Normalización
        foreach (var i in dto.Items)  i.Seccion = i.Seccion?.Trim().ToLowerInvariant() ?? "principal";
        foreach (var t in dto.Textos) { t.Seccion = t.Seccion!.Trim().ToLowerInvariant(); t.Tipo = t.Tipo?.Trim().ToLowerInvariant() ?? "vineta"; }

        return await repositorio.GuardarPropuestaAsync(dto, idUsuario, ct);
    }

    private static string? Validar(GuardarPropuestaDto dto)
    {
        if (dto.IdRequerimiento <= 0)
            return "Indique el requerimiento de origen.";

        if (dto.EsTercerizado)
        {
            if (string.IsNullOrWhiteSpace(dto.TerceroRuc) || !Regex.IsMatch(dto.TerceroRuc.Trim(), @"^\d{11}$"))
                return "El RUC del tercero debe tener 11 dígitos.";
            if (string.IsNullOrWhiteSpace(dto.TerceroRazonSocial))
                return "Indique la razón social del titular del certificado.";
        }

        if (dto.TipoCambio is <= 0)
            return "El tipo de cambio debe ser mayor a cero.";

        if (dto.DescuentoPct is < 0 or > 100)
            return "El porcentaje de descuento debe estar entre 0 y 100.";

        if (dto.DescuentoMonto is < 0 || dto.DescuentoOpcionales is < 0)
            return "Los descuentos no pueden ser negativos.";

        if (!string.IsNullOrWhiteSpace(dto.PlazoEntregaUnidad) && !UnidadesPlazo.Contains(dto.PlazoEntregaUnidad))
            return "La unidad del plazo de entrega no es válida.";

        foreach (var i in dto.Items)
        {
            if (!string.IsNullOrWhiteSpace(i.Seccion) && !SeccionesItem.Contains(i.Seccion.Trim().ToLowerInvariant()))
                return $"Sección de ítem no válida: '{i.Seccion}'.";
            if (i.EsEspaciado) continue;
            if (string.IsNullOrWhiteSpace(i.Descripcion))
                return "Todos los ítems deben tener descripción.";
            if (i.Cantidad <= 0 || i.Frecuencia <= 0)
                return $"La cantidad y la frecuencia deben ser mayores a cero ('{i.Descripcion}').";
            if (i.PrecioUnitario < 0 || i.Descuento < 0)
                return $"El precio y el descuento no pueden ser negativos ('{i.Descripcion}').";
            if (i.Descuento > i.Cantidad * i.Frecuencia * i.PrecioUnitario)
                return $"El descuento supera el importe del ítem ('{i.Descripcion}').";
        }

        foreach (var t in dto.Textos)
        {
            if (string.IsNullOrWhiteSpace(t.Seccion) || !SeccionesTexto.Contains(t.Seccion.Trim().ToLowerInvariant()))
                return $"Sección de texto no válida: '{t.Seccion}'.";
            if (!string.IsNullOrWhiteSpace(t.Tipo) && !TiposTexto.Contains(t.Tipo.Trim().ToLowerInvariant()))
                return $"Tipo de texto no válido: '{t.Tipo}' (use 'titulo' o 'vineta').";
        }

        foreach (var f in dto.FormasPago)
        {
            if (f.Porcentaje <= 0 || f.Porcentaje > 100)
                return "Cada forma de pago debe tener un porcentaje entre 1 y 100.";
            if (string.IsNullOrWhiteSpace(f.Condicion))
                return "Cada forma de pago debe indicar su condición.";
        }

        foreach (var e in dto.Equipos.Where(e => e.IdEquipo is null && e.Id is null))
        {
            if (string.IsNullOrWhiteSpace(e.NumSerie) || string.IsNullOrWhiteSpace(e.Marca) || string.IsNullOrWhiteSpace(e.Modelo))
                return "Los equipos ingresados manualmente requieren número de serie, marca y modelo.";
        }

        return null;
    }
}
