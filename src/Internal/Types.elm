module Internal.Types exposing (Attribute(..), Html(..), cid, toString)

import Bytes exposing (Bytes)


type Html
    = Node String (List Attribute) (List Html)
    | InlineImage { content : Bytes, mimeType : String, name : String } (List Attribute) (List Html)
    | TextNode String


type Attribute
    = StyleAttribute String String
    | Attribute String String


type alias Acc =
    { depth : Int
    , stack : List ( String, List Html )
    , result : List String
    }


toString : Html -> String
toString html =
    let
        initialAcc : Acc
        initialAcc =
            { depth = 0
            , stack = []
            , result = []
            }
    in
    toStringHelper [ html ] initialAcc
        |> .result
        |> List.reverse
        |> String.concat


toStringHelper : List Html -> Acc -> Acc
toStringHelper tags acc =
    case tags of
        [] ->
            case acc.stack of
                [] ->
                    acc

                ( tagName, cont ) :: rest ->
                    toStringHelper
                        cont
                        { acc
                            | result = closingTag tagName :: acc.result
                            , depth = acc.depth - 1
                            , stack = rest
                        }

        (Node tagName attributes children) :: rest ->
            case children of
                [] ->
                    toStringHelper
                        rest
                        { acc | result = tag tagName attributes :: acc.result }

                childNodes ->
                    toStringHelper
                        childNodes
                        { acc
                            | result = tag tagName attributes :: acc.result
                            , depth = acc.depth + 1
                            , stack = ( tagName, rest ) :: acc.stack
                        }

        (InlineImage { name } attributes children) :: rest ->
            case children of
                [] ->
                    toStringHelper
                        rest
                        { acc | result = tag "img" (Attribute "src" (cid name) :: attributes) :: acc.result }

                childNodes ->
                    toStringHelper
                        childNodes
                        { acc
                            | result = tag "img" (Attribute "src" (cid name) :: attributes) :: acc.result
                            , depth = acc.depth + 1
                            , stack = ( "img", rest ) :: acc.stack
                        }

        (TextNode string) :: rest ->
            toStringHelper
                rest
                { acc | result = escapeHtmlText string :: acc.result }


cid : String -> String
cid filename =
    "cid:" ++ filename



--++ filename


tag : String -> List Attribute -> String
tag tagName attributes =
    "<" ++ String.join " " (tagName :: attributesToString attributes) ++ ">"


escapeHtmlText : String -> String
escapeHtmlText =
    String.replace "&" "&amp;"
        >> String.replace "<" "&lt;"
        >> String.replace ">" "&gt;"


attributesToString : List Attribute -> List String
attributesToString attrs =
    let
        ( classes, styles, regular ) =
            List.foldl addAttribute ( [], [], [] ) attrs
    in
    regular
        |> withClasses classes
        |> withStyles styles


withClasses : List String -> List String -> List String
withClasses classes attrs =
    case classes of
        [] ->
            attrs

        _ ->
            buildProp "class" (String.join " " classes) :: attrs


withStyles : List String -> List String -> List String
withStyles styles attrs =
    case styles of
        [] ->
            attrs

        _ ->
            buildProp "style" (String.join "; " styles) :: attrs


type alias AttrAcc =
    ( List String, List String, List String )


buildProp : String -> String -> String
buildProp key value =
    hyphenate key ++ "=\"" ++ escape value ++ "\""


addAttribute : Attribute -> AttrAcc -> AttrAcc
addAttribute attribute ( classes, styles, attrs ) =
    case attribute of
        Attribute key value ->
            ( classes, styles, buildProp key value :: attrs )

        StyleAttribute key value ->
            ( classes
            , (escape key ++ ": " ++ escape value) :: styles
            , attrs
            )


escape : String -> String
escape =
    String.foldl
        (\char acc ->
            if char == '"' then
                acc ++ "\\\""

            else
                acc ++ String.fromChar char
        )
        ""


hyphenate : String -> String
hyphenate =
    String.foldl
        (\char acc ->
            if Char.isUpper char then
                acc ++ "-" ++ String.fromChar (Char.toLower char)

            else
                acc ++ String.fromChar char
        )
        ""


closingTag : String -> String
closingTag tagName =
    "</" ++ tagName ++ ">"


indent : Int -> Int -> String -> String
indent perLevel level x =
    String.repeat (perLevel * level) " " ++ x
