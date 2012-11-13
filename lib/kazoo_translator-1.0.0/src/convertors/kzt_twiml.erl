%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, 2600Hz
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kzt_twiml).

-include("../kzt.hrl").

-export([exec/2
         ,base_req_params/1
        ]).

-spec exec/2 :: (whapps_call:call(), #xmlElement{} | text()) ->
                        {'error', whapps_call:call()} |
                        {'req', whapps_call:call()} |
                        {'stop', whapps_call:call()}.
exec(Call, #xmlElement{name='Response', content=Els}) ->
    exec_elements(Call, Els);
exec(Call, Resp) ->
    try xmerl_scan:string(Resp) of
        {#xmlElement{name='Response', content=Els}, _} ->
            exec_elements(Call, Els);
        _Other ->
            lager:debug("failed to exec twiml: ~p", [_Other]),
            {error, Call}
    catch
        _E:_R ->
            lager:debug("xml extraction fail: ~s: ~p", [_E, _R]),
            {error, Call}
    end.

-spec exec_elements/2 :: (whapps_call:call(), [#xmlElement{},...]) ->
                                 {'error', whapps_call:call()} |
                                 {'req', whapps_call:call()} |
                                 {'stop', whapps_call:call()}.
exec_elements(Call, []) -> {ok, Call};
exec_elements(Call, [El|Els]) ->
    try exec_element(Call, El) of
        {ok, Call1} -> exec_elements(Call1, Els);
        {req, _Call}=REQ -> REQ;
        {error, _Call}=ERR -> ERR;
        {stop, _Call}=STOP -> STOP
    catch
        throw:{unknown_element, Name} ->
            lager:debug("unknown element in response: ~s", [Name]),
            {error, kzt_util:set_error(Call, <<"unknown_element">>, Name)};
        _E:_R ->
            lager:debug("'~s' when execing el ~p: ~p", [_E, El, _R]),
            {error, Call}
    end.

-spec exec_element/2 :: (whapps_call:call(), #xmlElement{}) ->
                                {'ok', whapps_call:call()} |
                                {'req', whapps_call:call()} |
                                {'stop', whapps_call:call()} |
                                {'error', whapps_call:call()}.
exec_element(Call, #xmlElement{name='Dial'
                               ,content=Endpoints
                               ,attributes=Attrs
                              }) ->
    dial(Call, Endpoints, Attrs);
exec_element(Call, #xmlElement{name='Record'
                               ,content=[] % nothing inside the tags please
                               ,attributes=Attrs
                              }) ->
    record_call(Call, Attrs);
exec_element(Call, #xmlElement{name='Gather'
                                  ,content=SubActions
                                  ,attributes=Attrs
                                 }) ->
    gather(Call, SubActions, Attrs);
exec_element(Call, #xmlElement{name='Play'
                                  ,content=ToPlay
                                  ,attributes=Attrs
                                 }) ->
    play(Call, ToPlay, Attrs);
exec_element(Call, #xmlElement{name='Say'
                                  ,content=ToSay
                                  ,attributes=Attrs
                                 }) ->
    say(Call, ToSay, Attrs);
exec_element(Call, #xmlElement{name='Redirect'
                                  ,content=RedirectUrl
                                  ,attributes=Attrs
                                 }) ->
    redirect(Call, RedirectUrl, Attrs);
exec_element(Call, #xmlElement{name='Pause'
                                  ,content=[]
                                  ,attributes=Attrs
                                 }) ->
    pause(Call, Attrs);
exec_element(Call, #xmlElement{name='Variable'
                                  ,content=[]
                                  ,attributes=Attrs
                                 }) ->
    set_variable(Call, Attrs);
exec_element(Call, #xmlElement{name='Hangup'
                                  ,content=[]
                                  ,attributes=[]
                                 }) ->
    hangup(Call);
exec_element(Call, #xmlElement{name='Reject'
                               ,content=[]
                               ,attributes=Attrs
                              }) ->
    reject(Call, Attrs);
exec_element(_Call, #xmlElement{name=Unknown
                               ,content=_Content
                               ,attributes=_Attrs
                              }) ->
    throw({unknown_element, Unknown}).

-spec base_req_params/1 :: (whapps_call:call()) -> wh_proplist().
base_req_params(Call) ->
    [{<<"CallSid">>, whapps_call:call_id(Call)}
     ,{<<"AccountSid">>, whapps_call:account_id(Call)}
     ,{<<"From">>, whapps_call:from_user(Call)}
     ,{<<"To">>, whapps_call:to_user(Call)}
     ,{<<"CallStatus">>, whapps_call:kvs_fetch(<<"call_status">>, ?STATUS_RINGING, Call)}
     ,{<<"ApiVersion">>, <<"2010-04-01">>}
     ,{<<"Direction">>, <<"inbound">>}
     ,{<<"CallerName">>, whapps_call:caller_id_name(Call)}
    ].

