import Foundation
import Observation

/// 한 판의 대국을 진행하는 뷰모델.
/// 1인용은 AI가 상대 무브를 만들고, 2인용은 RoomClient가 상대 무브를 전달한다.
/// 양쪽 모두 동일한 `GameEngine`을 통해 상태가 결정된다.
@Observable
@MainActor
final class GameViewModel {
    enum Mode {
        case solo(AIPlayer.Difficulty)
        case online(RoomClient)
    }

    let mode: Mode
    private(set) var engine = GameEngine()
    private(set) var localPlayer: Player

    /// 배치 단계에서 내가 방금 굴린 주사위 값 (배치할 칸 선택 대기)
    private(set) var pendingRoll: Int?
    /// 현재 화면에 공개 중인 내 게임판 칸들 (칸 → 숫자, 족보 제출 단계 전용)
    private(set) var myRevealed: [Int: Int] = [:]
    /// 현재 화면에 공개 중인 상대 게임판 칸들
    private(set) var oppRevealed: [Int: Int] = [:]
    /// 족보 선언에서 첫 번째로 선택한 끝 칸 (두 번째 끝 칸 선택 대기)
    private(set) var anchorSelection: Int?
    /// 상단 안내 문구
    private(set) var banner: String = ""
    /// 족보 제출 단계 남은 시간 (초)
    private(set) var secondsLeft: Int = Int(GameEngine.turnTimeLimit)
    /// 암기 위반(스크린샷)으로 몰수패했는지
    private(set) var forfeitedByViolation = false
    /// 전적을 이미 기록했는지 (중복 기록 방지)
    private var statsRecorded = false
    /// 상대가 나갔는지 (온라인)
    var opponentLeft = false

    private var ai: AIPlayer?
    private var aiTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    /// 라운드 공개 연출 세대 — 새 선언이 시작되면 이전 "다시 덮기" 예약을 무효화
    private var revealGeneration = 0

