# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: escenario2.exs
# FECHA: 25/10/2018
# TIEMPO: 15 horas entre todos los escenarios
# DESCRIPCIÓN: código para el servidor, en el que una vez le llega la peticion del cliente, crea un thread para realizar
#              la tarea y seguir recibiendo peticiones, mientras que el thread realiza el problema y se lo manda al cliente.


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

  def lanzar_process(pid, perfectos) do
    time1 = :os.system_time(:millisecond)
    perfectos = encuentra_perfectos({1, 10000})
    time2 = :os.system_time(:millisecond)    
    send(pid, {time2 - time1, perfectos})
  end

  def servidor() do
    receive do
      {pid, :perfectos} ->  spawn(fn -> Perfectos.lanzar_process(pid, :perfectos) end)    #Invoca un thread para realizar la tarea, y sigue
    end
    servidor()    
  end 

  def init() do
     Node.connect(:"nodo2@192.168.1.43")         #Se conecta con el nodo cliente
     Process.register(self(), :server)           #Registra este nodo como servidor
     servidor()                                  #Empieza a funcionar como servidor
  end
end

#Lanzamiento del server: Perfectos.init()
