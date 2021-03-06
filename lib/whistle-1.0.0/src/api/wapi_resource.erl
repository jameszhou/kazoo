%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(wapi_resource).

-include_lib("whistle/include/wh_api.hrl").

-export([originate_req/1, originate_req_v/1
         ,originate_resp/1, originate_resp_v/1
         ,eavesdrop_req/1, eavesdrop_req_v/1
         ,eavesdrop_resp/1, eavesdrop_resp_v/1
        ]).

-export([is_valid_mode/1]).

-export([bind_q/2, unbind_q/2]).

-export([publish_originate_req/1, publish_originate_req/2
         ,publish_originate_resp/2, publish_originate_resp/3
         ,publish_eavesdrop_req/1, publish_eavesdrop_req/2
         ,publish_eavesdrop_resp/2, publish_eavesdrop_resp/3
        ]).

%% Eavesdrop: If you set a Group ID, the Call-ID is ignored and "all" is used instead
-define(EAVESDROP_VALID_MODES, [<<"listen">>   % hear both sides - default
                                ,<<"whisper">> % talk to one side
                                ,<<"full">>    % talk to both sides
                               ]).
-define(EAVESDROP_MODE, {<<"Eavesdrop-Mode">>, ?EAVESDROP_VALID_MODES}).

-define(KEY_EAVESDROP_REQ, <<"eavesdrop.resource.req">>). %% corresponds to eavesdrop_req/1 api call

-define(EAVESDROP_REQ_HEADERS, [<<"Account-ID">>, <<"Endpoint-ID">>]).
-define(OPTIONAL_EAVESDROP_REQ_HEADERS, [<<"Eavesdrop-Group-ID">>, <<"Eavesdrop-Mode">>
                                         ,<<"Eavesdrop-Call-ID">>
                                             | ?OPTIONAL_ORIGINATE_REQ_HEADERS
                                        ]).
-define(EAVESDROP_REQ_VALUES, [{<<"Event-Category">>, <<"resource">>}
                               ,{<<"Event-Name">>, <<"eavesdrop_req">>}
                               ,?EAVESDROP_MODE
                              ]).
-define(EAVESDROP_REQ_TYPES, []).

-define(EAVESDROP_RESP_HEADERS, [<<"Status">>]).
-define(OPTIONAL_EAVESDROP_RESP_HEADERS, [<<"Eavesdropper-Call-ID">>
                                          ,<<"Error-Msg">>
                                         ]).
-define(EAVESDROP_RESP_VALUES, [{<<"Event-Category">>, <<"resource">>}
                                ,{<<"Event-Name">>, <<"eavesdrop_resp">>}
                                ,{<<"Status">>, [<<"started">>, <<"error">>]}
                               ]).
-define(EAVESDROP_RESP_TYPES, []).

 %% corresponds to originate_req/1 api call
-define(KEY_RESOURCE_REQ, <<"originate.resource.req">>).

-define(ORIGINATE_REQ_HEADERS, [<<"Endpoints">>, <<"Application-Name">>]).
-define(OPTIONAL_ORIGINATE_REQ_HEADERS, [<<"Application-Data">>, <<"Custom-Channel-Vars">>
                                         ,<<"Export-Custom-Channel-Vars">>, <<"Outbound-Call-ID">>
                                         ,<<"Existing-Call-ID">> % If set, use this node, otherwise ignore
                                         %% Eavesdrop
                                         ,<<"Eavesdrop-Call-ID">>, <<"Eavesdrop-Mode">>, <<"Eavesdrop-Group-ID">>
                                         | fun() ->
                                                   wapi_dialplan:optional_bridge_req_headers()
                                           end()
                                        ]).
-define(ORIGINATE_REQ_VALUES, [{<<"Event-Category">>, <<"resource">>}
                               ,{<<"Event-Name">>, <<"originate_req">>}
                               ,{<<"Dial-Endpoint-Method">>, [<<"single">>, <<"simultaneous">>]}
                               ,{<<"Media">>, [<<"process">>, <<"bypass">>, <<"auto">>]}
                               ,{<<"Continue-On-Fail">>, [<<"true">>, <<"false">>]}
                               ,{<<"Application-Name">>, [<<"park">>, <<"bridge">>, <<"transfer">>
                                                          ,<<"fax">>, <<"eavesdrop">>
                                                         ]}
                               %% Eavesdrop
                               ,?EAVESDROP_MODE
                              ]).
