%%% File    : db_server.erl
%%% Author  : Savas Aydin <savasaydin@gmail.com>,
%%%           contributed by Ali Issa with registration funtionality.
%%% Description : This module is to connect to db, create table with necessary 
%%%               attributes and performs the functions constructed.
%%% Created : 10 Dec 2010 by Savas Aydin <savasaydin@gmail.com>
%%% References:  http://weblog.hypotheticalabs.com/ -  author :Kevin Smith 


-module(db_server).

-behaviour(gen_server).

%%------------------------------------------------------------------------------
%%to perform qlc functions. 
%%------------------------------------------------------------------------------
-include_lib("stdlib/include/qlc.hrl").

-define(SERVER, ?MODULE).

%%------------------------------------------------------------------------------
%%table "chat_message" has 4 attributes, username, password, message and login.
%%The idea of having login attribute is to check if user is online or not. 
%%Whenever user logs in, it will be written "logged_in" and
%%When ever user logs out, it will be written "logged_out" 
%%to give user a online status.
%%------------------------------------------------------------------------------
-record(chat_message,
	{username,
	 password,
	 message=[],
	 login=[]}).

%%------------------------------------------------------------------------------
%% Client API
%%------------------------------------------------------------------------------
-export([start_link/0, shutdown/0,regist/2,find_messages/1,login/2, logout/1, save_message/2,check_log_in/1,store_message/2,get_messages/1,clear_table/0]).

%%------------------------------------------------------------------------------
%% gen_server callbacks
%%------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state, {}).

%%------------------------------------------------------------------------------
%% Client API
%%------------------------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

find_messages(Name) ->
  case gen_server:call(?SERVER, {find_msgs, Name}) of
    {ok, Rely_Messages} ->
      Rely_Messages
  end.

save_message(Name,Message) ->
  gen_server:call(?SERVER, {save_msg, Name,Message}).

shutdown() ->
  gen_server:call(?SERVER, stop).

%% gen_server callbacks
%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
  process_flag(trap_exit,true),
  io:format("~p starting~n",[?MODULE]),
  init_store(),
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%----------------------------------------------------------------------------- 
%%find the message in table related with username
%%------------------------------------------------------------------------------
handle_call({find_msgs, Name}, _From, State) ->
  Reply_Messages = get_messages(Name),
  {reply, {ok, Reply_Messages}, State};

%%------------------------------------------------------------------------------
%%write the message in table
%%------------------------------------------------------------------------------
handle_call({save_msg, Name,  Message}, _From, State) ->
  store_message(Name, Message),
  {reply, ok, State};

%%------------------------------------------------------------------------------
%%to stop mnesia connection
%%------------------------------------------------------------------------------
handle_call(stop, _From, State) ->
  mnesia:stop(),
  {stop, normal, State};

handle_call(_Request, _From, State) ->
  {reply, ignored_message, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%------------------------------------------------------------------------------
%%                initial functions
%%------------------------------------------------------------------------------
%%starts mnesia connection, create table called chat_message,
%%with specified attributes in beginning
%%------------------------------------------------------------------------------
init_store() ->
  mnesia:create_schema([node()]),
  mnesia:start(),
  A=chat_message.message,
  mnesia:transaction(A),
  B=chat_message.login,
  mnesia:transaction(B),  
  try
    mnesia:table_info(chat_message, type)
  catch
    exit: _ ->
      mnesia:create_table(chat_message, [{attributes, record_info(fields, chat_message)},
					 {type, bag},
					 {disc_copies, [node()]}])
  end.

%%------------------------------------------------------------------------------
%%reads the row of specified username, then gets the "message" record 
%%in chat_table, returns it
%%------------------------------------------------------------------------------
get_messages(Name) ->
  F = fun() ->
	  Query = qlc:q([M || M <- mnesia:table(chat_message),
			      M#chat_message.username =:= Name]),
	  Results = qlc:e(Query),
%	  delete_messages(Results), 
%	  mnesia:write(Results#chat_message{message = []}),
	  lists:map(fun(Msg) -> Msg#chat_message.message end, Results)end,
 
  {atomic, Messages} = mnesia:transaction(F),  
  Messages.

%%------------------------------------------------------------------------------
%%write Username and password into initial records at table.
%%------------------------------------------------------------------------------
regist(User,Pass)-> 
    Ron= do(qlc:q([{X#chat_message.username} || X <- mnesia:table(chat_message),X#chat_message.username==User])),
    if
	Ron /=[] ->
	    io:format("byt fakink username tack\n");
	Ron == []->
	    Userinfo = #chat_message{username=User,password=Pass},
	    F=fun()->
		      mnesia:write(Userinfo) end,
    mnesia:transaction(F)
    end.
%%------------------------------------------------------------------------------
%%to get the value in specified row.
%%------------------------------------------------------------------------------
do(Q) ->
    F = fun() -> qlc:e(Q) end,
    {atomic, Val} = mnesia:transaction(F),
    Val.

%%------------------------------------------------------------------------------
%%reads the row of username, check password is correct 
%%If it is not it return wrong code, 
%%otherwise deletes what written in "login" attribute 
%%and writes "logged_in" to "login" attribute. 
%%------------------------------------------------------------------------------
login(UserName,Password)->
    Fun = 
        fun() ->
            mnesia:read({chat_message, UserName})
        end,
    {atomic, [Row]}=mnesia:transaction(Fun),
    case Row#chat_message.password =:= Password of
	true->
	    F = fun()->
		mnesia:delete_object(Row),
		mnesia:write(Row#chat_message{login = logged_in}) end, 
	    mnesia:transaction(F),
	    logged_in;
	false->
	    wrong_code
    end.

%%------------------------------------------------------------------------------
%%read the row of username and delete what is written in "login" record 
%%and then writes "logged_out" to "login" record. 
%%Of course if there is no such a username, then it returns "wrong name"
%%------------------------------------------------------------------------------
logout(UserName)->
    Fun = 
        fun() ->
            mnesia:read({chat_message, UserName})
        end,
    {atomic, [Row]}=mnesia:transaction(Fun),
    case [Row] == [] of
	false->
	     F = fun()->
		mnesia:delete_object(Row),
		mnesia:write(Row#chat_message{login = logged_out}) end, 
	    mnesia:transaction(F),
	    logged_out;
	true->
	    wrong_name
    end.

%%------------------------------------------------------------------------------
%%read the row of name and the writes message into "message" record at this row.
%%------------------------------------------------------------------------------
store_message(Name, Message) ->
    F = fun()->
		[E]=mnesia:read(chat_message,Name),
		mnesia:delete_object(E),
		mnesia:write(E#chat_message{message = Message})
    end, 
    mnesia:transaction(F).

%%------------------------------------------------------------------------------
%%to check what is written in "login" record. 
%%If it is "logged_in" then returns "online", otherwise returns "offline".
%%------------------------------------------------------------------------------
check_log_in(Name)->
    Fun = fun() ->
            mnesia:read({chat_message, Name})
	  end,
    {atomic, [Row]}=mnesia:transaction(Fun),
    case Row#chat_message.login =:= logged_in of
	    true->
		online;
	    false->
		offline
     end.

clear_table()->
    mnesia:clear_table(chat_message).
