namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/equipos. IdEquipo = 0 para crear.</summary>
public class GuardarEquipoClienteDto
{
    public long    IdEquipo       { get; set; }
    public string? NumSerie       { get; set; }
    public long    IdCliente      { get; set; }
    public long    IdSede         { get; set; }
    public string? CodigoCliente  { get; set; }
    public string? Clasificacion  { get; set; }
    public string? Marca          { get; set; }
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
    public string? Observaciones      { get; set; }

    public string? EstadoOperativo { get; set; }
    public bool    EsActivo        { get; set; } = true;

    public bool GuardarComoBorrador { get; set; }
}
