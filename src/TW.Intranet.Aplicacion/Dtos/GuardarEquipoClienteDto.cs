namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/equipos. IdEquipo = 0 para crear.</summary>
public class GuardarEquipoClienteDto
{
    public long    IdEquipo       { get; set; }
    public string? NumSerie       { get; set; }
    public long    IdCliente      { get; set; }
    public long    IdSede         { get; set; }
    public string? CodigoCliente  { get; set; }
    /// <summary>equipo | instrumento | pesa. Define qué campos de la sección 2 se guardan.</summary>
    public string? Clasificacion  { get; set; }
    /// <summary>Opcional: si no se envía se toma del suministro (o "Genérico"). En edición no cambia.</summary>
    public string? Marca          { get; set; }
    /// <summary>Opcional: igual que Marca.</summary>
    public string? Modelo         { get; set; }

    public string? UbicacionEspecifica    { get; set; }
    public bool    EsPreRevisado          { get; set; }
    public bool    BloqueadoParaServicios { get; set; }

    public long?   IdSuministro       { get; set; }
    public string? DivisionMinima     { get; set; }
    public string? DivisionVerif      { get; set; }
    public bool    DivisionVerifIgual { get; set; } = true;
    public string? ClaseExactitud     { get; set; }
    public string? AlcanceMaximo      { get; set; }
    public string? EscalaGraduacion   { get; set; }
    public string? PuntosCalibracion  { get; set; }
    public string? RangoOperativoReal { get; set; }
    /// <summary>Solo pesas.</summary>
    public string? Material           { get; set; }
    /// <summary>Solo pesas (ej. "20 kg").</summary>
    public string? ValorNominal       { get; set; }
    public string? Observaciones      { get; set; }

    public string? EstadoOperativo { get; set; }
    public bool    EsActivo        { get; set; } = true;

    public bool GuardarComoBorrador { get; set; }
}
