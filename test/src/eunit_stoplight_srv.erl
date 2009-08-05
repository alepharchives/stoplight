-module(eunit_stoplight_srv).

-include_lib("eunit/include/eunit.hrl").
-include_lib("../../include/defines.hrl").

setup() ->
    % ?TRACE("seed servers", self()),
    {ok, Node1Pid} = stoplight_srv:start_named(node1, {seed, undefined}),
    {ok, _Node2Pid} = stoplight_srv:start_named(node2, {seed, Node1Pid}),
    {ok, _Node3Pid} = stoplight_srv:start_named(node3, {seed, Node1Pid}),
    [node1, node2, node3].

teardown(Servers) ->
    % io:format(user, "teardown: ~p ~p ~n", [Servers, global:registered_names()]),
    lists:map(fun(Pname) -> 
        Pid = whereis(Pname),
        % io:format(user, "takedown: ~p ~p ~n", [Pname, Pid]),
        gen_cluster:cast(Pid, stop), 
        unregister(Pname)
     end, Servers),

    lists:map(fun(Pname) -> 
        Pid = global:whereis_name(Pname),
        % io:format(user, "takedown: ~p ~p ~n", [Pname, Pid]),
        gen_cluster:cast(Pid, stop), 
        global:unregister_name(Pname)
    end, global:registered_names()),
    ok.

node_state_test_() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         ?assert(true =:= true),
         {ok, State1} = gen_server:call(node1, {state}),
         ?assert(is_record(State1, srv_state) =:= true),

         {ok, Plist} = gen_cluster:call(node1, {'$gen_cluster', plist}),
         ?assertEqual(3, length(Plist)),
         % ?assertEqual(testnode1, gen_server:call(testnode1, {registered_name})),
         {ok}
      end
  }.

stale_req_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->

         % generate the initial request
         Req0 = #req{name=food, owner=self(), timestamp=100},
         {response, CurrentOwner0} = gen_cluster:call(node1, {mutex, request, Req0}),
         ?assertEqual(Req0, CurrentOwner0), 

         % make sure we get a stale response and the actual owner
         Req1 = #req{name=food, owner=self(), timestamp=50},
         {stale, CurrentOwner1} = gen_cluster:call(node1, {mutex, request, Req1}),
         ?assertEqual(Req0, CurrentOwner0), 

         % release, test more

         {ok}
      end
  }.

mutex_release_test_() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->

         % generate the initial request
         Req0 = #req{name=food, owner=self(), timestamp=100},
         {response, CurrentOwner0} = gen_cluster:call(node1, {mutex, request, Req0}),
         ?assertEqual(Req0, CurrentOwner0), 

         % release
         {stale, CurrentOwner1} = gen_cluster:call(node1, {mutex, release, Req0}),
 
         {ok}
      end
  }.

mutex_inquiry_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         ?assert(true =:= true),
         {ok}
      end
  }.

mutex_request_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         ?assert(true =:= true),
         {ok}
      end
  }.

mutex_yield_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         ?assert(true =:= true),
         {ok}
      end
  }.


delete_request_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         ?assert(true =:= true),
         {ok}
      end
  }.


