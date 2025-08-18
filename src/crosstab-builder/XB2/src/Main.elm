module Main exposing
    ( Model
    , Msg
    , State
    , main
    )

{-| Pluggable Crosstabs application.
-}

import Browser
import Browser.Navigation
import Cmd.Extra as Cmd
import Crosstabs
import Glue
import Glue.Lazy as LazyGlue
import Html
import Html.Extra as Html
import Json.Decode as Decode
import Json.Encode as Encode
import Maybe.Extra as Maybe
import Process
import Result
import Result.Extra as Result
import Task
import Time
import Url
import Url.Builder as UrlBuilder
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression as Expression
import XB2.Ports as Ports
import XB2.Router as Router
import XB2.Share.Analytics as Analytics
import XB2.Share.Config
import XB2.Share.Data.User as User
import XB2.Share.DefaultQueryParams
import XB2.Share.ErrorHandling
import XB2.Share.Gwi.Http as GwiHttp
import XB2.Share.Permissions as Permissions
import XB2.Share.Platform2.Router as P2Router
import XB2.Share.Ports
import XB2.Share.Store.Platform2 as P2Store
import XB2.Views.SplashScreen as SplashScreen


{-| Error types that can happen during app initialization (i.e. plugging it into the
kernel).
-}
type AppError
    = NotMounted
    | InitializationError Decode.Error
      -- TODO: `AppLocked` should maybe be considered as regular `Model`
    | AppLocked { isAppMounted : Bool, userEmail : String, userPlan : User.Plan }


{-| A wrapper around the application state to keep it alive when leaving Crosstabs, we
need it to restore routes and allow platform-app intercommunication.
-}
type alias ElmApp model =
    Result AppError model


{-| Runtime config.
-}
main : Program Encode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| TODO: Prefer module scoped `Msg`s and `Cmd.map`s/`Html.map`s over tagger params.

TODO: Merge XB2 module with this one.

-}
xbConfig : Crosstabs.Config Msg
xbConfig =
    Crosstabs.configure
        { msg = XB2Msg
        , navigateTo = NavigateToRoute
        , forceNavigateTo = ForceNavigateTo
        , runStoreActions = ProcessStoreActions
        , openNewWindow = OpenUrlInNewWindow
        , createAudienceWithExpression = CreateAudienceWithExpression
        , createNewAudienceInP2 = CreateNewAudienceInP2
        , editAudienceInP2 = EditAudienceInP2
        , openSupportChat = OpenSupportChat
        }


{-| TODO: Remove usage of Glue in favour of usual `Cmd.map`, `Sub.map` & `Html.map`.
-}
xbGlue : LazyGlue.LazyGlue Model Crosstabs.Model Msg Msg
xbGlue =
    Glue.poly
        { get = Result.toMaybe << Result.map .xb2Model
        , set =
            \maybeXb2Model ->
                case maybeXb2Model of
                    Just xb2Model ->
                        Result.map (\state -> { state | xb2Model = xb2Model })

                    Nothing ->
                        identity
        }


{-| TODO: Prefer module scoped `Msg`s and `Cmd.map`s/`Html.map`s over tagger params.

TODO: Store shouldn't be a shared module with its own messages. It should be part of the
app.

-}
p2StoreConfig : P2Store.Config Msg
p2StoreConfig =
    P2Store.configure
        { msg = Platform2StoreMsg
        , err = Platform2StoreError { showModal = True }
        , errWithoutModal = Platform2StoreError { showModal = False }
        , notFoundError = always (NavigateToRoute Router.ProjectList)
        }


{-| TODO: Remove usage of Glue in favour of usual `Cmd.map`, `Sub.map` & `Html.map`.
-}
p2StoreGlue : LazyGlue.LazyGlue Model P2Store.Store Msg Msg
p2StoreGlue =
    Glue.poly
        { get = Result.toMaybe << Result.map .platform2Store
        , set =
            \store model ->
                case store of
                    Just s ->
                        Result.map (\state -> { state | platform2Store = s }) model

                    Nothing ->
                        model
        }


