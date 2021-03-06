%% @copyright 2016 Choven Corp.
%%
%% This file is part of erlangzmq.
%%
%% erlangzmq is free software: you can redistribute it and/or modify
%% it under the terms of the GNU Affero General Public License as published by
%% the Free Software Foundation, either version 3 of the License, or
%% (at your option) any later version.
%%
%% erlangzmq is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU Affero General Public License for more details.
%%
%% You should have received a copy of the GNU Affero General Public License
%% along with erlangzmq.  If not, see <http://www.gnu.org/licenses/>

-module(erlangzmq_protocol_test).

-include_lib("eunit/include/eunit.hrl").

build_greeting_frame_test() ->
    Frame = erlangzmq_protocol:build_greeting_frame(),
    ?assertEqual(is_binary(Frame), true),
    ?assertEqual(byte_size(Frame), 64),
    <<16#ff, Padding:64/bitstring, 16#7f, VersionMajor, VersionMinor,
      Mechanism:160/bitstring, AsServer:8,
      Filler/binary>> = Frame,
    ?assertEqual(Padding, <<0:64>>),
    ?assertEqual(VersionMajor, 3),
    ?assertEqual(VersionMinor, 1),
    ?assertEqual(Mechanism, <<"NULL", 0:128>>),
    ?assertEqual(AsServer, 0),
    ?assertEqual(Filler, <<0:248>>).

decode_greeting_frame_test() ->
    Frame = valid_gretting_frame(),
    ?assertEqual(byte_size(Frame), 64),
    Decoder = erlangzmq_protocol:new_decoder(),
    {ready, NewDecoder} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder), <<"">>),
    {ok, NewDecoder2} = erlangzmq_protocol:continue_decode(NewDecoder),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder2), nil).

decoder_receive_only_signature_message_test() ->
    Frame = <<16#ff, 0:64, 16#7f, 3>>,         %% Signature
    Decoder = erlangzmq_protocol:new_decoder(),

    {ok, NewDecoder} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder), waiting_minor_version).

decoder_receive_only_signature_and_version_message_test() ->
    Frame = <<16#ff, 0:64, 16#7f, 3, 1>>,   %% Signature and Version
    Decoder = erlangzmq_protocol:new_decoder(),

    {ok, NewDecoder} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder), waiting_mechanism).


decoder_understand_version_test() ->
    EmptyDecoder = erlangzmq_protocol:new_decoder(),
    Frame30 = <<16#ff, 0:64, 16#7f, 3, 0>>,   %% Signature and Version
    Frame31 = <<16#ff, 0:64, 16#7f, 3, 1>>,   %% Signature and Version

    {ok, Decoder30} = erlangzmq_protocol:decode(EmptyDecoder, Frame30),
    {ok, Decoder31} = erlangzmq_protocol:decode(EmptyDecoder, Frame31),

    ?assertEqual({3, 0}, erlangzmq_protocol:decoder_version(Decoder30)),
    ?assertEqual({3, 1}, erlangzmq_protocol:decoder_version(Decoder31)).


decoder_receive_invalid_signature_message_test() ->
    Decoder = erlangzmq_protocol:new_decoder(),
    ?assertEqual(erlangzmq_protocol:decoder_state(Decoder), initial),

    ?assertEqual(
       erlangzmq_protocol:decode(Decoder, <<"Invalid frame">>),
       {error, {bad_greeting_frame, <<"Invalid frame">>}}).

decoder_receive_greeting_frame_with_invalid_version_test() ->
    Frame = <<16#ff, 0:64, 16#7f, 2>>, %% Signature and MajorVersion
    Decoder = erlangzmq_protocol:new_decoder(),
    ?assertEqual(erlangzmq_protocol:decode(Decoder, Frame),
                 {error,{invalid_version,2}}).

