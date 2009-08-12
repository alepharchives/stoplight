%%%-------------------------------------------------------------------
%%% File    : stoplight_client.erl
%%% Author  : Nate Murray <nmurray@attinteractive>
%%% Description : desc
%%% Created     : 2009-08-07
%%%-------------------------------------------------------------------

%% Stoplight client
-module(stoplight_client).
-include_lib("../include/defines.hrl").
-behaviour(gen_server).

-export([start_link/2, start_named/2]).

% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

% debug
-compile(export_all).

%% Macros
-record(state, {pid, timestamp, servers, responses}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(_Type, _Args) ->
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
    InitialState = #state{
                      pid=self(),
                      timestamp=0,
                      servers=[],
                      responses=dict:new()
                   },
    {ok, InitialState}.

%%--------------------------------------------------------------------
%% Function: handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(state, _From, State) ->
    {reply, {ok, State}, State};

handle_call({try_mutex, Name}, From, State) ->
    {Response, NewState} = handle_try_mutex(Name, From, State),
    {reply, Response, NewState};

handle_call(_Request, _From, State) -> 
    {reply, okay, State}.

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

handle_try_mutex(Name, From, State) ->
    todo.

%% interface (thrift or whatever) calls try -> on client. client needs to, at
%% the same time, pass this off to another process as well as block the caller 

%% where we're at: http://www.trapexit.org/Building_a_Non-blocking_TCP_server_using_OTP_principles
%% write a non-blocking listener. stoplight_interface_sup,
%% stoplight_interface_listener . listener immediately spawns off a lobbyist
%% and hands the request over to them. we probably need to supervise the
%% lobbyists, though im not sure why. the server actually is already monitoring
%% them, so no real reason to need to do so. better idea is have the process be
%% linked to whatever user is talking to it. 
%% 
