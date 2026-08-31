import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

/// One joined player, as stored in the room doc's "players" array.
struct Player: Hashable {
    let id: String
    let name: String
}

/// Lets any number of phones play together over the REAL internet using
/// Firebase Firestore as a relay - a direct port of InternetConnectionManager.kt.
///
/// How it works, in plain terms:
/// 1. One phone taps "Create Game" - this makes a "room" in the cloud with a
///    short numeric code (like "739215") and starts waiting, holding a cap on
///    how many players it'll accept (maxPlayers, chosen up front).
/// 2. Everyone else taps "Join Game" and types that code in - any number of
///    people can join, up to maxPlayers, while the room is still "waiting".
/// 3. The host taps "Start Game" whenever they're ready (at least 2 joined) -
///    every phone in the room sees this the instant it happens and moves on
///    to the actual game together.
/// 4. From there, every move any phone makes gets written to that room as a
///    tiny message, and every OTHER phone picks it up almost instantly
///    through a live listener. Each phone tags its own messages with a
///    random per-session id (myId) instead of a fixed "HOST"/"GUEST" label,
///    since there can now be more than 2 senders.
///
/// Every game screen talks to this exact same singleton, the same way every
/// Android game Activity talks to the Kotlin `object`.
final class InternetConnectionManager {
    // Only ever created/used on the main thread (every game/lobby view calls
    // in from onAppear/button actions), same pattern as ThemeManager/MusicManager.
    nonisolated(unsafe) static let shared = InternetConnectionManager()
    private init() {}

    private var db: Firestore { Firestore.firestore() }

    private var roomCode: String?
    private var myRole: String? // "HOST" or "GUEST" - still exactly 2 values, just about room ownership, not in-game turn order
    private var myId: String? // unique per-session id, used as the message "sender" and as this player's entry in the players list
    private(set) var connected = false

    // Bumped every time stop() runs. create/joinRoom capture the value right
    // after that, so if stop() gets called again (Cancel tapped, or another
    // create/join starts) before their Firestore calls finish, the stale
    // callback can tell it's no longer wanted and back out instead of
    // resurrecting a connection nobody asked for anymore.
    private var sessionId = 0

    private var roomListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?

    private var onPlayersChanged: (([Player]) -> Void)?
    private var onGameStarted: (() -> Void)?
    private var onMessage: ((String) -> Void)?
    private var onDisconnected: (() -> Void)?

    // Rides the room DOCUMENT's own live listener instead of the messages
    // subcollection, so a screen can watch the host's word-mode pick without
    // touching bufferingEnabled - which would prematurely flush the message
    // buffer a later game screen still needs for its own turn-order setup.
    private var onWordModeChanged: ((String) -> Void)?
    private var latestWordMode: String?
    // Edge-detection caches so onPlayersChanged/onGameStarted only fire when
    // something actually changed, not on every unrelated snapshot update.
    private var latestPlayers: [Player] = []
    private var latestStatus: String?

    // Messages that arrive before the real game screen has attached its
    // listener get buffered and replayed the moment it does.
    private var bufferingEnabled = true
    private var messageBuffer: [String] = []

    func isConnected() -> Bool { connected }

    /// Whichever phone called createRoom() is the host; whoever called
    /// joinRoom() is a guest. Decides who gets to choose PICKER vs RACE on
    /// HangmanModeChoiceView, and who's allowed to tap "Start Game" on
    /// OnlineLobbyView, instead of each phone picking/starting independently.
    func isHost() -> Bool { myRole == "HOST" }

    /// Every game message and every player-list entry needs to know "which
    /// one of these is me" - this is that id.
    func myPlayerId() -> String? { myId }

    /// The full current player list, in join order (seat 0 is always the host).
    func currentPlayers() -> [Player] { latestPlayers }

    // MARK: - Auth

    // Firestore's security rules require a signed-in user. There's nothing
    // for someone to log into here - this is a device-anonymous ticket so
    // the rules have a request.auth to check - so it happens silently.
    //
    // Guarded on FirebaseApp.app() first: Auth.auth()/Firestore.firestore()
    // both hit a hard fatalError() if FirebaseApp.configure() was never
    // called (see BuddyVerseApp.swift - it's only called when a real
    // GoogleService-Info.plist is present, see this project's CLAUDE.md).
    // Without this check, tapping "Create Game"/"Join Game" on a build
    // that's missing that file would crash the whole app instead of just
    // failing this one connection attempt with a message the player can
    // actually act on.
    private func ensureSignedIn(onReady: @escaping () -> Void, onError: @escaping (String) -> Void) {
        guard FirebaseApp.app() != nil else {
            onError("Online play isn't set up on this build yet. Ask the developer to add GoogleService-Info.plist.")
            return
        }
        if Auth.auth().currentUser != nil {
            onReady()
            return
        }
        Auth.auth().signInAnonymously { _, error in
            if let error {
                print("InternetConnectionManager: anonymous sign-in failed: \(error)")
                onError("Couldn't reach the game server - check your internet connection and try again.")
            } else {
                onReady()
            }
        }
    }

