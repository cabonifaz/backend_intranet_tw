using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-53 Registro operativo del Asistente (Sprint 5). Todo pasa por SPs parametrizados.</summary>
public class RegistroAsistenteRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IRegistroAsistenteRepositorio
{
    public Task<RespuestaDto<FormularioRegistroAsistenteDto>> ObtenerFormularioAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerFormularioRegistroServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<FormularioRegistroAsistenteDto>(3, "El procedimiento no devolvió el contexto.");
                var ctx = new ContextoRegistroAsistenteDto(Texto(r, "RegistrandoComo") ?? "", Texto(r, "HoraActual") ?? "", Texto(r, "Numero") ?? "", Texto(r, "Tecnico"),
                    Texto(r, "EstadoActual") ?? "", Entero(r, "NivelActual"), Booleano(r, "PuedeRegistrar"));

                await r.NextResultAsync(ct);
                var tipos = new List<OpcionRegistroAsistenteDto>();
                while (await r.ReadAsync(ct))
                    tipos.Add(new OpcionRegistroAsistenteDto(Entero(r, "IdTipo"), Texto(r, "Nombre") ?? "", Texto(r, "Codigo") ?? ""));

                await r.NextResultAsync(ct);
                var motivos = new List<OpcionRegistroAsistenteDto>();
                while (await r.ReadAsync(ct))
                    motivos.Add(new OpcionRegistroAsistenteDto(Entero(r, "IdMotivo"), Texto(r, "Nombre") ?? "", Texto(r, "Codigo") ?? ""));

                await r.NextResultAsync(ct);
                var estados = new List<EstadoRegistroAsistenteDto>();
                while (await r.ReadAsync(ct))
                    estados.Add(new EstadoRegistroAsistenteDto(Texto(r, "Codigo") ?? "", Texto(r, "Nombre") ?? "", Entero(r, "Nivel"), Booleano(r, "Permitido")));

                await r.NextResultAsync(ct);
                var eventos = new List<EventoVinculableDto>();
                while (await r.ReadAsync(ct))
                    eventos.Add(new EventoVinculableDto(Texto(r, "Clave") ?? "", Texto(r, "Hora") ?? "", Texto(r, "Titulo") ?? ""));

                await r.NextResultAsync(ct);
                var mios = new List<MiRegistroAsistenteDto>();
                while (await r.ReadAsync(ct))
                    mios.Add(new MiRegistroAsistenteDto(EnteroLargo(r, "IdRegistro"), Texto(r, "Modo") ?? "", Texto(r, "Hora") ?? "", Texto(r, "Texto") ?? "",
                        Texto(r, "Fuente"), Texto(r, "Badge") ?? "", Entero(r, "HaceMin")));

                return new RespuestaDto<FormularioRegistroAsistenteDto>(2, mensaje, new FormularioRegistroAsistenteDto(ctx, tipos, motivos, estados, eventos, mios));
            },
            ct);

    public Task<RespuestaDto<RegistroAsistenteCreadoDto>> RegistrarAsync(long idUsuario, long idOs, RegistroAsistenteNormalizado d, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarAsistenteServicioRuta",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_modo", d.Modo);
                p.AddWithValue("p_descripcion", Valor(d.Descripcion));
                p.AddWithValue("p_fuente", Valor(d.Fuente));
                p.AddWithValue("p_vinculo", Valor(d.Vinculo));
                p.AddWithValue("p_id_tipo", Valor(d.IdTipo));
                p.AddWithValue("p_duracion", Valor(d.DuracionMin));
                p.AddWithValue("p_impacto", Valor(d.Impacto));
                p.AddWithValue("p_evidencia", Valor(d.EvidenciaUrl));
                p.AddWithValue("p_nuevo_estado", Valor(d.NuevoEstado));
                p.AddWithValue("p_id_motivo", Valor(d.IdMotivo));
                p.AddWithValue("p_comentario", Valor(d.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RegistroAsistenteCreadoDto>(3, "El procedimiento no devolvió el registro creado.");
                return new RespuestaDto<RegistroAsistenteCreadoDto>(2, mensaje,
                    new RegistroAsistenteCreadoDto(EnteroLargo(r, "IdRegistro"), Texto(r, "Modo") ?? "", Entero(r, "Notificados"), Texto(r, "EstadoNuevo")));
            },
            ct);
}
