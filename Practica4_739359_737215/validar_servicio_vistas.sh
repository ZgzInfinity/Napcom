# Ejecución del programa de tests
elixir  --name maestro@127.0.0.1 --cookie 'palabrasecreta' \
	--erl  '-kernel inet_dist_listen_min 32000' \
	--erl  '-kernel inet_dist_listen_max 32049' \
	servicio_vistas_tests.exs

#Una vez terminada ejecución programa, eliminar demonio de conexiones red Erlang
# Hay que extenderlo para que elimine epmds de OTRAS maquinas fisicas !!!
pkill epmd
