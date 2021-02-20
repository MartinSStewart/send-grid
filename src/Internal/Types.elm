module Internal.Types exposing (..)

import Bytes exposing (Bytes)


type Html
    = Node String (List Attribute) (List Html)
    | InlineImage { imageData : Bytes, mimeType : String } (List Attribute) (List Html)


type Attribute
    = StyleAttribute String String
    | Attribute String String
