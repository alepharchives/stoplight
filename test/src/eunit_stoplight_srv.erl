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

node_state_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         ?assert(true =:= true),
         {ok, State1} = gen_cluster:call(node1, {state}),
         ?assert(is_record(State1, srv_state) =:= true),

         {ok, Plist} = gen_cluster:call(node1, {'$gen_cluster', plist}),
         ?assertEqual(3, length(Plist)),
         {ok}
      end
  }.

stale_req_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->

         {ok, Mock} = gen_server_mock:new(),

         % mock should get a response from node1 because of Req0
         gen_server_mock:expect_cast(Mock, fun({mutex, response, _Req}, _State) -> ok end),

         % generate the initial request
         Req0 = #req{name=food, owner=Mock, timestamp=100},
         gen_cluster:cast(node1, {mutex, request, Req0}),
         {ok, CurrentOwner0} = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req0, CurrentOwner0), 

         % make sure we get a stale response and the actual owner
         Req1 = #req{name=food, owner=self(), timestamp=50},
         gen_cluster:cast(node1, {mutex, request, Req1}),

         % current owner shouldn't change
         {ok, CurrentOwner1} = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req0, CurrentOwner1), 

         gen_server_mock:assert_expectations(Mock),
         {ok}
      end
  }.

mutex_release_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->

         % generate the initial request
         Req0 = #req{name=food, owner=self(), timestamp=100},
         gen_cluster:cast(node1, {mutex, request, Req0}),

         % verify we are now the owner
         {ok, CurrentOwner0} = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req0, CurrentOwner0), 

         % release
         gen_cluster:cast(node1, {mutex, release, Req0}),
         {ok, CurrentOwner3}       = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(undefined, CurrentOwner3),
 
         {ok}
      end
  }.

mutex_replace_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         {ok, Mock} = gen_server_mock:new(),

         % mock should get a response from node1 because of Req0
         gen_server_mock:expect_cast(Mock,  fun({mutex, response, _Req}, _State) -> ok end),
         gen_server_mock:expect_cast(Mock,  fun({mutex, response, _Req}, _State) -> ok end),

         % generate the initial request
         Req0 = #req{name=food, owner=Mock, timestamp=100},
         gen_cluster:cast(node1, {mutex, request, Req0}),

         % verify Mock is current owner for that name
         {ok, CurrentOwner2} = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req0, CurrentOwner2),

         % generate a replacement request
         Req1 = #req{name=food, owner=Mock, timestamp=101},
         gen_cluster:cast(node1, {mutex, request, Req1}),

         % % verify Mock is current owner for that name
         {ok, CurrentOwner4}       = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req1, CurrentOwner4),

         % release
         gen_cluster:cast(node1, {mutex, release, Req1}),
         {ok, CurrentOwner5}       = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(undefined, CurrentOwner5),

         %%%%%%%%%%%%%%
         % test replacing our current request when our current request is in the queue
         gen_server_mock:assert_expectations(Mock),
 
         {ok}
      end
  }.

mutex_queue_promotion_test_() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         {ok, Mock}  = gen_server_mock:new(),
         {ok, Mock2} = gen_server_mock:new(),
         % gen_server_mock:expect_cast(Mock2,  fun({mutex, response, _Req}, _State) -> ok end),

         % test having something in the queue, test that it gets promoted when rm'd from the queue

         % generate the initial request
         Req0 = #req{name=food, owner=Mock, timestamp=100},
         gen_server_mock:expect_cast(Mock, fun({mutex, response, Req0}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, request, Req0}),

         % verify Mock is the current owner for that name
         {ok, CurrentOwner1}       = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req0, CurrentOwner1),

         % generate request from someone else
         Req1 = #req{name=food, owner=Mock2, timestamp=110},

         % expect that we'll get back Req0, the request shouldn't change b/c our request is taken by someone else
         gen_server_mock:expect_cast(Mock2,  fun({mutex, response, Req0}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, request, Req1}),

         % but the owner should stay the same
         {ok, CurrentOwner2}       = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req0, CurrentOwner2), 

         % and our second request should be in the Queue
         {ok, Queue} = gen_cluster:call(node1, {queue, food}),
         ?assertEqual(Req1, hd(Queue)),

         % when released, Mock2 should get a response saying that Req0 was released and now Req1 is the current owner
         gen_server_mock:expect_cast(Mock2,  fun({mutex, response, Req1}, _State) -> ok end),

         % release
         gen_cluster:cast(node1, {mutex, release, Req0}),

         {ok, CurrentOwner4} = gen_cluster:call(node1, {current_owner, food}),
         ?assertEqual(Req1, CurrentOwner4),

         gen_server_mock:assert_expectations(Mock),
         gen_server_mock:assert_expectations(Mock2),
         {ok}
      end
  }.

