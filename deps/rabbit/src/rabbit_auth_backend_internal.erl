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

-module(rabbit_auth_backend_internal).
-include("rabbit.hrl").

-behaviour(rabbit_authn_backend).
-behaviour(rabbit_authz_backend).

-export([user_login_authentication/2, user_login_authorization/1,
         check_vhost_access/3, check_resource_access/3]).

-export([add_user/2, delete_user/1, lookup_user/1,
         change_password/2, clear_password/1,
         hash_password/2, change_password_hash/2, change_password_hash/3,
         set_tags/2, set_permissions/5, clear_permissions/2,
         add_user_sans_validation/2]).
-export([user_info_keys/0, perms_info_keys/0,
         user_perms_info_keys/0, vhost_perms_info_keys/0,
         user_vhost_perms_info_keys/0,
         list_users/0, list_users/2, list_permissions/0,
         list_user_permissions/1, list_user_permissions/3,
         list_vhost_permissions/1, list_vhost_permissions/3,
         list_user_vhost_permissions/2]).

%% for testing
-export([hashing_module_for_user/1]).

%%----------------------------------------------------------------------------

-type regexp() :: binary().

-spec add_user(rabbit_types:username(), rabbit_types:password()) -> 'ok' | {'error', string()}.
-spec delete_user(rabbit_types:username()) -> 'ok'.
-spec lookup_user
        (rabbit_types:username()) ->
            rabbit_types:ok(rabbit_types:internal_user()) |
            rabbit_types:error('not_found').
-spec change_password
        (rabbit_types:username(), rabbit_types:password()) -> 'ok'.
-spec clear_password(rabbit_types:username()) -> 'ok'.
-spec hash_password
        (module(), rabbit_types:password()) -> rabbit_types:password_hash().
-spec change_password_hash
        (rabbit_types:username(), rabbit_types:password_hash()) -> 'ok'.
-spec set_tags(rabbit_types:username(), [atom()]) -> 'ok'.
-spec set_permissions
        (rabbit_types:username(), rabbit_types:vhost(), regexp(), regexp(),
         regexp()) ->
            'ok'.
-spec clear_permissions
        (rabbit_types:username(), rabbit_types:vhost()) -> 'ok'.
-spec user_info_keys() -> rabbit_types:info_keys().
-spec perms_info_keys() -> rabbit_types:info_keys().
-spec user_perms_info_keys() -> rabbit_types:info_keys().
-spec vhost_perms_info_keys() -> rabbit_types:info_keys().
-spec user_vhost_perms_info_keys() -> rabbit_types:info_keys().
-spec list_users() -> [rabbit_types:infos()].
-spec list_users(reference(), pid()) -> 'ok'.
-spec list_permissions() -> [rabbit_types:infos()].
-spec list_user_permissions
        (rabbit_types:username()) -> [rabbit_types:infos()].
-spec list_user_permissions
        (rabbit_types:username(), reference(), pid()) -> 'ok'.
-spec list_vhost_permissions
        (rabbit_types:vhost()) -> [rabbit_types:infos()].
-spec list_vhost_permissions
        (rabbit_types:vhost(), reference(), pid()) -> 'ok'.
-spec list_user_vhost_permissions
        (rabbit_types:username(), rabbit_types:vhost()) -> [rabbit_types:infos()].

%%----------------------------------------------------------------------------
%% Implementation of rabbit_auth_backend

%% Returns a password hashing module for the user record provided. If
%% there is no information in the record, we consider it to be legacy
%% (inserted by a version older than 3.6.0) and fall back to MD5, the
%% now obsolete hashing function.
hashing_module_for_user(#internal_user{
    hashing_algorithm = ModOrUndefined}) ->
        rabbit_password:hashing_mod(ModOrUndefined).

-define(BLANK_PASSWORD_REJECTION_MESSAGE,
        "user '~s' attempted to log in with a blank password, which is prohibited by the internal authN backend. "
        "To use TLS/x509 certificate-based authentication, see the rabbitmq_auth_mechanism_ssl plugin and configure the client to use the EXTERNAL authentication mechanism. "
        "Alternatively change the password for the user to be non-blank.").

%% For cases when we do not have a set of credentials,
%% namely when x509 (TLS) certificates are used. This should only be
%% possible when the EXTERNAL authentication mechanism is used, see
%% rabbit_auth_mechanism_plain:handle_response/2 and rabbit_reader:auth_phase/2.
user_login_authentication(Username, []) ->
    internal_check_user_login(Username, fun(_) -> true end);