{-| The actual model of the application.
-}
type alias State =
    { flags : XB2.Share.Config.Flags -- Config coming from the kernel
    , isAppMounted : Bool -- `True` when on app routes, `False` otherwise
    , route : Router.Route

    -- Used in platform-app intercommunication
    , routeToRestoreWhenComingToList : Maybe Router.Route

    -- TODO: Remove `Maybe` and use `Router.Route` directly
    , url : Maybe Url.Url

    -- A 'cache'; data fetched from the API
    -- TODO: Move this from here to a local module
    , platform2Store : P2Store.Store

    -- Used to generate dates for crosstab titles (e.g. "New Crosstab 21 Aug 24 23:22")
    , zone : Time.Zone

    -- XB2 app state
    -- TODO: Make it work with routes to avoid having unnecessary memory occupied
    , xb2Model : Crosstabs.Model

    -- TODO: Investigate how this works
    , internalRouteChange : Bool
    }


{-| Model of the app. State is wrapped inside a Result type because of mounting
side-effect-y-ness.
-}
type alias Model =
    ElmApp State


{-| `init` function helper.

TODO: Merge XB2 module with this one.

-}
initHelp : XB2.Share.Config.Flags -> ( Model, Cmd Msg )
initHelp flags =
    let
        route : Router.Route
        route =
            Router.ProjectList

        p2Store : P2Store.Store
        p2Store =
            P2Store.init
    in
    Crosstabs.init xbConfig
        |> Tuple.mapFirst
            (\m ->
                Ok
                    { flags = flags

                    -- We leave `isAppMounted` field to be updated by the kernel ports
                    , isAppMounted = False
                    , route = route
                    , routeToRestoreWhenComingToList = Nothing
                    , url = Nothing
                    , platform2Store = p2Store
                    , zone = Time.utc
                    , xb2Model = m
                    , internalRouteChange = False
                    }
            )
        |> LazyGlue.updateWith xbGlue
            (Crosstabs.updateForRoute
                xbConfig
                flags
                route
                p2Store
            )
        |> Cmd.add (Task.perform UpdateTimeZone Time.here)


{-| Decodes configuration flags received from the kernel and initializes the application.

We have an special case of app being locked by the _crosstabs\_locked_ flag. A
webcomponent renders an splash screen, so we have to wait for the crosstabs' index.ts
`mount` function to resolve before loading it into the view. We check mounting state
through the `isAppMounted` field in the model.

```plaintext
                                ┌───────────────bootstrap────────────┐
                                │                                    │
                              ┌─▼──┐                                 │
                              │init│                                 │
                              └─┬──┘                                 │
                                │                                    │
                                │                                    │
                         ┌──────▼─────────┐                          │
         ┌───────────────┼doWeHaveAnError?┼────────┐                 │
        no               └────────────────┘        │                 │
         │                                        yes                │
┌────────▼──────────┐                              │                 │
│isAppLockedByFlags?│                         ┌────▼────┐            │
└────────┬─────────┬┘                         │errorView│            │
         │         │                          └─────────┘            │
         │         └──────────────────yes/ask for mount────────────┐ │
         │                                                        ┌▼─┴───┐
         └──────────────────────────no/ask for mount──────────────►kernel│
                                                                  └──┬───┘
                                                     mount completed, render the app
                                                                     │
                                         ┌───────────────────────────┤
                                    ┌────▼──────┐               ┌────▼─────┐
                                    │regularView│               │splashView│
                                    └───────────┘               └──────────┘
```

-}
init : Encode.Value -> ( Model, Cmd Msg )
init flags_ =
    case XB2.Share.Config.decode flags_ of
        Ok flags ->
            if flags.can Permissions.UseCrosstabs then
                initHelp flags

            else
                ( Err
                    (AppLocked
                        { isAppMounted = False
                        , userEmail = flags.user.email
                        , userPlan = flags.user.planHandle
                        }
                    )
                , Analytics.track
                    ( "P2 - Crosstabs Management - Opened"
                    , Encode.object
                        [ ( "splash_screen", Encode.bool True ) ]
                    )
                )

        Err err ->
            ( Err <| InitializationError err, Cmd.none )


