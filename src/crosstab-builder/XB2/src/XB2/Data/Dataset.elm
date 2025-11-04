module XB2.Data.Dataset exposing
    ( Code
    , Dataset
    , DatasetCategory
    , StringifiedCode
    , codeDecoder
    , codeToString
    , decoder
    , encodeCode
    , encodeForWebcomponent
    , listDecoder
    , naCode
    )

import Json.Decode as Decode
import Json.Decode.Extra as Decode
import Json.Encode as Encode
import XB2.Data.Namespace as Namespace
import XB2.Share.Data.Id as Id
import XB2.Share.Data.Labels as Labels


type alias Dataset =
    { code : Code
    , name : String
    , description : String
    , baseNamespaceCode : Namespace.Code
    , categories : List DatasetCategory
    , depth : Int
    , order : Float
    }


type Code
    = DatasetCode StringifiedCode


type alias StringifiedCode =
    String


codeToString : Code -> StringifiedCode
codeToString (DatasetCode code) =
    code


codeDecoder : Decode.Decoder Code
codeDecoder =
    Decode.map DatasetCode Decode.string


encodeCode : Code -> Encode.Value
encodeCode (DatasetCode code) =
    Encode.string code


naCode : Code
naCode =
    DatasetCode "n/a"


type alias DatasetCategory =
    { id : Labels.CategoryId
    , name : String
    , order : Float
    }


listDecoder : Decode.Decoder (List Dataset)
listDecoder =
    Decode.list decoderWithoutOrder
        |> Decode.map
            (\almostDatasets ->
                almostDatasets
                    |> List.indexedMap (\order toDataset -> toDataset <| toFloat order)
            )


decoderWithoutOrder : Decode.Decoder (Float -> Dataset)
decoderWithoutOrder =
    Decode.succeed Dataset
        |> Decode.andMap (Decode.field "code" codeDecoder)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap (Decode.field "description" Decode.string)
        |> Decode.andMap (Decode.field "base_namespace_code" Namespace.codeDecoder)
        |> Decode.andMap
            (Decode.field "categories"
                (Decode.list
                    (Decode.succeed DatasetCategory
                        |> Decode.andMap (Decode.field "id" Id.decode)
                        |> Decode.andMap (Decode.field "name" Decode.string)
                        |> Decode.andMap (Decode.field "order" Decode.float)
                    )
                )
                |> Decode.maybe
                |> Decode.map (Maybe.withDefault [])
            )
        |> Decode.andMap
            (Decode.field "depth" Decode.int
                |> Decode.maybe
                |> Decode.map (Maybe.withDefault 0)
            )


decoder : Decode.Decoder Dataset
decoder =
    Decode.succeed Dataset
        |> Decode.andMap (Decode.field "code" codeDecoder)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap (Decode.field "description" Decode.string)
        |> Decode.andMap (Decode.field "base_namespace_code" Namespace.codeDecoder)
        |> Decode.andMap
            (Decode.field "categories"
                (Decode.list
                    (Decode.succeed DatasetCategory
                        |> Decode.andMap (Decode.field "id" Id.decode)
                        |> Decode.andMap (Decode.field "name" Decode.string)
                        |> Decode.andMap (Decode.field "order" Decode.float)
                    )
                )
                |> Decode.maybe
                |> Decode.map (Maybe.withDefault [])
            )
        |> Decode.andMap
            (Decode.field "depth" Decode.int
                |> Decode.maybe
                |> Decode.map (Maybe.withDefault 0)
            )
        |> Decode.andMap
            (Decode.optionalNullableField "order" Decode.float
                |> Decode.map (Maybe.withDefault 0)
            )


{-| NOTE: This will later be updated to be 1:1 with the decoder, but for that
the webcomponents themselves need to be updated.
-}
encodeForWebcomponent : Dataset -> Encode.Value
encodeForWebcomponent dataset =
    Encode.object
        [ ( "code", encodeCode dataset.code )
        , ( "name", Encode.string dataset.name )
        , ( "description", Encode.string dataset.description )
        , ( "base_namespace_code", Namespace.encodeCode dataset.baseNamespaceCode )
        , ( "categories"
          , Encode.list
                (\category ->
                    Encode.object
                        [ ( "id", Id.encode category.id )
                        , ( "name", Encode.string category.name )
                        , ( "order", Encode.float category.order )
                        ]
                )
                dataset.categories
          )
        , ( "depth", Encode.int dataset.depth )
        , ( "order", Encode.float dataset.order )
        ]