%% For cases when we do have a set of credentials. rabbit_auth_mechanism_plain:handle_response/2
%% performs initial validation.
user_login_authentication(Username, AuthProps) ->
    case lists:keyfind(password, 1, AuthProps) of
        %% Passwordless users are not supposed to be used with
        %% this backend (and PLAIN authentication mechanism in general).
        {password, <<"">>} ->
            {refused, ?BLANK_PASSWORD_REJECTION_MESSAGE,
             [Username]};
        {password, ""} ->
            {refused, ?BLANK_PASSWORD_REJECTION_MESSAGE,
             [Username]};
        {password, Cleartext} ->
            internal_check_user_login(
              Username,
              fun (#internal_user{
                        password_hash = <<Salt:4/binary, Hash/binary>>
                    } = U) ->
                  Hash =:= rabbit_password:salted_hash(
                      hashing_module_for_user(U), Salt, Cleartext);
                  %% rabbitmqctl clear_password will set password_hash to an empty
                  %% binary.
                  %% 
                  %% See the comment on passwordless users above.
                  (#internal_user{
                        password_hash = <<"">>}) ->
                      false;
                  (#internal_user{}) ->
                      false
              end);
        false -> exit({unknown_auth_props, Username, AuthProps})
    end.

user_login_authorization(Username) ->
    case user_login_authentication(Username, []) of
        {ok, #auth_user{impl = Impl, tags = Tags}} -> {ok, Impl, Tags};
        Else                                       -> Else
    end.

internal_check_user_login(Username, Fun) ->
    Refused = {refused, "user '~s' - invalid credentials", [Username]},
    case lookup_user(Username) of
        {ok, User = #internal_user{tags = Tags}} ->
            case Fun(User) of
                true -> {ok, #auth_user{username = Username,
                                        tags     = Tags,
                                        impl     = none}};
                _    -> Refused
            end;
        {error, not_found} ->
            Refused
    end.

check_vhost_access(#auth_user{username = Username}, VHostPath, _Sock) ->
    case mnesia:dirty_read({rabbit_user_permission,
                            #user_vhost{username     = Username,
                                        virtual_host = VHostPath}}) of
        []   -> false;
        [_R] -> true
    end.

check_resource_access(#auth_user{username = Username},
                      #resource{virtual_host = VHostPath, name = Name},
                      Permission) ->
    case mnesia:dirty_read({rabbit_user_permission,
                            #user_vhost{username     = Username,
                                        virtual_host = VHostPath}}) of
        [] ->
            false;
        [#user_permission{permission = P}] ->
            PermRegexp = case element(permission_index(Permission), P) of
                             %% <<"^$">> breaks Emacs' erlang mode
                             <<"">> -> <<$^, $$>>;
                             RE     -> RE
                         end,
            case re:run(Name, PermRegexp, [{capture, none}]) of
                match    -> true;
                nomatch  -> false
            end
    end.

permission_index(configure) -> #permission.configure;
permission_index(write)     -> #permission.write;
permission_index(read)      -> #permission.read.

%%----------------------------------------------------------------------------
%% Manipulation of the user database

validate_credentials(Username, Password) ->
    rabbit_credential_validation:validate(Username, Password).

validate_and_alternate_credentials(Username, Password, Fun) ->
    case validate_credentials(Username, Password) of
        ok           ->
            Fun(Username, Password);
        {error, Err} ->
            rabbit_log:error("Credential validation for '~s' failed!~n", [Username]),
            {error, Err}
    end.

add_user(Username, Password) ->
    validate_and_alternate_credentials(Username, Password, fun add_user_sans_validation/2).

add_user_sans_validation(Username, Password) ->
    rabbit_log:info("Creating user '~s'~n", [Username]),
    %% hash_password will pick the hashing function configured for us
    %% but we also need to store a hint as part of the record, so we
    %% retrieve it here one more time
    HashingMod = rabbit_password:hashing_mod(),
    User = #internal_user{username          = Username,
                          password_hash     = hash_password(HashingMod, Password),
                          tags              = [],
                          hashing_algorithm = HashingMod},
    R = rabbit_misc:execute_mnesia_transaction(
          fun () ->
                  case mnesia:wread({rabbit_user, Username}) of
                      [] ->
                          ok = mnesia:write(rabbit_user, User, write);
                      _ ->
                          mnesia:abort({user_already_exists, Username})
                  end
          end),
    rabbit_event:notify(user_created, [{name, Username}]),
    R.

