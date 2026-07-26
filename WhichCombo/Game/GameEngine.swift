import Foundation

// MARK: - 기본 타입

/// 대국의 두 플레이어. `first`가 선(先), `second`가 후(後).
enum Player: Int, Codable, Equatable, Sendable {
    case first = 0
    case second = 1

    var opponent: Player { self == .first ? .second : .first }
    var label: String { self == .first ? "선" : "후" }
}

/// 게임 진행 단계
enum Phase: String, Codable, Equatable, Sendable {
    /// 게임판 설정 단계 — 주사위(1~10)를 굴려 나온 숫자를 자기 5×5 게임판에 배치
    case placement
    /// 족보 제출 단계 — 암기한 게임판에서 한 방향으로 이어진 4칸을 골라 족보를 선언
    case combo
    /// 게임 종료
    case finished
}

/// 플레이어가 취할 수 있는 행동
enum Move: Codable, Equatable, Sendable {
    /// 배치 단계: 주사위로 나온 `value`(1~10)를 자기 게임판의 빈 칸 `cell`에 배치
    case place(cell: Int, value: Int)
    /// 족보 제출 단계: 자기 게임판의 라인(`GameEngine.lines`의 인덱스) 하나를 족보로 선언
    case declare(line: Int)
    /// 기권 또는 몰수패(암기 위반 등)
    case forfeit

    private enum CodingKeys: String, CodingKey { case kind, cell, value, line }
    private enum Kind: String, Codable { case place, declare, forfeit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .place: self = .place(cell: try c.decode(Int.self, forKey: .cell),
                                   value: try c.decode(Int.self, forKey: .value))
        case .declare: self = .declare(line: try c.decode(Int.self, forKey: .line))
        case .forfeit: self = .forfeit
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .place(let cell, let value):
            try c.encode(Kind.place, forKey: .kind)
            try c.encode(cell, forKey: .cell)
            try c.encode(value, forKey: .value)
        case .declare(let line):
            try c.encode(Kind.declare, forKey: .kind)
            try c.encode(line, forKey: .line)
        case .forfeit:
            try c.encode(Kind.forfeit, forKey: .kind)
        }
    }
}

// MARK: - 족보

/// 4개의 숫자로 만든 족보. 순위 비교가 가능하다.
struct Hand: Codable, Equatable, Comparable, Sendable {
    enum Rank: Int, Codable, Equatable, Comparable, Sendable, CaseIterable {
        case high = 0        // 7위 하이 — 같은 숫자도 없고 연속도 아님
        case pair            // 6위 원페어
        case triple          // 5위 트리플
        case twoPair         // 4위 투페어
        case straight        // 3위 스트레이트 — 연속이지만 순서가 뒤섞임
        case royalStraight   // 2위 로얄 스트레이트 — 순서대로 연속
        case quad            // 1위 쿼드 — 4개 모두 동일

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .high: return "하이"
            case .pair: return "원페어"
            case .triple: return "트리플"
            case .twoPair: return "투페어"
            case .straight: return "스트레이트"
            case .royalStraight: return "로얄 스트레이트"
            case .quad: return "쿼드"
            }
        }
    }

    let rank: Rank
    /// 라인 순서 그대로의 숫자 4개
    let values: [Int]

    /// 같은 족보끼리는 사용한 숫자가 높은 쪽이 승리 — 내림차순 사전식 비교
    var tiebreak: [Int] { values.sorted(by: >) }

    init(values: [Int]) {
        self.values = values
        self.rank = Self.evaluate(values)
    }

    private static func evaluate(_ values: [Int]) -> Rank {
        var counts: [Int: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }

        if counts.values.contains(4) { return .quad }

        // 연속 판정 (4개 모두 서로 다른 숫자여야 함)
        if counts.count == 4 {
            let sorted = values.sorted()
            let consecutive = (0..<3).allSatisfy { sorted[$0 + 1] == sorted[$0] + 1 }
            if consecutive {
                let steps = (0..<3).map { values[$0 + 1] - values[$0] }
                let sequential = steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
                return sequential ? .royalStraight : .straight
            }
        }

        let pairCount = counts.values.filter { $0 == 2 }.count
        if pairCount == 2 { return .twoPair }
        if counts.values.contains(3) { return .triple }
        if pairCount == 1 { return .pair }
        return .high
    }

    static func < (lhs: Hand, rhs: Hand) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        for (l, r) in zip(lhs.tiebreak, rhs.tiebreak) where l != r { return l < r }
        return false
    }

    /// "스트레이트 (1·3·2·4)" 형태의 표시용 문자열
    var description: String {
        "\(rank.label) (\(values.map(String.init).joined(separator: "·")))"
    }
}

/// 한 라운드에서 먼저 제출된 족보 선언
struct Declaration: Codable, Equatable, Sendable {
    let player: Player
    let line: Int
    let hand: Hand
}

