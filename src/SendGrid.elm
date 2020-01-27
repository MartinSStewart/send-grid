module SendGrid exposing
    ( ApiKey
    , Email
    , EmailAndName
    , Error(..)
    , apiKey
    , encodeSendEmail
    , htmlContent
    , sendEmail
    , textContent
    )

{-| -}

import Codec exposing (Codec)
import Html.String
import Http
import Json.Decode as JD
import Json.Encode as JE
import List.Nonempty
import String.Nonempty exposing (Nonempty)


{-| An email address and name combo.
-}
type alias EmailAndName =
    { email : EmailAddress
    , name : String
    }


{-| An email address. For example "example@yahoo.com"
-}
type alias EmailAddress =
    String


{-| The body of our email. This can either be plain text or html.
-}
type Content a
    = TextContent Nonempty
    | HtmlContent (Html.String.Html a)


{-| Create a text body for an email.
-}
textContent : Nonempty -> Content a
textContent text =
    TextContent text


{-| Create an html body for an email.
-}
htmlContent : Html.String.Html a -> Content a
htmlContent html =
    HtmlContent html


encodeContent : Content a -> JE.Value
encodeContent content =
    case content of
        TextContent text ->
            JE.object [ ( "type", JE.string "text/plain" ), ( "value", encodeNonemptyString text ) ]

        HtmlContent html ->
            JE.object [ ( "type", JE.string "text/html" ), ( "value", html |> Html.String.toString 0 |> JE.string ) ]


encodeEmailAndName : EmailAndName -> JE.Value
encodeEmailAndName emailAndName =
    JE.object [ ( "email", JE.string emailAndName.email ), ( "name", JE.string emailAndName.name ) ]


encodePersonalization : ( List.Nonempty.Nonempty EmailAddress, List EmailAddress, List EmailAddress ) -> JE.Value
encodePersonalization ( to, cc, bcc ) =
    let
        addName =
            List.map (\address -> { email = address, name = "" })

        ccJson =
            if List.isEmpty cc then
                []

            else
                [ ( "cc", addName cc |> JE.list encodeEmailAndName ) ]

        bccJson =
            if List.isEmpty bcc then
                []

            else
                [ ( "bcc", addName bcc |> JE.list encodeEmailAndName ) ]

        toJson =
            ( "to"
            , to
                |> List.Nonempty.map (\address -> { email = address, name = "" })
                |> encodeNonemptyList encodeEmailAndName
            )
    in
    JE.object (toJson :: ccJson ++ bccJson)


encodeNonemptyList : (a -> JE.Value) -> List.Nonempty.Nonempty a -> JE.Value
encodeNonemptyList encoder list =
    List.Nonempty.toList list |> JE.list encoder


type alias Email a =
    { subject : Nonempty
    , content : Content a
    , to : List.Nonempty.Nonempty EmailAddress
    , cc : List EmailAddress
    , bcc : List EmailAddress
    , from : EmailAndName
    }


encodeNonemptyString : Nonempty -> JE.Value
encodeNonemptyString nonemptyString =
    String.Nonempty.toString nonemptyString |> JE.string


encodeSendEmail : Email a -> JE.Value
encodeSendEmail { content, subject, from, to, cc, bcc } =
    JE.object
        [ ( "subject", encodeNonemptyString subject )
        , ( "content", JE.list encodeContent [ content ] )
        , ( "personalizations", JE.list encodePersonalization [ ( to, cc, bcc ) ] )
        , ( "from", encodeEmailAndName from )
        ]


{-| A SendGrid API key. In order to user their API you must have one of these.
-}
type ApiKey
    = ApiKey String


{-| Create an API key from a raw string.
-}
apiKey : String -> ApiKey
apiKey apiKey_ =
    ApiKey apiKey_


{-| Send an email using the SendGrid API.
-}
sendEmail : (Result Error () -> msg) -> ApiKey -> Email a -> Cmd msg
sendEmail msg (ApiKey apiKey_) email =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ apiKey_) ]
        , url = "https://api.sendgrid.com/v3/mail/send"
        , body = encodeSendEmail email |> Http.jsonBody
        , expect =
            Http.expectStringResponse msg
                (\response ->
                    case response of
                        Http.BadUrl_ url ->
                            BadUrl url |> Err

                        Http.Timeout_ ->
                            Err Timeout

                        Http.NetworkError_ ->
                            Err NetworkError

                        Http.BadStatus_ metadata body ->
                            decodeBadStatus metadata body |> Err

                        Http.GoodStatus_ _ _ ->
                            Ok ()
                )
        , timeout = Nothing
        , tracker = Nothing
        }


decodeBadStatus : Http.Metadata -> String -> Error
decodeBadStatus metadata body =
    let
        toErrorCode : (a -> Error) -> Result e a -> Error
        toErrorCode errorCode result =
            case result of
                Ok value ->
                    errorCode value

                Err _ ->
                    UnknownError { statusCode = metadata.statusCode, body = body }
    in
    case metadata.statusCode of
        400 ->
            Codec.decodeString codecErrorResponse body |> toErrorCode StatusCode400

        401 ->
            Codec.decodeString codecErrorResponse body |> toErrorCode StatusCode401

        403 ->
            Codec.decodeString codec403ErrorResponse body |> toErrorCode StatusCode403

        413 ->
            Codec.decodeString codecErrorResponse body |> toErrorCode StatusCode413

        _ ->
            UnknownError { statusCode = metadata.statusCode, body = body }


{-| Possible error codes we might get back when trying to send an email.
Some are just normal HTTP errors, others are specific to the SendGrid API.
-}
type Error
    = StatusCode400 (List ErrorMessage)
    | StatusCode401 (List ErrorMessage)
    | StatusCode403 { errors : List ErrorMessage403, id : Maybe String }
    | StatusCode413 (List ErrorMessage)
    | UnknownError { statusCode : Int, body : String }
    | NetworkError
    | Timeout
    | BadUrl String


{-| The content of a generic SendGrid error.
-}
type alias ErrorMessage =
    { field : Maybe String
    , message : String
    , errorId : Maybe String
    }


codecErrorResponse : Codec (List ErrorMessage)
codecErrorResponse =
    Codec.object identity
        |> Codec.field "errors" identity (Codec.list codecErrorMessage)
        |> Codec.buildObject


{-| The content of a 403 status code error.
-}
type alias ErrorMessage403 =
    { message : Maybe String
    , field : Maybe String
    , help : Maybe JD.Value
    }


codec403Error : Codec ErrorMessage403
codec403Error =
    Codec.object ErrorMessage403
        |> Codec.optionalField "message" .message Codec.string
        |> Codec.optionalField "field" .field Codec.string
        |> Codec.optionalField "help" .help Codec.value
        |> Codec.buildObject


codec403ErrorResponse : Codec { errors : List ErrorMessage403, id : Maybe String }
codec403ErrorResponse =
    Codec.object (\errors id -> { errors = errors |> Maybe.withDefault [], id = id })
        |> Codec.optionalField "errors" (.errors >> Just) (Codec.list codec403Error)
        |> Codec.optionalField "id" .id Codec.string
        |> Codec.buildObject


codecErrorMessage : Codec ErrorMessage
codecErrorMessage =
    Codec.object ErrorMessage
        |> Codec.optionalField "field" .field Codec.string
        |> Codec.field "message" .message Codec.string
        |> Codec.optionalField "error_id" .errorId Codec.string
        |> Codec.buildObject