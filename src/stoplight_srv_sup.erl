%% Stoplight server supervisor
-module(stoplight_srv_sup).
-behaviour(supervisor).
-include_lib("../include/defines.hrl").

-export([start_link/2]).
-export([init/1]).

start_link(Type, Args) -> supervisor:start_link(?MODULE, [Type, Args]).

init([Type, Args]) ->
  RestartStrategy = one_for_one,
  MaxRestarts = 1000,
  MaxTimeBetRestarts = 3600,
  TimeoutTime = 5000,
  SupFlags = {RestartStrategy, MaxRestarts, MaxTimeBetRestarts},

  NodeServer     = {?SERVER_MODULE,      {?SERVER_MODULE,     start_link, [Type, Args]}, permanent, TimeoutTime, worker, []},
  ClientListener = {stoplight_listener,  {stoplight_listener, start_link, [Type, Args]}, permanent, TimeoutTime, worker, []},

  {ok, {SupFlags, [
      NodeServer,
      ClientListener
    ]}}.
