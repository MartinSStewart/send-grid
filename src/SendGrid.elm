module SendGrid exposing
    ( Email, sendEmail, Error(..)
    , ApiKey, apiKey
    , Content, textContent, htmlContent
    )

{-|


# Email

@docs Email, sendEmail, Error


# API Key

In order to send email via SendGrid, you need an API key.
To do this signup for a SendGrid account.

Then after you've logged in, click on the settings tab, then API Keys, and finally "Create API Key".
You'll get to choose if the API key has `Full Access`, `Restricted Access`, or `Billing Access`.
For this package it's best if you select restricted access and then set `Mail Send` to `Full Access` and leave everything else as `No Access`.

Once you've done this you'll be given an API key. Store it in a password manager or something for safe keeping. _You are highly recommended to not hard code the API key into your source code!_

@docs ApiKey, apiKey


# Email content

@docs Content, textContent, htmlContent

-}

import Codec exposing (Codec)
import Html.String
import Http
import Json.Decode as JD
import Json.Encode as JE
import List.Nonempty
import String.Nonempty


{-| An email address. For example "example@yahoo.com"
-}
type alias EmailAddress =
    String


{-| The body of our email. This can either be plain text or html.
-}
type Content a
    = TextContent String.Nonempty.Nonempty
    | HtmlContent (Html.String.Html a)


{-| Create a text body for an email.
-}
textContent : String.Nonempty.Nonempty -> Content a
textContent text =
    TextContent text


{-| Create an html body for an email.
Note that this function expects Html._String_.Html as a parameter.
To create those you'll need to run `elm install zwilias/elm-html-string`.
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


encodeEmailAndName : { name : String, email : EmailAddress } -> JE.Value
encodeEmailAndName { email, name } =
    JE.object [ ( "email", JE.string email ), ( "name", JE.string name ) ]


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


{-| -}
type alias Email a =
    { subject : String.Nonempty.Nonempty
    , content : Content a
    , to : List.Nonempty.Nonempty EmailAddress
    , cc : List EmailAddress
    , bcc : List EmailAddress
    , nameOfSender : String
    , emailAddressOfSender : EmailAddress
    }


encodeNonemptyString : String.Nonempty.Nonempty -> JE.Value
encodeNonemptyString nonemptyString =
    String.Nonempty.toString nonemptyString |> JE.string


encodeSendEmail : Email a -> JE.Value
encodeSendEmail { content, subject, nameOfSender, emailAddressOfSender, to, cc, bcc } =
    JE.object
        [ ( "subject", encodeNonemptyString subject )
        , ( "content", JE.list encodeContent [ content ] )
        , ( "personalizations", JE.list encodePersonalization [ ( to, cc, bcc ) ] )
        , ( "from", encodeEmailAndName { name = nameOfSender, email = emailAddressOfSender } )
        ]


{-| A SendGrid API key. In order to use the SendGrid API you must have one of these.
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