{-| Subscriptions of the app. Some of them handle routing, mounting & cookie/localstorage
changes
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.unmountXB2 (\() -> SetMountedState False)
        , Ports.mountXB2 (\() -> SetMountedState True)
        , Ports.bookADemoButtonClicked (\() -> BookADemoButtonClicked)
        , Ports.routeChangedXB2 UrlChanged
        , XB2.Share.Ports.setNewAccessToken SetNewAccessToken
        , model
            |> Result.map
                (\state ->
                    Crosstabs.subscriptions
                        xbConfig
                        state.route
                        state.xb2Model
                )
            |> Result.withDefault Sub.none
        , Ports.checkRouteInterruptionXB2 CheckInterruptRouting
        ]


type Msg
    = LoadExternalUrl String
    | SetMountedState Bool
      {- TODO: Store shouldn't be a shared module with its own messages. It should be
         part of the app.
      -}
    | ProcessStoreActions (List P2Store.StoreAction)
      {- TODO: Store shouldn't be a shared module with its own messages. It should be
         part of the app.
      -}
    | Platform2StoreMsg P2Store.Msg
    | XB2Msg Crosstabs.Msg -- TODO: Merge XB2 module with this one.
    | UrlChanged String
    | NavigateToRoute Router.Route
    | ForceNavigateTo Router.Route
    | CreateNewAudienceInP2
    | EditAudienceInP2 Audience.Id
    | UpdateTimeZone Time.Zone
    | CreateAudienceWithExpression
        { name : String
        , expression : Expression.Expression
        }
      {- TODO: Store shouldn't be a shared module with its own messages. It should be
         part of the app.
      -}
    | Platform2StoreError
        { showModal : Bool }
        (P2Store.Store
         -> P2Store.Store
        )
        (GwiHttp.Error Never)
    | OpenUrlInNewWindow String
    | CheckInterruptRouting String -- TODO: Investigate how this works.
      {- TODO: Change this `Maybe String` into a custom type for error ids that may not
         be present.
      -}
    | OpenSupportChat (Maybe String)
      {- TODO: Wrap access token into an opaque type.
         TODO: Isn't this a duplicate of `SetToken`?
      -}
    | SetNewAccessToken String
    | BookADemoButtonClicked
    | UpgradeButtonClicked
    | TalkToAnExpertButtonClicked


{-| A function that handles the signout whenever an API response gives Forbidden 401.
-}
handleAjaxError :
    (Model -> ( Model, Cmd Msg ))
    -> GwiHttp.Error err
    -> Model
    -> ( Model, Cmd Msg )
handleAjaxError showErrorDialog err model =
    case model of
        Ok state ->
            XB2.Share.ErrorHandling.signOutOn401
                state.flags
                err
                -- TODO: Unwrapping this maybe here looks fishy
                (Maybe.unwrap "" Url.toString state.url)
                LoadExternalUrl
                showErrorDialog
                (Ok state)

        Err appErr ->
            Cmd.pure (Err appErr)


{-| TODO: Investigate how this works.
-}
interruptRoutingCmd : Router.Route -> State -> Maybe (Cmd Msg)
interruptRoutingCmd route state =
    case route of
        Router.Project _ ->
            Nothing

        Router.ProjectList ->
            Crosstabs.saveProjectAndNavigateToListIfProjectIsUnsaved xbConfig state.xb2Model

        Router.ExternalUrl urlString ->
            Crosstabs.showUnsavedChangesDialog xbConfig
                (Router.ExternalUrl urlString)
                state.xb2Model