dial(Call, [#xmlText{value=DialMe, type=text}], Attrs) ->
    lager:debug("dial '~s'", [DialMe]),

    Props = kzt_util:attributes_to_proplist(Attrs),

    Timeout = timeout_s(Props),
    RecordCall = should_record_call(Props),
    HangupDTMF = hangup_dtmf(Props),

    Setters = [{fun whapps_call:set_request/2, request_id(DialMe, Call)}
               ,{fun whapps_call:set_caller_id_number/2, caller_id(Props, Call)}
               ,{fun kzt_util:set_hangup_dtmf/2, HangupDTMF}
               ,{fun kzt_util:set_record_call/2, RecordCall}
               ,{fun kzt_util:set_call_timeout/2, Timeout}
               ,{fun kzt_util:set_call_time_limit/2, timelimit_s(Props)}
              ],
    Call1 = lists:foldl(fun({F, V}, C) when is_function(F, 2) -> F(V, C) end
                        ,Call
                        ,Setters
                       ),

    OffnetProps = wh_json:from_list(
                    [{<<"Timeout">>, Timeout}
                     ,{<<"Media">>, media_processing(RecordCall, HangupDTMF)}
                    ]),

    ok = kzt_util:offnet_req(OffnetProps, Call1),

    case kzt_receiver:wait_for_offnet(Call1) of
        {ok, Call2, _ResultProps} ->
            {stop, Call2};
        {error, Call2, _E} ->
            lager:debug("offnet failed: ~p", [_E]),
            {ok, Call2} % will progress to next TwiML element
    end.

-spec hangup/1 :: (whapps_call:call()) -> {'stop', whapps_call:call()}.
hangup(Call) ->
    whapps_call_command:b_answer(Call),
    whapps_call_command:hangup(Call),
    {stop, kzt_util:update_call_status(Call1, ?STATUS_COMPLETED)}.

play(Call, XmlText, Attrs) ->
    whapps_call_command:answer(Call),
    PlayMe = xml_text_to_binary(XmlText),
    lager:debug("playing '~s'", [PlayMe]),
    Props = kzt_util:attributes_to_proplist(Attrs),

    LoopCount = loop_count(Props),

    case get_loop_count(props:get_value(loop, attrs_to_proplist(Attrs), 1)) of
        %% TODO: play music in a continuous loop
        0 -> whapps_call_command:b_play(PlayMe, Call);
        1 -> whapps_call_command:b_play(PlayMe, Call);
        N when N > 1 -> play_loop(Call, PlayMe, N)
    end,
    {ok, Call}.

play_loop(Call, PlayMe, N) ->
    Play = [{play, PlayMe} || _ <- lists:seq(1, N)],
    NoopId = whapps_call_command:audio_macro(Play, Call),
    kzt_receiver:wait_for_noop(NoopId).

-spec xml_text_to_binary/1 :: ([#xmlText{},...]|[]) -> binary().
xml_text_to_binary(Vs) when is_list(Vs) ->
    iolist_to_binary([V || #xmlText{value=V, type='text'} <- Vs]).

-spec caller_id/2 :: (wh_proplist(), whapps_call:call()) -> ne_binary().
caller_id(Props, Call) ->
    wh_util:to_binary(
      props:get_value(callerId, Props, whapps_call:caller_id_number(Call))
     ).

timeout_s(Props) -> props:get_integer_value(timeout, Props, 30).
timelimit_s(Props) -> props:get_integer_value(timeLimit, Props, 14400).
loop_count(Props) -> props:get_integer_value(loop, Props, 1).

request_id(N, Call) -> iolist_to_binary([N, $@, whapps_call:from_realm(Call)]).
should_record_call(Props) -> wh_util:is_true(props:get_value(record, Props, false)).

-spec hangup_dtmf/1 :: (wh_proplist() | api_binary()) -> api_binary().
hangup_dtmf(Props) when is_list(Props) ->
    case props:get_value(hangupOnStar, Props) of
        true -> <<"*">>;
        _ -> hangup_dtmf(props:get_binary_value(hangupOn, Props))
    end;
hangup_dtmf(DTMF) ->
    case lists:member(DTMF, ?ANY_DIGIT) of
        true -> DTMF;
        false -> undefined
    end.

media_processing(false, undefined) -> <<"bypass">>;
media_processing(_ShouldRecord, _HangupDTMF) -> <<"process">>.
