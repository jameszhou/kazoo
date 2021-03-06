%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2012, VoIP INC
%%% @doc
%%% NoAuthZ module
%%%
%%% Authorizes everyone! PARTY TIME!
%%%
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(cb_noauthz).

-export([init/0
         ,authorize/1
        ]).

-include("include/crossbar.hrl").

%%%===================================================================
%%% API
%%%===================================================================
init() ->
    crossbar_bindings:bind(<<"v1_resource.authorize">>, ?MODULE, authorize).

-spec authorize/1 :: (#cb_context{}) -> 'true'.
authorize(_) ->
    lager:debug("noauthz authorizing request"),
    true.
