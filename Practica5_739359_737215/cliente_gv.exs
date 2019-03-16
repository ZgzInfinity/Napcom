# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: cliente_gv.exs
# FECHA: 20/12/2018
# TIEMPO: 15 horas
# DESCRIPCIÓN: Cliente del gestor de vistas
#              Se ha añadido la función de devolver el nodo copia

Code.require_file("#{__DIR__}/servidor_gv.exs")

defmodule ClienteGV do

    @tiempo_espera_de_respuesta 150


    @doc """
        Solicitar al cliente que envie un ping al servidor de vistas
    """
    @spec latido(node, integer) :: ServidorGV.t_vista
    def latido(nodo_servidor_gv, num_vista) do
        send({:servidor_gv, nodo_servidor_gv}, {:latido, num_vista, Node.self()})

        receive do   # esperar respuesta del ping
            {:vista_tentativa, vista, encontrado?} ->
                IO.puts "he recibido"
                {:vista_tentativa, vista, encontrado?}

        after @tiempo_espera_de_respuesta ->
            {:vista_tentativa, ServidorGV.vista_inicial(), false}
        end
    end

    def init() do
        
    end


    @doc """
        Solicitar al cliente que envie una petición de obtención de vista válida
    """
    @spec obten_vista(node) :: {ServidorGV.t_vista, boolean}
    def obten_vista(nodo_servidor_gv) do
       send({:servidor_gv, nodo_servidor_gv}, {:obten_vista, self()})

        receive do   # esperar respuesta del ping
            {:vista_valida, vista, is_ok?} -> {vista, is_ok?}

        after @tiempo_espera_de_respuesta  ->
            {:vista_valida, ServidorGV.vista_inicial(), false}
        end
    end


    @doc """
        Solicitar al cliente que consiga el primario del servicio de vistas
    """
    @spec primario(node) :: node
    def primario(nodo_servidor_gv) do
        resultado = obten_vista(nodo_servidor_gv)

        case resultado do
            {vista, true} ->  vista.primario

            {_vista, false} -> :undefined
        end
    end


    @doc """
        Solicitar al cliente que consiga la copia del servicio de vistas
    """
    @spec copia(node) :: node
    def copia(nodo_servidor_gv) do
        resultado = obten_vista(nodo_servidor_gv)

        case resultado do
            {vista, true} ->  vista.copia

            {_vista, false} -> :undefined
        end
    end
end