    private func describeFirestoreFailure(_ error: Error) -> String {
        let nsError = error as NSError
        switch FirestoreErrorCode.Code(rawValue: nsError.code) {
        case .unavailable, .deadlineExceeded, .aborted:
            return "Couldn't reach the game server - check your internet connection and try again."
        case .permissionDenied:
            return "Couldn't reach the game server - access was denied. Please try again later."
        default:
            return "Couldn't reach the game server - please try again."
        }
    }

    // MARK: - Create / Join

    /// Call when the host taps "Create Game". Makes a new room and reports back the short code to share.
    func createRoom(
        hostName: String,
        gameType: String,
        maxPlayers: Int,
        onCodeReady: @escaping (String) -> Void,
        onPlayersChanged: @escaping ([Player]) -> Void,
        onGameStarted: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onDisconnected: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        stop()
        let session = sessionId
        bufferingEnabled = true
        messageBuffer.removeAll()
        let hostId = UUID().uuidString
        self.onPlayersChanged = onPlayersChanged
        self.onGameStarted = onGameStarted
        self.onMessage = onMessage
        self.onDisconnected = onDisconnected

        ensureSignedIn(
            onReady: { [weak self] in
                guard let self, session == self.sessionId else { return }
                self.createRoomWithFreshCode(hostName: hostName, hostId: hostId, gameType: gameType, maxPlayers: maxPlayers, session: session, attemptsLeft: 5, onCodeReady: onCodeReady, onError: onError)
            },
            onError: onError
        )
    }

    // Picks a room code and only writes the room doc if that code isn't
    // already taken, regenerating and retrying a few times on collision.
    private func createRoomWithFreshCode(
        hostName: String,
        hostId: String,
        gameType: String,
        maxPlayers: Int,
        session: Int,
        attemptsLeft: Int,
        onCodeReady: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let code = Self.generateRoomCode()
        let docRef = db.collection("rooms").document(code)

        docRef.getDocument { [weak self] snapshot, error in
            guard let self, session == self.sessionId else { return }
            if let error {
                onError(self.describeFirestoreFailure(error))
                return
            }
            if snapshot?.exists == true {
                if attemptsLeft > 0 {
                    self.createRoomWithFreshCode(hostName: hostName, hostId: hostId, gameType: gameType, maxPlayers: maxPlayers, session: session, attemptsLeft: attemptsLeft - 1, onCodeReady: onCodeReady, onError: onError)
                } else {
                    onError("Couldn't create a game - please try again.")
                }
                return
            }

            let roomData: [String: Any] = [
                "gameType": gameType,
                "status": "waiting",
                "maxPlayers": maxPlayers,
                "players": [["id": hostId, "name": hostName]]
            ]
            docRef.setData(roomData) { [weak self] error in
                guard let self, session == self.sessionId else {
                    // Cancelled while in flight - don't resurrect a room nobody wants.
                    docRef.updateData(["status": "ended"])
                    return
                }
                if let error {
                    onError(self.describeFirestoreFailure(error))
                    return
                }
                self.roomCode = code
                self.myRole = "HOST"
                self.myId = hostId
                self.connected = true
                onCodeReady(code)
                self.listenToRoom(code)
                self.listenToMessages(code)
            }
        }
    }

    /// Call when a guest taps "Join Game" with a code they were given.
    func joinRoom(
        code: String,
        guestName: String,
        gameType: String,
        onJoined: @escaping () -> Void,
        onJoinFailed: @escaping (String) -> Void,
        onPlayersChanged: @escaping ([Player]) -> Void,
        onGameStarted: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onDisconnected: @escaping () -> Void
    ) {
        stop()
        let session = sessionId
        bufferingEnabled = true
        messageBuffer.removeAll()
        self.onPlayersChanged = onPlayersChanged
        self.onGameStarted = onGameStarted

        let cleanCode = code.filter(\.isNumber)
        let guestId = UUID().uuidString

        ensureSignedIn(
            onReady: { [weak self] in
                guard let self, session == self.sessionId else { return }
                self.joinRoomAfterAuth(cleanCode: cleanCode, guestName: guestName, guestId: guestId, gameType: gameType, session: session, onJoined: onJoined, onJoinFailed: onJoinFailed, onMessage: onMessage, onDisconnected: onDisconnected)
            },
            onError: onJoinFailed
        )
    }

    private struct JoinRejected: Error { let message: String }

