import SwiftUI

struct LoginWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var lastFM = LastFmService.shared
    @State private var isFinishingLogin = false

    private let accent = Color(red: 0.82, green: 0.13, blue: 0.20)

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(accent).frame(width: 68, height: 68)
                Text("L.f").font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
            .padding(.top, 12)

            VStack(spacing: 7) {
                Text("Войти в Last.fm").font(.system(size: 24, weight: .bold))
                Text("Подключите аккаунт, чтобы отправлять историю прослушивания из Яндекс Музыки.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                instruction(number: "1", text: "Откройте Last.fm и разрешите доступ приложению.")
                instruction(number: "2", text: "Вернитесь сюда и подтвердите подключение.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))

            if lastFM.isLoggedIn {
                Label("Подключено: \(lastFM.sessionUsername ?? "Last.fm")", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                Button("Готово") { dismissWindow(id: "lastfm-login") }
                    .buttonStyle(.borderedProminent).tint(accent).controlSize(.large).frame(maxWidth: .infinity)
            } else if lastFM.hasPendingToken {
                Button {
                    Task {
                        isFinishingLogin = true
                        await lastFM.finishLogin()
                        isFinishingLogin = false
                        if lastFM.isLoggedIn {
                            appState.lastFMConnectionChanged()
                            dismissWindow(id: "lastfm-login")
                        }
                    }
                } label: {
                    if isFinishingLogin {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Я разрешил доступ — продолжить")
                    }
                }
                .buttonStyle(.borderedProminent).tint(accent).controlSize(.large).frame(maxWidth: .infinity)
                .disabled(isFinishingLogin)
                Button("Открыть Last.fm ещё раз") { openAuthorizationPage() }
                    .buttonStyle(.link).frame(maxWidth: .infinity)
            } else {
                Button {
                    Task { await lastFM.startAuth() }
                } label: {
                    Label("Продолжить через Last.fm", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            }

            if let error = lastFM.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            Text("Сессия хранится в связке ключей macOS.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 5)
        }
        .padding(26)
        .frame(width: 420, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func instruction(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(accent, in: Circle())
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openAuthorizationPage() {
        lastFM.reopenAuthorizationPage()
    }
}
