# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: servidor_gv.exs
# FECHA: 1/12/2018
# TIEMPO: 15 horas
# DESCRIPCIÓN: Fichero del servidor, en el que se define la estructura de la vista,
#              se reciben los latidos y mensajes de los demás nodos, y se procesa
#              la situación de los servidores actuales.

require IEx # Para utilizar IEx.pry

defmodule ServidorGV do
    @moduledoc """
        modulo del servicio de vistas
    """

    # Tipo estructura de datos que guarda el estado del servidor de vistas
    # COMPLETAR  con lo campos necesarios para gestionar
    # el estado del gestor de vistas
    defstruct  num_vista: 0, primario: :undefined, copia: :undefined, 
               primario_fallos: 0, copia_fallos: 0, vistaValida: :undefined,
               lista_espera: []

    # Constantes
    @latidos_fallidos 4

    @intervalo_latidos 50


    @doc """
        Acceso externo para constante de latidos fallios
    """
    def latidos_fallidos() do
        @latidos_fallidos
    end

    @doc """
        acceso externo para constante intervalo latido
    """
   def intervalo_latidos() do
       @intervalo_latidos
   end

   @doc """
        Generar un estructura de datos vista inicial
    """
    def vista_inicial() do
        %{num_vista: 0, primario: :undefined, copia: :undefined, 
           primario_fallos: 0, copia_fallos: 0, vistaValida: :undefined, lista_espera: []}
    end

    @doc """
        Poner en marcha el servidor para gestión de vistas
        Devolver atomo que referencia al nuevo nodo Elixir
    """
    @spec startNodo(String.t, String.t) :: node
    def startNodo(nombre, maquina) do
                                         # fichero en curso
        NodoRemoto.start(nombre, maquina, __ENV__.file)
    end

    @doc """
        Poner en marcha servicio trás esperar al pleno funcionamiento del nodo
    """
    @spec startService(node) :: boolean
    def startService(nodoElixir) do
        NodoRemoto.esperaNodoOperativo(nodoElixir, __MODULE__)
        
        # Poner en marcha el código del gestor de vistas
        Node.spawn(nodoElixir, __MODULE__, :init_sv, [])
   end

    #------------------- FUNCIONES PRIVADAS ----------------------------------

    # Estas 2 primeras deben ser defs para llamadas tipo (MODULE, funcion,[])
    def init_sv() do
        Process.register(self(), :servidor_gv)

        spawn(__MODULE__, :init_monitor, [self()]) # otro proceso concurrente

        vista = vista_inicial()

        bucle_recepcion(vista)
    end

    def init_monitor(pid_principal) do
        send(pid_principal, {:procesa_situacion_servidores})
        Process.sleep(@intervalo_latidos)
        init_monitor(pid_principal)
    end


    defp bucle_recepcion(vista) do
        vista_dos = receive do
                    {:latido, n_vista_latido, nodo_emisor} ->
                      vista_latido(vista, n_vista_latido, nodo_emisor)
                
                    {:obten_vista, pid} ->
                      if (vista.vistaValida != :undefined and vista.vistaValida != :error) do
                        send(pid,{:vista_valida, vista.vistaValida ,true})
                      else
                        send(pid,{:vista_valida, vista.vistaValida ,false})
                      end
                      vista               

                    {:procesa_situacion_servidores} ->
                      vista=procesarSituacion_servidores(vista)
                      vista

        end

        bucle_recepcion(vista_dos)
    end


    defp vista_latido(vista, n_vista_latido, nodo_emisor) do

      if(vista.primario == :error) do
        send({:cliente_gv,nodo_emisor}, {:vista_tentativa, %{num_vista: vista.num_vista,
                            primario: :error, copia: :error}, true})
        bucle_recepcion(vista)
      end
      # Para saber luego si primario falla.
      vista=
      if (vista.primario == nodo_emisor) do
        vista = Map.put(vista, :primario_fallos, 0)
        vista
      else
        vista
      end

      # Para saber luego si copia falla.
      vista=
      if (vista.copia == nodo_emisor) do
        vista = Map.put(vista, :copia_fallos, 0)
        vista
      else
        vista
      end

      # Si no hay primario se introduce el primer nodo que llega.
      vista =
      if (vista.primario == :undefined) do
        vista = Map.put(vista, :primario, nodo_emisor)
        vista = Map.put(vista, :num_vista, vista.num_vista + 1)
        vista
      else
        # Si no hay copia se introduce el primer nodo que llega y que no sea el mismo que el primario.
        vista=
        if (vista.copia == :undefined && vista.primario != nodo_emisor) do
            vista = Map.put(vista, :copia, nodo_emisor)
            vista = Map.put(vista, :num_vista, vista.num_vista + 1)
            vista
        else
            #Se introduce el nodo en pendientes
            lista=vista.lista_espera
            vista=
            if(vista.primario != nodo_emisor && vista.copia != nodo_emisor && !Enum.member?(lista, nodo_emisor)) do
              vista= Map.put(vista, :lista_espera, List.insert_at(vista.lista_espera, length(vista.lista_espera), nodo_emisor))
              vista
            else
              vista
            end
            vista
        end
        vista
      end


      # Paso a de tentativa a válida.
      vista=
      if(vista.primario != :undefined && vista.copia != :undefined) do
        vista=
        if(vista.primario == nodo_emisor && vista.num_vista == n_vista_latido) do
          vista = Map.put(vista, :vistaValida, %{num_vista: vista.num_vista, primario: vista.primario, copia: vista.copia})
          vista
        else
          vista
        end
        vista
      else
        vista
      end

      send({:cliente_gv,nodo_emisor}, {:vista_tentativa, %{num_vista: vista.num_vista,
                            primario: vista.primario, copia: vista.copia}, true})
      vista
    end 




    
    defp procesarSituacion_servidores(vista) do
      # Si no hay primario no hay vista.
    
      vista=
      if (vista.primario != :undefined) do
        vista = Map.put(vista, :primario_fallos, vista.primario_fallos + 1)


        vista=
        if (vista.copia != :undefined) do
          vista=
            if(vista.vistaValida.num_vista == vista.num_vista) do
              vista = Map.put(vista, :copia_fallos, vista.copia_fallos + 1)
              vista
            else
              vista = Map.put(vista, :primario, :error)
              vista = Map.put(vista, :copia, :error)
              vista = Map.put(vista, :vistaValida, %{num_vista: vista.num_vista, primario: :error, copia: :error})
              vista
            end
            vista
        else
          vista
        end
  
        fallo_primario = vista.primario_fallos == @latidos_fallidos
        fallo_copia = vista.copia_fallos == @latidos_fallidos

        # Fallan los dos.
        vista=
        if (fallo_primario && fallo_copia) do
          #vista = vista_inicial()
          vista = Map.put(vista, :primario, :error)
          vista = Map.put(vista, :copia, :error)
          vista = Map.put(vista, :vistaValida, %{num_vista: vista.num_vista, primario: :error, copia: :error})
          vista
        else
          vista
        end
          
        # Falla el primario pero la copia no.  
        vista=
        if (fallo_primario && !fallo_copia) do
          vista = Map.put(vista, :primario, vista.copia)
          lista = List.pop_at(vista.lista_espera, 0, :undefined)
          vista = Map.put(vista, :copia, lista |> elem(0))
          vista = Map.put(vista, :lista_espera, lista |> elem(1))
          vista = Map.put(vista, :num_vista, vista.num_vista + 1)
          vista = Map.put(vista, :primario_fallos, vista.copia_fallos)
          vista = Map.put(vista, :copia_fallos, 0)
          vista
        else
          vista
        end

        # No falla el primario pero la copia si.
        vista=
        if (!fallo_primario && fallo_copia) do
          lista = List.pop_at(vista.lista_espera, 0, :undefined)
          vista = Map.put(vista, :copia, lista |> elem(0))
          vista = Map.put(vista, :lista_espera, lista |> elem(1))
          vista = Map.put(vista, :num_vista, vista.num_vista + 1)
          vista = Map.put(vista, :copia_fallos, 0)
          vista
        else
          vista
        end
        vista

      else
        vista
      end  
      vista
  end

end
