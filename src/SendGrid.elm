module SendGrid exposing
    ( Email, sendEmail, sendEmailTask, Error(..), ErrorMessage, ErrorMessage403
    , ApiKey, apiKey
    , Content, textContent, htmlContent
    )

{-|


# Email

@docs Email, sendEmail, sendEmailTask, Error, ErrorMessage, ErrorMessage403


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

import Html.String
import Http
import Json.Decode as JD
import Json.Encode as JE
import List.Nonempty exposing (Nonempty)
import String.Nonempty exposing (NonemptyString)
import Task exposing (Task)


{-| An email address. For example "example@yahoo.com"
-}
type alias EmailAddress =
    String


{-| The body of our email. This can either be plain text or html.
-}
type Content a
    = TextContent NonemptyString
    | HtmlContent (Html.String.Html a)


{-| Create a text body for an email.
-}
textContent : NonemptyString -> Content a
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


encodePersonalization : ( Nonempty EmailAddress, List EmailAddress, List EmailAddress ) -> JE.Value
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


encodeNonemptyList : (a -> JE.Value) -> Nonempty a -> JE.Value
encodeNonemptyList encoder list =
    List.Nonempty.toList list |> JE.list encoder


{-| -}
type alias Email a =
    { subject : NonemptyString
    , content : Content a
    , to : Nonempty EmailAddress
    , cc : List EmailAddress
    , bcc : List EmailAddress
    , nameOfSender : String
    , emailAddressOfSender : EmailAddress
    }


encodeNonemptyString : NonemptyString -> JE.Value
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
        , url = sendGridApiUrl
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


{-| Send an email using the SendGrid API. This is the task version of [sendEmail](#sendEmail).
-}
sendEmailTask : ApiKey -> Email a -> Task Error ()
sendEmailTask (ApiKey apiKey_) email =
    Http.task
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ apiKey_) ]
        , url = sendGridApiUrl
        , body = encodeSendEmail email |> Http.jsonBody
        , resolver =
            Http.stringResolver
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
        }


sendGridApiUrl =
    "https://api.sendgrid.com/v3/mail/send"


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
            JD.decodeString codecErrorResponse body |> toErrorCode StatusCode400

        401 ->
            JD.decodeString codecErrorResponse body |> toErrorCode StatusCode401

        403 ->
            JD.decodeString codec403ErrorResponse body |> toErrorCode StatusCode403

        413 ->
            JD.decodeString codecErrorResponse body |> toErrorCode StatusCode413

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


codecErrorResponse : JD.Decoder (List ErrorMessage)
codecErrorResponse =
    JD.field "errors" (JD.list codecErrorMessage)


{-| The content of a 403 status code error.
-}
type alias ErrorMessage403 =
    { message : Maybe String
    , field : Maybe String
    , help : Maybe String
    }


codec403Error : JD.Decoder ErrorMessage403
codec403Error =
    JD.map3 ErrorMessage403
        (optionalField "message" JD.string)
        (optionalField "field" JD.string)
        (optionalField "help" (JD.value |> JD.map (JE.encode 0)))


codec403ErrorResponse : JD.Decoder { errors : List ErrorMessage403, id : Maybe String }
codec403ErrorResponse =
    JD.map2 (\errors id -> { errors = errors |> Maybe.withDefault [], id = id })
        (optionalField "errors" (JD.list codec403Error))
        (optionalField "id" JD.string)


codecErrorMessage : JD.Decoder ErrorMessage
codecErrorMessage =
    JD.map3 ErrorMessage
        (optionalField "field" JD.string)
        (JD.field "message" JD.string)
        (optionalField "error_id" JD.string)


{-| Borrowed from elm-community/json-extra
-}
optionalField : String -> JD.Decoder a -> JD.Decoder (Maybe a)
optionalField fieldName decoder =
    let
        finishDecoding json =
            case JD.decodeValue (JD.field fieldName JD.value) json of
                Ok val ->
                    -- The field is present, so run the decoder on it.
                    JD.map Just (JD.field fieldName decoder)

                Err _ ->
                    -- The field was missing, which is fine!
                    JD.succeed Nothing
    in
    JD.value
        |> JD.andThen finishDecoding
