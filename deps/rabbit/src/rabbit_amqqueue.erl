%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2017 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_amqqueue).

-export([recover/0, stop/0, start/1, declare/5, declare/6,
         delete_immediately/1, delete/3, purge/1, forget_all_durable/1,
         delete_crashed/1, delete_crashed_internal/1]).
-export([pseudo_queue/2, immutable/1]).
-export([lookup/1, not_found_or_absent/1, with/2, with/3, with_or_die/2,
         assert_equivalence/5,
         check_exclusive_access/2, with_exclusive_access_or_die/3,
         stat/1, deliver/2, requeue/3, ack/3, reject/4]).
-export([list/0, list/1, info_keys/0, info/1, info/2, info_all/1, info_all/2,
         info_all/5, info_local/1, list_names/0, list_local_names/0]).
-export([list_down/1]).
-export([force_event_refresh/1, notify_policy_changed/1]).
-export([consumers/1, consumers_all/1,  consumers_all/3, consumer_info_keys/0]).
-export([basic_get/4, basic_consume/10, basic_cancel/4, notify_decorators/1]).
-export([notify_sent/2, notify_sent_queue_down/1, resume/2]).
-export([notify_down_all/2, notify_down_all/3, activate_limit_all/2, credit/5]).
-export([on_node_up/1, on_node_down/1]).
-export([update/2, store_queue/1, update_decorators/1, policy_changed/2]).
-export([update_mirroring/1, sync_mirrors/1, cancel_sync_mirrors/1]).
-export([is_mirrored/1, is_dead_exclusive/1]). % Note: exported due to use in qlc expression.

-export([pid_of/1, pid_of/2]).

%% internal
-export([internal_declare/2, internal_delete/1, run_backing_queue/3,
         set_ram_duration_target/2, set_maximum_since_use/2]).

-include("rabbit.hrl").
-include_lib("stdlib/include/qlc.hrl").

-define(INTEGER_ARG_TYPES, [byte, short, signedint, long,
                            unsignedbyte, unsignedshort, unsignedint]).

-define(MORE_CONSUMER_CREDIT_AFTER, 50).

%%----------------------------------------------------------------------------

-export_type([name/0, qmsg/0, absent_reason/0]).

-type name() :: rabbit_types:r('queue').
-type qpids() :: [pid()].
-type qlen() :: rabbit_types:ok(non_neg_integer()).
-type qfun(A) :: fun ((rabbit_types:amqqueue()) -> A | no_return()).
-type qmsg() :: {name(), pid(), msg_id(), boolean(), rabbit_types:message()}.
-type msg_id() :: non_neg_integer().
-type ok_or_errors() ::
        'ok' | {'error', [{'error' | 'exit' | 'throw', any()}]}.
-type absent_reason() :: 'nodedown' | 'crashed'.
-type queue_or_absent() :: rabbit_types:amqqueue() |
                           {'absent', rabbit_types:amqqueue(),absent_reason()}.
-type not_found_or_absent() ::
        'not_found' | {'absent', rabbit_types:amqqueue(), absent_reason()}.
-spec recover() -> [rabbit_types:amqqueue()].
-spec stop() -> 'ok'.
-spec start([rabbit_types:amqqueue()]) -> 'ok'.
-spec declare
        (name(), boolean(), boolean(), rabbit_framing:amqp_table(),
         rabbit_types:maybe(pid())) ->
            {'new' | 'existing' | 'absent' | 'owner_died',
             rabbit_types:amqqueue()} |
            rabbit_types:channel_exit().
-spec declare
        (name(), boolean(), boolean(), rabbit_framing:amqp_table(),
         rabbit_types:maybe(pid()), node()) ->
            {'new' | 'existing' | 'owner_died', rabbit_types:amqqueue()} |
            {'absent', rabbit_types:amqqueue(), absent_reason()} |
            rabbit_types:channel_exit().
-spec internal_declare(rabbit_types:amqqueue(), boolean()) ->
          queue_or_absent() | rabbit_misc:thunk(queue_or_absent()).
-spec update
        (name(), fun((rabbit_types:amqqueue()) -> rabbit_types:amqqueue())) ->
            'not_found' | rabbit_types:amqqueue().
-spec lookup
        (name()) ->
            rabbit_types:ok(rabbit_types:amqqueue()) |
            rabbit_types:error('not_found');
        ([name()]) ->
            [rabbit_types:amqqueue()].
-spec not_found_or_absent(name()) -> not_found_or_absent().
-spec with(name(), qfun(A)) ->
          A | rabbit_types:error(not_found_or_absent()).
-spec with(name(), qfun(A), fun((not_found_or_absent()) -> B)) -> A | B.
-spec with_or_die(name(), qfun(A)) -> A | rabbit_types:channel_exit().
-spec assert_equivalence
        (rabbit_types:amqqueue(), boolean(), boolean(),
         rabbit_framing:amqp_table(), rabbit_types:maybe(pid())) ->
            'ok' | rabbit_types:channel_exit() | rabbit_types:connection_exit().
-spec check_exclusive_access(rabbit_types:amqqueue(), pid()) ->
          'ok' | rabbit_types:channel_exit().
-spec with_exclusive_access_or_die(name(), pid(), qfun(A)) ->
          A | rabbit_types:channel_exit().
-spec list() -> [rabbit_types:amqqueue()].
-spec list(rabbit_types:vhost()) -> [rabbit_types:amqqueue()].
-spec list_names() -> [rabbit_amqqueue:name()].
-spec list_down(rabbit_types:vhost()) -> [rabbit_types:amqqueue()].
-spec info_keys() -> rabbit_types:info_keys().
-spec info(rabbit_types:amqqueue()) -> rabbit_types:infos().
-spec info(rabbit_types:amqqueue(), rabbit_types:info_keys()) ->
          rabbit_types:infos().
-spec info_all(rabbit_types:vhost()) -> [rabbit_types:infos()].
-spec info_all(rabbit_types:vhost(), rabbit_types:info_keys()) ->
          [rabbit_types:infos()].
-type info_all_filter() :: 'all' | 'online' | 'offline' | 'local'.
-spec info_all
        (rabbit_types:vhost(), rabbit_types:info_keys(), info_all_filter(),
         reference(), pid()) ->
            'ok'.
