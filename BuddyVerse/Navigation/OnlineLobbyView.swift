import SwiftUI

/// Mirrors OnlineLobbyActivity/activity_online_lobby.xml: create-or-join-a-room
/// screen for real internet multiplayer, via InternetConnectionManager. For
/// games that support more than 2 players (GameCatalog.multiSeatMultiplayerGames),
/// shows a live roster as people join and a host-only "Start Game" button;
/// Tic-Tac-Toe (the one real-multiplayer game that stays 2-player) keeps the
/// older behavior of jumping straight into the game the instant one guest
/// joins - no roster, no Start button.
struct OnlineLobbyView: View {
    let gameType: String
    let maxPlayers: Int
    @EnvironmentObject private var router: Router

    private enum Stage { case nameEntry, hosting, joining }

    @State private var stage: Stage = .nameEntry
    @State private var playerName = ""
    @State private var joinCode = ""
    @State private var roomCode: String?
    @State private var hostStatus = "Waiting for players to join..."
    @State private var joinStatus = "Joining game..."
    @State private var errorMessage: String?
    @State private var connected = false
    @State private var gameStarted = false
    @State private var players: [Player] = []

    private var isMultiSeat: Bool { GameCatalog.multiSeatMultiplayerGames.contains(gameType) }

    // activity_online_lobby.xml's android:background="@drawable/welcome_gradient"
    // has no drawable-night override, so this exact gradient (which happens to
    // match WelcomeView's dark-mode background) is used in both light and dark.
    private let rootGradient = LinearGradient(
        colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
        startPoint: .bottomLeading, endPoint: .topTrailing
    )
    private let hintTextColor = Color(hex: 0xE0F7FA)
    private let placeholderColor = Color.white.opacity(0xAA / 255.0)
    private let createButtonBg = Color(hex: 0x4CAF50)
    private let cancelButtonBg = Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)

    var body: some View {
        ZStack {
            rootGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Play Online")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 16)

                switch stage {
                case .nameEntry: nameEntrySection
                case .hosting: hostingSection
                case .joining: joiningSection
                }

                Button("Cancel") {
                    InternetConnectionManager.shared.stop()
                    router.popToRoot()
                }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x333333))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(cancelButtonBg)
                .buttonStyle(.plain)
                .padding(.top, 30)
            }
            .padding(30)
        }
        .navigationBarHidden(true)
        // The `presenting:`/`message:` alert overload needs iOS 15 - this is
        // the iOS-13-compatible Alert(title:message:dismissButton:) form.
        .alert(isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Alert(
                title: Text("Couldn't Connect"),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("OK")) { errorMessage = nil }
            )
        }
        .onDisappear {
            // Only tear the connection down if we're leaving without handing
            // it off to the game screen.
            if !gameStarted { InternetConnectionManager.shared.stop() }
        }
    }

    private var nameEntrySection: some View {
        VStack(spacing: 0) {
            Text("What's your name?")
                .font(.system(size: 16))
                .foregroundColor(hintTextColor)
                .padding(.bottom, 12)

            androidField("Enter your name", text: $playerName)
                .padding(.bottom, 20)

            Button("Create Game") { createGame() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(createButtonBg)
                .buttonStyle(.plain)
                .padding(.bottom, 12)

            androidField("Have a code? Type it here", text: $joinCode, keyboard: .numberPad)
                .padding(.bottom, 12)

            Button("Join Game") { joinGame() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x1A237E))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .buttonStyle(.plain)
        }
    }

    private var hostingSection: some View {
        VStack(spacing: 0) {
            Text("Share this code with your friends:")
                .font(.system(size: 16))
                .foregroundColor(hintTextColor)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text(roomCode ?? "------")
                .font(.system(size: 36, weight: .bold))
                .tracking(2)
                .foregroundColor(.white)
                .padding(.bottom, 20)

            ProgressView()
                .accentColor(.white)
                .scaleEffect(1.4)
                .padding(.bottom, 16)

            Text(hostStatus)
                .font(.system(size: 15))
                .foregroundColor(hintTextColor)
                .multilineTextAlignment(.center)

            if isMultiSeat && !players.isEmpty {
                rosterText
                    .padding(.top, 16)

                if players.count >= 2 {
                    Button("Start Game") {
                        InternetConnectionManager.shared.startGame()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(createButtonBg)
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
        }
    }

    private var joiningSection: some View {
        VStack(spacing: 0) {
            ProgressView()
                .accentColor(.white)
                .scaleEffect(1.4)
                .padding(.bottom, 16)

            Text(joinStatus)
                .font(.system(size: 15))
                .foregroundColor(hintTextColor)
                .multilineTextAlignment(.center)

            if isMultiSeat && !players.isEmpty {
                rosterText
                    .padding(.top, 16)
                Text("Waiting for the host to start...")
                    .font(.system(size: 14))
                    .foregroundColor(hintTextColor)
                    .padding(.top, 8)
            }
        }
    }

    private var rosterText: some View {
        Text("\(players.count) / \(maxPlayers) joined\n" + players.map(\.name).joined(separator: "\n"))
            .font(.system(size: 14))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
    }

    // Rough stand-in for EditText's textColorHint - SwiftUI's TextField
    // placeholder color isn't directly styleable, so this overlays a manually
    // colored placeholder and an underline to mirror the plain-underline
    // Android EditText look.
    private func androidField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder).foregroundColor(placeholderColor)
            }
            TextField("", text: text)
                .foregroundColor(.white)
                .keyboardType(keyboard)
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }

    private func createGame() {
        let name = playerName.trimmingCharacters(in: .whitespaces)
        stage = .hosting
        InternetConnectionManager.shared.createRoom(
            hostName: name.isEmpty ? "Player" : name,
            gameType: gameType,
            maxPlayers: maxPlayers,
            onCodeReady: { code in DispatchQueue.main.async { roomCode = code } },
            onPlayersChanged: { newPlayers in DispatchQueue.main.async { onPlayersChanged(newPlayers) } },
            onGameStarted: { DispatchQueue.main.async { onGameStarted() } },
            onMessage: { _ in },
            onDisconnected: {
                DispatchQueue.main.async {
                    if !connected { hostStatus = "Something went wrong. Tap Cancel and try again." }
                }
            },
            onError: { message in
                DispatchQueue.main.async {
                    errorMessage = message
                    stage = .nameEntry
                }
            }
        )
    }

    private func joinGame() {
        let code = joinCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else {
            errorMessage = "Type in the code your friend shared with you."
            return
        }
        let name = playerName.trimmingCharacters(in: .whitespaces)
        stage = .joining
        InternetConnectionManager.shared.joinRoom(
            code: code,
            guestName: name.isEmpty ? "Player" : name,
            gameType: gameType,
            onJoined: { DispatchQueue.main.async { connected = true } },
            onJoinFailed: { message in
                DispatchQueue.main.async {
                    errorMessage = message
                    stage = .nameEntry
                }
            },
            onPlayersChanged: { newPlayers in DispatchQueue.main.async { onPlayersChanged(newPlayers) } },
            onGameStarted: { DispatchQueue.main.async { onGameStarted() } },
            onMessage: { _ in },
            onDisconnected: {
                DispatchQueue.main.async {
                    if !connected { joinStatus = "Something went wrong. Tap Cancel and try again." }
                }
            }
        )
    }

    private func onPlayersChanged(_ newPlayers: [Player]) {
        players = newPlayers
        connected = true

        if !isMultiSeat {
            // Tic-Tac-Toe (the one game that stays 2-player): keep the
            // original behavior exactly - the instant a second player has
            // joined, the host starts the game automatically, no roster or
            // manual Start button ever shown.
            if newPlayers.count >= 2 && InternetConnectionManager.shared.isHost() {
                InternetConnectionManager.shared.startGame()
            }
        }
    }

    private func onGameStarted() {
        guard !gameStarted else { return }
        gameStarted = true

        let selection = GameSelection(gameType: gameType, isBot: false, isNearby: true, players: players)
        // Hangman is the only game with a choice of how the secret word gets
        // picked, so it gets one extra screen here before the normal rules screen.
        if gameType == "HANGMAN" {
            router.push(.hangmanModeChoice(selection))
        } else {
            router.push(.instructionsChoice(selection))
        }
    }
}
