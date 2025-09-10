port module XB2.Ports exposing
    ( mountXB2, mountedXB2, unmountXB2, unmountedXB2
    , checkRouteInterruptionXB2, interruptRoutingStatusXB2, navigateToXB2, openNewWindowXB2, routeChangedXB2, setXBProjectCheckBeforeLeave
    , bookADemoButtonClicked, talkToAnExpertSplashEvent, upgradeSplashEvent
    )

{-| The module where the Crosstabs' ports dwell.


# single-spa

@docs mountXB2, mountedXB2, unmountXB2, unmountedXB2


# Routing

@docs checkRouteInterruptionXB2, interruptRoutingStatusXB2, navigateToXB2, openNewWindowXB2, routeChangedXB2, setXBProjectCheckBeforeLeave


# Subscriptions from web components

@docs bookADemoButtonClicked, talkToAnExpertSplashEvent, upgradeSplashEvent

-}


port unmountXB2 : (() -> msg) -> Sub msg


port mountXB2 : (() -> msg) -> Sub msg


port mountedXB2 : () -> Cmd msg


port unmountedXB2 : () -> Cmd msg


port routeChangedXB2 : (String -> msg) -> Sub msg


port navigateToXB2 : String -> Cmd msg


port openNewWindowXB2 : String -> Cmd msg


port checkRouteInterruptionXB2 : (String -> msg) -> Sub msg


port interruptRoutingStatusXB2 : Bool -> Cmd msg


port setXBProjectCheckBeforeLeave : Bool -> Cmd nsg


port bookADemoButtonClicked : (() -> msg) -> Sub msg


port talkToAnExpertSplashEvent : (() -> msg) -> Sub msg


port upgradeSplashEvent : (() -> msg) -> Sub msg
