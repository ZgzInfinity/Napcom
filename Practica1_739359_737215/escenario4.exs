# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: escenario4.exs
# FECHA: 25/10/2018
# TIEMPO: 15 horas entre todos los escenarios
# DESCRIPCIÓN: código para el master, en el que  se crean dos procesos, el principal (master_master) que recibe las peticiones
#              de los clientes y la manda a los workers con un identificador tarea, y el segundo (collect) en el que 
#              recibe la solucion del worker y se la manda al cliente. 
#              Para iniciarlo se le pasa una lista con todos los pid de los workers, y se recorre la lista
#              para mandar las peticiones. La función collect contiene una lista de tareas pendientes, en la que se 
#              almacenan todas las peticiones que ya han sido atendidas, para cuando llegue una respuesta del worker con un id
#              de tarea ya atendido, no haga caso a ese mensaje.
#              Código para el worker, en el que una vez le llega la peticion del master, crea tres threads para realizar
#              la tarea y seguir recibiendo peticiones, mientras que los threads realizan el problema y se lo mandan al master.


defmodule Master do
  def collect(tarea_actual, lista_pendientes) do
    if Enum.member?(lista_pendientes, tarea_actual) do       #Si la tarea actual esta en la lista, se quita de la lista y se avanza
      collect(tarea_actual+1, List.delete(lista_pendientes, tarea_actual))
    else
      receive do
        {tarea, tiempos, perfectos, pid_c} -> if tarea == tarea_actual do
                                                send(pid_c, {tiempos, perfectos})
                                                collect(tarea_actual+1, lista_pendientes)
                                              end
                                              if tarea > tarea_actual do
                                                send(pid_c, {tiempos, perfectos})
                                                collect(tarea_actual, lista_pendientes ++ [tarea])
                                              end
                                              if tarea < tarea_actual do
                                                collect(tarea_actual, lista_pendientes)
                                              end
      end
      #Se recibe la solución de un worker, si la tarea recibida es igual a la actual, se manda y aumenta la tarea actual en 1
      #Si la tarea recibida es mayor, se mete en la lista de pendientes, y si es menor no se hace nada
    end
  end

  def master_master(workers, i, pid_collect, tarea) do
    receive do
      {pid, :perfectos_ht} -> send(Enum.at(workers,i), {pid_collect, :perfectos_ht, pid, tarea}) #Recibe la peticion del cliente, y se la manda al worker i de la lista
    end
    if i<length(workers)-1, do: master_master(workers, i+1, pid_collect, tarea+1), else: master_master(workers, 0, pid_collect, tarea+1)
    # Se invoca a si misma recursivamente aumentando en uno la tarea y el indice de la lista, o a 0 si era el último elemento
  end

  def init(workers) do
    Node.connect(:"nodo2@192.168.1.43")          #Se conecta con el nodo cliente
    Process.register(self(), :server)            #Registra este nodo como servidor
    pid_collect=spawn(fn -> collect(0, []) end)  #Se invoca un thread con la funcion de collect
    master_master(workers,0,pid_collect, 0)      #Inicia el master_assign con el índice de la lista de workers y la tarea a 0
  end
end


defmodule Perfectos do

  defp suma_divisores_propios(n, 1) do
    1
  end
  
  defp suma_divisores_propios(n, i) when i > 1 do
    if rem(n, i)==0, do: i + suma_divisores_propios(n, i - 1), else: suma_divisores_propios(n, i - 1)
  end

  def suma_divisores_propios(n) do
    suma_divisores_propios(n, n - 1)
  end
  
  def es_perfecto?(1) do
    false
  end
  
  def es_perfecto?(a) when a > 1 do
    suma_divisores_propios(a) == a
  end
 
  defp encuentra_perfectos({a, a}, queue) do
    if es_perfecto?(a), do: [a | queue], else: queue
  end

  defp encuentra_perfectos({a, b}, queue) when a != b do
    encuentra_perfectos({a, b - 1}, (if es_perfecto?(b), do: [b | queue], else: queue))
  end

  def encuentra_perfectos({a, b}) do
    encuentra_perfectos({a, b}, [])
  end 

  def lanzar_process(pid, perfectos, pid_c, tarea) do
    time1 = :os.system_time(:millisecond)
    if :rand.uniform(100)>60, do: Process.sleep(round(:rand.uniform(100)/100 * 2000))
    perfectos = encuentra_perfectos({1, 10000})
    time2 = :os.system_time(:millisecond)
    send(pid, {tarea, time2 - time1, perfectos, pid_c})
  end

  def servidor() do
    receive do  
      {pid, :perfectos_ht, pid_c, tarea} -> spawn(fn -> Perfectos.lanzar_process(pid, :perfectos_ht, pid_c, tarea) end)
                                            spawn(fn -> Perfectos.lanzar_process(pid, :perfectos_ht, pid_c, tarea) end)
                                            spawn(fn -> Perfectos.lanzar_process(pid, :perfectos_ht, pid_c, tarea) end)
    #Recibe la peticion del master, e invoca tres threads identicos para realizar la petición, y luego sigue
    end
    servidor()    
  end 

  def init() do
    Node.connect(:"nodo3@192.168.1.43")         #Se conecta con el nodo cliente
    Process.register(self(), :worker)           #Registra este nodo como worker
    servidor()                                  #Empieza a funcionar como worker
  end
end

# Lanzamiento del worker:  Perfectos.init()


# Ejemplo de lanzamiento del master : Master.init([{:worker,:"nodo1@192.168.1.39"}, {:worker,:"nodo4@192.168.1.39"}, {:worker,:"nodo5@192.168.1.39"},{:worker,:"nodo6@192.168.1.39"}])