{-| TODO: Investigate how this works.
-}
navigateToWithCheck : Router.Route -> Model -> ( Model, Cmd Msg )
navigateToWithCheck route model =
    let
        prefix : Maybe String
        prefix =
            Result.map .flags model
                |> Result.toMaybe
                |> Maybe.andThen XB2.Share.Config.combinePrefixAndFeature

        queryParams : List UrlBuilder.QueryParameter
        queryParams =
            XB2.Share.DefaultQueryParams.fromResult model

        maybeInterruptCmd : Maybe (Cmd Msg)
        maybeInterruptCmd =
            Result.toMaybe model
                |> Maybe.andThen (interruptRoutingCmd route)
    in
    ( if Maybe.isJust maybeInterruptCmd then
        model

      else
        Result.map (\s -> { s | internalRouteChange = True }) model
    , Maybe.withDefault
        (Ports.navigateToXB2 (Router.toUrlString prefix route queryParams))
        maybeInterruptCmd
    )


{-| Helper function for `update`. Since `State` is wrapped inside a `Result` type, we
extract a helper function to reduce cognitive complexity.
-}
updateHelp : Msg -> Model -> State -> ( Model, Cmd Msg )
updateHelp msg model state =
    case msg of
        LoadExternalUrl urlString ->
            ( model, Browser.Navigation.load urlString )

        UpdateTimeZone zone ->
            Cmd.pure (Ok { state | zone = zone })

        SetMountedState bool ->
            ( Ok { state | isAppMounted = bool }
            , if bool then
                Ports.mountedXB2 ()

              else
                Ports.unmountedXB2 ()
            )

        ProcessStoreActions list ->
            Cmd.pure model
                |> LazyGlue.updateWith
                    p2StoreGlue
                    (P2Store.storeActionMany list
                        p2StoreConfig
                        state.flags
                    )

        Platform2StoreMsg platform2Msg ->
            LazyGlue.update
                p2StoreGlue
                (P2Store.update p2StoreConfig)
                platform2Msg
                (Cmd.pure model)
                -- TODO: This is hard to read, reduce cognitive complexity
                |> (\( model_, cmds ) ->
                        model_
                            |> Result.map
                                (\state_ ->
                                    ( model_, cmds )
                                        |> LazyGlue.updateWith xbGlue
                                            (Crosstabs.onP2StoreChange
                                                xbConfig
                                                state_.flags
                                                state_.route
                                                state_.platform2Store
                                                platform2Msg
                                            )
                                )
                            |> Result.withDefault ( model_, cmds )
                   )

        Platform2StoreError showModal storeUpdateFn err ->
            model
                |> LazyGlue.updateModelWith p2StoreGlue storeUpdateFn
                -- TODO: This is hard to read, reduce cognitive complexity
                |> handleAjaxError
                    (\model_ ->
                        model_
                            |> Result.map
                                (\state_ ->
                                    Cmd.pure model_
                                        |> LazyGlue.updateWith xbGlue
                                            (Crosstabs.onP2StoreError
                                                xbConfig
                                                showModal
                                                state_.flags
                                                state_.route
                                                state_.platform2Store
                                                err
                                                state.url
                                            )
                                )
                            |> Result.withDefault (Cmd.pure model_)
                    )
                    err

        UrlChanged string ->
            let
                maybeUrl : Maybe Url.Url
                maybeUrl =
                    Url.fromString string

                newRoute : Router.Route
                newRoute =
                    maybeUrl
                        |> Maybe.andThen (Router.parseUrl state.flags)
                        |> Maybe.withDefault state.route

                prefix : Maybe String
                prefix =
                    XB2.Share.Config.combinePrefixAndFeature state.flags

                queryParams : List UrlBuilder.QueryParameter
                queryParams =
                    XB2.Share.DefaultQueryParams.fromResult model

                setNewRoute : State -> ( Model, Cmd Msg )
                setNewRoute state_ =
                    -- TODO: This is hard to read, reduce cognitive complexity
                    case state_.routeToRestoreWhenComingToList of
                        Just routeToRestoreWhenComingToList ->
                            case newRoute of
                                Router.ProjectList ->
                                    let
                                        newState : State
                                        newState =
                                            { state_
                                                | route = routeToRestoreWhenComingToList
                                                , url =
                                                    Url.fromString <|
                                                        Router.toUrlString prefix
                                                            routeToRestoreWhenComingToList
                                                            queryParams
                                                , routeToRestoreWhenComingToList = Nothing
                                            }
                                    in
                                    Ok newState
                                        |> navigateToWithCheck
                                            routeToRestoreWhenComingToList

                                Router.Project maybeProjectId ->
                                    Ok
                                        { state_
                                            | route = Router.Project maybeProjectId
                                            , url = maybeUrl
                                        }
                                        |> Cmd.pure

                                Router.ExternalUrl urlString ->
                                    Ok
                                        { state_
                                            | route =
                                                Router.ExternalUrl
                                                    urlString
                                            , url = maybeUrl
                                        }
                                        |> Cmd.pure

                        Nothing ->
                            Ok { state_ | route = newRoute, url = maybeUrl }
                                |> Cmd.pure
            in
            if state.internalRouteChange then
                setNewRoute { state | internalRouteChange = False }
                    |> LazyGlue.updateWith xbGlue
                        (Crosstabs.updateForRoute
                            xbConfig
                            state.flags
                            newRoute
                            state.platform2Store
                        )

            else
                ( Ok { state | internalRouteChange = True }
                , Ports.navigateToXB2 <|
                    Router.toUrlString prefix
                        state.route
                        queryParams
                )
                    |> Cmd.add
                        (Process.sleep 100
                            |> Task.map
                                (\_ ->
                                    NavigateToRoute newRoute
                                )
                            |> Task.perform identity
                        )

        OpenUrlInNewWindow urlString ->
            ( model, Ports.openNewWindowXB2 urlString )

        NavigateToRoute route ->
            navigateToWithCheck route model

        ForceNavigateTo route ->
            let
                prefix : Maybe String
                prefix =
                    Result.map .flags model
                        |> Result.toMaybe
                        |> Maybe.andThen XB2.Share.Config.combinePrefixAndFeature

                queryParams : List UrlBuilder.QueryParameter
                queryParams =
                    XB2.Share.DefaultQueryParams.fromResult model
            in
            ( Ok { state | internalRouteChange = True }
            , Ports.navigateToXB2 <|
                Router.toUrlString prefix route queryParams
            )

        CreateNewAudienceInP2 ->
            Ok
                { state
                    | routeToRestoreWhenComingToList = Just state.route
                    , internalRouteChange = True
                }
                |> navigateToWithCheck
                    (Router.ExternalUrl <|
                        P2Router.toUrlString state.flags
                            P2Router.AudienceBuilderNew
                    )

        EditAudienceInP2 audienceId ->
            ( Ok { state | internalRouteChange = True }
            , Ports.navigateToXB2 <|
                P2Router.toUrlString state.flags <|
                    P2Router.AudienceBuilderDetail audienceId
            )

        XB2Msg xbMsg ->
            Cmd.pure model
                |> LazyGlue.update xbGlue
                    (Crosstabs.update
                        xbConfig
                        state.zone
                        state.flags
                        state.url
                        state.route
                        state.platform2Store
                    )
                    xbMsg

        CreateAudienceWithExpression params ->
            Cmd.pure model
                |> LazyGlue.updateWith p2StoreGlue
                    (P2Store.createAudienceWithExpression
                        p2StoreConfig
                        params.name
                        params.expression
                        state.flags
                    )

        CheckInterruptRouting urlString ->
            let
                maybeUrl : Maybe Url.Url
                maybeUrl =
                    Url.fromString urlString

                newRoute : Router.Route
                newRoute =
                    maybeUrl
                        |> Maybe.andThen (Router.parseUrl state.flags)
                        |> Maybe.withDefault (Router.ExternalUrl urlString)
            in
            case interruptRoutingCmd newRoute state of
                Just interruptCmd ->
                    ( model, interruptCmd )
                        |> Cmd.add (Ports.interruptRoutingStatusXB2 True)

                Nothing ->
                    ( model
                    , Ports.interruptRoutingStatusXB2 False
                    )

        OpenSupportChat errorId ->
            ( model
            , XB2.Share.Ports.openChatWithErrorId
                (Maybe.unwrap Encode.null Encode.string errorId)
            )

        SetNewAccessToken token ->
            let
                flags : XB2.Share.Config.Flags
                flags =
                    state.flags
            in
            Cmd.pure (Ok { state | flags = { flags | token = token } })

        BookADemoButtonClicked ->
            ( model
            , Cmd.none
            )

        UpgradeButtonClicked ->
            ( model
            , Cmd.none
            )

        TalkToAnExpertButtonClicked ->
            ( model
            , Cmd.none
            )


