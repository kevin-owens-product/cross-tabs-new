module XB2.Share.Config.Main exposing
    ( Config
    , Stage(..)
    , Uri
    , envDecoder
    , get
    , stageToString
    )

import Json.Decode as Decode
import Url.Builder


type Stage
    = Development
    | TestSuite
    | Testing -- legacy-testing.globalwebindex.com
    | Alpha -- legacy-alpha.globalwebindex.com
    | Staging -- legacy-staging.globalwebindex.com
    | Production -- app.globalwebindex.com


envDecoder : Decode.Decoder Stage
envDecoder =
    let
        decode value =
            case value of
                "development" ->
                    Decode.succeed Development

                "testsuite" ->
                    Decode.succeed TestSuite

                "testing" ->
                    Decode.succeed Testing

                "staging" ->
                    Decode.succeed Staging

                "alpha" ->
                    Decode.succeed Alpha

                "production" ->
                    Decode.succeed Production

                _ ->
                    Decode.fail <| "Invalid ENV type" ++ value
    in
    Decode.andThen decode Decode.string


stageToString : Stage -> String
stageToString env =
    case env of
        Development ->
            "development"

        TestSuite ->
            "testsuite"

        Testing ->
            "testing"

        Staging ->
            "staging"

        Alpha ->
            "alpha"

        Production ->
            "production"


type alias Uri =
    { api : String
    , signOut : { redirectTo : String } -> String
    , app : String
    , attributes : String
    , collections : String
    , audiences : String
    , audiencesCore : String
    , datasets : String
    , analytics : String
    , serviceLayer : String
    }


type alias Config =
    { uri : Uri
    , authCookieName : String
    }


signOutUrl : String -> { redirectTo : String } -> String
signOutUrl host { redirectTo } =
    Url.Builder.crossOrigin
        host
        [ "sign-out" ]
        [ Url.Builder.string "return_to" redirectTo ]


testingUris : Uri
testingUris =
    { api = "https://api-testing.globalwebindex.com"
    , signOut = signOutUrl "https://signin-testing.globalwebindex.com"
    , app = "https://legacy-testing.globalwebindex.com"
    , attributes = "https://api-testing.globalwebindex.com/v2/attributes"
    , collections = "https://api-testing.globalwebindex.com/v1/collections"
    , audiences = "https://api-testing.globalwebindex.com/v1/audience-builder"
    , audiencesCore = "https://api-testing.globalwebindex.com/v2/audiences"
    , datasets = "https://api-testing.globalwebindex.com/v1/datasets"
    , analytics = "https://api-testing.globalwebindex.com/v1/analytics"
    , serviceLayer = "https://api-testing.globalwebindex.com/platform"
    }


stagingUris : Uri
stagingUris =
    { api = "https://api-staging.globalwebindex.com"
    , signOut = signOutUrl "https://signin-staging.globalwebindex.com"
    , app = "https://legacy-staging.globalwebindex.com"
    , attributes = "https://api-staging.globalwebindex.com/v2/attributes"
    , collections = "https://api-staging.globalwebindex.com/v1/collections"
    , audiences = "https://api-staging.globalwebindex.com/v1/audience-builder"
    , audiencesCore = "https://api-staging.globalwebindex.com/v2/audiences"
    , datasets = "https://api-staging.globalwebindex.com/v1/datasets"
    , analytics = "https://api-staging.globalwebindex.com/v1/analytics"
    , serviceLayer = "https://api-staging.globalwebindex.com/platform"
    }


alphaUris : Uri
alphaUris =
    { api = "https://api-alpha.globalwebindex.com"
    , signOut = signOutUrl "https://signin-alpha.globalwebindex.com"
    , app = "https://legacy-alpha.globalwebindex.com"
    , attributes = "https://api-alpha.globalwebindex.com/v2/attributes"
    , collections = "https://api-alpha.globalwebindex.com/v1/collections"
    , audiences = "https://api-alpha.globalwebindex.com/v1/audience-builder"
    , audiencesCore = "https://api-alpha.globalwebindex.com/v2/audiences"
    , datasets = "https://api-alpha.globalwebindex.com/v1/datasets"
    , analytics = "https://api-alpha.globalwebindex.com/v1/analytics"
    , serviceLayer = "https://api-alpha.globalwebindex.com/platform"
    }


productionUris : Uri
productionUris =
    { api = "https://api.globalwebindex.com"
    , signOut = signOutUrl "https://signin.globalwebindex.com"
    , app = "https://legacy.globalwebindex.com"
    , attributes = "https://api.globalwebindex.com/v2/attributes"
    , collections = "https://api.globalwebindex.com/v1/collections"
    , audiences = "https://api.globalwebindex.com/v1/audience-builder"
    , audiencesCore = "https://api.globalwebindex.com/v2/audiences"
    , datasets = "https://api.globalwebindex.com/v1/datasets"
    , analytics = "https://api.globalwebindex.com/v1/analytics"
    , serviceLayer = "https://api.globalwebindex.com/platform"
    }


testing : Config
testing =
    { uri = testingUris
    , authCookieName = "auth_gwi_testing"
    }


staging : Config
staging =
    { uri = stagingUris
    , authCookieName = "auth_gwi_staging"
    }


alpha : Config
alpha =
    { uri = alphaUris
    , authCookieName = "auth_gwi_alpha"
    }


development : Config
development =
    { uri = testingUris
    , authCookieName = "auth_gwi_development"
    }


production : Config
production =
    { uri = productionUris
    , authCookieName = "auth_gwi_production"
    }


testsuite : Config
testsuite =
    { uri =
        { api = ""
        , signOut = always ""
        , app = ""
        , collections = ""
        , attributes = ""
        , audiences = ""
        , audiencesCore = ""
        , datasets = ""
        , analytics = ""
        , serviceLayer = ""
        }
    , authCookieName = ""
    }


get : Stage -> Config
get stage =
    case stage of
        Development ->
            development

        TestSuite ->
            testsuite

        Testing ->
            testing

        Staging ->
            staging

        Alpha ->
            alpha

        Production ->
            production