-spec force_event_refresh(reference()) -> 'ok'.
-spec notify_policy_changed(rabbit_types:amqqueue()) -> 'ok'.
-spec consumers(rabbit_types:amqqueue()) ->
          [{pid(), rabbit_types:ctag(), boolean(), non_neg_integer(),
            rabbit_framing:amqp_table()}].
-spec consumer_info_keys() -> rabbit_types:info_keys().
-spec consumers_all(rabbit_types:vhost()) ->
          [{name(), pid(), rabbit_types:ctag(), boolean(),
            non_neg_integer(), rabbit_framing:amqp_table()}].
-spec consumers_all(rabbit_types:vhost(), reference(), pid()) -> 'ok'.
-spec stat(rabbit_types:amqqueue()) ->
          {'ok', non_neg_integer(), non_neg_integer()}.
-spec delete_immediately(qpids()) -> 'ok'.
-spec delete
        (rabbit_types:amqqueue(), 'false', 'false') ->
            qlen();
        (rabbit_types:amqqueue(), 'true' , 'false') ->
            qlen() | rabbit_types:error('in_use');
        (rabbit_types:amqqueue(), 'false', 'true' ) ->
            qlen() | rabbit_types:error('not_empty');
        (rabbit_types:amqqueue(), 'true' , 'true' ) ->
            qlen() |
            rabbit_types:error('in_use') |
            rabbit_types:error('not_empty').
-spec delete_crashed(rabbit_types:amqqueue()) -> 'ok'.
-spec delete_crashed_internal(rabbit_types:amqqueue()) -> 'ok'.
-spec purge(rabbit_types:amqqueue()) -> qlen().
-spec forget_all_durable(node()) -> 'ok'.
-spec deliver([rabbit_types:amqqueue()], rabbit_types:delivery()) ->
                        qpids().
-spec requeue(pid(), [msg_id()],  pid()) -> 'ok'.
-spec ack(pid(), [msg_id()], pid()) -> 'ok'.
-spec reject(pid(), [msg_id()], boolean(), pid()) -> 'ok'.
-spec notify_down_all(qpids(), pid()) -> ok_or_errors().
-spec notify_down_all(qpids(), pid(), non_neg_integer()) ->
          ok_or_errors().
-spec activate_limit_all(qpids(), pid()) -> ok_or_errors().
-spec basic_get(rabbit_types:amqqueue(), pid(), boolean(), pid()) ->
          {'ok', non_neg_integer(), qmsg()} | 'empty'.
-spec credit
        (rabbit_types:amqqueue(), pid(), rabbit_types:ctag(), non_neg_integer(),
         boolean()) ->
            'ok'.
-spec basic_consume
        (rabbit_types:amqqueue(), boolean(), pid(), pid(), boolean(),
         non_neg_integer(), rabbit_types:ctag(), boolean(),
         rabbit_framing:amqp_table(), any()) ->
            rabbit_types:ok_or_error('exclusive_consume_unavailable').
-spec basic_cancel
        (rabbit_types:amqqueue(), pid(), rabbit_types:ctag(), any()) -> 'ok'.
-spec notify_decorators(rabbit_types:amqqueue()) -> 'ok'.
-spec resume(pid(), pid()) -> 'ok'.
-spec internal_delete(name()) ->
          rabbit_types:ok_or_error('not_found') |
          rabbit_types:connection_exit() |
          fun (() ->
              rabbit_types:ok_or_error('not_found') |
              rabbit_types:connection_exit()).
-spec run_backing_queue
        (pid(), atom(), (fun ((atom(), A) -> {[rabbit_types:msg_id()], A}))) ->
            'ok'.
-spec set_ram_duration_target(pid(), number() | 'infinity') -> 'ok'.
-spec set_maximum_since_use(pid(), non_neg_integer()) -> 'ok'.
-spec on_node_up(node()) -> 'ok'.
-spec on_node_down(node()) -> 'ok'.
-spec pseudo_queue(name(), pid()) -> rabbit_types:amqqueue().
-spec immutable(rabbit_types:amqqueue()) -> rabbit_types:amqqueue().
-spec store_queue(rabbit_types:amqqueue()) -> 'ok'.
-spec update_decorators(name()) -> 'ok'.
-spec policy_changed(rabbit_types:amqqueue(), rabbit_types:amqqueue()) ->
          'ok'.
-spec update_mirroring(pid()) -> 'ok'.
-spec sync_mirrors(rabbit_types:amqqueue() | pid()) ->
          'ok' | rabbit_types:error('not_mirrored').
-spec cancel_sync_mirrors(rabbit_types:amqqueue() | pid()) ->
          'ok' | {'ok', 'not_syncing'}.
-spec is_mirrored(rabbit_types:amqqueue()) -> boolean().

-spec pid_of(rabbit_types:amqqueue()) ->
          {'ok', pid()} | rabbit_types:error('not_found').
-spec pid_of(rabbit_types:vhost(), rabbit_misc:resource_name()) ->
          {'ok', pid()} | rabbit_types:error('not_found').

%%----------------------------------------------------------------------------

-define(CONSUMER_INFO_KEYS,
        [queue_name, channel_pid, consumer_tag, ack_required, prefetch_count,
         arguments]).

