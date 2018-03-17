module SetupWizard exposing (settings, viewSettings)

import Dialog exposing (labeledItem)
import Html exposing (Html, div, input, p, span, text)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick, onInput)
import Language exposing (Language(..))
import Model
import Util exposing (ButtonSettings, Position(..), button)
import WizardDialog.Model exposing (..)
import WizardDialog.View
    exposing
        ( infoText
        , infoTextWithHeader
        , infoTextWithHeaders
        )


steps : List (StepConfig Model.Model Model.Msg)
steps =
    [ ( "Welcome", step1 )
    , ( "Account Setup", step2 )
    , ( "Account Login", step3 )
    , ( "Account Signup", step4 )
    , ( "Key Creation", step5 )
    ]


settings : Model.Model -> WizardSettings Model.Msg
settings model =
    { address = Model.WizardDialogMsg
    , onFinishMsg = Just Model.SetupWizardFinished
    , steps = steps |> List.map Tuple.first
    , wizardType = SetupWizard
    , closable = False
    }


wizardContent : List (Html msg) -> Html msg
wizardContent body =
    div [ class "MainScreen-SetupWizard" ]
        body


viewSettings : State Model.Msg -> Model.Model -> Maybe (ViewSettings Model.Msg)
viewSettings state model =
    WizardDialog.Model.viewSettings steps state model



-- STEPS


step1 model state =
    Just
        { title = "Welcome to Syncrypt"
        , contents =
            wizardContent
                [ infoText []
                    [ "We'll guide you through a step-by-step setup process to initiate your Syncrypt account."
                    , "Please pick a language:"
                    ]
                , div [ class "Options" ]
                    [ button []
                        { label = "GERMAN"
                        , onClick = Model.SetLanguage German
                        }
                    , button []
                        { label = "ENGLISH"
                        , onClick = Model.SetLanguage English
                        }
                    ]
                ]
        , buttons = DefaultNoCancel
        }


step2 model state =
    Just
        { title = "Account setup"
        , contents =
            wizardContent
                [ infoTextWithHeader []
                    "Do you already have a Syncrypt Account?"
                    [ "You can login with an existing account or create a new one and get started right away." ]
                , div [ class "Options" ]
                    [ button []
                        { label = "Yes, login with account"
                        , onClick = state.address (ToStepWithName "Account Login")
                        }
                    , button []
                        { label = "No, sign up with new account"
                        , onClick = state.address (ToStepWithName "Account Signup")
                        }
                    ]
                ]
        , buttons = DefaultNoCancel
        }


step3 : Model.Model -> State Model.Msg -> Maybe (ViewSettings Model.Msg)
step3 model state =
    Just
        { title = "Account Login"
        , contents =
            wizardContent
                [ infoTextWithHeader []
                    "Login with your existing Syncrypt Account"
                    [ "If you forgot your password, enter your email and press the button below."
                    , "We will send you a password reset link to the email you entered."
                    ]
                , div [ class "Options" ]
                    [ labeledItem [ class "InputLabel" ]
                        { side = Left
                        , onClick = Nothing
                        , label = text "Email"
                        , item =
                            div []
                                [ input [ type_ "email", onInput Model.SetupWizardEmail ]
                                    [ text "Your Email" ]
                                ]
                        }
                    , labeledItem [ class "InputLabel" ]
                        { side = Left
                        , onClick = Nothing
                        , label = text "Password"
                        , item =
                            div []
                                [ input [ type_ "password", onInput Model.SetupWizardPassword ]
                                    [ text "" ]
                                ]
                        }
                    , button [ class "ForgotPasswordButton" ]
                        { label = "Forgot Password"
                        , onClick = Model.SendPasswordResetLink
                        }
                    , if model.setupWizard.passwordResetSent then
                        div []
                            [ text "Password reset link has been sent." ]
                      else
                        text ""
                    ]
                ]
        , buttons =
            CustomNavNoCancel
                { prev = Auto
                , next = NavWithLabel (state.address (ToStepWithName "Key Creation")) "Login"
                }
        }


step4 model state =
    Just
        { title = "Account Signup"
        , contents =
            wizardContent
                [ infoTextWithHeaders [ class "TermsOfService" ]
                    "Legal Notice"
                    "Please read and confirm the following agreement and terms of service:"
                    [ "I hereby permit SYNCRYPT UG (haftungsbeschränkt), henceforth: Syncrypt, to collect, save, process and use my personal data."
                    , "The collected data in particular is: Last name, first name & email adress to create and sustain a customer account. It is collected with the registration and saved for the entire period of service."
                    , "The IP-adress is stored for a period of maximum two weeks to be able to identify and prevent attacks on our servers."
                    , "Syncrypt stores and uses the personal data only to provide the service."
                    , "Under no circumstance will Syncrypt sell personal Data to advertisers or other third parties."
                    , "It is possible that the government and/or justice system will contact Syncrypt and ask to provide personal data. Every request will be examined by Syncrypt to full extent before releasing any data. If the legal requirements are granted, Syncrypt can be forced to give away this data and any stored encrypted files. All stored files are still encrypted with your private key. Syncrypt has no way to circumvent or lift this encryption."
                    , "I give my permission voluntarily. I can withdraw it anytime without having to state a reason. To do so, I can simply write an email to alpha@syncrypt.space."
                    , "I understand that this service can not be provided without this permission. If I disagree with this document, I can not use the service."
                    , "Syncrypt can change parts of this permission in the future. In that case I will be informed and have to give a new permission."
                    , "The current Privacy Policy and this document can be found at syncrypt.space/legal."
                    , "This permission is in accordance with §§ 4a I, 28 BDSG."
                    ]
                ]
        , buttons =
            CustomNavNoCancel
                { prev = Nav <| state.address (ToStepWithName "Account Setup")
                , next = AutoWithLabel "I agree"
                }
        }


step5 model state =
    Just
        { title = "Key Creation"
        , contents =
            wizardContent
                [ text "Coming soon with a nice animation next to this text." ]
        , buttons =
            CustomNavNoCancel
                { prev = Hidden
                , next = Hidden
                }
        }
