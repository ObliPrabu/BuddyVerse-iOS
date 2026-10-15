import Foundation
import UIKit
import FirebaseCore
@preconcurrency import FirebaseFirestore
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
final class InternetConnectionManager: @unchecked Sendable {
    // @unchecked Sendable: the room/session state below is only touched on
    // the main thread - Firestore delivers its callbacks on the main queue,
    // and the ones that call back into UI code hop there explicitly via
    // runOnMain - so there's no real cross-thread sharing to guard.
    // Only ever created/used on the main thread (every game/lobby view calls
    // in from onAppear/button actions), same pattern as ThemeManager/MusicManager.
    static let shared = InternetConnectionManager()
    private init() {
        // iOS suspends a backgrounded app outright, so nothing here can run
        // a 60-second countdown while the player is away. Instead we note
        // when they left and judge how long they were gone the moment they
        // return (see handleReturnedToForeground) - the same 60s grace
        // Android gives a backgrounded game, just checked on resume.
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.backgroundedAt = Self.monotonicNow()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleReturnedToForeground()
        }
    }

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
    // Optional sender-aware sibling of onMessage: lets a game check that a
    // move really came from the player whose turn it is. Exactly ONE of the
    // two fires per message (see deliverMessage), so a game that supplies
    // both can't double-process.
    private var onMessageWithSender: ((String, String) -> Void)?
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
    // The roster the host froze at the instant it flipped the room to
    // "playing". Every phone builds the game's player list from this so turn
    // order agrees even if someone joins/leaves right around Start.
    private var latestStartedPlayers: [Player]?
    private var latestStatus: String?

    // Messages that arrive before the real game screen has attached its
    // listener get buffered and replayed the moment it does.
    private var bufferingEnabled = true
    private var messageBuffer: [(sender: String, text: String)] = []

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

    /// The roster every phone should hand to the game screen: the host's
    /// frozen `startedPlayers` if present, otherwise the live player list
    /// (a room from a client that doesn't write startedPlayers).
    func playersForGame() -> [Player] { latestStartedPlayers ?? latestPlayers }

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
    private func ensureSignedIn(onReady: @escaping () -> Void, onError: @escaping @MainActor (String) -> Void) {
        guard FirebaseApp.app() != nil else {
            runOnMain { onError("Online play isn't set up on this build yet. Ask the developer to add GoogleService-Info.plist.") }
            return
        }
        if Auth.auth().currentUser != nil {
            onReady()
            return
        }
        Auth.auth().signInAnonymously { _, error in
            if let error {
                print("InternetConnectionManager: anonymous sign-in failed: \(error)")
                runOnMain { onError("Couldn't reach the game server - check your internet connection and try again.") }
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
        onCodeReady: @escaping @MainActor (String) -> Void,
        onPlayersChanged: @escaping ([Player]) -> Void,
        onGameStarted: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onDisconnected: @escaping () -> Void,
        onError: @escaping @MainActor (String) -> Void
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

    // Thrown (as an NSError code) from inside the create transaction when the
    // randomly-picked code already belongs to a live room.
    private static let codeTakenErrorCode = 100

    // Picks a room code and only writes the room doc if that code isn't
    // already taken, regenerating and retrying a few times on collision. The
    // "does it exist" check and the write happen inside one Firestore
    // transaction, so two hosts that happen to generate the same code at the
    // same moment can't both pass the check and overwrite each other's room.
    private func createRoomWithFreshCode(
        hostName: String,
        hostId: String,
        gameType: String,
        maxPlayers: Int,
        session: Int,
        attemptsLeft: Int,
        onCodeReady: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        let code = Self.generateRoomCode()
        let docRef = db.collection("rooms").document(code)

        let roomData: [String: Any] = [
            "gameType": gameType,
            "status": "waiting",
            "maxPlayers": maxPlayers,
            "players": [["id": hostId, "name": hostName]],
            // Presence: see startHeartbeat(). Written up front so a guest can
            // tell a long-abandoned "waiting" room from a live one.
            "lastSeen": [hostId: FieldValue.serverTimestamp()]
        ]

        db.runTransaction({ transaction, errorPointer -> Any? in
            do {
                let existing = try transaction.getDocument(docRef)
                if existing.exists {
                    errorPointer?.pointee = NSError(domain: "BuddyVerse", code: Self.codeTakenErrorCode, userInfo: nil)
                    return nil
                }
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            transaction.setData(roomData, forDocument: docRef)
            return nil
        }) { [weak self] _, error in
            guard let self else { return }
            guard session == self.sessionId else {
                // Cancelled while in flight - don't resurrect a room nobody
                // wants, just make sure it doesn't sit around advertising
                // itself as "waiting". (Only if our own write actually landed.)
                if error == nil { docRef.updateData(["status": "ended"]) }
                return
            }
            if let error {
                let nsError = error as NSError
                if nsError.domain == "BuddyVerse", nsError.code == Self.codeTakenErrorCode {
                    if attemptsLeft > 0 {
                        self.createRoomWithFreshCode(hostName: hostName, hostId: hostId, gameType: gameType, maxPlayers: maxPlayers, session: session, attemptsLeft: attemptsLeft - 1, onCodeReady: onCodeReady, onError: onError)
                    } else {
                        runOnMain { onError("Couldn't create a game - please try again.") }
                    }
                } else {
                    runOnMain { onError(self.describeFirestoreFailure(error)) }
                }
                return
            }
            self.roomCode = code
            self.myRole = "HOST"
            self.myId = hostId
            self.connected = true
            self.startHeartbeat(code: code, session: session)
            runOnMain { onCodeReady(code) }
            self.listenToRoom(code)
            self.listenToMessages(code)
        }
    }

    /// Call when a guest taps "Join Game" with a code they were given.
    func joinRoom(
        code: String,
        guestName: String,
        gameType: String,
        onJoined: @escaping @MainActor () -> Void,
        onJoinFailed: @escaping @MainActor (String) -> Void,
        onPlayersChanged: @escaping ([Player]) -> Void,
        onGameStarted: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onDisconnected: @escaping () -> Void
    ) {
        // ASCII digits only (Character.isNumber also accepts things like
        // "½" or Arabic-Indic digits), and exactly 6 of them, checked BEFORE
        // touching Firestore: an empty or odd code would otherwise build a
        // document path like rooms/"" which the SDK treats as a fatal error.
        let cleanCode = code.filter { $0 >= "0" && $0 <= "9" }
        guard cleanCode.count == 6 else {
            runOnMain { onJoinFailed("That doesn't look like a valid code. Room codes are exactly 6 digits.") }
            return
        }

        stop()
        let session = sessionId
        bufferingEnabled = true
        messageBuffer.removeAll()
        self.onPlayersChanged = onPlayersChanged
        self.onGameStarted = onGameStarted

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
        onJoined: @escaping @MainActor () -> Void,
        onJoinFailed: @escaping @MainActor (String) -> Void,
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
            // TTL check: a "waiting" room whose host hasn't heartbeated for
            // minutes is a leftover from a killed process. A missing
            // lastSeen (an older client that never writes one) is treated as
            // alive. The generous window absorbs clock skew between phones.
            if let hostId = existingPlayers.first?["id"],
               let hostSeen = (snapshot.get("lastSeen") as? [String: Any])?[hostId] as? Timestamp,
               Date().timeIntervalSince(hostSeen.dateValue()) > Self.joinTTLSeconds {
                errorPointer?.pointee = NSError(domain: "BuddyVerse", code: 5, userInfo: [NSLocalizedDescriptionKey: "That game is no longer available. Ask your friend to create a new one."])
                return nil
            }
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
                // Our own rejections ("code doesn't exist", "room is full", ...)
                // carry a message written for the player; anything else is a
                // raw SDK error and gets the friendly generic wording instead.
                let nsError = error as NSError
                let message = nsError.domain == "BuddyVerse" ? nsError.localizedDescription : self.describeFirestoreFailure(error)
                runOnMain { onJoinFailed(message) }
                return
            }
            self.roomCode = cleanCode
            self.myRole = "GUEST"
            self.myId = guestId
            self.connected = true
            self.onMessage = onMessage
            self.onDisconnected = onDisconnected
            self.startHeartbeat(code: cleanCode, session: session)
            runOnMain { onJoined() }
            self.listenToRoom(cleanCode)
            self.listenToMessages(cleanCode)
        }
    }

    /// Host-only: called when they tap "Start Game" once at least 2 players have joined.
    func startGame() {
        guard let code = roomCode else { return }
        let docRef = db.collection("rooms").document(code)
        // A transaction (not a plain update) so the roster is read and frozen
        // at the exact moment the room flips to "playing". A guest whose join
        // committed just before this is included in the frozen
        // "startedPlayers" list; one that commits after is rejected by
        // joinRoom's own "status must be waiting" check - so every phone,
        // host included, builds the same player list from this one field.
        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            guard snapshot.exists, snapshot.get("status") as? String == "waiting" else { return nil }
            transaction.updateData([
                "status": "playing",
                "startedPlayers": snapshot.get("players") ?? []
            ], forDocument: docRef)
            return nil
        }, completion: { _, error in
            if let error { print("InternetConnectionManager: startGame transaction failed: \(error)") }
        })
    }

    // MARK: - Listeners

    private static func parsePlayers(_ raw: Any?) -> [Player]? {
        guard let entries = raw as? [[String: String]] else { return nil }
        return entries.compactMap { entry -> Player? in
            guard let id = entry["id"], let name = entry["name"] else { return nil }
            return Player(id: id, name: name)
        }
    }

    private func listenToRoom(_ code: String) {
        roomListener?.remove()
        let session = sessionId
        roomListener = db.collection("rooms").document(code).addSnapshotListener { [weak self] snapshot, error in
            guard let self, session == self.sessionId else { return }
            // Firestore permanently kills a listener after a non-retryable
            // error, so carrying on would leave this phone deaf with no hint
            // why - treat it as the connection being lost.
            if error != nil {
                print("InternetConnectionManager: room listener failed: \(error!)")
                self.handleConnectionLost(session)
                return
            }
            guard let snapshot else { return }
            if !snapshot.exists {
                // The host deletes the room right after marking it "ended",
                // so a guest who missed that brief "ended" update only ever
                // sees the doc vanish. A cache-only "missing" answer (e.g.
                // offline) proves nothing, so only trust one from the server.
                if !snapshot.metadata.isFromCache { self.handleConnectionLost(session) }
                return
            }

            self.trackPeerHeartbeats(snapshot.get("lastSeen"))

            let status = snapshot.get("status") as? String
            let players = Self.parsePlayers(snapshot.get("players")) ?? []

            // Once the game is underway, a seat vanishing means that player
            // left (a guest's stop() only removes their own seat, it never
            // sets "ended" - only the host's does). The games' turn order is
            // a frozen copy of the roster, so carrying on would stall
            // everyone on the leaver's turn forever. Only checked while
            // "playing" - guests coming and going in the lobby is normal.
            let someoneLeftMidGame = self.latestStatus == "playing" && status == "playing" &&
                self.latestPlayers.contains { old in !players.contains { $0.id == old.id } }

            self.latestStartedPlayers = Self.parsePlayers(snapshot.get("startedPlayers"))

            if players != self.latestPlayers {
                self.latestPlayers = players
                self.onPlayersChanged?(players)
            }

            if someoneLeftMidGame && self.connected {
                self.latestStatus = status
                self.connected = false
                self.onDisconnected?()
                return
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
        let session = sessionId
        messagesListener = db.collection("rooms").document(code).collection("messages")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, session == self.sessionId else { return }
                if error != nil {
                    print("InternetConnectionManager: messages listener failed: \(error!)")
                    self.handleConnectionLost(session)
                    return
                }
                guard let snapshot else { return }
                for change in snapshot.documentChanges where change.type == .added {
                    let data = change.document.data()
                    guard let sender = data["sender"] as? String, let text = data["text"] as? String else { continue }
                    // Firestore notifies EVERY phone in the room about every
                    // new message, including whoever sent it - skip our own
                    // so we don't process our own moves as if they came from
                    // someone else.
                    if sender == self.myId { continue }

                    if self.bufferingEnabled {
                        self.messageBuffer.append((sender: sender, text: text))
                    }
                    self.deliverMessage(sender: sender, text: text)
                }
            }
    }

    // Single delivery point for live and replayed messages: the
    // sender-aware callback wins when a game supplied one, otherwise the
    // plain onMessage is the fallback - never both.
    private func deliverMessage(sender: String, text: String) {
        if let withSender = onMessageWithSender {
            withSender(sender, text)
        } else {
            onMessage?(text)
        }
    }

    /// Swaps out the message/disconnect handlers without touching the
    /// connection - used when moving from the lobby screen into the actual
    /// game screen. Replays any messages that arrived too early.
    /// `onMessageWithSender` is the optional opt-in that also hands back the
    /// real Firestore sender id, for games that verify who sent a move.
    func setListeners(
        onMessage: @escaping (String) -> Void,
        onDisconnected: @escaping () -> Void,
        onMessageWithSender: ((String, String) -> Void)? = nil
    ) {
        self.onMessage = onMessage
        self.onMessageWithSender = onMessageWithSender
        self.onDisconnected = onDisconnected

        if bufferingEnabled {
            bufferingEnabled = false
            let queued = messageBuffer
            messageBuffer.removeAll()
            queued.forEach { deliverMessage(sender: $0.sender, text: $0.text) }
        }

        // If the room already ended while we were mid-transition, deliver it
        // right now instead of leaving the new screen hanging on
        // "Connecting..." forever.
        if !connected {
            onDisconnected()
        }
    }

    /// For the screens between the lobby and the game (Hangman's mode choice,
    /// the instruction screens) that have no message handling of their own.
    /// Unlike setListeners this ONLY swaps the disconnect handler - it never
    /// touches the message buffer the real game screen still needs to
    /// replay. If the room was already lost before this screen attached, it
    /// fires right away; the game screen's own setListeners later replaces
    /// this handler (and replays a disconnect that happened in between).
    func setInterstitialDisconnectListener(_ onDisconnected: @escaping () -> Void) {
        self.onDisconnected = onDisconnected
        if !connected { onDisconnected() }
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
        let session = sessionId
        db.collection("rooms").document(code).collection("messages").addDocument(data: message) { [weak self] error in
            // Games apply a move locally before sending it, so a failed write
            // means the other players will never see it and the game would
            // hang silently - end the session through the normal disconnect
            // path instead.
            if let error {
                print("InternetConnectionManager: sendMessage failed: \(error)")
                self?.handleConnectionLost(session)
            }
        }
    }

    // MARK: - Presence / heartbeat
    //
    // Firestore queues writes offline and snapshot listeners just go quiet
    // when a phone loses signal or its process is killed, so neither
    // sendMessage's failure path nor the listeners' error callbacks ever
    // fire. So every member periodically writes its own "lastSeen.<id>"
    // server timestamp on the room doc, and everyone watches the others'.
    //
    // Staleness is judged by how long ago WE LAST SAW a peer's value change
    // (a local monotonic clock), never by comparing timestamps to our own
    // wall clock, so phone clock skew can't cause false timeouts. A peer is
    // only ever timed out after we've seen it write lastSeen at least once.
    // Our own heartbeat write only completes once the server acknowledges it,
    // so if those acks stop we know WE are the one offline.
    //
    // The numbers are the SAME as Android's, on purpose: both platforms share
    // these rooms, so a peer on either must be judged by the same clock.
    private static let heartbeatInterval: TimeInterval = 10
    // A peer is only declared gone after peerStale, which must exceed the 60s
    // a backgrounded player is allowed (backgroundGrace) plus a margin.
    private static let peerStale: TimeInterval = 90
    private static let ownAckLost: TimeInterval = 45
    private static let ownAckMaxAge: TimeInterval = 25
    // A tick arriving this much later than scheduled means the app was
    // suspended or the device slept, so our own ack and our view of every
    // peer's heartbeat are stale through no one's fault.
    private static let tickLateSlack: TimeInterval = 15
    private static let joinTTLSeconds: TimeInterval = 3 * 60
    /// How long a game may sit in the background before the room is torn down.
    static let backgroundGrace: TimeInterval = 60

    private var peerLastValue: [String: Timestamp] = [:]
    private var peerChangedAt: [String: TimeInterval] = [:]
    private var lastOwnAckAt: TimeInterval = 0
    private var lastTickAt: TimeInterval = 0
    private var heartbeatTimer: Timer?
    private var backgroundedAt: TimeInterval?

    // CLOCK_MONOTONIC_RAW keeps counting while the device sleeps (unlike
    // ProcessInfo.systemUptime), which is exactly what "how long have we been
    // away / how long since we last saw this peer" needs.
    private static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    private func startHeartbeat(code: String, session: Int) {
        stopHeartbeat()
        lastOwnAckAt = Self.monotonicNow()
        lastTickAt = lastOwnAckAt
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.heartbeatTick(code: code, session: session)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        peerLastValue.removeAll()
        peerChangedAt.removeAll()
    }

    private func heartbeatTick(code: String, session: Int) {
        guard session == sessionId, connected, let id = myId else { return }
        let tickNow = Self.monotonicNow()
        if tickNow - lastTickAt > Self.heartbeatInterval + Self.tickLateSlack {
            // We were suspended/asleep: give everything a fresh window instead
            // of judging on the first tick after waking.
            lastOwnAckAt = tickNow
            for key in peerChangedAt.keys { peerChangedAt[key] = tickNow }
        }
        lastTickAt = tickNow
        db.collection("rooms").document(code).updateData([FieldPath(["lastSeen", id]): FieldValue.serverTimestamp()]) { [weak self] error in
            if let error {
                print("InternetConnectionManager: heartbeat write failed: \(error)")
            } else {
                self?.lastOwnAckAt = Self.monotonicNow()
            }
        }
        checkPresence(code: code, session: session)
    }

    private func trackPeerHeartbeats(_ raw: Any?) {
        guard let map = raw as? [String: Any] else { return }
        let now = Self.monotonicNow()
        for (id, value) in map {
            guard id != myId, let timestamp = value as? Timestamp else { continue }
            if peerLastValue[id] != timestamp {
                peerLastValue[id] = timestamp
                peerChangedAt[id] = now
            }
        }
    }

    private func checkPresence(code: String, session: Int) {
        let now = Self.monotonicNow()
        // No server ack for our own heartbeat: we're the offline one.
        if now - lastOwnAckAt > Self.ownAckLost {
            handleConnectionLost(session)
            return
        }
        // If our own acks are lagging we can't tell "peer is gone" from "our
        // snapshots are behind", so don't judge anyone yet.
        if now - lastOwnAckAt > Self.ownAckMaxAge { return }
        let playing = latestStatus == "playing"
        let hostId = latestPlayers.first?.id
        for player in latestPlayers {
            if player.id == myId { continue }
            guard let changedAt = peerChangedAt[player.id] else { continue }
            if now - changedAt <= Self.peerStale { continue }
            if playing || (player.id == hostId && !isHost()) {
                handleConnectionLost(session)
                return
            }
            // Host in the lobby: quietly free the seat of a guest that vanished.
            if isHost() {
                peerChangedAt.removeValue(forKey: player.id)
                peerLastValue.removeValue(forKey: player.id)
                removeSelf(from: db.collection("rooms").document(code), playerId: player.id)
            }
        }
    }

    // Shared "we can no longer trust this connection" path for failed sends,
    // dead snapshot listeners and heartbeat timeouts. Ignored if the session
    // it was raised for is already over, or if we already told the game.
    private func handleConnectionLost(_ session: Int) {
        guard session == sessionId, connected else { return }
        connected = false
        onDisconnected?()
    }

    // Called when the app comes back to the foreground. iOS froze everything
    // while we were away, so judge by how long that was: within the grace
    // period the session carries on untouched (the heartbeat then re-syncs
    // everyone); past it, the other players have already been told we're
    // gone, so end our side too and let the game show its disconnect screen.
    private func handleReturnedToForeground() {
        defer { backgroundedAt = nil }
        guard let left = backgroundedAt, roomCode != nil, connected else { return }
        if Self.monotonicNow() - left > Self.backgroundGrace {
            let callback = onDisconnected
            stop()
            callback?()
        }
    }

    /// Call when leaving the game/lobby so the room is cleaned up properly.
    /// The HOST owns the room's lifecycle - them leaving ends it for
    /// everyone, same as always. A GUEST leaving must only vacate their own
    /// seat: the room, its messages, and everyone else still in it need to
    /// keep going untouched, otherwise one guest backing out mid-game would
    /// disconnect the host and every other guest too.
    func stop() {
        stopHeartbeat()
        backgroundedAt = nil
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
                let database = db
                roomRef.collection("messages").getDocuments { snapshot, _ in
                    guard let snapshot else { return }
                    // A Firestore batch holds at most 500 writes, so a long
                    // session's messages are deleted in chunks of 400; the
                    // room doc goes last, in its own batch, so it's only
                    // removed after every message chunk was queued.
                    let refs = snapshot.documents.map { $0.reference }
                    var start = 0
                    while start < refs.count {
                        let batch = database.batch()
                        for ref in refs[start..<min(start + 400, refs.count)] { batch.deleteDocument(ref) }
                        batch.commit()
                        start += 400
                    }
                    let last = database.batch()
                    last.deleteDocument(roomRef)
                    last.commit()
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
        latestStartedPlayers = nil
        latestStatus = nil
        onMessage = nil
        onMessageWithSender = nil
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