recover() ->
    %% Clear out remnants of old incarnation, in case we restarted
    %% faster than other nodes handled DOWN messages from us.
    on_node_down(node()),
    DurableQueues = queues_to_recover(),

    L = length(DurableQueues),

    %% if there are not enough file handles, the server might hang
    %% when trying to recover queues, warn the user:
    case file_handle_cache:get_limit() < L of
        true ->
            rabbit_log:warning(
              "Recovering ~p queues, available file handles: ~p. Please increase max open file handles limit to at least ~p!~n",
              [L, file_handle_cache:get_limit(), L]);
        false ->
            ok
    end,

    {ok, BQ} = application:get_env(rabbit, backing_queue_module),

    %% We rely on BQ:start/1 returning the recovery terms in the same
    %% order as the supplied queue names, so that we can zip them together
    %% for further processing in recover_durable_queues.
    {ok, OrderedRecoveryTerms} =
        BQ:start([QName || #amqqueue{name = QName} <- DurableQueues]),
    {ok,_} = supervisor:start_child(
               rabbit_sup,
               {rabbit_amqqueue_sup_sup,
                {rabbit_amqqueue_sup_sup, start_link, []},
                transient, infinity, supervisor, [rabbit_amqqueue_sup_sup]}),
    recover_durable_queues(lists:zip(DurableQueues, OrderedRecoveryTerms)).

stop() ->
    ok = supervisor:terminate_child(rabbit_sup, rabbit_amqqueue_sup_sup),
    ok = supervisor:delete_child(rabbit_sup, rabbit_amqqueue_sup_sup),
    {ok, BQ} = application:get_env(rabbit, backing_queue_module),
    ok = BQ:stop().

start(Qs) ->
    %% At this point all recovered queues and their bindings are
    %% visible to routing, so now it is safe for them to complete
    %% their initialisation (which may involve interacting with other
    %% queues).
    [Pid ! {self(), go} || #amqqueue{pid = Pid} <- Qs],
    ok.

queues_to_recover() ->
    DurableQueues = find_durable_queues(),
    VHosts = rabbit_vhost:list(),

    {QueuesWithVhost, QueuesWithoutVhost} = lists:partition(
        fun(#amqqueue{name = #resource{virtual_host = VHost}}) ->
            lists:member(VHost, VHosts)
        end,
        DurableQueues),

    {LocalQueuesWithoutVhost, _RemoteQueuesWithoutVhost} = lists:partition(
        fun(#amqqueue{pid = QPid}) -> node(QPid) == node() end,
        QueuesWithoutVhost),

    {atomic, ok} =
        mnesia:sync_transaction(
            fun () ->
                [ internal_delete1(Name, false)
                  || #amqqueue{name = Name} <- LocalQueuesWithoutVhost ],
                ok
            end),

    QueuesWithVhost.

find_durable_queues() ->
    Node = node(),
    mnesia:async_dirty(
      fun () ->
              qlc:e(qlc:q([Q || Q = #amqqueue{name = Name,
                                              pid  = Pid}
                                    <- mnesia:table(rabbit_durable_queue),
                                node(Pid) == Node andalso
                                %% Terminations on node down will not remove the rabbit_queue
                                %% record if it is a mirrored queue (such info is now obtained from
                                %% the policy). Thus, we must check if the local pid is alive
                                %% - if the record is present - in order to restart.
                                                    (mnesia:read(rabbit_queue, Name, read) =:= []
                                                     orelse not erlang:is_process_alive(Pid))]))
      end).

recover_durable_queues(QueuesAndRecoveryTerms) ->
    {Results, Failures} =
        gen_server2:mcall(
          [{rabbit_amqqueue_sup_sup:start_queue_process(node(), Q, recovery),
            {init, {self(), Terms}}} || {Q, Terms} <- QueuesAndRecoveryTerms]),
    [rabbit_log:error("Queue ~p failed to initialise: ~p~n",
                      [Pid, Error]) || {Pid, Error} <- Failures],
    [Q || {_, {new, Q}} <- Results].

declare(QueueName, Durable, AutoDelete, Args, Owner) ->
    declare(QueueName, Durable, AutoDelete, Args, Owner, node()).


%% The Node argument suggests where the queue (master if mirrored)
%% should be. Note that in some cases (e.g. with "nodes" policy in
%% effect) this might not be possible to satisfy.
declare(QueueName, Durable, AutoDelete, Args, Owner, Node) ->
    ok = check_declare_arguments(QueueName, Args),
    Q = rabbit_queue_decorator:set(
          rabbit_policy:set(#amqqueue{name               = QueueName,
                                      durable            = Durable,
                                      auto_delete        = AutoDelete,
                                      arguments          = Args,
                                      exclusive_owner    = Owner,
                                      pid                = none,
                                      slave_pids         = [],
                                      sync_slave_pids    = [],
                                      recoverable_slaves = [],
                                      gm_pids            = [],
                                      state              = live,
                                      policy_version     = 0 })),

    Node1 = case rabbit_queue_master_location_misc:get_location(Q)  of
              {ok, Node0}  -> Node0;
              {error, _}   -> Node
            end,

    Node1 = rabbit_mirror_queue_misc:initial_queue_node(Q, Node1),
    gen_server2:call(
      rabbit_amqqueue_sup_sup:start_queue_process(Node1, Q, declare),
      {init, new}, infinity).

internal_declare(Q, true) ->
    rabbit_misc:execute_mnesia_tx_with_tail(
      fun () ->
              ok = store_queue(Q#amqqueue{state = live}),
              rabbit_misc:const(Q)
      end);
internal_declare(Q = #amqqueue{name = QueueName}, false) ->
    rabbit_misc:execute_mnesia_tx_with_tail(
      fun () ->
              case mnesia:wread({rabbit_queue, QueueName}) of
                  [] ->
                      case not_found_or_absent(QueueName) of
                          not_found           -> Q1 = rabbit_policy:set(Q),
                                                 Q2 = Q1#amqqueue{state = live},
                                                 ok = store_queue(Q2),
                                                 B = add_default_binding(Q1),
                                                 fun () -> B(), Q1 end;
                          {absent, _Q, _} = R -> rabbit_misc:const(R)
                      end;
                  [ExistingQ] ->
                      rabbit_misc:const(ExistingQ)
              end
      end).

update(Name, Fun) ->
    case mnesia:wread({rabbit_queue, Name}) of
        [Q = #amqqueue{durable = Durable}] ->
            Q1 = Fun(Q),
            ok = mnesia:write(rabbit_queue, Q1, write),
            case Durable of
                true -> ok = mnesia:write(rabbit_durable_queue, Q1, write);
                _    -> ok
            end,
            Q1;
        [] ->
            not_found
    end.

store_queue(Q = #amqqueue{durable = true}) ->
    ok = mnesia:write(rabbit_durable_queue,
                      Q#amqqueue{slave_pids      = [],
                                 sync_slave_pids = [],
                                 gm_pids         = [],
                                 decorators      = undefined}, write),
    store_queue_ram(Q);
store_queue(Q = #amqqueue{durable = false}) ->
    store_queue_ram(Q).

store_queue_ram(Q) ->
    ok = mnesia:write(rabbit_queue, rabbit_queue_decorator:set(Q), write).

update_decorators(Name) ->
    rabbit_misc:execute_mnesia_transaction(
      fun() ->
              case mnesia:wread({rabbit_queue, Name}) of
                  [Q] -> store_queue_ram(Q),
                         ok;
                  []  -> ok
              end
      end).

policy_changed(Q1 = #amqqueue{decorators = Decorators1},
               Q2 = #amqqueue{decorators = Decorators2}) ->
    rabbit_mirror_queue_misc:update_mirrors(Q1, Q2),
    D1 = rabbit_queue_decorator:select(Decorators1),
    D2 = rabbit_queue_decorator:select(Decorators2),
    [ok = M:policy_changed(Q1, Q2) || M <- lists:usort(D1 ++ D2)],
    %% Make sure we emit a stats event even if nothing
    %% mirroring-related has changed - the policy may have changed anyway.
    notify_policy_changed(Q1).

add_default_binding(#amqqueue{name = QueueName}) ->
    ExchangeName = rabbit_misc:r(QueueName, exchange, <<>>),
    RoutingKey = QueueName#resource.name,
    rabbit_binding:add(#binding{source      = ExchangeName,
                                destination = QueueName,
                                key         = RoutingKey,
                                args        = []}).

lookup([])     -> [];                             %% optimisation
lookup([Name]) -> ets:lookup(rabbit_queue, Name); %% optimisation
lookup(Names) when is_list(Names) ->
    %% Normally we'd call mnesia:dirty_read/1 here, but that is quite
    %% expensive for reasons explained in rabbit_misc:dirty_read/1.
    lists:append([ets:lookup(rabbit_queue, Name) || Name <- Names]);
lookup(Name) ->
    rabbit_misc:dirty_read({rabbit_queue, Name}).

not_found_or_absent(Name) ->
    %% NB: we assume that the caller has already performed a lookup on
    %% rabbit_queue and not found anything
    case mnesia:read({rabbit_durable_queue, Name}) of
        []  -> not_found;
        [Q] -> {absent, Q, nodedown} %% Q exists on stopped node
    end.

not_found_or_absent_dirty(Name) ->
    %% We should read from both tables inside a tx, to get a
    %% consistent view. But the chances of an inconsistency are small,
    %% and only affect the error kind.
    case rabbit_misc:dirty_read({rabbit_durable_queue, Name}) of
        {error, not_found} -> not_found;
        {ok, Q}            -> {absent, Q, nodedown}
    end.

with(Name, F, E) ->
    with(Name, F, E, 2000).

with(Name, F, E, RetriesLeft) ->
    case lookup(Name) of
        {ok, Q = #amqqueue{}} when RetriesLeft =:= 0 ->
            %% Something bad happened to that queue, we are bailing out
            %% on processing current request.
            E({absent, Q, timeout});
        {ok, Q = #amqqueue{state = crashed}} ->
            E({absent, Q, crashed});
        {ok, Q = #amqqueue{pid = QPid}} ->
            %% We check is_process_alive(QPid) in case we receive a
            %% nodedown (for example) in F() that has nothing to do
            %% with the QPid. F() should be written s.t. that this
            %% cannot happen, so we bail if it does since that
            %% indicates a code bug and we don't want to get stuck in
            %% the retry loop.
            rabbit_misc:with_exit_handler(
              fun () -> false = rabbit_mnesia:is_process_alive(QPid),
                        timer:sleep(30),
                        with(Name, F, E, RetriesLeft - 1)
              end, fun () -> F(Q) end);
        {error, not_found} ->
            E(not_found_or_absent_dirty(Name))
    end.

with(Name, F) -> with(Name, F, fun (E) -> {error, E} end).

with_or_die(Name, F) ->
    with(Name, F, fun (not_found)           -> rabbit_misc:not_found(Name);
                      ({absent, Q, Reason}) -> rabbit_misc:absent(Q, Reason)
                  end).

assert_equivalence(#amqqueue{name        = QName,
                             durable     = Durable,
                             auto_delete = AD} = Q,
                   Durable1, AD1, Args1, Owner) ->
    rabbit_misc:assert_field_equivalence(Durable, Durable1, QName, durable),
    rabbit_misc:assert_field_equivalence(AD, AD1, QName, auto_delete),
    assert_args_equivalence(Q, Args1),
    check_exclusive_access(Q, Owner, strict).

check_exclusive_access(Q, Owner) -> check_exclusive_access(Q, Owner, lax).

check_exclusive_access(#amqqueue{exclusive_owner = Owner}, Owner, _MatchType) ->
    ok;
check_exclusive_access(#amqqueue{exclusive_owner = none}, _ReaderPid, lax) ->
    ok;
check_exclusive_access(#amqqueue{name = QueueName}, _ReaderPid, _MatchType) ->
    rabbit_misc:protocol_error(
      resource_locked,
      "cannot obtain exclusive access to locked ~s",
      [rabbit_misc:rs(QueueName)]).

with_exclusive_access_or_die(Name, ReaderPid, F) ->
    with_or_die(Name,
                fun (Q) -> check_exclusive_access(Q, ReaderPid), F(Q) end).

assert_args_equivalence(#amqqueue{name = QueueName, arguments = Args},
                        RequiredArgs) ->
    rabbit_misc:assert_args_equivalence(Args, RequiredArgs, QueueName,
                                        [Key || {Key, _Fun} <- declare_args()]).

check_declare_arguments(QueueName, Args) ->
    check_arguments(QueueName, Args, declare_args()).

check_consume_arguments(QueueName, Args) ->
    check_arguments(QueueName, Args, consume_args()).

check_arguments(QueueName, Args, Validators) ->
    [case rabbit_misc:table_lookup(Args, Key) of
         undefined -> ok;
         TypeVal   -> case Fun(TypeVal, Args) of
                          ok             -> ok;
                          {error, Error} -> rabbit_misc:protocol_error(
                                              precondition_failed,
                                              "invalid arg '~s' for ~s: ~255p",
                                              [Key, rabbit_misc:rs(QueueName),
                                               Error])
                      end
     end || {Key, Fun} <- Validators],
    ok.

declare_args() ->
    [{<<"x-expires">>,                 fun check_expires_arg/2},
     {<<"x-message-ttl">>,             fun check_message_ttl_arg/2},
     {<<"x-dead-letter-exchange">>,    fun check_dlxname_arg/2},
     {<<"x-dead-letter-routing-key">>, fun check_dlxrk_arg/2},
     {<<"x-max-length">>,              fun check_non_neg_int_arg/2},
     {<<"x-max-length-bytes">>,        fun check_non_neg_int_arg/2},
     {<<"x-max-priority">>,            fun check_max_priority_arg/2},
     {<<"x-queue-mode">>,              fun check_queue_mode/2}].

consume_args() -> [{<<"x-priority">>,              fun check_int_arg/2},
                   {<<"x-cancel-on-ha-failover">>, fun check_bool_arg/2}].

check_int_arg({Type, _}, _) ->
    case lists:member(Type, ?INTEGER_ARG_TYPES) of
        true  -> ok;
        false -> {error, {unacceptable_type, Type}}
    end.

check_bool_arg({bool, _}, _) -> ok;
check_bool_arg({Type, _}, _) -> {error, {unacceptable_type, Type}}.

check_non_neg_int_arg({Type, Val}, Args) ->
    case check_int_arg({Type, Val}, Args) of
        ok when Val >= 0 -> ok;
        ok               -> {error, {value_negative, Val}};
        Error            -> Error
    end.

check_expires_arg({Type, Val}, Args) ->
    case check_int_arg({Type, Val}, Args) of
        ok when Val == 0 -> {error, {value_zero, Val}};
        ok               -> rabbit_misc:check_expiry(Val);
        Error            -> Error
    end.

check_message_ttl_arg({Type, Val}, Args) ->
    case check_int_arg({Type, Val}, Args) of
        ok    -> rabbit_misc:check_expiry(Val);
        Error -> Error
    end.

check_max_priority_arg({Type, Val}, Args) ->
    case check_non_neg_int_arg({Type, Val}, Args) of
        ok when Val =< ?MAX_SUPPORTED_PRIORITY -> ok;
        ok                                     -> {error, {max_value_exceeded, Val}};
        Error                                  -> Error
    end.

%% Note that the validity of x-dead-letter-exchange is already verified
%% by rabbit_channel's queue.declare handler.
check_dlxname_arg({longstr, _}, _) -> ok;
check_dlxname_arg({Type,    _}, _) -> {error, {unacceptable_type, Type}}.

check_dlxrk_arg({longstr, _}, Args) ->
    case rabbit_misc:table_lookup(Args, <<"x-dead-letter-exchange">>) of
        undefined -> {error, routing_key_but_no_dlx_defined};
        _         -> ok
    end;
check_dlxrk_arg({Type,    _}, _Args) ->
    {error, {unacceptable_type, Type}}.

check_queue_mode({longstr, Val}, _Args) ->
    case lists:member(Val, [<<"default">>, <<"lazy">>]) of
        true  -> ok;
        false -> {error, invalid_queue_mode}
    end;
check_queue_mode({Type,    _}, _Args) ->
    {error, {unacceptable_type, Type}}.

list() -> mnesia:dirty_match_object(rabbit_queue, #amqqueue{_ = '_'}).

list_names() -> mnesia:dirty_all_keys(rabbit_queue).

list_local_names() ->
    [ Q#amqqueue.name || #amqqueue{state = State, pid = QPid} = Q <- list(),
           State =/= crashed,
           node() =:= node(QPid) ].

list(VHostPath) ->
    list(VHostPath, rabbit_queue).

%% Not dirty_match_object since that would not be transactional when used in a
%% tx context
list(VHostPath, TableName) ->
    mnesia:async_dirty(
      fun () ->
              mnesia:match_object(
                TableName,
                #amqqueue{name = rabbit_misc:r(VHostPath, queue), _ = '_'},
                read)
      end).

list_down(VHostPath) ->
    case rabbit_vhost:exists(VHostPath) of
        false -> [];
        true  ->
            Present = list(VHostPath),
            Durable = list(VHostPath, rabbit_durable_queue),
            PresentS = sets:from_list([N || #amqqueue{name = N} <- Present]),
            sets:to_list(sets:filter(fun (#amqqueue{name = N}) ->
                                             not sets:is_element(N, PresentS)
                                     end, sets:from_list(Durable)))
    end.

info_keys() -> rabbit_amqqueue_process:info_keys().

map(Qs, F) -> rabbit_misc:filter_exit_map(F, Qs).

info(Q = #amqqueue{ state = crashed }) -> info_down(Q, crashed);
info(#amqqueue{ pid = QPid }) -> delegate:call(QPid, info).

info(Q = #amqqueue{ state = crashed }, Items) ->
    info_down(Q, Items, crashed);
info(#amqqueue{ pid = QPid }, Items) ->
    case delegate:call(QPid, {info, Items}) of
        {ok, Res}      -> Res;
        {error, Error} -> throw(Error)
    end.

info_down(Q, DownReason) ->
    info_down(Q, rabbit_amqqueue_process:info_keys(), DownReason).

info_down(Q, Items, DownReason) ->
    [{Item, i_down(Item, Q, DownReason)} || Item <- Items].

i_down(name,               #amqqueue{name               = Name}, _) -> Name;
i_down(durable,            #amqqueue{durable            = Dur},  _) -> Dur;
i_down(auto_delete,        #amqqueue{auto_delete        = AD},   _) -> AD;
i_down(arguments,          #amqqueue{arguments          = Args}, _) -> Args;
i_down(pid,                #amqqueue{pid                = QPid}, _) -> QPid;
i_down(recoverable_slaves, #amqqueue{recoverable_slaves = RS},   _) -> RS;
i_down(state, _Q, DownReason)                                     -> DownReason;
i_down(K, _Q, _DownReason) ->
    case lists:member(K, rabbit_amqqueue_process:info_keys()) of
        true  -> '';
        false -> throw({bad_argument, K})
    end.

info_all(VHostPath) ->
    map(list(VHostPath), fun (Q) -> info(Q) end) ++
        map(list_down(VHostPath), fun (Q) -> info_down(Q, down) end).

info_all(VHostPath, Items) ->
    map(list(VHostPath), fun (Q) -> info(Q, Items) end) ++
        map(list_down(VHostPath), fun (Q) -> info_down(Q, Items, down) end).

info_all_partial_emit(VHostPath, Items, all, Ref, AggregatorPid) ->
    info_all_partial_emit(VHostPath, Items, online, Ref, AggregatorPid),
    info_all_partial_emit(VHostPath, Items, offline, Ref, AggregatorPid);
info_all_partial_emit(VHostPath, Items, online, Ref, AggregatorPid) ->
    rabbit_control_misc:emitting_map_with_exit_handler(
      AggregatorPid, Ref, fun(Q) -> info(Q, Items) end,
      list(VHostPath),
      continue);
info_all_partial_emit(VHostPath, Items, offline, Ref, AggregatorPid) ->
    rabbit_control_misc:emitting_map_with_exit_handler(
      AggregatorPid, Ref, fun(Q) -> info_down(Q, Items, down) end,
      list_down(VHostPath),
      continue);
info_all_partial_emit(VHostPath, Items, local, Ref, AggregatorPid) ->
    rabbit_control_misc:emitting_map_with_exit_handler(
      AggregatorPid, Ref, fun(Q) -> info(Q, Items) end,
      list_local(VHostPath),
      continue).

info_all(VHostPath, Items, Filter, Ref, AggregatorPid) ->
    info_all_partial_emit(VHostPath, Items, Filter, Ref, AggregatorPid),
    %% Previous map(s) are incomplete, finalize emission
    rabbit_control_misc:emitting_map(AggregatorPid, Ref, fun(_) -> no_op end, []).

info_local(VHostPath) ->
    map(list_local(VHostPath), fun (Q) -> info(Q, [name]) end).

list_local(VHostPath) ->
    [ Q || #amqqueue{state = State, pid=QPid} = Q <- list(VHostPath),
           State =/= crashed,
           node() =:= node(QPid) ].

force_event_refresh(Ref) ->
    [gen_server2:cast(Q#amqqueue.pid,
                      {force_event_refresh, Ref}) || Q <- list()],
    ok.

notify_policy_changed(#amqqueue{pid = QPid}) ->
    gen_server2:cast(QPid, policy_changed).

consumers(#amqqueue{ pid = QPid }) -> delegate:call(QPid, consumers).

consumer_info_keys() -> ?CONSUMER_INFO_KEYS.

consumers_all(VHostPath) ->
    ConsumerInfoKeys = consumer_info_keys(),
    lists:append(
      map(list(VHostPath),
          fun(Q) -> get_queue_consumer_info(Q, ConsumerInfoKeys) end)).

consumers_all(VHostPath, Ref, AggregatorPid) ->
    ConsumerInfoKeys = consumer_info_keys(),
    rabbit_control_misc:emitting_map(
      AggregatorPid, Ref,
      fun(Q) -> get_queue_consumer_info(Q, ConsumerInfoKeys) end,
      list(VHostPath)).

get_queue_consumer_info(Q, ConsumerInfoKeys) ->
    [lists:zip(ConsumerInfoKeys,
               [Q#amqqueue.name, ChPid, CTag,
                AckRequired, Prefetch, Args]) ||
        {ChPid, CTag, AckRequired, Prefetch, Args} <- consumers(Q)].

stat(#amqqueue{pid = QPid}) -> delegate:call(QPid, stat).

pid_of(#amqqueue{pid = Pid}) -> Pid.
pid_of(VHost, QueueName) ->
  case lookup(rabbit_misc:r(VHost, queue, QueueName)) of
    {ok, Q}                -> pid_of(Q);
    {error, not_found} = E -> E
  end.

delete_immediately(QPids) ->
    [gen_server2:cast(QPid, delete_immediately) || QPid <- QPids],
    ok.

delete(Q, IfUnused, IfEmpty) ->
    case wait_for_promoted_or_stopped(Q) of
        {promoted, _Q1 = #amqqueue{pid = QPid}} ->
            delegate:call(QPid, {delete, IfUnused, IfEmpty});
        {stopped, Q1} ->
            #resource{name = Name, virtual_host = Vhost} = Q1#amqqueue.name,
            case IfEmpty of
                true ->
                    rabbit_log:error("Queue ~s in vhost ~s has its master node down and "
                                     "no mirrors available or eligible for promotion. "
                                     "The queue may be non-empty. "
                                     "Refusing to force-delete.",
                                     [Name, Vhost]),
                    {error, not_empty};
                false ->
                    rabbit_log:warning("Queue ~s in vhost ~s has its master node is down and "
                                       "no mirrors available or eligible for promotion. "
                                       "Forcing queue deletion.",
                                       [Name, Vhost]),
                    delete_crashed_internal(Q1),
                    {ok, 0}
            end;
        {error, not_found} ->
            %% Assume the queue was deleted
            {ok, 0}
    end.

-spec wait_for_promoted_or_stopped(#amqqueue{}) -> {promoted, #amqqueue{}} | {stopped, #amqqueue{}} | {error, not_found}.
wait_for_promoted_or_stopped(#amqqueue{name = QName}) ->
    case lookup(QName) of
        {ok, Q = #amqqueue{pid = QPid, slave_pids = SPids}} ->
            case rabbit_mnesia:is_process_alive(QPid) of
                true  -> {promoted, Q};
                false ->
                    case lists:any(fun(Pid) ->
                                       rabbit_mnesia:is_process_alive(Pid)
                                   end, SPids) of
                        %% There is a live slave. May be promoted
                        true ->
                            timer:sleep(100),
                            wait_for_promoted_or_stopped(Q);
                        %% All slave pids are stopped.
                        %% No process left for the queue
                        false -> {stopped, Q}
                    end
            end;
        {error, not_found} ->
            {error, not_found}
    end.

delete_crashed(#amqqueue{ pid = QPid } = Q) ->
    ok = rpc:call(node(QPid), ?MODULE, delete_crashed_internal, [Q]).

delete_crashed_internal(Q = #amqqueue{ name = QName }) ->
    {ok, BQ} = application:get_env(rabbit, backing_queue_module),
    BQ:delete_crashed(Q),
    ok = internal_delete(QName).

purge(#amqqueue{ pid = QPid }) -> delegate:call(QPid, purge).

requeue(QPid, MsgIds, ChPid) -> delegate:call(QPid, {requeue, MsgIds, ChPid}).

ack(QPid, MsgIds, ChPid) -> delegate:cast(QPid, {ack, MsgIds, ChPid}).

reject(QPid, Requeue, MsgIds, ChPid) ->
    delegate:cast(QPid, {reject, Requeue, MsgIds, ChPid}).

notify_down_all(QPids, ChPid) ->
    notify_down_all(QPids, ChPid, ?CHANNEL_OPERATION_TIMEOUT).

notify_down_all(QPids, ChPid, Timeout) ->
    case rpc:call(node(), delegate, call,
                  [QPids, {notify_down, ChPid}], Timeout) of
        {badrpc, timeout} -> {error, {channel_operation_timeout, Timeout}};
        {badrpc, Reason}  -> {error, Reason};
        {_, Bads} ->
            case lists:filter(
                   fun ({_Pid, {exit, {R, _}, _}}) ->
                           rabbit_misc:is_abnormal_exit(R);
                       ({_Pid, _})                 -> false
                   end, Bads) of
                []    -> ok;
                Bads1 -> {error, Bads1}
            end;
        Error         -> {error, Error}
    end.

activate_limit_all(QPids, ChPid) ->
    delegate:cast(QPids, {activate_limit, ChPid}).

credit(#amqqueue{pid = QPid}, ChPid, CTag, Credit, Drain) ->
    delegate:cast(QPid, {credit, ChPid, CTag, Credit, Drain}).

basic_get(#amqqueue{pid = QPid}, ChPid, NoAck, LimiterPid) ->
    delegate:call(QPid, {basic_get, ChPid, NoAck, LimiterPid}).

basic_consume(#amqqueue{pid = QPid, name = QName}, NoAck, ChPid, LimiterPid,
              LimiterActive, ConsumerPrefetchCount, ConsumerTag,
              ExclusiveConsume, Args, OkMsg) ->
    ok = check_consume_arguments(QName, Args),
    delegate:call(QPid, {basic_consume, NoAck, ChPid, LimiterPid, LimiterActive,
                         ConsumerPrefetchCount, ConsumerTag, ExclusiveConsume,
                         Args, OkMsg}).

basic_cancel(#amqqueue{pid = QPid}, ChPid, ConsumerTag, OkMsg) ->
    delegate:call(QPid, {basic_cancel, ChPid, ConsumerTag, OkMsg}).

notify_decorators(#amqqueue{pid = QPid}) ->
    delegate:cast(QPid, notify_decorators).

notify_sent(QPid, ChPid) ->
    rabbit_amqqueue_common:notify_sent(QPid, ChPid).

notify_sent_queue_down(QPid) ->
    rabbit_amqqueue_common:notify_sent_queue_down(QPid).

resume(QPid, ChPid) -> delegate:cast(QPid, {resume, ChPid}).

internal_delete1(QueueName, OnlyDurable) ->
    ok = mnesia:delete({rabbit_queue, QueueName}),
    mnesia:delete({rabbit_durable_queue, QueueName}),
    %% we want to execute some things, as decided by rabbit_exchange,
    %% after the transaction.
    rabbit_binding:remove_for_destination(QueueName, OnlyDurable).

internal_delete(QueueName) ->
    rabbit_misc:execute_mnesia_tx_with_tail(
      fun () ->
              case {mnesia:wread({rabbit_queue, QueueName}),
                    mnesia:wread({rabbit_durable_queue, QueueName})} of
                  {[], []} ->
                      rabbit_misc:const({error, not_found});
                  _ ->
                      Deletions = internal_delete1(QueueName, false),
                      T = rabbit_binding:process_deletions(Deletions),
                      fun() ->
                              ok = T(),
                              rabbit_core_metrics:queue_deleted(QueueName),
                              ok = rabbit_event:notify(queue_deleted,
                                                       [{name, QueueName}])
                      end
              end
      end).

forget_all_durable(Node) ->
    %% Note rabbit is not running so we avoid e.g. the worker pool. Also why
    %% we don't invoke the return from rabbit_binding:process_deletions/1.
    {atomic, ok} =
        mnesia:sync_transaction(
          fun () ->
                  Qs = mnesia:match_object(rabbit_durable_queue,
                                           #amqqueue{_ = '_'}, write),
                  [forget_node_for_queue(Node, Q) ||
                      #amqqueue{pid = Pid} = Q <- Qs,
                      node(Pid) =:= Node],
                  ok
          end),
    ok.

%% Try to promote a slave while down - it should recover as a
%% master. We try to take the oldest slave here for best chance of
%% recovery.
forget_node_for_queue(DeadNode, Q = #amqqueue{recoverable_slaves = RS}) ->
    forget_node_for_queue(DeadNode, RS, Q).

forget_node_for_queue(_DeadNode, [], #amqqueue{name = Name}) ->
    %% No slaves to recover from, queue is gone.
    %% Don't process_deletions since that just calls callbacks and we
    %% are not really up.
    internal_delete1(Name, true);

%% Should not happen, but let's be conservative.
forget_node_for_queue(DeadNode, [DeadNode | T], Q) ->
    forget_node_for_queue(DeadNode, T, Q);

forget_node_for_queue(DeadNode, [H|T], Q) ->
    case node_permits_offline_promotion(H) of
        false -> forget_node_for_queue(DeadNode, T, Q);
        true  -> Q1 = Q#amqqueue{pid = rabbit_misc:node_to_fake_pid(H)},
                 ok = mnesia:write(rabbit_durable_queue, Q1, write)
    end.

node_permits_offline_promotion(Node) ->
    case node() of
        Node -> not rabbit:is_running(); %% [1]
        _    -> All = rabbit_mnesia:cluster_nodes(all),
                Running = rabbit_mnesia:cluster_nodes(running),
                lists:member(Node, All) andalso
                    not lists:member(Node, Running) %% [2]
    end.
%% [1] In this case if we are a real running node (i.e. rabbitmqctl
%% has RPCed into us) then we cannot allow promotion. If on the other
%% hand we *are* rabbitmqctl impersonating the node for offline
%% node-forgetting then we can.
%%
%% [2] This is simpler; as long as it's down that's OK

run_backing_queue(QPid, Mod, Fun) ->
    gen_server2:cast(QPid, {run_backing_queue, Mod, Fun}).

set_ram_duration_target(QPid, Duration) ->
    gen_server2:cast(QPid, {set_ram_duration_target, Duration}).

set_maximum_since_use(QPid, Age) ->
    gen_server2:cast(QPid, {set_maximum_since_use, Age}).

update_mirroring(QPid) -> ok = delegate:cast(QPid, update_mirroring).

sync_mirrors(#amqqueue{pid = QPid}) -> delegate:call(QPid, sync_mirrors);
sync_mirrors(QPid)                  -> delegate:call(QPid, sync_mirrors).
cancel_sync_mirrors(#amqqueue{pid = QPid}) -> delegate:call(QPid, cancel_sync_mirrors);
cancel_sync_mirrors(QPid)                  -> delegate:call(QPid, cancel_sync_mirrors).

is_mirrored(Q) ->
    rabbit_mirror_queue_misc:is_mirrored(Q).

is_dead_exclusive(#amqqueue{exclusive_owner = none}) ->
    false;
is_dead_exclusive(#amqqueue{exclusive_owner = Pid}) when is_pid(Pid) ->
    not rabbit_mnesia:is_process_alive(Pid).

on_node_up(Node) ->
    ok = rabbit_misc:execute_mnesia_transaction(
           fun () ->
                   Qs = mnesia:match_object(rabbit_queue,
                                            #amqqueue{_ = '_'}, write),
                   [maybe_clear_recoverable_node(Node, Q) || Q <- Qs],
                   ok
           end).

maybe_clear_recoverable_node(Node,
                             #amqqueue{sync_slave_pids    = SPids,
                                       recoverable_slaves = RSs} = Q) ->
    case lists:member(Node, RSs) of
        true  ->
            %% There is a race with
            %% rabbit_mirror_queue_slave:record_synchronised/1 called
            %% by the incoming slave node and this function, called
            %% by the master node. If this function is executed after
            %% record_synchronised/1, the node is erroneously removed
            %% from the recoverable slaves list.
            %%
            %% We check if the slave node's queue PID is alive. If it is
            %% the case, then this function is executed after. In this
            %% situation, we don't touch the queue record, it is already
            %% correct.
            DoClearNode =
                case [SP || SP <- SPids, node(SP) =:= Node] of
                    [SPid] -> not rabbit_misc:is_process_alive(SPid);
                    _      -> true
                end,
            if
                DoClearNode -> RSs1 = RSs -- [Node],
                               store_queue(
                                 Q#amqqueue{recoverable_slaves = RSs1});
                true        -> ok
            end;
        false ->
            ok
    end.

on_node_down(Node) ->
    {QueueNames, QueueDeletions} = delete_queues_on_node_down(Node),
    notify_queue_binding_deletions(QueueDeletions),
    rabbit_core_metrics:queues_deleted(QueueNames),
    notify_queues_deleted(QueueNames),
    ok.

delete_queues_on_node_down(Node) ->
    lists:unzip(lists:flatten([
        rabbit_misc:execute_mnesia_transaction(
          fun () -> [{Queue, delete_queue(Queue)} || Queue <- Queues] end
        ) || Queues <- partition_queues(queues_to_delete_when_node_down(Node))
    ])).

delete_queue(QueueName) ->
    ok = mnesia:delete({rabbit_queue, QueueName}),
    rabbit_binding:remove_transient_for_destination(QueueName).

% If there are many queues and we delete them all in a single Mnesia transaction,
% this can block all other Mnesia operations for a really long time.
% In situations where a node wants to (re-)join a cluster,
% Mnesia won't be able to sync on the new node until this operation finishes.
% As a result, we want to have multiple Mnesia transactions so that other
% operations can make progress in between these queue delete transactions.
%
% 10 queues per Mnesia transaction is an arbitrary number, but it seems to work OK with 50k queues per node.
partition_queues([Q0,Q1,Q2,Q3,Q4,Q5,Q6,Q7,Q8,Q9 | T]) ->
    [[Q0,Q1,Q2,Q3,Q4,Q5,Q6,Q7,Q8,Q9] | partition_queues(T)];
partition_queues(T) ->
    [T].

queues_to_delete_when_node_down(NodeDown) ->
    rabbit_misc:execute_mnesia_transaction(fun () ->
        qlc:e(qlc:q([QName ||
            #amqqueue{name = QName, pid = Pid} = Q <- mnesia:table(rabbit_queue),
                node(Pid) == NodeDown andalso
                not rabbit_mnesia:is_process_alive(Pid) andalso
                (not rabbit_amqqueue:is_mirrored(Q) orelse
                rabbit_amqqueue:is_dead_exclusive(Q))]
        ))
    end).

notify_queue_binding_deletions(QueueDeletions) ->
    rabbit_misc:execute_mnesia_tx_with_tail(
        fun() ->
            rabbit_binding:process_deletions(
                lists:foldl(
                    fun rabbit_binding:combine_deletions/2,
                    rabbit_binding:new_deletions(),
                    QueueDeletions
                )
            )
        end
    ).

notify_queues_deleted(QueueDeletions) ->
    lists:foreach(
      fun(Queue) ->
              ok = rabbit_event:notify(queue_deleted,
                                       [{name, Queue}])
      end,
      QueueDeletions).

pseudo_queue(QueueName, Pid) ->
    #amqqueue{name         = QueueName,
              durable      = false,
              auto_delete  = false,
              arguments    = [],
              pid          = Pid,
              slave_pids   = []}.

immutable(Q) -> Q#amqqueue{pid                = none,
                           slave_pids         = none,
                           sync_slave_pids    = none,
                           recoverable_slaves = none,
                           gm_pids            = none,
                           policy             = none,
                           decorators         = none,
                           state              = none}.

deliver([], _Delivery) ->
    %% /dev/null optimisation
    [];

deliver(Qs, Delivery = #delivery{flow = Flow}) ->
    {MPids, SPids} = qpids(Qs),
    QPids = MPids ++ SPids,
    %% We use up two credits to send to a slave since the message
    %% arrives at the slave from two directions. We will ack one when
    %% the slave receives the message direct from the channel, and the
    %% other when it receives it via GM.
    case Flow of
        %% Here we are tracking messages sent by the rabbit_channel
        %% process. We are accessing the rabbit_channel process
        %% dictionary.
        flow   -> [credit_flow:send(QPid) || QPid <- QPids],
                  [credit_flow:send(QPid) || QPid <- SPids];
        noflow -> ok
    end,

    %% We let slaves know that they were being addressed as slaves at
    %% the time - if they receive such a message from the channel
    %% after they have become master they should mark the message as
    %% 'delivered' since they do not know what the master may have
    %% done with it.
    MMsg = {deliver, Delivery, false},
    SMsg = {deliver, Delivery, true},
    delegate:cast(MPids, MMsg),
    delegate:cast(SPids, SMsg),
    QPids.

qpids([]) -> {[], []}; %% optimisation
qpids([#amqqueue{pid = QPid, slave_pids = SPids}]) -> {[QPid], SPids}; %% opt
qpids(Qs) ->
    {MPids, SPids} = lists:foldl(fun (#amqqueue{pid = QPid, slave_pids = SPids},
                                      {MPidAcc, SPidAcc}) ->
                                         {[QPid | MPidAcc], [SPids | SPidAcc]}
                                 end, {[], []}, Qs),
    {MPids, lists:append(SPids)}.
