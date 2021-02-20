module Email.Html exposing (Attribute, Html, a, br, div, img, inlineImg, node, table, td, th, tr)

import Bytes exposing (Bytes)
import Internal.Types


type alias Html =
    Internal.Types.Html


type alias Attribute =
    Internal.Types.Attribute


node : String -> List Attribute -> List Html -> Html
node =
    Internal.Types.Node


div : List Attribute -> List Html -> Html
div =
    Internal.Types.Node "div"


table : List Attribute -> List Html -> Html
table =
    Internal.Types.Node "table"


tr : List Attribute -> List Html -> Html
tr =
    Internal.Types.Node "tr"


td : List Attribute -> List Html -> Html
td =
    Internal.Types.Node "tr"


th : List Attribute -> List Html -> Html
th =
    Internal.Types.Node "th"


br : List Attribute -> List Html -> Html
br =
    Internal.Types.Node "br"


a : List Attribute -> List Html -> Html
a =
    Internal.Types.Node "a"


img : List Attribute -> List Html -> Html
img =
    Internal.Types.Node "img"


inlineImg : { imageData : Bytes, mimeType : String } -> List Attribute -> List Html -> Html
inlineImg =
    Internal.Types.InlineImage