/// 무브 적용 결과 — UI 연출과 AI 관찰에 사용
enum MoveOutcome: Equatable, Sendable {
    /// 게임판에 숫자 배치됨
    case placed(player: Player, cell: Int, value: Int)
    /// 라운드의 첫 족보 선언 — 상대의 선언을 기다림
    case declared(player: Player, line: Int, values: [Int], hand: Hand)
    /// 라운드의 두 번째 선언으로 라운드 판정 완료 (`roundWinner`가 nil이면 무승부)
    case resolved(player: Player, line: Int, values: [Int], hand: Hand,
                  lead: Declaration, roundWinner: Player?, round: Int, scores: [Int])
    /// 기권/몰수패 — 상대 승리
    case forfeited(player: Player)
}

enum EngineError: Error, Equatable {
    case gameFinished
    case notYourTurn
    case wrongPhase
    case cellOutOfRange
    case cellOccupied
    case invalidValue      // 주사위 값이 1~10 범위 밖
    case lineOutOfRange
    case lineAlreadyUsed   // 이미 선언한 조합은 재사용 불가
}

// MARK: - 게임 엔진

/// 「위치, 콤보!」 규칙 상태기계.
/// 순수 값 타입이라 온라인 대전에서 양쪽 기기가 같은 무브 스트림으로 동일 상태를 재현한다.
/// (배치 숫자는 주사위 랜덤이므로 `place` 무브가 값을 함께 실어 나른다.)
struct GameEngine: Codable, Equatable {
    static let boardSize = 5
    static let cellCount = 25
    static let diceSides = 10
    static let totalRounds = 12
    static let turnTimeLimit: TimeInterval = 60

    /// 플레이어별 게임판 (0 = 빈 칸, 1~10 = 배치된 숫자)
    private(set) var boards: [[Int]]
    private(set) var phase: Phase
    /// 족보 제출 단계의 현재 라운드 (1~12)
    private(set) var round: Int
    /// 이번 라운드에 먼저 선언하는 플레이어 (라운드마다 교대)
    private(set) var roundLeader: Player
    private(set) var currentTurn: Player
    /// 이번 라운드의 첫 선언 (두 번째 선언을 기다리는 중이면 non-nil)
    private(set) var pendingDeclaration: Declaration?
    /// 플레이어별로 이미 선언해 재사용할 수 없는 라인들
    private(set) var usedLines: [Set<Int>]
    /// 승점
    private(set) var scores: [Int]
    private(set) var winner: Player?
    /// 12라운드 종료 시 승점까지 동일한 무승부인지
    private(set) var endedInDraw: Bool
    /// 몰수패/기권으로 끝났는지 (승리 연출 구분용)
    private(set) var endedByForfeit: Bool

    init() {
        boards = [Array(repeating: 0, count: Self.cellCount),
                  Array(repeating: 0, count: Self.cellCount)]
        phase = .placement
        round = 1
        roundLeader = .first
        currentTurn = .first
        pendingDeclaration = nil
        usedLines = [[], []]
        scores = [0, 0]
        winner = nil
        endedInDraw = false
        endedByForfeit = false
    }

    // MARK: 라인 (가로/세로/대각선으로 이어진 4칸) — 총 28개

    /// 모든 유효한 라인. 각 라인은 게임판 셀 인덱스 4개(방향 순서 유지).
    static let lines: [[Int]] = makeLines()

    private static func makeLines() -> [[Int]] {
        var result: [[Int]] = []
        func cell(_ r: Int, _ c: Int) -> Int { r * boardSize + c }
        // 가로
        for r in 0..<boardSize {
            for c0 in 0...(boardSize - 4) {
                result.append((0..<4).map { cell(r, c0 + $0) })
            }
        }
        // 세로
        for c in 0..<boardSize {
            for r0 in 0...(boardSize - 4) {
                result.append((0..<4).map { cell(r0 + $0, c) })
            }
        }
        // 대각선 ↘
        for r0 in 0...(boardSize - 4) {
            for c0 in 0...(boardSize - 4) {
                result.append((0..<4).map { cell(r0 + $0, c0 + $0) })
            }
        }
        // 대각선 ↙
        for r0 in 0...(boardSize - 4) {
            for c0 in 3..<boardSize {
                result.append((0..<4).map { cell(r0 + $0, c0 - $0) })
            }
        }
        return result
    }

    /// "A1" 형식의 셀 이름 (행 A~E, 열 1~5)
    static func cellName(_ cell: Int) -> String {
        let rows = ["A", "B", "C", "D", "E"]
        return rows[cell / boardSize] + "\(cell % boardSize + 1)"
    }

    /// "A1–A4" 형식의 라인 이름
    static func lineName(_ line: Int) -> String {
        let cells = lines[line]
        return "\(cellName(cells[0]))–\(cellName(cells[3]))"
    }