delete_user(Username) ->
    rabbit_log:info("Deleting user '~s'~n", [Username]),
    R = rabbit_misc:execute_mnesia_transaction(
          rabbit_misc:with_user(
            Username,
            fun () ->
                    ok = mnesia:delete({rabbit_user, Username}),
                    [ok = mnesia:delete_object(
                            rabbit_user_permission, R, write) ||
                        R <- mnesia:match_object(
                               rabbit_user_permission,
                               #user_permission{user_vhost = #user_vhost{
                                                  username = Username,
                                                  virtual_host = '_'},
                                                permission = '_'},
                               write)],
                    ok
            end)),
    rabbit_event:notify(user_deleted, [{name, Username}]),
    R.

lookup_user(Username) ->
    rabbit_misc:dirty_read({rabbit_user, Username}).

change_password(Username, Password) ->
    validate_and_alternate_credentials(Username, Password, fun change_password_sans_validation/2).

change_password_sans_validation(Username, Password) ->
    rabbit_log:info("Changing password for '~s'~n", [Username]),
    HashingAlgorithm = rabbit_password:hashing_mod(),
    R = change_password_hash(Username,
                             hash_password(rabbit_password:hashing_mod(),
                                           Password),
                             HashingAlgorithm),
    rabbit_event:notify(user_password_changed, [{name, Username}]),
    R.

clear_password(Username) ->
    rabbit_log:info("Clearing password for '~s'~n", [Username]),
    R = change_password_hash(Username, <<"">>),
    rabbit_event:notify(user_password_cleared, [{name, Username}]),
    R.

hash_password(HashingMod, Cleartext) ->
    rabbit_password:hash(HashingMod, Cleartext).

change_password_hash(Username, PasswordHash) ->
    change_password_hash(Username, PasswordHash, rabbit_password:hashing_mod()).


change_password_hash(Username, PasswordHash, HashingAlgorithm) ->
    update_user(Username, fun(User) ->
                                  User#internal_user{
                                    password_hash     = PasswordHash,
                                    hashing_algorithm = HashingAlgorithm }
                          end).

set_tags(Username, Tags) ->
    rabbit_log:info("Setting user tags for user '~s' to ~p~n",
                    [Username, Tags]),
    R = update_user(Username, fun(User) ->
                                      User#internal_user{tags = Tags}
                              end),
    rabbit_event:notify(user_tags_set, [{name, Username}, {tags, Tags}]),
    R.

set_permissions(Username, VHostPath, ConfigurePerm, WritePerm, ReadPerm) ->
    rabbit_log:info("Setting permissions for "
                    "'~s' in '~s' to '~s', '~s', '~s'~n",
                    [Username, VHostPath, ConfigurePerm, WritePerm, ReadPerm]),
    lists:map(
      fun (RegexpBin) ->
              Regexp = binary_to_list(RegexpBin),
              case re:compile(Regexp) of
                  {ok, _}         -> ok;
                  {error, Reason} -> throw({error, {invalid_regexp,
                                                    Regexp, Reason}})
              end
      end, [ConfigurePerm, WritePerm, ReadPerm]),
    R = rabbit_misc:execute_mnesia_transaction(
          rabbit_vhost:with_user_and_vhost(
            Username, VHostPath,
            fun () -> ok = mnesia:write(
                             rabbit_user_permission,
                             #user_permission{user_vhost = #user_vhost{
                                                username     = Username,
                                                virtual_host = VHostPath},
                                              permission = #permission{
                                                configure = ConfigurePerm,
                                                write     = WritePerm,
                                                read      = ReadPerm}},
                             write)
            end)),
    rabbit_event:notify(permission_created, [{user,      Username},
                                             {vhost,     VHostPath},
                                             {configure, ConfigurePerm},
                                             {write,     WritePerm},
                                             {read,      ReadPerm}]),
    R.

clear_permissions(Username, VHostPath) ->
    R = rabbit_misc:execute_mnesia_transaction(
          rabbit_vhost:with_user_and_vhost(
            Username, VHostPath,
            fun () ->
                    ok = mnesia:delete({rabbit_user_permission,
                                        #user_vhost{username     = Username,
                                                    virtual_host = VHostPath}})
            end)),
    rabbit_event:notify(permission_deleted, [{user,  Username},
                                             {vhost, VHostPath}]),
    R.


