module SendGrid.Internal exposing (..)

import Email.Html
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Internal
import Test exposing (..)


suite : Test
suite =
    describe "The Email.HTML module" [
        describe "Email.Html.toHtml"
            [ test "includes HTML after a <br>" <|
                \_ ->
                    Email.Html.div [] [Email.Html.text "line 1", Email.Html.br [] [], Email.Html.text "line 2"]
                        |> Internal.toString
                        |> Tuple.first
                        |> String.contains "line 2"
                        |> Expect.true "Expected the HTML to contain \"line 2\" "


        ]
    ]
