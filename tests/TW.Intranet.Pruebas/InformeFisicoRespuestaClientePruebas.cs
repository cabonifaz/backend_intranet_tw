using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de la respuesta del cliente: guarda lo que recibe.</summary>
internal sealed class RespuestaClienteRepoFalso : IProgramacionDetalleRepositorio
{
    public NuevaRespuestaCliente? Recibida { get; private set; }
    public int Llamadas { get; private set; }

    public Task<RespuestaDto<DetalleProgramacionDto>> ObtenerDetalleAsync(long idProgramacion, long idUsuario, CancellationToken ct) => throw new NotSupportedException();

    public Task<RespuestaDto<RespuestaClienteRegistradaDto>> RegistrarRespuestaClienteAsync(NuevaRespuestaCliente respuesta, long idUsuario, CancellationToken ct)
    {
        Llamadas++;
        Recibida = respuesta;
        return Task.FromResult(new RespuestaDto<RespuestaClienteRegistradaDto>(2, "OK",
            new RespuestaClienteRegistradaDto(1, respuesta.IdProgramacion, "PR-1", "confirmada", "Programado", respuesta.Canal, respuesta.Resultado, respuesta.Comentario, 7, "OS-000007",
                "gestionar_viaticos", true, false, false, [], respuesta.InformeFisico)));
    }
}

/// <summary>«¿El servicio tendrá informe físico?» en la respuesta del cliente (HU-37): solo cuenta con «Aceptó»; sin dato se toma como SÍ.</summary>
public class InformeFisicoRespuestaClientePruebas
{
    private static async Task<(NuevaRespuestaCliente? Recibida, RespuestaDto<RespuestaClienteRegistradaDto> Respuesta)> Registrar(RegistrarRespuestaClienteDto d)
    {
        var repo = new RespuestaClienteRepoFalso();
        var r = await new RegistrarRespuestaClienteCasoDeUso(repo).EjecutarAsync(10, d, 5);
        return (repo.Recibida, r);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Al_aceptar_se_envia_lo_que_el_usuario_eligio(bool informeFisico)
    {
        var (recibida, r) = await Registrar(new RegistrarRespuestaClienteDto { Canal = "correo", Resultado = "acepto", InformeFisico = informeFisico });

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(informeFisico, recibida!.InformeFisico);
        Assert.Equal(informeFisico, r.Datos!.InformeFisico);
    }

    [Fact]
    public async Task Al_aceptar_sin_dato_se_toma_como_si()
    {
        var (recibida, _) = await Registrar(new RegistrarRespuestaClienteDto { Canal = "llamada", Resultado = "acepto" });

        Assert.True(recibida!.InformeFisico);
    }

    [Theory]
    [InlineData("pidio_reprogramar")]
    [InlineData("cancelo")]
    public async Task Con_otras_respuestas_el_informe_fisico_se_descarta(string resultado)
    {
        var (recibida, r) = await Registrar(new RegistrarRespuestaClienteDto { Canal = "whatsapp", Resultado = resultado, InformeFisico = false });

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Null(recibida!.InformeFisico);
    }

    [Fact]
    public async Task Sin_canal_o_resultado_no_llega_al_repositorio()
    {
        var repo = new RespuestaClienteRepoFalso();
        var r = await new RegistrarRespuestaClienteCasoDeUso(repo).EjecutarAsync(10, new RegistrarRespuestaClienteDto { Resultado = "acepto", InformeFisico = false }, 5);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public void La_cabecera_de_evidencias_asume_informe_fisico_si_no_se_indica()
    {
        var c = new CabeceraEvidenciasMovilDto(1, 2, "OS-1", "Balanza", 1, null, null, null, null, null, null, "en_ejecucion", true, null, 9, 0, 0, 0, 2, false);

        Assert.True(c.InformeFisico);
        Assert.False((c with { InformeFisico = false }).InformeFisico);
    }
}
