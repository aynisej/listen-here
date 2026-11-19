import SwiftUI

private enum ListenHerePage: String, CaseIterable, Identifiable {
    case scrobbler = "Скробблер"
    case settings = "Настройки"
    var id: String { rawValue }
    var symbol: String { self == .scrobbler ? "waveform.path" : "slider.horizontal.3" }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var lastFM = LastFmService.shared
    @State private var selection: ListenHerePage? = .scrobbler
    @State private var didAutoOpenLogin = false

    private let accent = Color(red: 0.82, green: 0.13, blue: 0.20)

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 235)
        } detail: {
            Group {
                if selection == .settings { settingsPage } else { dashboardPage }
            }
            .frame(minWidth: 560, minHeight: 500)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .frame(minWidth: 820, minHeight: 600)
        .onAppear {
            guard !lastFM.isLoggedIn, !didAutoOpenLogin else { return }
            didAutoOpenLogin = true
            openWindow(id: "lastfm-login")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(accent).frame(width: 38, height: 38)
                    Text("L.f").font(.system(size: 17, weight: .black, design: .rounded)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listen Here").font(.headline)
                    Text("Last.fm scrobbler").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)

            List(selection: $selection) {
                ForEach(ListenHerePage.allCases) { page in
                    Label(page.rawValue, systemImage: page.symbol).tag(page as ListenHerePage?)
                }
            }
            .listStyle(.sidebar)

            Divider().padding(.horizontal, 14)
            HStack(spacing: 10) {
                Circle().fill(lastFM.isLoggedIn ? Color.green : Color.orange).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastFM.sessionUsername ?? "Last.fm не подключён").font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(lastFM.isLoggedIn ? "Аккаунт подключён" : "Нужно войти").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var dashboardPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Скробблер").font(.system(size: 28, weight: .bold))
                        Text("Слушайте музыку — история появится в Last.fm автоматически.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Скробблинг", isOn: $appState.isScrobblingEnabled)
                        .toggleStyle(.switch)
                        .fixedSize()
                }

                nowPlayingCard

                HStack(spacing: 14) {
                    statisticCard(title: "Скробблов отправлено", value: "\(appState.submittedCount)", symbol: "checkmark.circle.fill")
                    statisticCard(title: "В очереди", value: "\(appState.pendingCount)", symbol: "clock.arrow.circlepath")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Недавно отправлено").font(.title3.weight(.semibold))
                        Spacer()
                        if !appState.recentScrobbles.isEmpty {
                            Text("\(appState.recentScrobbles.count) последних").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if appState.recentScrobbles.isEmpty {
                        emptyRecent
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(appState.recentScrobbles.enumerated()), id: \.offset) { index, item in
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note").foregroundStyle(accent).frame(width: 24)
                                    Text(item).font(.subheadline).lineLimit(1)
                                    Spacer()
                                    Text("Отправлено").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                if index < appState.recentScrobbles.count - 1 { Divider().padding(.leading, 36) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(26)
        }
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("СЕЙЧАС ИГРАЕТ", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(appState.isPlaying ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(appState.isPlaying ? "Яндекс Музыка" : "Ожидание")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.1)).frame(width: 72, height: 72)
                    Image(systemName: "waveform").font(.system(size: 27, weight: .medium)).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(appState.currentTrack?.title ?? "Включите трек в Яндекс Музыке")
                        .font(.title3.weight(.semibold)).lineLimit(2)
                    Text(appState.currentTrack?.artist ?? "Текущий трек появится здесь")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let album = appState.currentAlbum, !album.isEmpty {
                        Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if appState.playbackDuration > 0 {
                ProgressView(value: min(appState.playbackPosition / Double(appState.playbackDuration), 1))
                    .tint(accent)
                HStack {
                    Text(formatTime(Int(appState.playbackPosition)))
                    Spacer()
                    Text(formatTime(appState.playbackDuration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text(appState.statusText).lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(19)
        .background(.background, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.primary.opacity(0.07)))
    }

    private var emptyRecent: some View {
        VStack(spacing: 9) {
            Image(systemName: "music.note.list").font(.system(size: 25)).foregroundStyle(.tertiary)
            Text("Тут появятся отправленные треки")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Трек отправляется после прослушивания половины или четырёх минут.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statisticCard(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.title2).foregroundStyle(accent)
                .frame(width: 42, height: 42).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title2.weight(.bold).monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)))
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Настройки").font(.system(size: 28, weight: .bold))
                    Text("Подключение аккаунтов и источники прослушивания.").foregroundStyle(.secondary)
                }

                settingsSection("Аккаунт Last.fm", symbol: "person.crop.circle") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lastFM.sessionUsername ?? "Не подключён").font(.headline)
                            Text(lastFM.isLoggedIn ? "Авторизация сохранена в связке ключей macOS" : "Войдите через Last.fm в браузере")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if lastFM.isLoggedIn {
                            Button("Выйти") {
                                lastFM.logout()
                                appState.lastFMConnectionChanged()
                            }
                        } else {
                            Button("Открыть окно входа") { openWindow(id: "lastfm-login") }
                                .buttonStyle(.borderedProminent).tint(accent)
                        }
                    }
                    if lastFM.hasPendingToken {
                        Divider()
                        Button("Продолжить вход в отдельном окне") { openWindow(id: "lastfm-login") }
                            .buttonStyle(.borderedProminent).tint(accent)
                    }
                    if let error = lastFM.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                    }
                }

                settingsSection("Яндекс Музыка", symbol: "waveform") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Отслеживание плеера включено в приложение")
                                .font(.subheadline.weight(.medium))
                            Text("Listen Here считывает название, исполнителя, длительность и позицию из интерфейса Яндекс Музыки. Аудиозапись и отправка звука не используются.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Разрешение Универсального доступа").font(.subheadline.weight(.medium))
                            Text(appState.needsAccessibilityPermission ? "Пока не выдано" : "Проверка разрешения при запуске скробблинга")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Открыть настройки") { appState.openAccessibilitySettings() }
                        Button("Проверить") { appState.requestAccessibilityPermission() }
                    }
                }

                settingsSection("Правила скробблинга", symbol: "checkmark.seal") {
                    Label("Треки короче 30 секунд пропускаются.", systemImage: "music.note")
                    Label("Скроббл отправляется после половины трека или четырёх минут — что наступит раньше.", systemImage: "timer")
                    Label("При отсутствии сети треки остаются в локальной очереди и отправляются позже.", systemImage: "arrow.clockwise")
                }
            }
            .padding(26)
        }
    }

    private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