decoder_receive_greeting_frame_with_invalid_mechanism_test() ->
    Frame = <<16#ff, 0:64, 16#7f,         %% Signature
              3, 1,                       %% Version
              "EMACS", 0:120>>,           %% Mechanism
    Decoder = erlangzmq_protocol:new_decoder(),
    ?assertEqual(erlangzmq_protocol:decode(Decoder, Frame),
                 {error,{invalid_mechanism,'EMACS'}}).

decoder_receive_greeting_frame_with_mechanism_not_supported_test() ->
    Frame1 = <<16#ff, 0:64, 16#7f,        %% Signature
              3, 1,                       %% Version
              "CURVE", 0:120>>,           %% Mechanism
    Decoder1 = erlangzmq_protocol:new_decoder(),
    ?assertEqual(erlangzmq_protocol:decode(Decoder1, Frame1),
                 {error,{mechanism_not_supported_yet,'CURVE'}}),

    Frame2 = <<16#ff, 0:64, 16#7f,        %% Signature
              3, 1,                       %% Version
              "PLAIN", 0:120>>,           %% Mechanism
    Decoder2 = erlangzmq_protocol:new_decoder(),
    ?assertEqual(erlangzmq_protocol:decode(Decoder2, Frame2),
                 {error,{mechanism_not_supported_yet,'PLAIN'}}).

valid_gretting_frame() ->
    {VersionMajor, VersionMinor} = {3, 1},
    <<16#ff, 0:64, 16#7f, VersionMajor, %% Signature
      VersionMinor,                     %% Version Minor
      "NULL", 0:128,                    %% MECHANISM
      0,                                %% As Server
      0:248                             %% Filler
    >>.

new_decoder_ready() ->
    Greeting = valid_gretting_frame(),
    Command = <<4, 41, 5, "READY",
                11, "Socket-Type", 0, 0, 0, 6, "DEALER",
                8, "Identity", 0, 0, 0, 0
              >>,
    Decoder1 = erlangzmq_protocol:new_decoder(),
    {ready, Decoder2} = erlangzmq_protocol:decode(Decoder1, <<Greeting/binary, Command/binary>>),
    Decoder2.

decoder_receive_a_small_command_test() ->
    Greeting = valid_gretting_frame(),
    CommandFlags = <<4, 41>>,
    Command = <<5, "READY",
              11, "Socket-Type", 0, 0, 0, 6, "DEALER",
              8, "Identity", 0, 0, 0, 0
            >>,
    ?assertEqual(byte_size(Command), 41),

    Decoder1 = erlangzmq_protocol:new_decoder(),
    {ready, Decoder2} = erlangzmq_protocol:decode(Decoder1, <<Greeting/binary, CommandFlags/binary, Command/binary>>),
    {ok, Decoder3, Commands} = erlangzmq_protocol:continue_decode(Decoder2),

    ?assertEqual(erlangzmq_protocol:decoder_state(Decoder3), ready),
    ?assertEqual(length(Commands), 1).

decoder_receive_a_large_command_test() ->
    Greeting = valid_gretting_frame(),
    CommandFlags = <<6, 0, 0, 0, 0, 0, 0, 2, 29>>,
    Identity = binary:copy(<<"large">>, 100),
    Command = <<5, "READY",
              11, "Socket-Type", 0, 0, 0, 6, "DEALER",
              8, "Identity", 0, 0, 1, 244, Identity/binary
            >>,
    ?assertEqual(byte_size(Command), 541),

    Decoder1 = erlangzmq_protocol:new_decoder(),
    {ready, Decoder2} = erlangzmq_protocol:decode(Decoder1, <<Greeting/binary, CommandFlags/binary, Command/binary>>),
    {ok, Decoder3, Commands} = erlangzmq_protocol:continue_decode(Decoder2),

    ?assertEqual(erlangzmq_protocol:decoder_state(Decoder3), ready),
    ?assertEqual(length(Commands), 1).