-define(ORIGINATE_REQ_TYPES, [{<<"Endpoints">>, fun is_list/1}
                              ,{<<"SIP-Headers">>, fun wh_json:is_json_object/1}
                              ,{<<"Custom-Channel-Vars">>, fun wh_json:is_json_object/1}
                             ]).

%% Originate Endpoints
-define(ORIGINATE_REQ_ENDPOINT_HEADERS, [<<"Invite-Format">>]).
-define(OPTIONAL_ORIGINATE_REQ_ENDPOINT_HEADERS, fun() -> wapi_dialplan:optional_bridge_req_endpoint_headers() end()).
-define(ORIGINATE_REQ_ENDPOINT_VALUES, [{<<"Ignore-Early-Media">>, [<<"true">>, <<"false">>]}
                                        ,{<<"Bypass-Media">>, [<<"true">>, <<"false">>]}
                                        ,{<<"Endpoint-Type">>, [<<"sip">>, <<"freetdm">>]}
                                       ]).
-define(ORIGINATE_REQ_ENDPOINT_TYPES, [{<<"SIP-Headers">>, fun wh_json:is_json_object/1}
                                       ,{<<"Custom-Channel-Vars">>, fun wh_json:is_json_object/1}
                                       ,{<<"Endpoint-Options">>, fun wh_json:is_json_object/1}
                                      ]).


%% Origintate Resp
-define(ORIGINATE_RESP_HEADERS, [<<"Call-ID">>, <<"Channel-Call-State">>]).
-define(OPTIONAL_ORIGINATE_RESP_HEADERS, fun() -> wapi_call:optional_call_event_headers() end()).
-define(ORIGINATE_RESP_VALUES, [{<<"Event-Category">>, <<"resource">>}
                               ,{<<"Event-Name">>, <<"originate_resp">>}
                               ]).
-define(ORIGINATE_RESP_TYPES, [{<<"Custom-Channel-Vars">>, fun wh_json:is_json_object/1}]).

%%--------------------------------------------------------------------
%% @doc Resource Request - see wiki
%% Takes proplist, creates JSON string or error
%% @end
%%--------------------------------------------------------------------
-spec originate_req/1 :: (api_terms()) ->
                                 {'ok', iolist()} |
                                 {'error', string()}.
originate_req(Prop) when is_list(Prop) ->
    case originate_req_v(Prop) of
        true -> wh_api:build_message(Prop, ?ORIGINATE_REQ_HEADERS, ?OPTIONAL_ORIGINATE_REQ_HEADERS);
        false -> {error, "Proplist failed validation for originate request"}
    end;
originate_req(JObj) ->
    originate_req(wh_json:to_proplist(JObj)).

-spec originate_req_v/1 :: (api_terms()) -> boolean().
originate_req_v(Prop) when is_list(Prop) ->
    wh_api:validate(Prop, ?ORIGINATE_REQ_HEADERS, ?ORIGINATE_REQ_VALUES, ?ORIGINATE_REQ_TYPES);
originate_req_v(JObj) ->
    originate_req_v(wh_json:to_proplist(JObj)).

%%--------------------------------------------------------------------
%% @doc Resource Request - see wiki
%% Takes proplist, creates JSON string or error
%% @end
%%--------------------------------------------------------------------
-spec originate_resp/1 :: (api_terms()) ->
                                  {'ok', iolist()} |
                                  {'error', string()}.
originate_resp(Prop) when is_list(Prop) ->
    case originate_resp_v(Prop) of
        true -> wh_api:build_message(Prop, ?ORIGINATE_RESP_HEADERS, ?OPTIONAL_ORIGINATE_RESP_HEADERS);
        false -> {error, "Proplist failed validation for originate response"}
    end;
