using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>Cartera de clientes: el administrador ve todos; el comercial solo los suyos.</summary>
public class ObtenerCarteraClientesCasoDeUso(ICarteraClientesRepositorio repositorio)
{
    public Task<RespuestaDto<CarteraClientesDto>> EjecutarAsync(FiltrosCarteraClientesDto filtros, long idUsuario, CancellationToken ct = default)
        => repositorio.ObtenerAsync(filtros, idUsuario, ct);
}

/// <summary>Asigna (o quita) clientes de la cartera de un comercial. Solo el Administrador.</summary>
public class AsignarCarteraClientesCasoDeUso(ICarteraClientesRepositorio repositorio)
{
    public const int MaximoClientes = 500;

    public async Task<RespuestaDto<int>> EjecutarAsync(AsignarCarteraClientesComandoDto comando, long idUsuario, CancellationToken ct = default)
    {
        var ids = (comando.IdsClientes ?? []).Where(i => i > 0).Distinct().ToList();
        if (ids.Count == 0)             return new(1, "Seleccione al menos un cliente.");
        if (ids.Count > MaximoClientes) return new(1, $"Máximo {MaximoClientes} clientes por asignación.");
        return await repositorio.AsignarAsync(comando with { IdsClientes = ids }, idUsuario, ct);
    }
}
