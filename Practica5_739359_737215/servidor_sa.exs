# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: servidor_sa.exs
# FECHA: 20/12/2018
# TIEMPO: 15 horas
# DESCRIPCIÓN: Servidor del sistema de almacenamiento


Code.require_file("#{__DIR__}/cliente_gv.exs")

defmodule ServidorSA do

    # estado del servidor
    defstruct   num_vista: 0,
				        base_datos: %{},     # Base de datos donde se guardan los strings con sus claves correspondientes
				        primario: :undefined,
				        copia: :undefined,
				        operaciones: []      #Lista de operaciones realizadas, con formato {id, pid_nodo}

    @intervalo_latido 50


    @doc """
        Obtener el hash de un string Elixir
            - Necesario pasar, previamente,  a formato string Erlang
         - Devuelve entero
    """
    def hash(string_concatenado) do
        String.to_charlist(string_concatenado) |> :erlang.phash2
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
  @spec startService(node, node) :: pid
  def startService(nodoSA, nodo_servidor_gv) do
    NodoRemoto.esperaNodoOperativo(nodoSA, __MODULE__)

    # Poner en marcha el código del gestor de vistas
    Node.spawn(nodoSA, __MODULE__, :init_sa, [nodo_servidor_gv])
 end

  #------------------- Funciones privadas -----------------------------

  def latidos(pid) do
  	# Indicamos la bucle principal de mandar un latido al gestor de vistas
    send(pid, :latido)
    Process.sleep(@intervalo_latido)
    latidos(pid)
  end

  def init_sa(nodo_servidor_gv) do
    Process.register(self(), :servidor_sa)
    spawn(__MODULE__,:latidos, [self()])
    #Process.register(self(), :cliente_gv)

    # Poner estado inicial
    estado = %{ num_vista: 0, primario: :undefined, copia: :undefined, base_datos: %{}, operaciones: []}

    bucle_recepcion_principal(estado, nodo_servidor_gv)
  end

  defp bucle_recepcion_principal(estado, nodo_servidor_gv ) do
    receive do
      # Recibe mensajes de lectura, escritura, latido y copia de la base de datos (si es copia)

      {:lee, param, nodo_origen, id} ->
      	IO.puts "voy a leer con id #{id}"
      	if(estado.primario == Node.self()) do	
      		# Se comprueba que la operacion no se ha realizado ya
            if(Enum.member?(estado.operaciones, {id, nodo_origen})) do
      	      # La operacion ya habia sido realizada, mandamos error
      	      send({:cliente_sa, nodo_origen},{:resultado, "ERROR"})
      	      bucle_recepcion_principal(estado, nodo_servidor_gv)
            end

			# Obtengo el valor					
            valor = Map.get(estado.base_datos, String.to_atom(param))						
            if(valor != nil) do 
				# Tiene valor asociado
                send({:cliente_sa, nodo_origen},{:resultado, valor})
            else
            	# No tiene un valor asociado
                send({:cliente_sa, nodo_origen},{:resultado, ""})
            end

            # Añado la operacion a la lista de operaciones
            estado = Map.put(estado, :operaciones, List.insert_at(estado.operaciones, length(estado.operaciones), {id,nodo_origen}))
            bucle_recepcion_principal(estado, nodo_servidor_gv)
        else 
		     # No soy el primario
            send({:cliente_sa, nodo_origen},{:resultado, :no_soy_primario_valido})
            bucle_recepcion_principal(estado, nodo_servidor_gv)
        end

      {:escribe_generico, {clave, nuevo_valor, con_hash}, nodo_origen, id}  ->
      	  IO.puts "voy a escribir con id #{id}"
      	  estado=escribe_generico_server(estado, clave, nuevo_valor, con_hash, nodo_origen, nodo_servidor_gv, id)
          bucle_recepcion_principal(estado, nodo_servidor_gv)

      {:copia_basedatos, nuevos_datos} -> 
          # Copio en mi base de datos los datos que he recibido
          estado=
          if(estado.copia== Node.self()) do
          	# Entro si soy la copia
          	estado = %{estado|base_datos: nuevos_datos}
          else
          	estado
          end
          bucle_recepcion_principal(estado, nodo_servidor_gv)

      :latido -> 
        # Se envia un latido al servidorGV
        send({:servidor_gv, nodo_servidor_gv}, {:latido, estado.num_vista, Node.self()})

        # Se obtiene la vista tentativa
        {vista, validada}=receive do 
            {:vista_tentativa, vista, encontrado?} ->
                {vista, encontrado?}

        after @intervalo_latido ->
            {ServidorGV.vista_inicial(), false}
        end

        # La vista recibida esta validada
        if (validada == true) do
          # Se actualiza el estado de este servidor
          estado = Map.put(estado, :num_vista, vista.num_vista)
          estado = Map.put(estado, :primario, vista.primario)
          estado = Map.put(estado, :copia, vista.copia)

          # Mandamos otro latido
          send({:servidor_gv, nodo_servidor_gv}, {:latido, estado.num_vista, Node.self()})
          {vista, validada}=receive do
            {:vista_tentativa, vista, encontrado?} ->
                {vista, encontrado?}

          after @intervalo_latido ->
            {ServidorGV.vista_inicial(), false}
          end
          bucle_recepcion_principal(estado, nodo_servidor_gv)

        # La vista recibida no esta validada
        else
        	# No actualizamos por si es errónea
            send({:servidor_gv, nodo_servidor_gv}, {:latido, estado.num_vista, Node.self()})
            {vista, validada}=receive do
              {:vista_tentativa, vista, encontrado?} ->
                {vista, encontrado?}

              after @intervalo_latido ->
                {ServidorGV.vista_inicial(), false}
            end
            bucle_recepcion_principal(estado, nodo_servidor_gv)
        end

    end
  end


  def escribe_generico_server(estado,clave, nuevo_valor, con_hash, nodo_origen, nodo_servidor_gv, id) do
  	estado=
  	if(estado.primario == Node.self()) do # Solo escribo si soy nodo primario

      # Se comprueba que la operacion no se ha realizado ya
      if(Enum.member?(estado.operaciones, {id, nodo_origen})) do
      	# La operacion ya habia sido realizada, mandamos error
      	send({:cliente_sa, nodo_origen},{:resultado, "ERROR"})
      	bucle_recepcion_principal(estado, nodo_servidor_gv)
      end

      # Pido el valor asociado, para saber si existe o no
      valorAsociado = Map.get(estado.base_datos, String.to_atom(clave))
      estado=
      if(valorAsociado != nil) do 
      	# Tiene un valor asociado
      	estado=
        if(con_hash == false) do
          # Se va a escribir sin hash
          nuevos_datos = Map.update(estado.base_datos, String.to_atom(clave), valorAsociado, fn valorAsociado -> nuevo_valor end)
          estado = %{estado|base_datos: nuevos_datos}
          # Copio los datos a la copia, si esta existe
          if(estado.copia != :undefined) do
            send({:servidor_sa, estado.copia},{:copia_basedatos, estado.base_datos})
          end

          # Añado la operacion a la lista de operaciones
          estado = Map.put(estado, :operaciones, List.insert_at(estado.operaciones, length(estado.operaciones), {id,nodo_origen}))

          # Envio el resultado
          send({:cliente_sa, nodo_origen},{:resultado, nuevo_valor})
          estado

        else
          #Es escritura hash con valor asociado
          	
          #Guardamos el valor en una variable para mandarlo como respuesta
          # ya que el hash modifica dicho valor
          valor_amandar = valorAsociado 

          nuevos_datos = Map.update(estado.base_datos, 
          	String.to_atom(clave), valorAsociado, fn valorAsociado ->hash(valorAsociado <> nuevo_valor) end)
          estado = %{estado|base_datos: nuevos_datos}
          # Copio los datos a la copia, si esta existe
          if(estado.copia != :undefined) do
            send({:servidor_sa, estado.copia},{:copia_basedatos, estado.base_datos})
          end

          # Añado la operacion a la lista de operaciones
          estado = Map.put(estado, :operaciones, List.insert_at(estado.operaciones, length(estado.operaciones), {id,nodo_origen}))

          # Envio el resultado
          send({:cliente_sa, nodo_origen},{:resultado, valor_amandar})
          estado
        end
        estado

      # No tiene un valor asociado
      else
        estado=
        if(con_hash == false) do
          # Se va a escribir sin hash
          nuevos_datos = Map.merge(estado.base_datos, Map.new([{String.to_atom(clave), nuevo_valor}]))
          estado = %{estado|base_datos: nuevos_datos}

          # Copio los datos a la copia, si esta existe
          if(estado.copia != :undefined) do
            send({:servidor_sa, estado.copia},{:copia_basedatos, estado.base_datos})
          end

          # Añado la operacion a la lista de operaciones
          estado = Map.put(estado, :operaciones, List.insert_at(estado.operaciones, length(estado.operaciones), {id,nodo_origen}))

          # Envio el resultado
          send({:cliente_sa, nodo_origen},{:resultado, nuevo_valor})
          estado
        else 
		  # Es escritura hash
          nuevos_datos = Map.merge(estado.base_datos, Map.new([{String.to_atom(clave), hash("" <> nuevo_valor)}]))
          estado = %{estado|base_datos: nuevos_datos}

          # Copio los datos a la copia, si esta existe
          if(estado.copia != :undefined) do
            send({:servidor_sa, estado.copia},{:copia_basedatos, estado.base_datos})
          end

          # Añado la operacion a la lista de operaciones
          estado = Map.put(estado, :operaciones, List.insert_at(estado.operaciones, length(estado.operaciones), {id,nodo_origen}))

          # Envio el resultado
          send({:cliente_sa, nodo_origen},{:resultado, ""})
          estado
        end
        estado
       end
       estado

    else
      send({:cliente_sa, nodo_origen},{:resultado, :no_soy_primario_valido})
      estado
    end
    estado
  end

end
