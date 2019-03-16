# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: master.exs
# FECHA: 22/11/2018
# TIEMPO: 15 horas
# DESCRIPCIÓN: Aquí se encuentran los módulos del cliente, del proxy y del master.
#              El cliente le manda al master la petición, y se queda esperando a la respuesta.
#              El proxy es el que comunica el master con los workers. El master le irá mandando peticiones,
#              el proxy se las mandará a los workers, y este recibirá la respuesta, la respuesta tardía, o no recibirá
#              nada (timeout del worker).
#              El master se encarga de gestionar los tres tipos de workers, los protocolos de mensajes, las listas
#              de las sumas y de números amigos.



#-----------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------- CLIENTE -------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
defmodule Cliente do                                #NODO3
  def init() do
    mi_pid=self()
    Node.connect(:"nodo1@192.168.1.40")            #Nos conectamos con el master
    pidMaster={:master,:"nodo1@192.168.1.40"}
    #lista=1..1000000
    send(pidMaster, {:reqCliente, mi_pid})
    
    IO.puts "Espero"
    receive do
      {:amigos_lista, amigos} -> IO.inspect amigos, label: "La lista de amigos es: "
    end
  end
end

#Cliente.init()

#-----------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------- PROXY -------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------

defmodule Proxy do                                  #NODO2
  def reciboMaster(m_pid) do
    receive do
      {:reqMaster, w_pid, m, indice} -> accion(w_pid, 300, 0, m_pid, m, indice)
    end
  end

  def accion(w_pid, timeout, retry, m_pid, m, indice) when retry < 5 do
    send(w_pid, {:reqWorker, self(), m, indice})
    receive do
      {:resWorker, done, miNum, w_pid, tipoWorker} -> if(miNum >= indice) do
                                                        send(m_pid, {:hecho, done})
                                                        reciboMaster(m_pid)
                                                      else
                                                        tipo=cond do
                                                          tipoWorker == 1 -> :tipoA
                                                          tipoWorker == 2 -> :tipoB
                                                          tipoWorker == 3 -> :tipoC
                                                        end
                                                        IO.puts("Se ha despertado un #{tipo}")
                                                        send(m_pid, {:despertado, w_pid, tipo})
                                                        reciboMaster(m_pid)
                                                      end
    after
      timeout -> accion(w_pid, timeout, retry + 1, m_pid, m, indice) #FALLO!!!
    end
  end


  def accion(w_pid, timeout, retry, m_pid, m, indice) when retry == 5 do
    send(m_pid, {:error, "timeout expiration"})
    reciboMaster(m_pid)
  end

  def init() do
    Process.register(self(), :proxy)
    Node.connect(:"nodo1@192.168.1.40")            #Nos conectamos con el master
    pidMaster={:master,:"nodo1@192.168.1.40"}
    reciboMaster(pidMaster)
  end
end

#Proxy.init()


#-----------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------- MASTER -------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------