    private func joinRoomAfterAuth(
        cleanCode: String,
        guestName: String,
        guestId: String,
        gameType: String,
        session: Int,
        onJoined: @escaping () -> Void,
        onJoinFailed: @escaping (String) -> Void,
        onMessage: @escaping (String) -> Void,
        onDisconnected: @escaping () -> Void
    ) {
        let docRef = db.collection("rooms").document(cleanCode)

        // Runs the whole check-and-set inside a single Firestore transaction
        // so it's atomic: Firestore guarantees only one of any number of
        // racing transactions against the same doc commits at a time
        // (retrying the others against the fresh data), so two people
        // typing in the same code at the same moment can't both grab the
        // last open seat, and nobody can join after the host already
        // started the game.
        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            guard snapshot.exists else {
                errorPointer?.pointee = NSError(domain: "BuddyVerse", code: 1, userInfo: [NSLocalizedDescriptionKey: "That code doesn't exist. Double check it and try again."])
                return nil
            }
            guard snapshot.get("status") as? String == "waiting" else {
                errorPointer?.pointee = NSError(domain: "BuddyVerse", code: 2, userInfo: [NSLocalizedDescriptionKey: "That game already started or ended."])
                return nil
            }
            // The room code alone doesn't guarantee everyone picked the
            // same game - without this a Hangman code typed into
            // Tic-Tac-Toe's join screen would connect anyway and desync.
            guard snapshot.get("gameType") as? String == gameType else {
                errorPointer?.pointee = NSError(domain: "BuddyVerse", code: 3, userInfo: [NSLocalizedDescriptionKey: "That code is for a different game. Double check it and try again."])
                return nil
            }
            let existingPlayers = (snapshot.get("players") as? [[String: String]]) ?? []
            let maxPlayers = (snapshot.get("maxPlayers") as? Int) ?? 2
            guard existingPlayers.count < maxPlayers else {
                errorPointer?.pointee = NSError(domain: "BuddyVerse", code: 4, userInfo: [NSLocalizedDescriptionKey: "This room is full."])
                return nil
            }
            let updatedPlayers = existingPlayers + [["id": guestId, "name": guestName]]
            transaction.updateData(["players": updatedPlayers], forDocument: docRef)
            return nil
        }) { [weak self] _, error in
            guard let self, session == self.sessionId else {
                // Cancelled while in flight - back out of the seat we just
                // joined instead of leaving a ghost seat nobody's actually
                // sitting in. Only remove OUR OWN seat, not the whole room -
                // the host and anyone else already in it must keep playing
                // uninterrupted.
                self?.removeSelf(from: docRef, playerId: guestId)
                return
            }
            if let error {
                onJoinFailed((error as NSError).localizedDescription.isEmpty ? self.describeFirestoreFailure(error) : error.localizedDescription)
                return
            }
            self.roomCode = cleanCode
            self.myRole = "GUEST"
            self.myId = guestId
            self.connected = true
            self.onMessage = onMessage
            self.onDisconnected = onDisconnected
            onJoined()
            self.listenToRoom(cleanCode)
            self.listenToMessages(cleanCode)
        }
    }

    /// Host-only: called when they tap "Start Game" once at least 2 players have joined.
    func startGame() {
        guard let code = roomCode else { return }
        db.collection("rooms").document(code).updateData(["status": "playing"])
    }

    // MARK: - Listeners

    private func listenToRoom(_ code: String) {
        roomListener?.remove()
        roomListener = db.collection("rooms").document(code).addSnapshotListener { [weak self] snapshot, error in
            guard let self, error == nil, let snapshot, snapshot.exists else { return }

            let status = snapshot.get("status") as? String
            let rawPlayers = (snapshot.get("players") as? [[String: String]]) ?? []
            let players = rawPlayers.compactMap { entry -> Player? in
                guard let id = entry["id"], let name = entry["name"] else { return nil }
                return Player(id: id, name: name)
            }

            if players != self.latestPlayers {
                self.latestPlayers = players
                self.onPlayersChanged?(players)
            }

            // Only relevant for a guest - the host is the one who sets this
            // field, so it'd just be echoing its own choice back to itself.
            if self.myRole == "GUEST",
               let wordMode = snapshot.get("wordMode") as? String,
               wordMode != self.latestWordMode {
                self.latestWordMode = wordMode
                self.onWordModeChanged?(wordMode)
            }

            if status == "playing", self.latestStatus != "playing" {
                self.latestStatus = status
                self.onGameStarted?()
            } else {
                self.latestStatus = status
            }

            if status == "ended" {
                self.connected = false
                self.onDisconnected?()
            }
        }
    }

    private func listenToMessages(_ code: String) {
        messagesListener?.remove()
        messagesListener = db.collection("rooms").document(code).collection("messages")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, error == nil, let snapshot else { return }
                for change in snapshot.documentChanges where change.type == .added {
                    let data = change.document.data()
                    guard let sender = data["sender"] as? String, let text = data["text"] as? String else { continue }
                    // Firestore notifies EVERY phone in the room about every
                    // new message, including whoever sent it - skip our own
                    // so we don't process our own moves as if they came from
                    // someone else.
                    if sender == self.myId { continue }

                    if self.bufferingEnabled {
                        self.messageBuffer.append(text)
                    }
                    self.onMessage?(text)
                }
            }
    }

    /// Swaps out the message/disconnect handlers without touching the
    /// connection - used when moving from the lobby screen into the actual
    /// game screen. Replays any messages that arrived too early.
    func setListeners(onMessage: @escaping (String) -> Void, onDisconnected: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onDisconnected = onDisconnected

        if bufferingEnabled {
            bufferingEnabled = false
            let queued = messageBuffer
            messageBuffer.removeAll()
            queued.forEach(onMessage)
        }

        // If the room already ended while we were mid-transition, deliver it
        // right now instead of leaving the new screen hanging on
        // "Connecting..." forever.
        if !connected {
            onDisconnected()
        }
    }

    // MARK: - Hangman word-mode sync

    /// Host-only: records which way Hangman's secret word gets picked
    /// (PICKER or RACE) on the shared room doc.
    func chooseWordMode(_ mode: String) {
        guard let code = roomCode else { return }
        db.collection("rooms").document(code).updateData(["wordMode": mode])
    }

    /// Non-host-only: reports the host's word-mode pick as soon as it's known.
    func observeWordMode(_ onChanged: @escaping (String) -> Void) {
        onWordModeChanged = onChanged
        if let latestWordMode { onChanged(latestWordMode) }
    }

    func clearWordModeObserver() {
        onWordModeChanged = nil
    }

    // MARK: - Messaging

    /// Sends a small text message to everyone else sharing this room.
    func sendMessage(_ text: String) {
        guard let code = roomCode, let id = myId else { return }
        let message: [String: Any] = ["text": text, "sender": id, "createdAt": FieldValue.serverTimestamp()]
        db.collection("rooms").document(code).collection("messages").addDocument(data: message)
    }

    /// Call when leaving the game/lobby so the room is cleaned up properly.
    /// The HOST owns the room's lifecycle - them leaving ends it for
    /// everyone, same as always. A GUEST leaving must only vacate their own
    /// seat: the room, its messages, and everyone else still in it need to
    /// keep going untouched, otherwise one guest backing out mid-game would
    /// disconnect the host and every other guest too.
    func stop() {
        sessionId += 1
        roomListener?.remove()
        messagesListener?.remove()
        roomListener = nil
        messagesListener = nil

        if let code = roomCode {
            let roomRef = db.collection("rooms").document(code)
            if myRole == "HOST" {
                // Mark "ended" first so everyone else's live listener
                // reliably sees it, then delete the messages subcollection
                // and the room doc itself so a later reuse of this code
                // never inherits stale messages and the rooms collection
                // doesn't grow unbounded.
                roomRef.updateData(["status": "ended"])
                roomRef.collection("messages").getDocuments { snapshot, _ in
                    guard let snapshot else { return }
                    let batch = self.db.batch()
                    for doc in snapshot.documents { batch.deleteDocument(doc.reference) }
                    batch.deleteDocument(roomRef)
                    batch.commit()
                }
            } else if let id = myId {
                removeSelf(from: roomRef, playerId: id)
            }
        }

        roomCode = nil
        myRole = nil
        myId = nil
        connected = false
        onPlayersChanged = nil
        onGameStarted = nil
        onWordModeChanged = nil
        latestWordMode = nil
        latestPlayers = []
        latestStatus = nil
        onMessage = nil
        onDisconnected = nil
        bufferingEnabled = true
        messageBuffer.removeAll()
    }

    // Transaction-based (like joinRoomAfterAuth's own seat-grab) so a guest
    // leaving can't race another guest joining/leaving that same instant and
    // silently drop the wrong seat or resurrect a seat someone else already removed.
    private func removeSelf(from roomRef: DocumentReference, playerId: String) {
        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(roomRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            guard snapshot.exists else { return nil }
            let existingPlayers = (snapshot.get("players") as? [[String: String]]) ?? []
            let updatedPlayers = existingPlayers.filter { $0["id"] != playerId }
            transaction.updateData(["players": updatedPlayers], forDocument: roomRef)
            return nil
        }, completion: { _, _ in })
    }

    // Numbers only, so it's quick to read off one phone and type into another.
    private static func generateRoomCode() -> String {
        String((0..<6).map { _ in "0123456789".randomElement()! })
    }
}
