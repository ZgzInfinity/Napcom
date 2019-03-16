# AUTORES: Ignacio Palacios Gracia, Rubén Rodriguez Esteban
# NIAs: 739359 - 737215
# FICHERO: Chat.exs
# FECHA: 7/11/2018
# TIEMPO: Aproximadamente 15 horas
# DESCRIPCIÓN: Modulo Chat, formado por 5 procesos diferentes. El primero es el proceso mutex, o almacén, que guarda 
#              todas las variables compartidas por el nodo. El segundo es el proceso que manda peticiones, espera
#              las respuestas de los nodos, manda el mensaje al chat y respuestas a los pendientes. El tercero recibe
#              las peticiones del resto de nodos y las procesa. El cuarto recibe las respuestas de los otros nodos a 
#              raíz de las peticiones enviadas anteriormente a los nodos. Por último, el quinto redirecciona los mensajes de
#              otros nodos a los procesos correspondientes del nodo, y saca por pantalla los mensajes del chat.


defmodule Chat do
  #Proceso "almacen" que garantiza la exclusión mutua cuando varios procesos intentan entrar a la vez.
  #Este almacen contiene todas las variables compartidas del nodo.
  #Espera a que le llegue un mensaje, y cuando le llega comprueba de que tipo ha sido este, y realiza las acciones necesarias,
  # ya sea mandarle una variables al proceso que lo ha pedido, o cambiar una o varias variables de valor.

  def mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me) do 
    receive do
      {:critical_manda, valor} -> critical_Section=valor
                                  our_SequenceNumber=highestSequenceNumber+1
                                  mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)

      {:oursequence, peticion} -> send(peticion, {:oursequenceRet, our_SequenceNumber})
                                  mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
      {:highestsequence, peticion, k} -> highestSequenceNumber = if highestSequenceNumber<k, do: k, else: highestSequenceNumber
                                         send(peticion, {:highestsequenceRet, highestSequenceNumber})
                                         mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)

      {:replycount, peticion} -> send(peticion, {:replycountRet, outstanding_Reply_Count})
                                 mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
      {:replycountCamManda} ->  outstanding_Reply_Count= n - 1
                                mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
      {:replycountCam} ->  outstanding_Reply_Count= outstanding_Reply_Count - 1
                           mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)

      {:critical_recibepeticion, peticion, k, j} -> 
                                               defer_it=critical_Section and ((k>our_SequenceNumber) or (k==our_SequenceNumber and j>me))
                                               send(peticion, {:defer, defer_it})
                                               mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
      {:secCriticaCam, valor} -> critical_Section=valor
                                 mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
      {:deferred, peticion, j} -> send(peticion, {:deferredRet, Enum.at(reply_Deferred,j)})
                                  mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
      {:deferredCam, j, valor} -> reply_Deferred=List.replace_at(reply_Deferred, j, valor)
                                  mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me)
    end
  end

  #---------------------------------    P R O C E S S W H I C H INVOKES M U T U A L EXCLUSION FOR THIS NODE

  #Función que manda peticiones a todos los nodos (menos a el mismo) para poder enviar un mensaje al chat
  defp funcion_mandar(nodos, n, j, our_sequencenumber, soy_yo) do
    if j+1 != soy_yo, do: send(Enum.at(nodos,j), {:request, Enum.at(nodos,soy_yo-1), soy_yo, our_sequencenumber})                   
    if j != n-1, do: funcion_mandar(nodos, n, j+1, our_sequencenumber, soy_yo)
  end

  #Función que espera a que todos los demás nodos restantes manden confirmación de que puede enviar al chat
  defp funcion_esperar(pid_mutex, esperar) do
    send(pid_mutex, {:replycount, self()})
    esperar = receive do
      {:replycountRet, reply_count} ->  if reply_count == 0, do: false, else: true                  
    end
    if esperar, do: funcion_esperar(pid_mutex, true)
  end

  #Función que manda respuestas a aquellos nodos que han mandado peticiones, pero se han quedado en pendiente
  defp funcion_reply(nodos, pid_mutex, n, j) do
    send(pid_mutex, {:deferred, self(), j})
    receive do
      {:deferredRet, pendiente} ->  if pendiente do
                                     send(pid_mutex, {:deferredCam, j, false})
                                     send(Enum.at(nodos,j), {:respuesta})
                                   end
    end
    if j != n-1, do: funcion_reply(nodos, pid_mutex, n, j+1)
  end

  #Función que manda el mensaje al chat
  defp mandar_chat(nodos,j, me, n) do
    mensaje="Soy el nodo #{me}"
    send(Enum.at(nodos,j), {:chat, mensaje})
    if j != n-1, do: mandar_chat(nodos,j+1, me, n)
  end

  #Función principal de este proceso, que manda peticiones a todos los demás nodos, espera sus respuestas, 
  #   manda el mensaje al chat y envia respuestas a los nodos pendientes.
  def manda(nodos, pid_mutex, n, our_sequencenumber, me) do
    send(pid_mutex, {:critical_manda, true})                           
    send(pid_mutex, {:replycountCamManda})

    send(pid_mutex, {:oursequence, self()})
    our_sequencenumber = receive do
      {:oursequenceRet, our_Sequence} -> our_Sequence
    end

    funcion_mandar(nodos, n, 0, our_sequencenumber, me)
    funcion_esperar(pid_mutex, true)

    mandar_chat(nodos, 0, me, n)

    send(pid_mutex, {:secCriticaCam, false})
    funcion_reply(nodos, pid_mutex, n, 0)

    :timer.sleep(:rand.uniform(3000))    #SE DUERME PARA ESPERAR UN TIEMPO ENTRE MENSAJES

    manda(nodos, pid_mutex, n, our_sequencenumber, me)
  end

  #---------------------------------    P R O C E S S W H I C H RECEIVES R E Q U E S T (k, j ) M E S S A G E S

  #Proceso que recibe peticiones de otros nodos, y compara su número de secuencia y su identificador de nodo con el nuestro,
  #   decidiendo así si lo ponemos en la lista de pendientes, o le enviamos la respuesta
  def recibe_peticion(j, k, highest, pid_mutex, pid_aresponder) do
    {pid_aresponder, j, k} = receive do
      {:requestReev, pid_llega, numNodo, su_sequence_number} ->  {pid_llega, numNodo, su_sequence_number}
    end
    #pid_aresponder=pid_llega
    #j=numNodo
    #k=su_sequence_number


    send(pid_mutex, {:highestsequence, self(), k})
    highest= receive do
      {:highestsequenceRet, highestsec} -> highestsec
    end

    send(pid_mutex, {:critical_recibepeticion, self(), k, j})
    #send(pid_mutex, {:critical_recibepeticion, self(), k, j-1})
    receive do
      {:defer, defer_it} -> if defer_it, do: send(pid_mutex, {:deferredCam, j-1, true}), else: send(pid_aresponder, {:respuesta})
    end

    recibe_peticion(j, k, highest, pid_mutex, 0)
  end

 
  #---------------------------------    P R O C E S S W H I C H RECEIVES REPLY M E S S A G E S

  #Proceso que recibe respuestas a las peticiones mandadas a los otros nodos.
  def recibe_respuesta(pid_mutex) do
    receive do
      {:respuestaReev} -> send(pid_mutex,{:replycountCam}) 
    end
    recibe_respuesta(pid_mutex)
  end


  #---------------------------------    PROCESS DE CHAT

  #Proceso que recibe todos los mensajes provenientes de otros nodos, redireccionandolos a los procesos correspondientes, o
  #  bien sacandolo por pantalla si se trata del mensaje del chat.
  def chat(pid1, pid2, pid3) do
    receive do
      {:chat, mensaje} -> IO.puts(mensaje)

      {:respuesta} -> send(pid3,{:respuestaReev})             

      {:request, pid_aMandar, me, our_sequencenumber} -> send(pid2,{:requestReev, pid_aMandar, me, our_sequencenumber})
    end
    chat(pid1, pid2, pid3)
  end


  #---------------------------------    INICIO Y CONEXIONES

  #Conectamos todos los nodos entre sí
  def conectar(nodos, 0, n) do
    {:persona,aConectar}=Enum.at(nodos,n-1)
    Node.connect(aConectar)
  end

  #Conectamos todos los nodos entre sí
  def conectar(nodos, j, n) do
    {:persona,aConectar}=Enum.at(nodos,j)
    Node.connect(aConectar)
    conectar(nodos,j-1,n)
  end

  #Esperamos a que todos los nodos hayan entrado a la función init
  def esperar_nodos(n) do
    receive do
      {:ya_estoy, numNodo} -> IO.puts "Nodo #{numNodo} conectado"
    end
    if n>1, do: esperar_nodos(n-1)
  end

  #Manda un mensaje al resto de nodos, para indicar que pueden empezar a realizar sus tareas
  def confir_nodos(nodos, n, j) do
    send(Enum.at(nodos,j), {:ya_estamos})
    if j<n, do: confir_nodos(nodos, n, j+1)
  end


  #Función que inicia todo
  #Si me==1, espera a que el resto de nodos le mande un mensaje, y luego les manda una comfirmación a todos ellos.
  #Si me!=1, manda un mensaje al nodo con identificador 1, y se espera a la confirmación de este para poder empezar.
  def init(me) do
    if me < 1, do: IO.puts "El identificador de nodo tiene que se mayor que 1"
    nodos=[{:persona,:"nodo1@192.168.1.39"}, {:persona,:"nodo2@192.168.1.39"}, {:persona,:"nodo3@192.168.1.39"}, {:persona,:"nodo4@192.168.1.33"}, {:persona,:"nodo5@192.168.1.33"}, {:persona,:"nodo6@192.168.1.33"}]
    Process.register(self(), :persona)
    n=length(nodos)
    conectar(nodos,n-1,n)
    our_SequenceNumber = n-1
    highestSequenceNumber = 0
    outstanding_Reply_Count = n-1  #cambiarlo
    critical_Section = false
    reply_Deferred = List.duplicate(false,n)

    #Esperamos a que todos los nodos esten ejecutandose
    if me == 1 do 
      esperar_nodos(n-1)
      confir_nodos(nodos, n-1, 1) 
    else 
      send(Enum.at(nodos,0), {:ya_estoy, me})
      receive do
        {:ya_estamos} -> IO.puts "Conectado"
      end
    end


    pid = spawn(fn -> Chat.mutex_nodo(our_SequenceNumber, highestSequenceNumber, outstanding_Reply_Count, critical_Section, reply_Deferred, n, me) end)
    pid1=spawn(fn -> Chat.manda(nodos, pid, n, our_SequenceNumber, me) end)
    pid2=spawn(fn -> Chat.recibe_peticion(0, 0, 0, pid, 0) end) 
    pid3=spawn(fn -> Chat.recibe_respuesta(pid) end) 
    chat(pid1, pid2, pid3)
  end
end

#Chat.init(1)