decoder_receive_a_command_by_partial_flags_test() ->
    Greeting = valid_gretting_frame(),
    CommandFlags = <<4>>,
    Command = <<41, 5, "READY", 11, "Socket-Type", 0, 0, 0, 6, "DEALER",
                8, "Identity", 0, 0, 0, 0>>,
    Decoder1 = erlangzmq_protocol:new_decoder(),

    {ready, Decoder2} = erlangzmq_protocol:decode(Decoder1, Greeting),
    {ok, Decoder3} = erlangzmq_protocol:decode(Decoder2, CommandFlags),
    {ok, Decoder4, Commands} = erlangzmq_protocol:decode(Decoder3, Command),

    ?assertEqual(erlangzmq_protocol:decoder_state(Decoder4), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(Decoder4), nil),
    ?assertEqual(length(Commands), 1).

decoder_receive_a_large_command_by_partial_flags_test() ->
    Greeting = valid_gretting_frame(),
    CommandFlags = <<6>>,
    Command = <<0,0,0,0,0,0,0,41, 5, "READY", 11, "Socket-Type", 0, 0, 0, 6, "DEALER",
                8, "Identity", 0, 0, 0, 0>>,
    Decoder1 = erlangzmq_protocol:new_decoder(),

    {ready, Decoder2} = erlangzmq_protocol:decode(Decoder1, Greeting),
    {ok, Decoder3} = erlangzmq_protocol:decode(Decoder2, CommandFlags),
    {ok, Decoder4, Commands} = erlangzmq_protocol:decode(Decoder3, Command),

    ?assertEqual(erlangzmq_protocol:decoder_state(Decoder4), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(Decoder4), nil),
    ?assertEqual(length(Commands), 1).

decoder_receive_a_command_by_partial_test() ->
    Greeting = valid_gretting_frame(),
    CommandFlags = <<4, 41>>,
    Command1 = <<5, "READY", 11, "Socket-Type", 0, 0, 0, 6, "DEALER">>,
    Command2 = <<8, "Identity", 0, 0, 0, 0>>,
    Decoder1 = erlangzmq_protocol:new_decoder(),

    {ready, Decoder2} = erlangzmq_protocol:decode(Decoder1, <<Greeting/binary, CommandFlags/binary, Command1/binary>>),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(Decoder2), <<CommandFlags/binary, Command1/binary>>),
    {ok, Decoder3} = erlangzmq_protocol:continue_decode(Decoder2),
    {ok, Decoder4, Commands} = erlangzmq_protocol:decode(Decoder3, Command2),

    ?assertEqual(erlangzmq_protocol:decoder_state(Decoder4), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(Decoder4), nil),
    ?assertEqual(length(Commands), 1).

decoder_receive_some_command_by_partial_test() ->
    Greeting = valid_gretting_frame(),
    CommandFlags1 = <<4, 41>>,
    Command1 = <<5, "READY", 11, "Socket-Type", 0, 0, 0, 6, "DEALER",
                 8, "Identity", 0, 0, 0, 0>>,
    CommandFlags2 = <<4, 38>>,
    Command2 = <<5, "READY", 11, "Socket-Type", 0, 0, 0, 3, "REQ",
                 8, "Identity", 0, 0, 0, 0>>,
    Decoder = erlangzmq_protocol:new_decoder(),
    Buffer = <<Greeting/binary,
               CommandFlags1/binary, Command1/binary,
               CommandFlags2/binary, Command2/binary>>,
    AfterReadyBuffer = <<CommandFlags1/binary, Command1/binary,
                         CommandFlags2/binary, Command2/binary>>,

    {ready, NewDecoder1} = erlangzmq_protocol:decode(Decoder, Buffer),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder1), AfterReadyBuffer),
    {ok, NewDecoder2, Commands} = erlangzmq_protocol:continue_decode(NewDecoder1),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder2), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder2), nil),
    ?assertEqual(length(Commands), 2).

encode_small_command_test()->
    Frame = erlangzmq_protocol:encode_command(<<5, "READY">>),
    ?assertEqual(Frame, <<4, 6, 5, "READY">>).