originate_resp(JObj) ->
    originate_resp(wh_json:to_proplist(JObj)).

-spec originate_resp_v/1 :: (api_terms()) -> boolean().
originate_resp_v(Prop) when is_list(Prop) ->
    wh_api:validate(Prop, ?ORIGINATE_RESP_HEADERS, ?ORIGINATE_RESP_VALUES, ?ORIGINATE_RESP_TYPES);
originate_resp_v(JObj) ->
    originate_resp_v(wh_json:to_proplist(JObj)).

%%--------------------------------------------------------------------
%% @doc Eavesdrop Request - see wiki
%% Takes proplist, creates JSON string or error
%% @end
%%--------------------------------------------------------------------
-spec eavesdrop_req/1 :: (api_terms()) ->
                                 {'ok', iolist()} |
                                 {'error', string()}.
eavesdrop_req(Prop) when is_list(Prop) ->
    case eavesdrop_req_v(Prop) of
        true -> wh_api:build_message(Prop, ?EAVESDROP_REQ_HEADERS, ?OPTIONAL_EAVESDROP_REQ_HEADERS);
        false -> {error, "Proplist failed validation for eavesdrop request"}
    end;
eavesdrop_req(JObj) ->
    eavesdrop_req(wh_json:to_proplist(JObj)).

-spec eavesdrop_req_v/1 :: (api_terms()) -> boolean().
eavesdrop_req_v(Prop) when is_list(Prop) ->
    wh_api:validate(Prop, ?EAVESDROP_REQ_HEADERS, ?EAVESDROP_REQ_VALUES, ?EAVESDROP_REQ_TYPES);
eavesdrop_req_v(JObj) ->
    eavesdrop_req_v(wh_json:to_proplist(JObj)).

%%--------------------------------------------------------------------
%% @doc Eavesdrop Response - see wiki
%% Takes proplist, creates JSON string or error
%% @end
%%--------------------------------------------------------------------
-spec eavesdrop_resp/1 :: (api_terms()) ->
                                  {'ok', iolist()} |
                                  {'error', string()}.
eavesdrop_resp(Prop) when is_list(Prop) ->
    case eavesdrop_resp_v(Prop) of
        true -> wh_api:build_message(Prop, ?EAVESDROP_RESP_HEADERS, ?OPTIONAL_EAVESDROP_RESP_HEADERS);
        false -> {error, "Proplist failed validation for eavesdrop response"}
    end;
eavesdrop_resp(JObj) ->
    eavesdrop_resp(wh_json:to_proplist(JObj)).

-spec eavesdrop_resp_v/1 :: (api_terms()) -> boolean().
eavesdrop_resp_v(Prop) when is_list(Prop) ->
    wh_api:validate(Prop, ?EAVESDROP_RESP_HEADERS, ?EAVESDROP_RESP_VALUES, ?EAVESDROP_RESP_TYPES);
eavesdrop_resp_v(JObj) ->
    eavesdrop_resp_v(wh_json:to_proplist(JObj)).

-spec is_valid_mode/1 :: (ne_binary()) -> boolean().
is_valid_mode(M) ->
    lists:member(M, ?EAVESDROP_VALID_MODES).

-spec bind_q/2 :: (ne_binary(), wh_proplist()) -> 'ok'.
bind_q(Queue, Prop) ->
    amqp_util:callmgr_exchange(),
    bind_q(Queue, Prop, props:get_value(restrict_to, Prop)).

bind_q(Queue, _Prop, undefined) ->
    ok = amqp_util:bind_q_to_callmgr(Queue, ?KEY_RESOURCE_REQ),
    amqp_util:bind_q_to_callmgr(Queue, ?KEY_EAVESDROP_REQ);
bind_q(Queue, Prop, [originate|T]) ->
    ok = amqp_util:bind_q_to_callmgr(Queue, ?KEY_RESOURCE_REQ),
    bind_q(Queue, Prop, T);
bind_q(Queue, Prop, [eavesdrop|T]) ->
    ok = amqp_util:bind_q_to_callmgr(Queue, ?KEY_EAVESDROP_REQ),
    bind_q(Queue, Prop, T);
