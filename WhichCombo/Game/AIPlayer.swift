import Foundation

/// 1인용 모드의 AI 상대.
///
/// 사람처럼 "불완전한 기억"으로 플레이한다: 자기 게임판에 배치한 숫자를 기억하되,
/// 난이도에 따라 일부를 잊거나 헷갈린다. 실제 게임판(`GameEngine.boards`)은
/// 절대 직접 읽지 않고 자신의 기억(`memory`)만으로 족보를 선언한다.
struct AIPlayer {
    enum Difficulty: String, CaseIterable, Identifiable {
        case easy, normal, hard

        var id: String { rawValue }
        var label: String {
            switch self {
            case .easy: return "쉬움"
            case .normal: return "보통"
            case .hard: return "어려움"
            }
        }
        /// 배치 직후 그 위치를 올바르게 기억할 확률
        var retention: Double {
            switch self {
            case .easy: return 0.55
            case .normal: return 0.78
            case .hard: return 0.95
            }
        }
        /// 매 턴 시작 시 기억 하나를 잊을 확률
        var decay: Double {
            switch self {
            case .easy: return 0.30
            case .normal: return 0.15
            case .hard: return 0.04
            }
        }
    }

    let difficulty: Difficulty
    let me: Player

    /// 자기 게임판 칸별로 "어떤 숫자가 있다고 기억하는지" (nil = 모름/잊음, 0 = 빈 칸)
    private(set) var memory: [Int?]
    private var rng: SystemRandomNumberGenerator

    init(difficulty: Difficulty, me: Player) {
        self.difficulty = difficulty
        self.me = me
        // 게임 시작 시 모든 칸이 비어 있다는 것은 자명한 정보
        self.memory = Array(repeating: 0, count: GameEngine.cellCount)
        self.rng = SystemRandomNumberGenerator()
    }

    // MARK: - 관찰 (엔진 outcome을 흘려 넣어 기억을 갱신)

    mutating func observe(_ outcome: MoveOutcome) {
        switch outcome {
        case .placed(let player, let cell, let value):
            // 자기 게임판 배치만 의미가 있다 — 난이도 확률로 기억
            guard player == me else { return }
            if Double.random(in: 0..<1, using: &rng) < difficulty.retention {
                memory[cell] = value
            } else {
                memory[cell] = nil
            }
        case .declared(let player, let line, let values, _),
             .resolved(let player, let line, let values, _, _, _, _, _):
            // 내 족보가 공개되면 그 4칸의 실제 숫자를 확실히 알게 된다
            guard player == me else { return }
            for (i, cell) in GameEngine.lines[line].enumerated() {
                memory[cell] = values[i]
            }
        case .forfeited:
            break
        }
    }

    /// 턴 사이에 자연스럽게 기억이 흐려진다
    mutating func decayMemory() {
        guard Double.random(in: 0..<1, using: &rng) < difficulty.decay else { return }
        let known = memory.indices.filter { (memory[$0] ?? 0) > 0 }
        if let victim = known.randomElement(using: &rng) {
            memory[victim] = nil
        }
    }

    // MARK: - 의사결정

    /// 배치 단계: 주사위 값 `value`를 놓을 빈 칸을 고른다.
    /// 기억하는 주변 숫자와의 시너지(쿼드/스트레이트 잠재력)를 점수화한다.
    func choosePlacement(value: Int, emptyCells: [Int]) -> Int {
        guard !emptyCells.isEmpty else { return 0 }
        if difficulty == .easy { return emptyCells.randomElement() ?? emptyCells[0] }

        var scored: [(cell: Int, score: Int)] = emptyCells.map { cell in
            var score = 0
            for line in GameEngine.linesThrough(cell: cell) {
                let others = GameEngine.lines[line].filter { $0 != cell }
                let knowns = others.compactMap { memory[$0] }.filter { $0 > 0 }
                // 같은 숫자가 모이면 쿼드/트리플/페어 잠재력
                score += knowns.filter { $0 == value }.count * 3
                // 3 이내로 가까운 숫자가 모이면 스트레이트 잠재력
                score += knowns.filter { $0 != value && abs($0 - value) <= 3 }.count
            }
            return (cell, score)
        }
        scored.shuffle()
        scored.sort { $0.score > $1.score }

        switch difficulty {
        case .easy:
            return emptyCells.randomElement() ?? emptyCells[0]
        case .normal:
            // 상위 3개 중 랜덤 — 약간의 실수 여지
            return scored.prefix(3).randomElement()?.cell ?? scored[0].cell
        case .hard:
            return scored[0].cell
        }
    }

    /// 족보 제출 단계: 선언할 라인을 고른다.
    /// - Parameter respondingTo: 상대가 먼저 선언한 족보 (내가 라운드 후공이면 non-nil)
    func chooseDeclaration(respondingTo target: Hand?, unusedLines: [Int]) -> Int {
        // 4칸을 모두 기억하는 라인만 족보를 예측할 수 있다
        let known: [(line: Int, hand: Hand)] = unusedLines.compactMap { line in
            let remembered = GameEngine.lines[line].compactMap { memory[$0] }.filter { $0 > 0 }
            guard remembered.count == 4 else { return nil }
            return (line, Hand(values: remembered))
        }

        if let target {
            // 후공: 이길 수 있는 가장 약한 족보로 승점을 따고, 못 이기면 최약체를 버린다
            let winners = known.filter { $0.hand > target }
            if let cheapest = winners.min(by: { $0.hand < $1.hand }) { return cheapest.line }
            if let weakest = known.min(by: { $0.hand < $1.hand }) { return weakest.line }
        } else if !known.isEmpty {
            // 선공: 중간 강도의 족보를 내고 강한 패는 후공 라운드를 위해 아낀다
            let sorted = known.sorted { $0.hand < $1.hand }
            return sorted[sorted.count / 2].line
        }

        // 기억이 모자라면 그나마 많이 기억하는 라인에 승부를 건다
        let byRemembered = unusedLines.map { line in
            (line: line, count: GameEngine.lines[line].compactMap { memory[$0] }.filter { $0 > 0 }.count)
        }
        let best = byRemembered.max { $0.count < $1.count }?.count ?? 0
        let candidates = byRemembered.filter { $0.count == best }.map(\.line)
        return candidates.randomElement() ?? unusedLines[0]
    }
}
