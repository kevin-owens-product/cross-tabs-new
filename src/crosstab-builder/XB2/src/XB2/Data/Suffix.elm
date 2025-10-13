module XB2.Data.Suffix exposing
    ( Code
    , Suffix
    , codeDecoder
    , codeFromString
    , codeToString
    , decoder
    , encodeCodeAsString
    )

import Json.Decode as Decode
import Json.Encode as Encode
import XB2.Data.Zod.Nullish as Nullish


{-| A `Suffix` is equivalent to an option. In the context of GWI's data structure, a
`Suffix` is an optional component of an attribute that represents different response
options or variations within a question.

E.g.

    Sports Followed >> FC Barcelona >> Support as a Main Club
    \__ Question __/  \_ Datapoint _/  \______ Suffix ______/

Where the other `Suffix` options might be:

    - Support as a Secondary Club
    - Have Interest In
    - Any Support / Interest

-}
type alias Suffix =
    { code : Code
    , name : String
    , midpoint : Nullish.Nullish Float
    }


type Code
    = SuffixCode Int


decoder : Decode.Decoder Suffix
decoder =
    Decode.map3 Suffix
        (Decode.oneOf
            [ Decode.field "code" codeDecoder
            , Decode.field "id" codeDecoder
            ]
        )
        (Decode.field "name" Decode.string)
        (Nullish.decodeField "midpoint" Decode.float)


codeDecoder : Decode.Decoder Code
codeDecoder =
    Decode.map SuffixCode <|
        Decode.oneOf
            [ Decode.int
            , Decode.string
                |> Decode.andThen
                    (\str ->
                        case String.toInt str of
                            Just i ->
                                Decode.succeed i

                            Nothing ->
                                Decode.fail
                                    ("Cannot parse suffix code from string: " ++ str)
                    )
            ]


codeToString : Code -> String
codeToString (SuffixCode i) =
    String.fromInt i


codeFromString : String -> Maybe Code
codeFromString str =
    Maybe.map SuffixCode (String.toInt str)


encodeCodeAsString : Code -> Encode.Value
encodeCodeAsString =
    Encode.string << codeToString