    var isMyTurn: Bool { engine.currentTurn == localPlayer && engine.phase != .finished }
    var isSolo: Bool {
        if case .solo = mode { return true }
        return false
    }
    var myScore: Int { engine.scores[localPlayer.rawValue] }
    var opponentScore: Int { engine.scores[localPlayer.opponent.rawValue] }
    var opponentName: String {
        if case .solo = mode { return "AI" }
        return "상대"
    }
    /// 라운드 후공으로서 이겨야 할 상대의 선(先)선언 족보
    var handToBeat: Hand? {
        guard let pending = engine.pendingDeclaration, pending.player != localPlayer else { return nil }
        return pending.hand
    }
    /// 배치 단계에서 내 게임판 숫자 표시 여부 — 배치 중에만 보이고 이후는 암기
    var myBoardVisible: Bool { engine.phase == .placement }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .solo(let difficulty):
            // 선/후는 랜덤 배정
            localPlayer = Bool.random() ? .first : .second
            ai = AIPlayer(difficulty: difficulty, me: localPlayer.opponent)
        case .online(let client):
            if case .matched(let me) = client.state {
                localPlayer = me
            } else {
                localPlayer = .first
            }
            client.onRemoteMove = { [weak self] move in
                self?.applyRemote(move)
            }
            client.onOpponentLeft = { [weak self] in
                guard let self, self.engine.phase != .finished else { return }
                self.opponentLeft = true
            }
        }
        prepareTurn()
    }

    func cancelAllWork() {
        aiTask?.cancel()
        timerTask?.cancel()
    }

    // MARK: - 사용자 입력

    func tapCell(_ cell: Int) {
        guard isMyTurn else { return }

        switch engine.phase {
        case .placement:
            guard let roll = pendingRoll,
                  engine.boards[localPlayer.rawValue][cell] == 0 else { return }
            pendingRoll = nil
            applyLocal(.place(cell: cell, value: roll))

        case .combo:
            if anchorSelection == cell {
                anchorSelection = nil
            } else if let anchor = anchorSelection,
                      let line = GameEngine.lineIndex(from: anchor, to: cell),
                      !engine.usedLines[localPlayer.rawValue].contains(line) {
                anchorSelection = nil
                applyLocal(.declare(line: line))
            } else if !validEndpoints(from: cell).isEmpty {
                anchorSelection = cell
            }

        case .finished:
            break
        }
    }

    /// 선택한 끝 칸에서 이어질 수 있는 반대쪽 끝 칸들 (아직 선언하지 않은 라인만)
    func validEndpoints(from anchor: Int) -> [Int] {
        engine.unusedLines(of: localPlayer).compactMap { line in
            let cells = GameEngine.lines[line]
            if cells.first == anchor { return cells.last }
            if cells.last == anchor { return cells.first }
            return nil
        }
    }

    /// 스크린샷 등 기록 행위 감지 시 — 규칙대로 몰수패
    func memoryViolation() {
        guard engine.phase != .finished else { return }
        forfeitedByViolation = true
        applyLocal(.forfeit)
    }

    func resign() {
        guard engine.phase != .finished else { return }
        applyLocal(.forfeit)
    }

    // MARK: - 무브 적용

    private func applyLocal(_ move: Move) {
        guard let outcome = try? engine.apply(move, by: localPlayer) else { return }
        if case .online(let client) = mode {
            client.send(move: move)
        }
        present(outcome)
    }

    private func applyRemote(_ move: Move) {
        guard let outcome = try? engine.apply(move, by: localPlayer.opponent) else { return }
        present(outcome)
    }

    private func applyAI(_ move: Move) {
        guard let aiPlayer = ai,
              let outcome = try? engine.apply(move, by: aiPlayer.me) else { return }
        present(outcome)
    }

    // MARK: - 연출/상태 반영

    private func present(_ outcome: MoveOutcome) {
        ai?.observe(outcome)

        switch outcome {
        case .placed(let player, let cell, let value):
            if player == localPlayer {
                banner = "\(GameEngine.cellName(cell))에 \(value)을(를) 배치했습니다. (\(engine.placedCount)/50)"
            } else {
                banner = "\(opponentName)가 숫자를 배치했습니다. (\(engine.placedCount)/50)"
            }
            if engine.phase == .combo {
                banner = "게임판 설정 완료! 숫자는 이제 가려집니다 — 암기한 위치로 족보를 선언하세요."
            }

        case .declared(let player, let line, let values, let hand):
            // 새 라운드 시작 — 이전 라운드의 공개 칸을 즉시 덮고 예약된 덮기를 무효화
            revealGeneration += 1
            myRevealed.removeAll()
            oppRevealed.removeAll()
            reveal(line: line, values: values, of: player)
            if player == localPlayer {
                banner = "나: \(GameEngine.lineName(line)) — \(hand.description) 선언!"
            } else {
                banner = "\(opponentName): \(hand.description) 선언 — 더 강한 족보로 응수하세요!"
            }

        case .resolved(let player, let line, let values, let hand, let lead, let roundWinner, let round, let scores):
            reveal(line: line, values: values, of: player)
            let myHand = player == localPlayer ? hand : lead.hand
            let oppHand = player == localPlayer ? lead.hand : hand
            let verdict: String
            if let roundWinner {
                verdict = roundWinner == localPlayer ? "나의 승점!" : "\(opponentName)의 승점!"
            } else {
                verdict = "무승부"
            }
            let myPts = scores[localPlayer.rawValue]
            let oppPts = scores[localPlayer.opponent.rawValue]
            banner = "R\(round): 나 \(myHand.rank.label) vs \(opponentName) \(oppHand.rank.label) — \(verdict) (\(myPts):\(oppPts))"
            scheduleCoverAfterRound()

        case .forfeited(let player):
            let name = player == localPlayer ? "나" : opponentName
            banner = forfeitedByViolation
                ? "암기 위반! \(name) 몰수패"
                : "\(name) 기권"
        }

        if engine.phase == .finished {
            revealAllBoards()
            recordStatsIfNeeded()
        }

        restartTimerIfNeeded()
        prepareTurn()
    }

    /// 다음 턴 준비 — 내 배치 턴이면 주사위를 굴리고, AI 턴이면 스케줄한다
    private func prepareTurn() {
        if engine.phase == .placement, isMyTurn, pendingRoll == nil {
            let roll = Int.random(in: 1...GameEngine.diceSides)
            pendingRoll = roll
            banner = "🎲 \(roll)이(가) 나왔습니다 — 배치할 칸을 선택하세요."
        } else if engine.phase == .placement, !isMyTurn, banner.isEmpty {
            banner = "\(opponentName)가 주사위를 굴려 배치하는 중…"
        } else if engine.phase == .combo, isMyTurn, handToBeat == nil, banner.isEmpty {
            banner = "라운드 \(engine.round) — 한 방향으로 이어진 4칸을 선택해 족보를 선언하세요."
        }
        scheduleAIIfNeeded()
    }

    private func recordStatsIfNeeded() {
        guard !statsRecorded else { return }
        statsRecorded = true
        // 무승부는 전적에 기록하지 않는다
        guard let winner = engine.winner else { return }
        let won = winner == localPlayer
        switch mode {
        case .solo(let difficulty):
            StatsStore.shared.recordSolo(difficulty: difficulty, won: won)
        case .online:
            StatsStore.shared.recordOnline(won: won)
        }
    }

    // MARK: - 공개/덮기 연출

    private func reveal(line: Int, values: [Int], of player: Player) {
        for (i, cell) in GameEngine.lines[line].enumerated() {
            if player == localPlayer {
                myRevealed[cell] = values[i]
            } else {
                oppRevealed[cell] = values[i]
            }
        }
    }

    /// 라운드 판정 후 잠시 보여주고 양쪽 게임판을 다시 덮는다
    private func scheduleCoverAfterRound() {
        revealGeneration += 1
        let generation = revealGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard let self, self.revealGeneration == generation,
                  self.engine.phase != .finished else { return }
            self.myRevealed.removeAll()
            self.oppRevealed.removeAll()
        }
    }

    /// 게임 종료 — 양쪽 게임판 전체 공개
    private func revealAllBoards() {
        revealGeneration += 1
        for cell in 0..<GameEngine.cellCount {
            myRevealed[cell] = engine.boards[localPlayer.rawValue][cell]
            oppRevealed[cell] = engine.boards[localPlayer.opponent.rawValue][cell]
        }
    }

    // MARK: - 턴 타이머 (족보 제출 단계 60초)

    private func restartTimerIfNeeded() {
        timerTask?.cancel()
        guard engine.phase == .combo else { return }
        secondsLeft = Int(GameEngine.turnTimeLimit)
        let turnOwner = engine.currentTurn
        timerTask = Task { [weak self] in
            while let self, self.secondsLeft > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.secondsLeft -= 1
            }
            guard let self, !Task.isCancelled else { return }
            // 내 차례에서만 시간 초과를 실제로 적용한다 (상대 기기는 자기 쪽에서 처리).
            // 시간 초과 시 남은 라인 중 하나가 무작위로 선언된다.
            if turnOwner == self.localPlayer, self.engine.currentTurn == turnOwner,
               self.engine.phase == .combo {
                self.anchorSelection = nil
                if let line = self.engine.unusedLines(of: self.localPlayer).randomElement() {
                    self.applyLocal(.declare(line: line))
                }
            }
        }
    }

    // MARK: - AI 턴 진행 (1인용)

    private func scheduleAIIfNeeded() {
        guard case .solo = mode, let aiPlayer = ai,
              engine.phase != .finished, engine.currentTurn == aiPlayer.me else { return }
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 1.0...2.0)))
            guard let self, !Task.isCancelled else { return }
            guard self.engine.currentTurn == aiPlayer.me, self.engine.phase != .finished else { return }

            switch self.engine.phase {
            case .placement:
                let roll = Int.random(in: 1...GameEngine.diceSides)
                let empty = self.engine.emptyCells(of: aiPlayer.me)
                let cell = self.ai?.choosePlacement(value: roll, emptyCells: empty) ?? empty[0]
                self.applyAI(.place(cell: cell, value: roll))

            case .combo:
                self.ai?.decayMemory()
                var responding: Hand?
                if let pending = self.engine.pendingDeclaration, pending.player != aiPlayer.me {
                    responding = pending.hand
                }
                let unused = self.engine.unusedLines(of: aiPlayer.me)
                let line = self.ai?.chooseDeclaration(respondingTo: responding, unusedLines: unused)
                    ?? unused[0]
                self.applyAI(.declare(line: line))

            case .finished:
                break
            }
        }
    }
}
