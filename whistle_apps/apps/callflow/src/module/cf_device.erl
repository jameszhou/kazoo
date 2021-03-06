%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2012, VoIP INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(cf_device).

-include("../callflow.hrl").

-export([handle/2]).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Entry point for this module, attempts to call an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successfull.
%% @end
%%--------------------------------------------------------------------
-spec handle/2 :: (wh_json:json_object(), whapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    case bridge_to_endpoints(Data, Call) of
        {ok, _} ->
            lager:debug("completed successful bridge to the device"),
            cf_exe:stop(Call);
        {fail, _}=F ->
            cf_util:handle_bridge_failure(F, Call);
        {error, _R} ->
            lager:debug("error bridging to device: ~p", [_R]),
            cf_exe:continue(Call)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempts to bridge to the endpoints created to reach this device
%% @end
%%--------------------------------------------------------------------
-spec bridge_to_endpoints/2 :: (wh_json:json_object(), whapps_call:call()) ->
                                       cf_api_bridge_return().
bridge_to_endpoints(Data, Call) ->
    EndpointId = wh_json:get_value(<<"id">>, Data),
    Params = wh_json:set_value(<<"source">>, ?MODULE, Data),
    case cf_endpoint:build(EndpointId, Params, Call) of
        {error, _}=E ->
            E;
        {ok, Endpoints} ->
            Timeout = wh_json:get_binary_value(<<"timeout">>, Data, ?DEFAULT_TIMEOUT),
            IgnoreEarlyMedia = cf_util:ignore_early_media(Endpoints),
            whapps_call_command:b_bridge(Endpoints, Timeout, <<"simultaneous">>, IgnoreEarlyMedia, Call)
    end.