update_user(Username, Fun) ->
    rabbit_misc:execute_mnesia_transaction(
      rabbit_misc:with_user(
        Username,
        fun () ->
                {ok, User} = lookup_user(Username),
                ok = mnesia:write(rabbit_user, Fun(User), write)
        end)).

%%----------------------------------------------------------------------------
%% Listing

-define(PERMS_INFO_KEYS, [configure, write, read]).
-define(USER_INFO_KEYS, [user, tags]).

user_info_keys() -> ?USER_INFO_KEYS.

perms_info_keys()            -> [user, vhost | ?PERMS_INFO_KEYS].
vhost_perms_info_keys()      -> [user | ?PERMS_INFO_KEYS].
user_perms_info_keys()       -> [vhost | ?PERMS_INFO_KEYS].
user_vhost_perms_info_keys() -> ?PERMS_INFO_KEYS.

list_users() ->
    [extract_internal_user_params(U) ||
        U <- mnesia:dirty_match_object(rabbit_user, #internal_user{_ = '_'})].

list_users(Ref, AggregatorPid) ->
    rabbit_control_misc:emitting_map(
      AggregatorPid, Ref,
      fun(U) -> extract_internal_user_params(U) end,
      mnesia:dirty_match_object(rabbit_user, #internal_user{_ = '_'})).

list_permissions() ->
    list_permissions(perms_info_keys(), match_user_vhost('_', '_')).

list_permissions(Keys, QueryThunk) ->
    [extract_user_permission_params(Keys, U) ||
        %% TODO: use dirty ops instead
        U <- rabbit_misc:execute_mnesia_transaction(QueryThunk)].

list_permissions(Keys, QueryThunk, Ref, AggregatorPid) ->
    rabbit_control_misc:emitting_map(
      AggregatorPid, Ref, fun(U) -> extract_user_permission_params(Keys, U) end,
      %% TODO: use dirty ops instead
      rabbit_misc:execute_mnesia_transaction(QueryThunk)).

filter_props(Keys, Props) -> [T || T = {K, _} <- Props, lists:member(K, Keys)].

list_user_permissions(Username) ->
    list_permissions(
      user_perms_info_keys(),
      rabbit_misc:with_user(Username, match_user_vhost(Username, '_'))).

list_user_permissions(Username, Ref, AggregatorPid) ->
    list_permissions(
      user_perms_info_keys(),
      rabbit_misc:with_user(Username, match_user_vhost(Username, '_')),
      Ref, AggregatorPid).

list_vhost_permissions(VHostPath) ->
    list_permissions(
      vhost_perms_info_keys(),
      rabbit_vhost:with(VHostPath, match_user_vhost('_', VHostPath))).

list_vhost_permissions(VHostPath, Ref, AggregatorPid) ->
    list_permissions(
      vhost_perms_info_keys(),
      rabbit_vhost:with(VHostPath, match_user_vhost('_', VHostPath)),
      Ref, AggregatorPid).

list_user_vhost_permissions(Username, VHostPath) ->
    list_permissions(
      user_vhost_perms_info_keys(),
      rabbit_vhost:with_user_and_vhost(
        Username, VHostPath, match_user_vhost(Username, VHostPath))).

extract_user_permission_params(Keys, #user_permission{
                                        user_vhost =
                                            #user_vhost{username     = Username,
                                                        virtual_host = VHostPath},
                                        permission = #permission{
                                                        configure = ConfigurePerm,
                                                        write     = WritePerm,
                                                        read      = ReadPerm}}) ->
    filter_props(Keys, [{user,      Username},
                        {vhost,     VHostPath},
                        {configure, ConfigurePerm},
                        {write,     WritePerm},
                        {read,      ReadPerm}]).

extract_internal_user_params(#internal_user{username = Username, tags = Tags}) ->
    [{user, Username}, {tags, Tags}].

match_user_vhost(Username, VHostPath) ->
    fun () -> mnesia:match_object(
                rabbit_user_permission,
                #user_permission{user_vhost = #user_vhost{
                                   username     = Username,
                                   virtual_host = VHostPath},
                                 permission = '_'},
                read)
    end.
