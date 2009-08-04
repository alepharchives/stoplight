%%%-------------------------------------------------------------------
%%% File    : stoplight_srv.erl
%%% Author  : nmurray
%%% Description : desc
%%% Created     : 2009-07-30
%%%-------------------------------------------------------------------
-module(stoplight_srv).
-behaviour(gen_cluster).
-include_lib("../include/defines.hrl").

-export([start_link/2, start_named/2]).

% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

% gen_cluster callback
-export([handle_join/3, handle_node_joined/3, handle_leave/4]).

% debug
-compile(export_all).

%% Macros
-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start() -> {ok,Pid} | ignore | {error,Error}
%% Description: Alias for start_link
%%--------------------------------------------------------------------
% start() ->
%     start_link(?DEFAULT_CONFIG). 

%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(_Type, _Args) ->
    io:format(user, "Got ~p in start_link for ~p~n", [{}, ?MODULE]),
    gen_cluster:start_link({local, stoplight_srv_local}, ?MODULE, _InitOpts=[], _GenServerOpts=[]).

%% for testing multiple servers
start_named(Name, Config) ->
    gen_cluster:start_link({local, Name}, ?MODULE, [Config], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------

init(_Args) -> 
    ?TRACE("Starting Stoplight Server", self()),
    InitialState = #srv_state{
                      pid=self(),
                      nodename=node(),
                      reqQs=dict:new(),
                      owners=dict:new()
                   },
    {ok, InitialState}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------

handle_call({mutex, _Tag, Req}, _From, State) when is_record(Req, req) ->
% if (ci, t') appears in (cowner, towner) or ReqQ then 
%   if t < t' then skip the rest;  {the message received is an older message} 
%   if t > t' then Delete(ci, tÕ, ReqQ, cowner, towner); 
%
% then handle_mutex from here
    {reply, todo, State};

handle_call({state}, _From, State) ->
    ?TRACE("queried state:", State),
    {reply, {ok, State}, State};

handle_call(_Request, _From, State) -> 
    {reply, okay, State}.

% e.g.
% handle_call({create_ring}, _From, State) ->
%     {Reply, NewState} = handle_create_ring(State),
%     {reply, Reply, NewState};
%
% handle_call({join, OtherNode}, _From, State) ->
%     {Reply, NewState} = handle_join(OtherNode, State),
%     {reply, Reply, NewState};
% ...
% etc.


%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) -> 
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) -> 
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) -> 
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) -> 
    {ok, State}.

handle_mutex({request, _Req}, _From, State) ->
    {reply, todo, State};

handle_mutex({yield, _Req}, _From, State) ->
    {reply, todo, State};

handle_mutex({release, _Req}, _From, State) ->
    {reply, todo, State};

handle_mutex({inquiry, _Req}, _From, State) ->
    {reply, todo, State}.

% ---- mutex helpers
have_previous_request_from_this_client(Req, State) -> % {true, OtherReq} | false
    case is_request_from_current_owner(Req, State) of
        {true, CurrentOwner} ->
            {true, CurrentOwner};
        _  ->
            is_there_a_request_from_owner_in_the_queue(Req, State)
    end.

% look at Req.owner, see if it is from our current owner, namespaced by name
is_request_from_current_owner(Req, State) when is_record(Req, req) -> % {true, CurrentOwner} | false
    #req{owner=Owner, name=Name} = Req,
    case current_owner_for_name(Name, State) of
        {ok, CurrentOwner} ->
            #req{owner=CurrentOwnerId} = CurrentOwner,
            #req{owner=ThisOwnerId}    = Req,
            case CurrentOwnerId =:= ThisOwnerId of
                true ->
                    {true, CurrentOwner};
                false ->
                    false
            end;
        _ ->
            false
    end.

% look at Req.owner, see if we have another request from this same owner in our
% queue that is namespaced by Req.name. If so, return the OtherReq that is in
% the queue. 
is_there_a_request_from_owner_in_the_queue(Req, State) -> % {true, OtherReq} | false
    #req{owner=Owner, name=Name} = Req,
    Q = queue_for_name(Name, State),
    case Q of 
        {ok, Queue} ->
             ReqsForOwner = lists:filter(fun(Elem) ->
                         #req{owner=ElemOwner} = Elem,
                         ElemOwner =:= Owner
                end, 
             Q),
             ReqsForOwnerSorted = stoplight_request:sort_by_timestamp(ReqsForOwner),
             {true, lists:nth(1, ReqsForOwnerSorted)};
        _ ->
            false
    end.

% checks the current owners list, namespaced by name
% CurrentOwner = #req
current_owner_for_name(Name, State) -> % {ok, req#CurrentOwner} | error
    #srv_state{owners=Owners} = State, 
    dict:find(Name, Owners).

% Queue = list() of #req
queue_for_name(Name, State) -> % {ok, Queue} | error
    #srv_state{reqQs=ReqQs} = State,
    dict:find(Name, reqQs).

%%--------------------------------------------------------------------
%% Function: handle_join(JoiningPid, Pidlist, State) -> {ok, State} 
%%     JoiningPid = pid(),
%%     Pidlist = list() of pids()
%% Description: Called whenever a node joins the cluster via this node
%% directly. JoiningPid is the node that joined. Note that JoiningPid may
%% join more than once. Pidlist contains all known pids. Pidlist includes
%% JoiningPid.
%%--------------------------------------------------------------------
handle_join(JoiningPid, Pidlist, State) ->
    io:format(user, "~p:~p handle join called: ~p Pidlist: ~p~n", [?MODULE, ?LINE, JoiningPid, Pidlist]),
    {ok, State}.

%%--------------------------------------------------------------------
%% Function: handle_node_joined(JoiningPid, Pidlist, State) -> {ok, State} 
%%     JoiningPid = pid(),
%%     Pidlist = list() of pids()
%% Description: Called whenever a node joins the cluster via another node and
%%     the joining node is simply announcing its presence.
%%--------------------------------------------------------------------

handle_node_joined(JoiningPid, Pidlist, State) ->
    io:format(user, "~p:~p handle node_joined called: ~p Pidlist: ~p~n", [?MODULE, ?LINE, JoiningPid, Pidlist]),
    {ok, State}.

handle_leave(LeavingPid, Pidlist, Info, State) ->
    io:format(user, "~p:~p handle leave called: ~p, Info: ~p Pidlist: ~p~n", [?MODULE, ?LINE, LeavingPid, Info, Pidlist]),
    {ok, State}.