{-| Main function to handle all the possible `Msg`s.

The special case for the AppLocked state needs to wait for the kernel to resolve the
`mount` function before rendering or we will have a React lifecycle error.

-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model of
        Err (AppLocked s) ->
            case msg of
                SetMountedState bool ->
                    ( Err (AppLocked { s | isAppMounted = bool })
                    , if bool then
                        Ports.mountedXB2 ()

                      else
                        Ports.unmountedXB2 ()
                    )

                BookADemoButtonClicked ->
                    ( model
                    , Analytics.track
                        ( "P2 - Platform - Book a demo"
                        , Encode.object [ ( "app_name", Encode.string "crosstabs" ) ]
                        )
                    )

                UpgradeButtonClicked ->
                    ( model
                    , Analytics.track
                        ( "P2 - Platform - Upgrade clicked"
                        , Encode.object [ ( "app_name", Encode.string "crosstabs" ) ]
                        )
                    )

                TalkToAnExpertButtonClicked ->
                    ( model
                    , Analytics.track
                        ( "P2 - Platform - Splash screen CTA"
                        , Encode.object [ ( "app_name", Encode.string "crosstabs" ) ]
                        )
                    )

                _ ->
                    ( Err (AppLocked s), Cmd.none )

        _ ->
            Result.map
                (updateHelp msg model)
                model
                |> Result.map
                    (LazyGlue.updateWith xbGlue
                        (\xb2Model ->
                            xb2Model
                                |> Cmd.with
                                    (Ports.setXBProjectCheckBeforeLeave <|
                                        Crosstabs.checkConfirmBeforeLeave xb2Model
                                    )
                        )
                    )
                |> Result.withDefault ( model, Cmd.none )


{-| When app gets unmounted we want to clear all the dom nodes
but we want to preserve the state. We can do so by using this function
within the view.
-}
handleMounting : Model -> Model
handleMounting model =
    case model of
        Ok s ->
            if s.isAppMounted then
                Ok s

            else
                Err NotMounted

        Err err ->
            Err err


{-| View when the app errs at mounting.

TODO: This is too poor, improve it a little bit.

-}
errorView : AppError -> Html.Html Msg
errorView error =
    case error of
        NotMounted ->
            Html.text "App is not mounted!"

        InitializationError err ->
            Html.text <| "Initialization error " ++ Decode.errorToString err

        AppLocked { isAppMounted, userEmail, userPlan } ->
            -- `isAppMounted` gets setted by kernel's ports.
            if isAppMounted then
                SplashScreen.view
                    { talkToAnExpert = TalkToAnExpertButtonClicked
                    , upgrade = UpgradeButtonClicked
                    }
                    { appName = "crosstabs"
                    , email = userEmail
                    , upgradePlanUrl = SplashScreen.getUpgradePlanUrlBasedOnUserPlan userPlan
                    }

            else
                Html.nothing


view : Model -> Html.Html Msg
view model =
    let
        xbView :
            XB2.Share.Config.Flags
            -> Router.Route
            -> Time.Zone
            -> P2Store.Store
            -> Maybe (Html.Html Msg)
        xbView flags route zone p2Store =
            LazyGlue.view xbGlue
                (Crosstabs.view
                    xbConfig
                    flags
                    zone
                    route
                    p2Store
                )
                model
    in
    handleMounting model
        |> Result.andThen
            (\state ->
                xbView
                    state.flags
                    state.route
                    state.zone
                    state.platform2Store
                    |> Result.fromMaybe NotMounted
            )
        |> Result.mapError errorView
        |> Result.merge
