module SendGrid.Internal exposing (..)

import Email.Html
import Email.Html.Attributes
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Internal
import Test exposing (..)


suite : Test
suite =
    describe "The Email.HTML module"
        [ describe "Email.Html.toHtml"
            [ test "includes HTML after a <br>" <|
                \_ ->
                    Email.Html.div [] [ Email.Html.text "line 1", Email.Html.br [] [], Email.Html.text "line 2" ]
                        |> Internal.toString
                        |> Tuple.first
                        |> Expect.equal "<div>line 1<br>line 2</div>"
            , test "Handle <br> with attributes" <|
                \_ ->
                    Email.Html.div
                        []
                        [ Email.Html.text "line 1"
                        , Email.Html.br [ Email.Html.Attributes.color "red" ] []
                        , Email.Html.text "line 2"
                        ]
                        |> Internal.toString
                        |> Tuple.first
                        |> Expect.equal "<div>line 1<br style=\"color: red\">line 2</div>"
            , test "Handle <br> with children" <|
                \_ ->
                    Email.Html.div
                        []
                        [ Email.Html.text "line 1"
                        , Email.Html.br [] [ Email.Html.text "inside br" ]
                        , Email.Html.text "line 2"
                        ]
                        |> Internal.toString
                        |> Tuple.first
                        |> Expect.equal "<div>line 1<br>inside br</br>line 2</div>"
            ]
        ]
