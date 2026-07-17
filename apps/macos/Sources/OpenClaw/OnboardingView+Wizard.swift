import Observation
import OpenClawProtocol
import SwiftUI

extension OnboardingView {
    func wizardPage() -> some View {
        self.onboardingPage {
            VStack(spacing: 16) {
                Text(MinimalGatewayConfig.shouldRunInteractiveWizard()
                    ? "Setup Wizard"
                    : "Start local gateway")
                    .font(.largeTitle.weight(.semibold))
                Text(MinimalGatewayConfig.shouldRunInteractiveWizard()
                    ? "Follow the guided setup from the Gateway. This keeps onboarding in sync with the CLI."
                    : "Writing minimal gateway config, registering launchd, and waiting until the local gateway is healthy. Models, channels, and skills are configured later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                self.onboardingCard(spacing: 14, padding: 16) {
                    OnboardingWizardCardContent(
                        wizard: self.onboardingWizard,
                        mode: self.state.connectionMode,
                        workspacePath: self.workspacePath)
                }
            }
            .task {
                await self.onboardingWizard.startIfNeeded(
                    mode: self.state.connectionMode,
                    workspace: self.workspacePath.isEmpty ? nil : self.workspacePath)
            }
        }
    }
}

private struct OnboardingWizardCardContent: View {
    @Bindable var wizard: OnboardingWizardModel
    let mode: AppState.ConnectionMode
    let workspacePath: String

    private enum CardState {
        case error(String)
        case starting
        case step(WizardStep)
        case complete
        case waiting
    }

    private var state: CardState {
        if let error = wizard.errorMessage { return .error(error) }
        if self.wizard.isStarting { return .starting }
        if let step = wizard.currentStep { return .step(step) }
        if self.wizard.isComplete { return .complete }
        return .waiting
    }

    var body: some View {
        switch self.state {
        case let .error(error):
            Text("Wizard error")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") {
                self.wizard.reset()
                Task {
                    await self.wizard.startIfNeeded(
                        mode: self.mode,
                        workspace: self.workspacePath.isEmpty ? nil : self.workspacePath)
                }
            }
            .buttonStyle(.borderedProminent)
        case .starting:
            HStack(spacing: 8) {
                ProgressView()
                Text(MinimalGatewayConfig.shouldRunInteractiveWizard()
                    ? "Starting wizard…"
                    : "Starting local gateway…")
                    .foregroundStyle(.secondary)
            }
        case let .step(step):
            OnboardingWizardStepView(
                step: step,
                isSubmitting: self.wizard.isSubmitting)
            { value in
                Task { await self.wizard.submit(step: step, value: value) }
            }
            .id(step.id)
        case .complete:
            Text(MinimalGatewayConfig.shouldRunInteractiveWizard()
                ? "Wizard complete. Continue to the next step."
                : "Local gateway is ready. Continue to the next step.")
                .font(.headline)
        case .waiting:
            HStack(spacing: 8) {
                ProgressView()
                Text(MinimalGatewayConfig.shouldRunInteractiveWizard()
                    ? "Waiting for wizard…"
                    : "Preparing gateway…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