mutex_inquiry_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         {ok, Mock}  = gen_server_mock:new(),
         {ok, Mock2}  = gen_server_mock:new(),

         % generate the initial request
         Req0 = #req{name=food, owner=Mock, timestamp=100},
         gen_server_mock:expect_cast(Mock, fun({mutex, response, _R}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, request, Req0}),

         % Mock2 should rec response for INQUIRY
         gen_server_mock:expect_cast(Mock2,   fun({mutex, response, Req0}, _State) -> ok end),

         % % request an inquiry
         Req1 = #req{name=food, owner=Mock2, timestamp=100},
         gen_cluster:cast(node1, {mutex, inquiry, Req1}),

         % % Mock request inquiry, shouldn't get a response
         gen_cluster:cast(node1, {mutex, inquiry, Req0}),

         % req'd to ensure node1 synced 
         {ok, _CurrentOwner1}       = gen_cluster:call(node1, {current_owner, food}),

         gen_server_mock:assert_expectations(Mock),
         gen_server_mock:assert_expectations(Mock2),

         {ok}
      end
  }.

mutex_yield_by_owner_test_not() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         {ok, Mock}  = gen_server_mock:new(),
         Req0 = #req{name=food, owner=Mock, timestamp=100},

         % cast a yield, nothing should happen
         gen_cluster:cast(node1, {mutex, yield, Req0}),

         % request a lock
         gen_server_mock:expect_cast(Mock, fun({mutex, response, _R}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, request, Req0}),

         % expect to get a response with our cast
         gen_server_mock:expect_cast(Mock, fun({mutex, response, _R}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, yield, Req0}),

         % sync
         {ok, _CurrentOwner1}       = gen_cluster:call(node1, {current_owner, food}),
         gen_server_mock:assert_expectations(Mock),
         {ok}
      end
  }.

mutex_yield_by_non_owner_test_() ->
  {
      setup, fun setup/0, fun teardown/1,
      fun () ->
         {ok, Mock}  = gen_server_mock:new(),
         {ok, Mock2}  = gen_server_mock:new(),

         Req0 = #req{name=food, owner=Mock,  timestamp=100},
         Req1 = #req{name=food, owner=Mock2, timestamp=110},

         % request a lock
         gen_server_mock:expect_cast(Mock, fun({mutex, response, _R}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, request, Req0}),

         % also request the lock with Mock2
         gen_server_mock:expect_cast(Mock2, fun({mutex, response, _R}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, request, Req1}),

         % expect to get a response with our cast
         gen_server_mock:expect_cast(Mock,  fun({mutex, response, _R}, _State) -> ok end),
         gen_server_mock:expect_cast(Mock2, fun({mutex, response, _R}, _State) -> ok end),
         gen_cluster:cast(node1, {mutex, yield, Req0}),

         % sync
         {ok, _CurrentOwner1}       = gen_cluster:call(node1, {current_owner, food}),
         gen_server_mock:assert_expectations(Mock),
         gen_server_mock:assert_expectations(Mock2),
         {ok}
      end
  }.

