module XB2.Share.Platform2.AudienceExpressionViewer exposing (Config, ExpressionAttribute, view)

import Html
import Html.Attributes as Attrs
import Html.Events as Events
import Html.Keyed
import Json.Decode as Decode
import Json.Decode.Extra as Decode
import Json.Encode as Encode
import WeakCss
import XB2.Data.Audience.Expression as Expression
import XB2.Data.Namespace as Namespace
import XB2.Share.Config as Config
import XB2.Share.Config.Main as MainConfig
import XB2.Share.Data.Id as Id
import XB2.Share.Data.Labels as Labels


type alias ExpressionAttribute =
    { questionCode : Labels.ShortQuestionCode
    , datapointCode : Labels.ShortDatapointCode
    , namespaceCode : Namespace.Code
    , datapointLabel : String
    , order : Float
    , questionDescription : Maybe String
    , questionLabel : String
    , suffixCode : Maybe Labels.SuffixCode
    , suffixLabel : Maybe String
    }


type alias Config msg =
    { attributeMetadataOpened : ExpressionAttribute -> msg
    , noOp : msg
    }


emptyStringAsNothing : (String -> a) -> String -> Maybe a
emptyStringAsNothing toExpectedType s =
    if String.isEmpty s then
        Nothing

    else
        Just <| toExpectedType s


expressionAttributeDecoder : Decode.Decoder ExpressionAttribute
expressionAttributeDecoder =
    Decode.succeed ExpressionAttribute
        |> Decode.andMap (Decode.field "question_code" Id.decode)
        |> Decode.andMap (Decode.field "datapoint_code" Id.decode)
        |> Decode.andMap (Decode.field "namespace_code" Namespace.codeDecoder)
        |> Decode.andMap (Decode.field "datapoint_label" Decode.string)
        |> Decode.andMap (Decode.field "order" Decode.float)
        |> Decode.andMap (Decode.maybe (Decode.field "question_description" Decode.string))
        |> Decode.andMap (Decode.field "question_label" Decode.string)
        |> Decode.andMap
            (Decode.optionalField "suffix_code" Decode.string
                |> Decode.map (Maybe.andThen (emptyStringAsNothing Id.fromString))
            )
        |> Decode.andMap
            (Decode.optionalNullableField "suffix_label" Decode.string
                |> Decode.map (Maybe.andThen (emptyStringAsNothing identity))
            )


view : Config.Flags -> Config msg -> WeakCss.ClassName -> Expression.Expression -> Html.Html msg
view flags config moduleClass expression =
    let
        uri : MainConfig.Uri
        uri =
            MainConfig.get flags.env
                |> .uri

        apiEncoded =
            Encode.object
                [ ( "SERVICE_LAYER_HOST", Encode.string uri.serviceLayer ) ]

        userEncoded =
            Encode.object
                [ ( "token", Encode.string flags.token )
                , ( "email", Encode.string flags.user.email )
                ]

        encodedConfig =
            Encode.object
                [ ( "environment", Encode.string <| MainConfig.stageToString flags.env )
                , ( "api", apiEncoded )
                , ( "user", userEncoded )
                ]
                |> Encode.encode 0

        encodedExpression =
            Expression.encode expression
                |> Encode.encode 0
    in
    Html.Keyed.node "x-et-audience-expression-viewer"
        [ Attrs.attribute "x-env-values" encodedConfig
        , Attrs.attribute "expression" encodedExpression
        , Attrs.attribute "app-name" "CrosstabBuilder"
        , WeakCss.nest "expression-viewer" moduleClass
        , Events.on "CrosstabBuilder-clickedQuestionMetadataViewNotesEvent"
            (Decode.value
                |> Decode.map
                    (\event ->
                        case Decode.decodeValue (Decode.at [ "detail", "payload", "attribute" ] expressionAttributeDecoder) event of
                            Ok decoded ->
                                config.attributeMetadataOpened decoded

                            Err _ ->
                                -- We ignore decoding errors for now
                                config.noOp
                    )
            )
        ]
        []