defmodule Master do                                 #NODO1

  def manda_proxy(p_pid, w_pid, m, indice) do  #Nodos A y C si protocolo == 1, B si == 2
    send(p_pid, {:reqMaster, w_pid, m, indice})
  end

  def master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos) when num == 1300 do
    IO.puts "SE HA TERMINADO"
    send(c_pid, {:amigos_lista, lista_amigos})
  end

  def master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos) when num < 1300 do
    IO.puts ("Vamos por numero #{num}")
    if protocolo == 1 do
      manda_proxy(p_pid, Enum.at(nodosA,0), num, num)
      receive do
        {:hecho, divisores} -> manda_proxy(p_pid, Enum.at(nodosC,0), divisores, num)
                             IO.puts "Mando a C"
                             suma = receive do
                               {:hecho, suma} -> suma
                               {:error, timeout} -> IO.puts("Se ha agotado el timeout en worker C")
                                                    NodosC = List.delete_at(nodosC, 0)
                                                    #IO.inspect nodosC, label: "NodosC: "
                                                    master(lista_sumas, 2, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos)
                               {:despertado, w_pid, tipoWorker} -> 
                                      IO.puts("Se ha despertado un #{tipoWorker}")
                                      {nodosA, nodosB, nodosC} = cond do
                                           tipoWorker == :tipoA -> nodosA=List.insert_at(nodosA, length(nodosA), w_pid)
                                                                   {nodosA, nodosB, nodosC}
                                           tipoWorker == :tipoB -> nodosB=List.insert_at(nodosB, length(nodosB), w_pid)
                                                                   {nodosA, nodosB, nodosC}
                                           tipoWorker == :tipoC -> nodosC=List.insert_at(nodosC, length(nodosC), w_pid)
                                                                   {nodosA, nodosB, nodosC}
                                       end
                                       master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos)
                             end

                             if(length(lista_sumas) >= suma-1) do    #Si el elemento a buscar tiene suma
                               sumaOtro=Enum.at(lista_sumas, suma-1)
                               if(num == sumaOtro) do
                                 lista_amigos= lista_amigos ++ [{suma, num}]
                                 lista_sumas= List.insert_at(lista_sumas, num-1, suma)
                                 master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num+1, lista_amigos)
                               else
                                 lista_sumas= List.insert_at(lista_sumas, num-1, suma)
                                 master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num+1, lista_amigos)
                               end
                             else
                               lista_sumas= List.insert_at(lista_sumas, num-1, suma)
                               master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num+1, lista_amigos)
                             end
        {:error, timeout} -> IO.puts("Se ha agotado el timeout en worker A")
                    nodosA = List.delete_at(nodosA, 0)
                    #IO.inspect nodosA, label: "NodosA: "
                    master(lista_sumas, 2, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos)
        {:despertado, w_pid, tipoWorker} -> IO.puts("Se ha despertado un #{tipoWorker}")
                                           {nodosA, nodosB, nodosC} = cond do
                                             tipoWorker == :tipoA -> nodosA=List.insert_at(nodosA, length(nodosA), w_pid)
                                                                   {nodosA, nodosB, nodosC}
                                             tipoWorker == :tipoB -> nodosB=List.insert_at(nodosB, length(nodosB), w_pid)
                                                                   {nodosA, nodosB, nodosC}
                                             tipoWorker == :tipoC -> nodosC=List.insert_at(nodosC, length(nodosC), w_pid)
                                                                   {nodosA, nodosB, nodosC}
                                           end
                                           master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos)

      end

    else
      IO.puts "Mando a B"
      manda_proxy(p_pid, Enum.at(nodosB,0), num, num)
      receive do
        {:hecho, suma_divisores} -> if(length(lista_sumas) >= suma_divisores-1) do    #Si el elemento a buscar tiene suma
                                      sumaOtro=Enum.at(lista_sumas, suma_divisores-1)
                                      if(num == sumaOtro) do
                                        lista_amigos= lista_amigos ++ [{suma_divisores, num}]
                                        lista_sumas= List.insert_at(lista_sumas, num-1, suma_divisores)
                                        master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num+1, lista_amigos)
                                      else
                                        lista_sumas= List.insert_at(lista_sumas, num-1, suma_divisores)
                                        master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num+1, lista_amigos)
                                      end
                                    else
                                      lista_sumas= List.insert_at(lista_sumas, num-1, suma_divisores)
                                      master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num+1, lista_amigos)
                                    end

        {:error, timeout} -> IO.puts("Se ha agotado el timeout en worker B")
                    nodosB = List.delete_at(nodosB, 0)
                    #IO.inspect nodosB, label: "NodosB: "
                    master(lista_sumas, 1, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos)
        {:despertado, w_pid, tipoWorker} -> IO.puts("Se ha despertado un #{tipoWorker}")
                                            {nodosA, nodosB, nodosC} = cond do
                                              tipoWorker == :tipoA -> nodosA=List.insert_at(nodosA, length(nodosA), w_pid)
                                                                      {nodosA, nodosB, nodosC}
                                              tipoWorker == :tipoB -> nodosB=List.insert_at(nodosB, length(nodosB), w_pid)
                                                                      {nodosA, nodosB, nodosC}
                                              tipoWorker == :tipoC -> nodosC=List.insert_at(nodosC, length(nodosC), w_pid)
                                                                      {nodosA, nodosB, nodosC}
                                            end
                                            master(lista_sumas, protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num, lista_amigos)
      end
    end
  end


  def recibe_cliente(protocolo, nodosA, nodosB, nodosC, p_pid, num) do
    receive do
      {:reqCliente, c_pid} -> master([], protocolo, nodosA, nodosB, nodosC, p_pid, c_pid, num, [])
    end
  end
  

  def init() do
    Process.register(self(), :master)
    proxy_pid = {:proxy, :"nodo2@192.168.1.40"}
    Node.connect(:"nodo2@192.168.1.40")    #Nos conectamos con el proxy
    nodosA=[{:worker,:"nodo4@192.168.1.39"}, {:worker,:"nodo5@192.168.1.39"}]
    nodosB=[{:worker,:"nodo6@192.168.1.39"}, {:worker,:"nodo7@192.168.1.39"}]
    nodosC=[{:worker,:"nodo8@192.168.1.39"}, {:worker,:"nodo9@192.168.1.39"}]
    
    protocolo=1    #1 para utilizar los workers tipo A y C, 2 para utilizar workers tipo B

    recibe_cliente(protocolo, nodosA, nodosB, nodosC, proxy_pid, 1)
  end
end

#Master.init()