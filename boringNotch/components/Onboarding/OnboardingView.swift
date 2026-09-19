//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Mark Greene on 2025-06-23.
//

import SwiftUI

enum OnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case accessibilityPermission
    case bluetoothPermission
    case screenRecordingPermission
    case spectrogramSetup
    case fullDiskAccessPermission
    case musicPermission
    case displaySetup
    case extensionsHighlight
    case activityReorderHighlight
    case aiUsageHighlight
    case thermalHighlight
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: (String) -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "DynamicNotch includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await PermissionRequester.request(.camera)
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "DynamicNotch can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                                await PermissionRequester.request(.calendar)
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .remindersPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .remindersPermission
                            }
                    }
                )
                .transition(.opacity)

                case .remindersPermission:
                    PermissionRequestView(
                        icon: Image(systemName: "checklist"),
                        title: "Enable Reminders Access",
                        description: "DynamicNotch can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                        privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                        onAllow: {
                            Task {
                                await PermissionRequester.request(.reminders)
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .accessibilityPermission
                                }
                            }
                        },
                        onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    )
                    .transition(.opacity)
                
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the DynamicNotch HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await PermissionRequester.request(.accessibility)
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .bluetoothPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .bluetoothPermission
                        }
                    }
                )
                .transition(.opacity)

            case .bluetoothPermission:
                PermissionRequestView(
                    icon: Image(systemName: "airpodspro"),
                    title: "Enable Bluetooth Access",
                    description: "DynamicNotch uses Bluetooth to identify your connected audio device and show the correct icon — AirPods, AirPods Pro, AirPods Max, Beats, and more — in the volume HUD.",
                    privacyNote: "Bluetooth access is only used to read the device name and class. No audio is accessed or transmitted.",
                    onAllow: {
                        Task {
                            await PermissionRequester.request(.bluetooth)
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .screenRecordingPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .screenRecordingPermission
                        }
                    }
                )
                .transition(.opacity)

            case .screenRecordingPermission:
                PermissionRequestView(
                    icon: Image(systemName: "record.circle"),
                    title: "Enable Screen Recording",
                    description: "DynamicNotch uses screen recording to capture system audio for the responsive spectrogram visualizer. No screen content is ever captured or stored — only audio data is used.",
                    privacyNote: "Screen recording access is used solely to read audio levels. Your screen is never recorded.",
                    onAllow: {
                        Task {
                            await PermissionRequester.request(.screenRecording)
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .spectrogramSetup
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .spectrogramSetup
                        }
                    }
                )
                .transition(.opacity)

            case .spectrogramSetup:
                SpectrogramSetupView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .fullDiskAccessPermission
                        }
                    }
                )
                .transition(.opacity)

            case .fullDiskAccessPermission:
                PermissionRequestView(
                    icon: Image(systemName: "externaldrive.fill"),
                    title: "Enable Full Disk Access",
                    description: "The Claude Usage feature reads your browser's session cookie to show your token usage in the notch. macOS protects browser cookies behind Full Disk Access — without it, the app cannot read the cookie automatically.\n\nClick Allow Access to open System Settings, add DynamicNotch to the list, then return here.",
                    privacyNote: "Only the claude.ai session cookie is ever read. No other files are accessed.",
                    onAllow: {
                        Task {
                            await PermissionRequester.request(.fullDiskAccess)
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .displaySetup
                        }
                    }
                )
                .transition(.opacity)

            case .displaySetup:
                DisplaySetupView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BoringViewCoordinator.shared.firstLaunch = false
                            step = .extensionsHighlight
                        }
                    }
                )
                .transition(.opacity)

            case .extensionsHighlight:
                FeatureHighlightView(
                    highlight: WhatsNewCatalog.highlight(id: "extensions"),
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .activityReorderHighlight
                        }
                    },
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)

            case .activityReorderHighlight:
                FeatureHighlightView(
                    highlight: WhatsNewCatalog.highlight(id: "reorderableActivities"),
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .aiUsageHighlight
                        }
                    },
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)

            case .aiUsageHighlight:
                FeatureHighlightView(
                    highlight: WhatsNewCatalog.highlight(id: "aiUsagePromotion"),
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = ThermalManager.shared.detectHasFans() ? .thermalHighlight : .finished
                        }
                    },
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)

            case .thermalHighlight:
                // Fan control is meaningless on fanless Macs, so this step only exists
                // when ThermalManager.detectHasFans() found real fans via SMC.
                FeatureHighlightView(
                    highlight: WhatsNewHighlight(
                        id: "thermal",
                        icon: "thermometer.medium",
                        title: "Take Control of Your Fans",
                        body: "DynamicNotch can read your CPU and GPU temperature and apply your own fan curve — anywhere from silent to max cooling — right from the notch.",
                        action: .settings(tab: "Thermal", label: "Open Thermal")
                    ),
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .finished
                        }
                    },
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: {
                    onOpenSettings("General")
                    onFinish()
                })
            }
        }
        .frame(width: 400, height: 600)
    }

}