encode_large_command_test()->
    Command = binary:copy(<<"big">>, 100),
    Frame = erlangzmq_protocol:encode_command(<<255, Command/binary>>),
    ?assertEqual(Frame, <<6, 0, 0, 0, 0, 0, 0, 1, 45, 255, Command/binary>>).

encode_small_last_message_test()->
    Frame = erlangzmq_protocol:encode_last_message(<<"Hello">>),
    ?assertEqual(Frame, <<0, 5, "Hello">>).

encode_large_last_message_test()->
    Message = binary:copy(<<"big">>, 100),
    Frame = erlangzmq_protocol:encode_last_message(Message),
    ?assertEqual(Frame, <<2, 0, 0, 0, 0, 0, 0, 1, 44, Message/binary>>).

encode_small_more_message_test()->
    Frame = erlangzmq_protocol:encode_more_message(<<"Hello">>),
    ?assertEqual(Frame, <<1, 5, "Hello">>).

encode_large_more_message_test()->
    Message = binary:copy(<<"big">>, 100),
    Frame = erlangzmq_protocol:encode_more_message(Message),
    ?assertEqual(Frame, <<3, 0, 0, 0, 0, 0, 0, 1, 44, Message/binary>>).

encode_message_multi_part_test()->
    Frame = erlangzmq_protocol:encode_message_multipart([<<"Hello">>, <<"World">>]),
    ?assertEqual(Frame, <<1, 5, "Hello", 0, 5, "World">>).

encode_old_subscribe_test()->
    Frame = erlangzmq_protocol:encode_old_subscribe(<<"Topic">>),
    ?assertEqual(Frame, <<0, 6, 1, "Topic">>).

encode_old_cancel_test()->
    Frame = erlangzmq_protocol:encode_old_cancel(<<"Topic">>),
    ?assertEqual(Frame, <<0, 6, 0, "Topic">>).


%%
%% Decode messages test
%%
decoder_receive_a_small_message_test() ->
    Decoder = new_decoder_ready(),
    Frame = <<0, 11, "Hello World">>,
    {ok, NewDecoder1, [Message]} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder1), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder1), nil),
    ?assertEqual(erlangzmq_protocol:message_data(Message), <<"Hello World">>),
    ?assertEqual(erlangzmq_protocol:message_has_more(Message), false).

decoder_receive_a_small_more_message_test() ->
    Decoder = new_decoder_ready(),
    Frame = <<1, 11, "Hello World">>,
    {ok, NewDecoder1, [Message]} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder1), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder1), nil),
    ?assertEqual(erlangzmq_protocol:message_data(Message), <<"Hello World">>),
    ?assertEqual(erlangzmq_protocol:message_has_more(Message), true).

decoder_receive_a_large_message_test() ->
    Decoder = new_decoder_ready(),
    MessageFrame = binary:copy(<<"more">>, 100),
    Frame = <<2, 0, 0, 0, 0, 0, 0, 1, 144, MessageFrame/binary>>,
    {ok, NewDecoder1, [Message]} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder1), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder1), nil),
    ?assertEqual(erlangzmq_protocol:message_data(Message), MessageFrame),
    ?assertEqual(erlangzmq_protocol:message_has_more(Message), false).

decoder_receive_a_large_more_message_test() ->
    Decoder = new_decoder_ready(),
    MessageFrame = binary:copy(<<"more">>, 100),
    Frame = <<3, 0, 0, 0, 0, 0, 0, 1, 144, MessageFrame/binary>>,
    {ok, NewDecoder1, [Message]} = erlangzmq_protocol:decode(Decoder, Frame),
    ?assertEqual(erlangzmq_protocol:decoder_state(NewDecoder1), ready),
    ?assertEqual(erlangzmq_protocol:decoder_buffer(NewDecoder1), nil),
    ?assertEqual(erlangzmq_protocol:message_data(Message), MessageFrame),
    ?assertEqual(erlangzmq_protocol:message_has_more(Message), true).
