# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: worker.exs
# FECHA: 22/11/2018
# TIEMPO: 15 horas
# DESCRIPCIÓN: Módulo del worker, que se encarga o de calcular los divisores de un número, o 
#              de sumar una lista con los divisores, o de calcular los divisores y sumarlos todo junto.
#              Los workers pueden ser también de 4 tipos, sin fallos, con retraso, con omisión y crash.


#-----------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------- WORKER -------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------

defmodule Worker do
  defp divisores_propios(1, 0, lista) do
    [1|lista]
  end

  defp divisores_propios(n, 1, lista) do
    [1|lista]
  end
  
  defp divisores_propios(n, i, lista) when i > 1 do
    #if rem(n, i)==0, do: [divisores_propios(n, i - 1, lista)] ++ [i], else: divisores_propios(n, i - 1, lista)
    divisores_propios(n,i-1, (if (rem(n, i)==0), do: [i|lista], else: lista))
  end

  def divisores_propios(n) do
    divisores_propios(n, n - 1, [])
  end

  def op(1, num) do  #divisores_propios
    divisores_propios(num)
  end


  defp suma_divisores_propios(n, 1) do
    1
  end
  
  defp suma_divisores_propios(n, i) when i > 1 do
    if rem(n, i)==0, do: i + suma_divisores_propios(n, i - 1), else: suma_divisores_propios(n, i - 1)
  end

  def suma_divisores_propios(n) do
    suma_divisores_propios(n, n - 1)
  end

  def op(2, num) do    #suma divisores propios
    suma_divisores_propios(num)
  end


  def op(3, listaNum) do   #suma lista
    Enum.sum(listaNum)
  end


  def init do 
    case :rand.uniform(100) do
      random when random > 80 -> :crash
      random when random > 50 -> :omission
      random when random > 25 -> :timing
      _ -> :no_fault
    end
  end  

  def loop(tipoWorker) do
    loopI(init(), tipoWorker)
  end
  
  defp loopI(worker_type, tipoWorker) do
    delay = case worker_type do
      :crash -> if :random.uniform(100) > 75, do: :infinity
      :timing -> :random.uniform(100)*1000
      _ ->  0
    end
    IO.puts "Soy #{worker_type}"
    IO.puts "Me duermo #{delay}"
    Process.sleep(delay)
    result = receive do
     {:reqWorker, p_pid, m, miNum} ->
             if (((worker_type == :omission) and (:rand.uniform(100) < 75)) or (worker_type == :timing) or (worker_type==:no_fault)), do: send(p_pid, {:resWorker, op(tipoWorker, m), miNum, self(), tipoWorker})
    end
    loopI(worker_type, tipoWorker)     #worker_type puede ser 1, 2 o 3
  end

  def worker(tipoWorker) do
    Process.register(self(), :worker)
    Node.connect(:"nodo2@192.168.1.40")            #Nos conectamos con el proxy
    loop(tipoWorker)
  end
end

#Worker.worker(1)

