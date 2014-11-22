%
% This Source Code Form is subject to the terms of the Mozilla Public
% License, v. 2.0. If a copy of the MPL was not distributed with this
% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%
% Copyright (C) 2014 Petr Gotthard <petr.gotthard@centrum.cz>
%

-module(rabbit_message_handler).
-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([start_link/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    terminate/2, code_change/3]).

-record(state, {connection, channel}).

start_link({VHost, Queue}, Domain) ->
    gen_server:start_link(?MODULE, [{VHost, Queue}, Domain], []).

init([{VHost, Queue}, Domain]) ->
    {ok, Connection} = amqp_connection:start(#amqp_params_direct{virtual_host=VHost}),
    {ok, Channel} = amqp_connection:open_channel(Connection),

    Subscribe = #'basic.consume'{queue=Queue, consumer_tag=Domain, no_ack=true},
        #'basic.consume_ok'{} = amqp_channel:call(Channel, Subscribe),

    State = #state{connection=Connection, channel=Channel},
    {ok, State}.

handle_call(_Msg, _From, State) ->
    {reply, unknown_command, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% This is the first message received
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

%% This is received when the subscription is cancelled
handle_info(#'basic.cancel_ok'{}, State) ->
    {noreply, State};

%% A delivery
handle_info({#'basic.deliver'{routing_key=Key, consumer_tag=Tag}, Content}, State) ->
    #amqp_msg{props = Properties, payload = Payload} = Content,

    rabbit_email_sender:send_email(
        construct_address(Key, Tag), Tag, Properties, Payload),
    {noreply, State};

handle_info(Msg, State) ->
    rabbit_log:info("~w", [Msg]),
    {noreply, State}.

terminate(_Reason, #state{connection=Connection, channel=Channel}) ->
    amqp_channel:close(Channel),
    amqp_connection:close(Connection),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

construct_address(Key, Tag) ->
    case binary:match(Key, <<"@">>) of
        nomatch -> <<Key/binary, $@, Tag/binary>>;
        _Else -> Key
    end.

% end of file

