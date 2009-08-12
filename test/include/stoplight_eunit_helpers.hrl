-define(stop_and_unregister_servers(Servers),
    ((fun () ->
        lists:map(fun(Pname) -> 
            Pid = whereis(Pname),
            gen_server:cast(Pid, stop), 
            try unregister(Pname)
            catch _:_ -> ok
            end
        end, Servers)
      end)())).

-define(stop_and_unregister_globals,
    ((fun () ->
        lists:map(fun(Pname) -> 
                Pid = global:whereis_name(Pname),
                gen_server:cast(Pid, stop), 
                global:unregister_name(Pname)
            end, global:registered_names())
      end)())).