bind_q(Queue, Prop, [_|T]) ->
    bind_q(Queue, Prop, T);
bind_q(_, _, []) ->
    ok.

-spec unbind_q/2 :: (ne_binary(), wh_proplist()) -> 'ok'.
unbind_q(Queue, Prop) ->
    unbind_q(Queue, Prop, props:get_value(restrict_to, Prop)).

unbind_q(Queue, _Prop, undefined) ->
    ok = amqp_util:unbind_q_from_callmgr(Queue, ?KEY_RESOURCE_REQ),
    amqp_util:unbind_q_from_callmgr(Queue, ?KEY_EAVESDROP_REQ);
unbind_q(Queue, Prop, [originate|T]) ->
    ok = amqp_util:unbind_q_from_callmgr(Queue, ?KEY_RESOURCE_REQ),
    unbind_q(Queue, Prop, T);
unbind_q(Queue, Prop, [eavesdrop|T]) ->
    ok = amqp_util:unbind_q_from_callmgr(Queue, ?KEY_EAVESDROP_REQ),
    unbind_q(Queue, Prop, T);
unbind_q(Queue, Prop, [_|T]) ->
    unbind_q(Queue, Prop, T);
unbind_q(_, _, []) ->
    ok.


-spec publish_originate_req/1 :: (api_terms()) -> 'ok'.
-spec publish_originate_req/2 :: (api_terms(), ne_binary()) -> 'ok'.
publish_originate_req(JObj) ->
    publish_originate_req(JObj, ?DEFAULT_CONTENT_TYPE).
publish_originate_req(Req, ContentType) ->
    {ok, Payload} = wh_api:prepare_api_payload(Req, ?ORIGINATE_REQ_VALUES, fun ?MODULE:originate_req/1),
    amqp_util:callmgr_publish(Payload, ContentType, ?KEY_RESOURCE_REQ, [{immediate, true}]).

-spec publish_originate_resp/2 :: (ne_binary(), api_terms()) -> 'ok'.
-spec publish_originate_resp/3 :: (ne_binary(), api_terms(), ne_binary()) -> 'ok'.
publish_originate_resp(TargetQ, JObj) ->
    publish_originate_resp(TargetQ, JObj, ?DEFAULT_CONTENT_TYPE).
publish_originate_resp(TargetQ, Resp, ContentType) ->
    {ok, Payload} = wh_api:prepare_api_payload(Resp, ?ORIGINATE_RESP_VALUES, fun ?MODULE:originate_resp/1),
    amqp_util:targeted_publish(TargetQ, Payload, ContentType).

-spec publish_eavesdrop_req/1 :: (api_terms()) -> 'ok'.
-spec publish_eavesdrop_req/2 :: (api_terms(), ne_binary()) -> 'ok'.
publish_eavesdrop_req(JObj) ->
    publish_eavesdrop_req(JObj, ?DEFAULT_CONTENT_TYPE).
publish_eavesdrop_req(Req, ContentType) ->
    {ok, Payload} = wh_api:prepare_api_payload(Req, ?EAVESDROP_REQ_VALUES, fun ?MODULE:eavesdrop_req/1),
    amqp_util:callmgr_publish(Payload, ContentType, ?KEY_EAVESDROP_REQ, [{immediate, true}]).

-spec publish_eavesdrop_resp/2 :: (ne_binary(), api_terms()) -> 'ok'.
-spec publish_eavesdrop_resp/3 :: (ne_binary(), api_terms(), ne_binary()) -> 'ok'.
publish_eavesdrop_resp(TargetQ, JObj) ->
    publish_eavesdrop_resp(TargetQ, JObj, ?DEFAULT_CONTENT_TYPE).
publish_eavesdrop_resp(TargetQ, Resp, ContentType) ->
    {ok, Payload} = wh_api:prepare_api_payload(Resp, ?EAVESDROP_RESP_VALUES, fun ?MODULE:eavesdrop_resp/1),
    amqp_util:targeted_publish(TargetQ, Payload, ContentType).
