# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: servicio_almacenamiento_tests.exs
# FECHA: 20/12/2018
# TIEMPO: 15 horas
# DESCRIPCIÓN: Tests del servicio de almacenamiento


Code.require_file("#{__DIR__}/nodo_remoto.exs")
Code.require_file("#{__DIR__}/servidor_gv.exs")
Code.require_file("#{__DIR__}/cliente_gv.exs")
Code.require_file("#{__DIR__}/servidor_sa.exs")
Code.require_file("#{__DIR__}/cliente_sa.exs")

#Poner en marcha el servicio de tests unitarios con tiempo de vida limitada
# seed: 0 para que la ejecucion de tests no tenga orden aleatorio
ExUnit.start([timeout: 20000, seed: 0, exclude: [:deshabilitado]]) # milisegundos

defmodule  ServicioAlmacenamientoTest do

    use ExUnit.Case

    # @moduletag timeout 100  para timeouts de todos lo test de este modulo

    @maquinas ["127.0.0.1", "127.0.0.1", "127.0.0.1","127.0.0.1"]
    # @maquinas ["155.210.154.192", "155.210.154.193", "155.210.154.194"]

    #@latidos_fallidos 4

    #@intervalo_latido 50


    #setup_all do

  # Test 1
  #@tag :deshabilitado
  test "Test 1: solo_arranque y parada" do
    IO.puts("Test: Solo arranque y parada ...")


    # Poner en marcha nodos, clientes, servidores alm., en @maquinas
    mapNodos = startServidores(["ca1"], ["sa1"], @maquinas)

    Process.sleep(300)

    # Parar todos los nodos y epmds
    stopServidores(mapNodos, @maquinas)

    IO.puts(" ... Superado")
  end

  # Test 2
  #@tag :deshabilitado
  test "Test 2: Algunas escrituras" do
    #:io.format "Pids de nodo MAESTRO ~p: principal = ~p~n", [node, self]

    #Process.flag(:trap_exit, true)

    # Para que funcione bien la función  ClienteGV.obten_vista
    Process.register(self(), :servidor_sa)

    # Arrancar nodos : 1 GV, 3 servidores y 1 cliente de almacenamiento
    mapa_nodos = startServidores(["ca1"], ["sa1", "sa2", "sa3"], @maquinas)

    # Espera configuracion y relacion entre nodos
    Process.sleep(200)

    IO.puts("Test: Comprobar escritura con primario, copia y espera ...")

    # Comprobar primeros nodos primario y copia
    {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
    assert p == mapa_nodos.sa1
    assert c == mapa_nodos.sa2

    ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 1)
    ClienteSA.escribe(mapa_nodos.ca1, "b", "bb", 2)
    ClienteSA.escribe(mapa_nodos.ca1, "c", "cc", 3)
    comprobar(mapa_nodos.ca1, "a", "aa", 4)
    comprobar(mapa_nodos.ca1, "b", "bb", 5)
    comprobar(mapa_nodos.ca1, "c", "cc", 6)

    IO.puts(" ... Superado")

    IO.puts("Test: Comprobar escritura despues de fallo de nodo copia ...")

    # Provocar fallo de nodo copia y seguido realizar una escritura
    {%{copia: nodo_copia},_} = ClienteGV.obten_vista(mapa_nodos.gv)
    NodoRemoto.stop(nodo_copia) # Provocar parada nodo copia

    Process.sleep(700) # esperar a reconfiguracion de servidores

    ClienteSA.escribe(mapa_nodos.ca1, "a", "aaa", 7)
    comprobar(mapa_nodos.ca1, "a", "aaa", 8)

    # Comprobar los nuevo nodos primario y copia
    {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
    assert p == mapa_nodos.sa1
    assert c == mapa_nodos.sa3

    IO.puts(" ... Superado")

    # Parar todos los nodos y epmds
    stopServidores(mapa_nodos, @maquinas)
  end

  # Test 3
  #@tag :deshabilitado
  test "Test 3 : Mismos valores concurrentes" do
    IO.puts("Test: Escrituras mismos valores clientes concurrentes ...")

    # Para que funcione bien la función  ClienteGV.obten_vista
    Process.register(self(), :servidor_sa)

    # Arrancar nodos : 1 GV, 3 servidores y 3 cliente de almacenamiento
    mapa_nodos = startServidores(["ca1", "ca2", "ca3"],
                                 ["sa1", "sa2", "sa3"],
                                 @maquinas)

    # Espera configuracion y relacion entre nodos
    Process.sleep(200)

    # Comprobar primeros nodos primario y copia
    {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
    assert p == mapa_nodos.sa1
    assert c == mapa_nodos.sa2

    # Escritura concurrente de mismas 2 claves, pero valores diferentes
    # Posteriormente comprobar que estan igual en primario y copia
    escritura_concurrente(mapa_nodos, 5)

    Process.sleep(200)

    #Obtener valor de las clave "0" y "1" con el primer primario
    valor1primario = ClienteSA.lee(mapa_nodos.ca1, "0", 1)
    valor2primario = ClienteSA.lee(mapa_nodos.ca3, "1", 2)

    # Forzar parada de primario
    NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

    # Esperar detección fallo y reconfiguración copia a primario
    Process.sleep(700)

    # Obtener valor de clave "0" y "1" con segundo primario (copia anterior)
    valor1copia = ClienteSA.lee(mapa_nodos.ca3, "0", 3)
    valor2copia = ClienteSA.lee(mapa_nodos.ca2, "1", 4)

    IO.puts "valor1primario = #{valor1primario}, valor1copia = #{valor1copia}"
        <> "valor2primario = #{valor2primario}, valor2copia = #{valor2copia}"
    # Verificar valores obtenidos con primario y copia inicial
    assert valor1primario == valor1copia
    assert valor2primario == valor2copia

    # Parar todos los nodos y epmds
    stopServidores(mapa_nodos, @maquinas)

    IO.puts(" ... Superado")
  end


  # Test 4 : Escrituras concurrentes y comprobación de consistencia
  #         tras caída de primario y copia.
  #         Se puede gestionar con cuatro nodos o con el primario rearrancado.
  #@tag :deshabilitado
  test "Test 4 : Escrituras concurrentes y comprobacion consistencia" do
    IO.puts("Test: Escrituras concurrentes y comprobación de consistencia...")

    # Para que funcione bien la función  ClienteGV.obten_vista
    Process.register(self(), :servidor_sa)

    # Arrancar nodos : 1 GV, 4 servidores y 4 cliente de almacenamiento
    mapa_nodos = startServidores(["ca1", "ca2", "ca3", "ca4"],
                                 ["sa1", "sa2", "sa3", "sa4"],
                                  @maquinas)

    # Espera configuracion y relacion entre nodos
    Process.sleep(200)

    # Comprobar primeros nodos primario y copia
    {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
    assert p == mapa_nodos.sa1
    assert c == mapa_nodos.sa2


    # Escritura concurrente de mismas 2 claves, pero valores diferentes
    # Posteriormente comprobar que estan igual en primario y copia
    escritura_concurrente(mapa_nodos, 7)


    #Obtener valor de las clave "0" y "1" con el primer primario
    valor1primario = ClienteSA.lee(mapa_nodos.ca1, "0", 1)
    valor2primario = ClienteSA.lee(mapa_nodos.ca3, "1", 2)


    # Parada de primario
    NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

    # Esperar detección fallo y reconfiguración copia a primario
    Process.sleep(700)


    # Obtener valor de clave "0" y "1" con segundo primario (copia anterior)
    valor1copia = ClienteSA.lee(mapa_nodos.ca3, "0", 3)
    valor2copia = ClienteSA.lee(mapa_nodos.ca2, "1", 4)

    IO.puts "valor1primario = #{valor1primario}, valor1copia = #{valor1copia}"
              <> "valor2primario = #{valor2primario}, valor2copia = #{valor2copia}"
    # Verificar valores obtenidos con primario y copia inicial
    assert valor1primario == valor1copia
    assert valor2primario == valor2copia

    # Paramos el nuevo primario
    NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

    Process.sleep(700) #Espero deteccion fallo y reconfiguracion copia a primario

    valor1espera = ClienteSA.lee(mapa_nodos.ca2, "0", 5)
    valor2espera = ClienteSA.lee(mapa_nodos.ca4, "1", 6)

    IO.puts "valor1primario = #{valor1primario}, valor1copia = #{valor1espera}"
              <> "valor2primario = #{valor2primario}, valor2copia = #{valor2espera}"

    # Verificar valores obtenidos con primario y nodos_espera
    assert valor1primario == valor1copia
    assert valor2primario == valor2copia

    # Parar todos los nodos y epmds
    stopServidores(mapa_nodos, @maquinas)

    IO.puts(" ... Superado")
  end

  # Test 5 : Petición de escritura inmediatamente después de la caída de nodo
  #         copia (con uno en espera que le reemplace).
  #@tag :deshabilitado
  test "Test 5 : Peticion escritura inmediatamente despues de caida del nodo copia" do
    IO.puts("Test: Peticion escritura inmediatamente despues de caida del nodo copia")

    # Para que funcione bien la función  ClienteGV.obten_vista
    Process.register(self(), :servidor_sa)

    # Arrancar nodos : 1 GV, 3 servidores y 3 cliente de almacenamiento
    mapa_nodos = startServidores(["ca1", "ca2", "ca3"],
                                 ["sa1", "sa2", "sa3",],
                                 @maquinas)

    # Espera configuracion y relacion entre nodos
    Process.sleep(200)

    # Comprobar primeros nodos primario y copia
    {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
    assert p == mapa_nodos.sa1
    assert c == mapa_nodos.sa2

    #Escritura pre-caida
    ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 1)

    #Tiramos el nodo copia
    NodoRemoto.stop(ClienteGV.copia(mapa_nodos.gv))
    IO.inspect Node.ping(mapa_nodos.sa2)

    #Esperamos que el gestor de vistas detecte que se ha caido
    Process.sleep(700)


    #Intentamos escritura post-caida 
    ClienteSA.escribe(mapa_nodos.ca1, "b", "bb", 2)

    #Leemos
    comprobar(mapa_nodos.ca1, "a", "aa", 3)

    # Parar todos los nodos y epmds
    stopServidores(mapa_nodos, @maquinas)

    IO.puts(" ... Superado")
  end
    


  # Test 6 : Petición de escritura duplicada por perdida de respuesta
  #         (modificación realizada en BD), con primario y copia.
  #@tag :deshabilitado
  test "Test 6 : Petición de escritura duplicada por perdida de respuesta" do
    IO.puts("Test: Petición de escritura duplicada por perdida de respuesta")
    
    # Para que funcione bien la función  ClienteGV.obten_vista
    Process.register(self(), :servidor_sa)

    # Arrancar nodos : 1 GV, 3 servidores y 3 cliente de almacenamiento
    mapa_nodos = startServidores(["ca1", "ca2", "ca3"],
                                 ["sa1", "sa2", "sa3",],
                                  @maquinas)

    # Espera configuracion y relacion entre nodos
    Process.sleep(200)

    # Comprobar primeros nodos primario y copia
    {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
    assert p == mapa_nodos.sa1
    assert c == mapa_nodos.sa2

    # Escribimos 2 veces el mensaje con el mismo id
    ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 1)
    ClienteSA.escribe(mapa_nodos.ca1, "a", "cc", 1)

    # Comprobamos que ha escrito la primera vez, y no ha escrito la segunda
    comprobar(mapa_nodos.ca1, "a", "aa", 3)

    # Parar todos los nodos y epmds
    stopServidores(mapa_nodos, @maquinas)

    IO.puts(" ... Superado")
  end

  # Test 7 : Comprobación de que un antiguo primario no debería servir
  #         operaciones de lectura.


  # Test 8 : Escrituras concurrentes de varios clientes sobre la misma clave,
  #         con comunicación con fallos (sobre todo pérdida de repuestas para
  #         comprobar gestión correcta de duplicados).


  # Test 9 : Comprobación de que un antiguo primario que se encuentra en otra
  #         partición de red no debería completar operaciones de lectura.


  # ------------------ FUNCIONES DE APOYO A TESTS ------------------------

    defp startServidores(clientes, serv_alm, maquinas) do
        tiempo_antes = :os.system_time(:milli_seconds)

        # Poner en marcha gestor de vistas y clientes almacenamiento
        sv = ServidorGV.startNodo("sv", "127.0.0.1")
            # Mapa con nodos cliente de almacenamiento
        clientesAlm = for c <- clientes, into: %{} do
                            {String.to_atom(c),
                            ClienteSA.startNodo(c, "127.0.0.1")}
                        end
        ServidorGV.startService(sv)
        for { _, n} <- clientesAlm, do: ClienteSA.startService(n, sv)


        # Mapa con nodos servidores almacenamiento
        servAlm = for {s, m} <-  Enum.zip(serv_alm, maquinas), into: %{} do
                      {String.to_atom(s),
                       ServidorSA.startNodo(s, m)}
                  end


        # Poner en marcha servicios de cada nodo servidor de almacenamiento
        for { _, n} <- servAlm do
            ServidorSA.startService(n, sv)
            #Process.sleep(60)
        end


        #Tiempo de puesta en marcha de nodos
        t_total = :os.system_time(:milli_seconds) - tiempo_antes
        IO.puts("Tiempo puesta en marcha de nodos  : #{t_total}")

        %{gv: sv} |> Map.merge(clientesAlm) |> Map.merge(servAlm)
    end

    defp stopServidores(nodos, maquinas) do
        IO.puts "Finalmente eliminamos nodos"

        # Primero el gestor de vistas para no tener errores por fallo de
        # servidores de almacenamiento
        { %{ gv: nodoGV}, restoNodos } = Map.split(nodos, [:gv])
        IO.inspect nodoGV, label: "nodo GV :"
        NodoRemoto.stop(nodoGV)
        IO.puts "UNO"
        Enum.each(restoNodos, fn ({ _ , nodo}) -> NodoRemoto.stop(nodo) end)
        IO.puts "DOS"
        # Eliminar epmd en cada maquina con nodos Elixir
        Enum.each(maquinas, fn(m) -> NodoRemoto.killEpmd(m) end)
    end

    defp comprobar(nodo_cliente, clave, valor_a_comprobar, id) do
        valor_en_almacen = ClienteSA.lee(nodo_cliente, clave, id)

        assert valor_en_almacen == valor_a_comprobar
    end


    def siguiente_valor(previo, actual) do
        ServidorSA.hash(previo <> actual) |> Integer.to_string
    end


    # Ejecutar durante un tiempo una escritura continuada de 3 clientes sobre
    # las mismas 2 claves pero con 3 valores diferentes de forma concurrente
    def escritura_concurrente(mapa_nodos, id_inicio) do
        aleat1 = :rand.uniform(1000)
        pid1 =spawn(__MODULE__, :bucle_infinito, [mapa_nodos.ca1, aleat1, id_inicio])
        aleat2 = :rand.uniform(1000)
        pid2 =spawn(__MODULE__, :bucle_infinito, [mapa_nodos.ca2, aleat2, id_inicio])
        aleat3 = :rand.uniform(1000)
        pid3 =spawn(__MODULE__, :bucle_infinito, [mapa_nodos.ca3, aleat3, id_inicio])

        Process.sleep(2000)

        Process.exit(pid1, :kill)
        Process.exit(pid2, :kill)
        Process.exit(pid3, :kill)
    end

    def bucle_infinito(nodo_cliente, aleat, id) do
        clave = Integer.to_string(rem(aleat, 2)) # solo claves "0" y "1"
        valor = Integer.to_string(aleat)
        miliseg = :rand.uniform(200)

        Process.sleep(miliseg)

        #:io.format "Nodo ~p, escribe clave = ~p, valor = ~p, sleep = ~p~n",
        #            [Node.self(), clave, valor, miliseg]

        ClienteSA.escribe(nodo_cliente, clave, valor, id)

        bucle_infinito(nodo_cliente, aleat, id+1)
    end
end
