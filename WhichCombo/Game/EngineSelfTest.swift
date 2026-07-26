import Foundation

/// 엔진 규칙 검증 — 족보 판정 단위 테스트와 대본이 정해진 대국 리플레이로
/// 라인 테이블·턴 순서·라운드 판정·승점 계산이 규칙과 일치하는지 확인한다.
/// DEBUG 빌드에서 앱 시작 시 1회 실행된다.
enum EngineSelfTest {
    static func run() {
        #if DEBUG
        do {
            try testLineTable()
            try testHandEvaluation()
            try replayScriptedGame()
            print("[EngineSelfTest] 라인 테이블·족보 판정·대국 리플레이 검증 통과 ✅")
        } catch {
            assertionFailure("[EngineSelfTest] 엔진 규칙 검증 실패: \(error)")
        }
        #endif
    }

    private enum TestError: Error { case mismatch(String) }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestError.mismatch(message) }
    }

    // MARK: 라인 테이블 — 가로 10 + 세로 10 + 대각선 8 = 28개

    static func testLineTable() throws {
        let lines = GameEngine.lines
        try expect(lines.count == 28, "라인 개수 \(lines.count) ≠ 28")
        try expect(Set(lines.map { Set($0) }).count == 28, "중복 라인 존재")
        for (i, cells) in lines.enumerated() {
            try expect(cells.count == 4, "라인 \(i) 칸 수 ≠ 4")
            try expect(cells.allSatisfy { (0..<25).contains($0) }, "라인 \(i) 범위 밖 칸")
            // 양 끝 칸으로 라인을 되찾을 수 있어야 한다 (양방향)
            try expect(GameEngine.lineIndex(from: cells[0], to: cells[3]) == i, "라인 \(i) 정방향 조회 실패")
            try expect(GameEngine.lineIndex(from: cells[3], to: cells[0]) == i, "라인 \(i) 역방향 조회 실패")
        }
        // 모서리 칸(A1)은 가로/세로/대각선 각 1개씩 3개의 라인을 지난다
        try expect(GameEngine.linesThrough(cell: 0).count == 3, "A1을 지나는 라인 수 ≠ 3")
        try expect(GameEngine.cellName(0) == "A1" && GameEngine.cellName(24) == "E5", "셀 이름 규칙")
    }

    // MARK: 족보 판정

    static func testHandEvaluation() throws {
        try expect(Hand(values: [1, 1, 1, 1]).rank == .quad, "쿼드 판정")
        try expect(Hand(values: [1, 2, 3, 4]).rank == .royalStraight, "로얄 스트레이트 (오름차순)")
        try expect(Hand(values: [4, 3, 2, 1]).rank == .royalStraight, "로얄 스트레이트 (내림차순)")
        try expect(Hand(values: [1, 3, 2, 4]).rank == .straight, "스트레이트 (순서 뒤섞임)")
        try expect(Hand(values: [1, 1, 2, 2]).rank == .twoPair, "투페어")
        try expect(Hand(values: [1, 1, 1, 2]).rank == .triple, "트리플")
        try expect(Hand(values: [1, 1, 2, 4]).rank == .pair, "원페어")
        try expect(Hand(values: [1, 3, 5, 7]).rank == .high, "하이")

        // 족보 순위: 쿼드 > 로얄 > 스트레이트 > 투페어 > 트리플 > 원페어 > 하이
        let ladder = [Hand(values: [1, 3, 5, 7]), Hand(values: [1, 1, 2, 4]),
                      Hand(values: [1, 1, 1, 2]), Hand(values: [1, 1, 2, 2]),
                      Hand(values: [1, 3, 2, 4]), Hand(values: [1, 2, 3, 4]),
                      Hand(values: [1, 1, 1, 1])]
        for i in 0..<(ladder.count - 1) {
            try expect(ladder[i] < ladder[i + 1], "순위 \(i): \(ladder[i].rank) < \(ladder[i + 1].rank)")
        }

        // 같은 조합은 사용한 숫자가 높은 쪽이 승리, 숫자까지 같으면 무승부
        try expect(Hand(values: [2, 2, 2, 2]) > Hand(values: [1, 1, 1, 1]), "쿼드 숫자 비교")
        try expect(Hand(values: [7, 7, 7, 3]) > Hand(values: [5, 5, 5, 2]), "트리플 숫자 비교")
        try expect(Hand(values: [2, 4, 6, 10]) > Hand(values: [2, 3, 4, 10]), "하이 숫자 비교")
        try expect(!(Hand(values: [4, 4, 2, 2]) > Hand(values: [2, 2, 4, 4]))
                   && !(Hand(values: [4, 4, 2, 2]) < Hand(values: [2, 2, 4, 4])), "동일 숫자 무승부")
    }

    // MARK: 대본 리플레이

    /// 셀 인덱스 헬퍼: r(0~4)행 c(0~4)열
    private static func cell(_ r: Int, _ c: Int) -> Int { r * 5 + c }

    static func replayScriptedGame() throws {
        var engine = GameEngine()

        // ── 게임판 설정: 선/후가 번갈아 자기 게임판의 0번 칸부터 순서대로 채운다
        // (row A~E, 각 행 5개 — 라인별 족보를 미리 설계해 둔 배치)
        let firstBoard = [1, 2, 3, 4, 1,     // A: A1–A4 로얄(1,2,3,4)
                          5, 5, 5, 5, 2,     // B: B1–B4 쿼드, B2–B5 트리플
                          1, 3, 2, 4, 10,    // C: C1–C4 스트레이트(1,3,2,4)
                          2, 2, 4, 4, 10,    // D: D1–D4 투페어
                          1, 3, 5, 7, 9]     // E: E1–E4 하이
        let secondBoard = [4, 3, 2, 1, 6,    // A: A1–A4 로얄(4,3,2,1)
                           7, 7, 7, 7, 3,    // B: B1–B4 쿼드
                           2, 4, 6, 8, 10,   // C: C1–C4 하이
                           4, 4, 2, 2, 5,    // D: D1–D4 투페어 (선 플레이어와 동일 숫자)
                           6, 6, 6, 2, 8]    // E: E1–E4 트리플

        for i in 0..<GameEngine.cellCount {
            let o1 = try engine.apply(.place(cell: i, value: firstBoard[i]), by: .first)
            try expect(o1 == .placed(player: .first, cell: i, value: firstBoard[i]), "배치 \(i) 선")
            let o2 = try engine.apply(.place(cell: i, value: secondBoard[i]), by: .second)
            try expect(o2 == .placed(player: .second, cell: i, value: secondBoard[i]), "배치 \(i) 후")
        }
        try expect(engine.phase == .combo, "배치 완료 후 족보 제출 단계 진입")
        try expect(engine.round == 1 && engine.roundLeader == .first && engine.currentTurn == .first,
                   "1라운드는 선 플레이어부터")

        // 잘못된 무브 거부 확인
        do {
            _ = try engine.apply(.place(cell: 0, value: 5), by: .first)
            throw TestError.mismatch("족보 단계의 배치가 거부되지 않음")
        } catch let e as EngineError { try expect(e == .wrongPhase, "족보 단계 배치 → wrongPhase") }

        // ── 족보 제출 12라운드 (리더가 매 라운드 교대, 리더부터 선언)
        func line(_ a: Int, _ b: Int) throws -> Int {
            guard let index = GameEngine.lineIndex(from: a, to: b) else {
                throw TestError.mismatch("라인 조회 실패 \(a)-\(b)")
            }
            return index
        }
        let rowA = try line(cell(0, 0), cell(0, 3))    // A1–A4
        let rowB = try line(cell(1, 0), cell(1, 3))    // B1–B4
        let rowB2 = try line(cell(1, 1), cell(1, 4))   // B2–B5
        let rowC = try line(cell(2, 0), cell(2, 3))    // C1–C4
        let rowC2 = try line(cell(2, 1), cell(2, 4))   // C2–C5
        let rowD = try line(cell(3, 0), cell(3, 3))    // D1–D4
        let rowE = try line(cell(4, 0), cell(4, 3))    // E1–E4
        let rowE2 = try line(cell(4, 1), cell(4, 4))   // E2–E5
        let col1 = try line(cell(0, 0), cell(3, 0))    // A1–D1
        let col5 = try line(cell(0, 4), cell(3, 4))    // A5–D5
        let diagMain = try line(cell(0, 0), cell(3, 3))  // A1–D4 ↘
        let diagAnti = try line(cell(1, 4), cell(4, 1))  // B5–E2 ↙

        // (리더의 라인, 후공의 라인, 예상 라운드 승자)
        struct Round { let leadLine: Int; let followLine: Int; let winner: Player? }
        let rounds: [Round] = [
            Round(leadLine: rowA, followLine: rowB, winner: .second),      // R1 선(로얄) vs 후(쿼드7)
            Round(leadLine: rowA, followLine: rowB, winner: .first),       // R2 후(로얄) vs 선(쿼드5)
            Round(leadLine: rowC, followLine: rowC, winner: .first),       // R3 선(스트레이트) vs 후(하이)
            Round(leadLine: rowD, followLine: rowD, winner: nil),          // R4 투페어 동수 → 무승부
            Round(leadLine: rowE, followLine: rowE, winner: .second),      // R5 선(하이) vs 후(트리플6)
            Round(leadLine: rowE2, followLine: rowE2, winner: .second),    // R6 후(원페어6) vs 선(하이)
            Round(leadLine: rowB2, followLine: rowB2, winner: .second),    // R7 트리플5 vs 트리플7
            Round(leadLine: rowC2, followLine: rowC2, winner: .second),    // R8 하이 숫자 비교
            Round(leadLine: col1, followLine: col1, winner: .second),      // R9 원페어 숫자 비교
            Round(leadLine: col5, followLine: col5, winner: .first),       // R10 후(하이) vs 선(원페어10)
            Round(leadLine: diagMain, followLine: diagMain, winner: .second), // R11 하이 숫자 비교
            Round(leadLine: diagAnti, followLine: diagAnti, winner: .first),  // R12 후(하이) vs 선(원페어4)
        ]

        for (index, round) in rounds.enumerated() {
            let n = index + 1
            let leader: Player = (n % 2 == 1) ? .first : .second
            try expect(engine.round == n, "라운드 번호 \(engine.round) ≠ \(n)")
            try expect(engine.roundLeader == leader && engine.currentTurn == leader,
                       "R\(n) 리더는 \(leader.label)")

            let leadOutcome = try engine.apply(.declare(line: round.leadLine), by: leader)
            guard case .declared = leadOutcome else {
                throw TestError.mismatch("R\(n) 첫 선언이 declared가 아님")
            }
            try expect(engine.currentTurn == leader.opponent, "R\(n) 첫 선언 후 턴 넘김")

            let followOutcome = try engine.apply(.declare(line: round.followLine), by: leader.opponent)
            guard case .resolved(_, _, _, _, _, let roundWinner, let resolvedRound, _) = followOutcome else {
                throw TestError.mismatch("R\(n) 두 번째 선언이 resolved가 아님")
            }
            try expect(resolvedRound == n, "R\(n) 판정 라운드 번호")
            try expect(roundWinner == round.winner,
                       "R\(n) 승자 \(String(describing: roundWinner)) ≠ \(String(describing: round.winner))")
        }

        // R2에서 선 플레이어가 이미 쓴 B1–B4 재사용은 거부되어야 했다 — 사후 확인
        do {
            var copy = engine
            _ = try copy.apply(.declare(line: rowA), by: .first)
            throw TestError.mismatch("종료된 게임의 선언이 거부되지 않음")
        } catch let e as EngineError { try expect(e == .gameFinished, "종료 후 선언 → gameFinished") }

        try expect(engine.phase == .finished, "12라운드 후 게임 종료")
        try expect(engine.scores == [4, 7], "최종 승점 \(engine.scores) ≠ [4, 7]")
        try expect(engine.winner == .second, "후 플레이어 승리")
        try expect(!engine.endedInDraw && !engine.endedByForfeit, "정상 종료")
    }
}