    /// 양 끝 셀로 라인 인덱스를 찾는다 (방향 무관). 없으면 nil.
    static func lineIndex(from a: Int, to b: Int) -> Int? {
        lines.firstIndex {
            ($0.first == a && $0.last == b) || ($0.first == b && $0.last == a)
        }
    }

    /// 특정 셀을 지나는 라인들의 인덱스
    static func linesThrough(cell: Int) -> [Int] {
        lines.indices.filter { lines[$0].contains(cell) }
    }

    // MARK: 조회

    /// 배치 단계에서 해당 플레이어의 아직 빈 칸들
    func emptyCells(of player: Player) -> [Int] {
        boards[player.rawValue].indices.filter { boards[player.rawValue][$0] == 0 }
    }

    /// 지금까지 배치된 숫자 개수 (양쪽 합, 진행 표시용)
    var placedCount: Int {
        boards[0].filter { $0 > 0 }.count + boards[1].filter { $0 > 0 }.count
    }

    /// 해당 플레이어가 아직 선언하지 않은 라인들
    func unusedLines(of player: Player) -> [Int] {
        Self.lines.indices.filter { !usedLines[player.rawValue].contains($0) }
    }

    /// 라인의 실제 숫자 4개 (플레이어 게임판 기준)
    func lineValues(_ line: Int, of player: Player) -> [Int] {
        Self.lines[line].map { boards[player.rawValue][$0] }
    }

    // MARK: 무브 적용

    @discardableResult
    mutating func apply(_ move: Move, by player: Player) throws -> MoveOutcome {
        guard phase != .finished else { throw EngineError.gameFinished }

        // 기권/몰수패(암기 위반)는 상대 턴 중에도 발생할 수 있다
        if case .forfeit = move {
            phase = .finished
            winner = player.opponent
            endedByForfeit = true
            return .forfeited(player: player)
        }

        guard player == currentTurn else { throw EngineError.notYourTurn }

        switch move {
        case .place(let cell, let value):
            return try applyPlace(cell: cell, value: value, by: player)
        case .declare(let line):
            return try applyDeclare(line: line, by: player)
        case .forfeit:
            fatalError("위에서 처리됨")
        }
    }

    private mutating func applyPlace(cell: Int, value: Int, by player: Player) throws -> MoveOutcome {
        guard phase == .placement else { throw EngineError.wrongPhase }
        guard boards[player.rawValue].indices.contains(cell) else { throw EngineError.cellOutOfRange }
        guard boards[player.rawValue][cell] == 0 else { throw EngineError.cellOccupied }
        guard (1...Self.diceSides).contains(value) else { throw EngineError.invalidValue }

        boards[player.rawValue][cell] = value

        // 선→후 순으로 한 칸씩 배치, 양쪽 게임판이 다 차면 족보 제출 단계로
        if player == .first {
            currentTurn = .second
        } else {
            if !boards[0].contains(0) && !boards[1].contains(0) {
                phase = .combo
                round = 1
                roundLeader = .first
                currentTurn = .first
            } else {
                currentTurn = .first
            }
        }
        return .placed(player: player, cell: cell, value: value)
    }

    private mutating func applyDeclare(line: Int, by player: Player) throws -> MoveOutcome {
        guard phase == .combo else { throw EngineError.wrongPhase }
        guard Self.lines.indices.contains(line) else { throw EngineError.lineOutOfRange }
        guard !usedLines[player.rawValue].contains(line) else { throw EngineError.lineAlreadyUsed }

        let values = lineValues(line, of: player)
        let hand = Hand(values: values)
        usedLines[player.rawValue].insert(line)

        guard let lead = pendingDeclaration else {
            // 라운드의 첫 선언 — 상대의 선언을 기다린다
            pendingDeclaration = Declaration(player: player, line: line, hand: hand)
            currentTurn = player.opponent
            return .declared(player: player, line: line, values: values, hand: hand)
        }

        // 라운드 판정 — 족보가 높은 쪽이 승점 1점
        let roundWinner: Player?
        if hand > lead.hand {
            roundWinner = player
        } else if lead.hand > hand {
            roundWinner = lead.player
        } else {
            roundWinner = nil
        }
        if let roundWinner { scores[roundWinner.rawValue] += 1 }

        let resolvedRound = round
        pendingDeclaration = nil

        if round == Self.totalRounds {
            phase = .finished
            if scores[0] != scores[1] {
                winner = scores[0] > scores[1] ? .first : .second
            } else {
                winner = nil
                endedInDraw = true
            }
        } else {
            round += 1
            roundLeader = roundLeader.opponent
            currentTurn = roundLeader
        }

        return .resolved(player: player, line: line, values: values, hand: hand,
                         lead: lead, roundWinner: roundWinner,
                         round: resolvedRound, scores: scores)
    }
}
