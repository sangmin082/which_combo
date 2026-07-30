import Combine
import SwiftUI
import UIKit

/// 대국 화면 — 상대 게임판(축소)과 내 게임판(5×5), 승점, 턴 타이머, 안내 배너.
struct GameView: View {
    @State var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showResignAlert = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.15),
                                    Color(red: 0.13, green: 0.08, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                scoreboard
                banner
                opponentBoard
                myBoard
                Spacer(minLength: 0)
                bottomBar
            }
            .padding()

            if viewModel.engine.phase == .finished {
                gameOverOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            // 규칙: 게임판을 물리적으로 기록하면 몰수패 (암기 위반)
            viewModel.memoryViolation()
        }
        .onDisappear { viewModel.cancelAllWork() }
        .alert("기권하시겠습니까?", isPresented: $showResignAlert) {
            Button("기권", role: .destructive) { viewModel.resign() }
            Button("계속하기", role: .cancel) {}
        }
        .alert("상대가 나갔습니다", isPresented: $viewModel.opponentLeft) {
            Button("나가기") { dismiss() }
        }
    }

    // MARK: 스코어보드

    private var scoreboard: some View {
        HStack(spacing: 12) {
            playerBadge(name: "나 (\(viewModel.localPlayer.label))",
                        score: viewModel.myScore,
                        active: viewModel.isMyTurn)
            VStack(spacing: 2) {
                if viewModel.engine.phase == .placement {
                    Text("배치")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(viewModel.engine.placedCount)/50")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                } else {
                    Text("R \(min(viewModel.engine.round, GameEngine.totalRounds))/\(GameEngine.totalRounds)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(viewModel.myScore) : \(viewModel.opponentScore)")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.white)
                }
            }
            playerBadge(name: "\(viewModel.opponentName) (\(viewModel.localPlayer.opponent.label))",
                        score: viewModel.opponentScore,
                        active: !viewModel.isMyTurn && viewModel.engine.phase != .finished)
        }
    }

    private func playerBadge(name: String, score: Int, active: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption.bold())
                .lineLimit(1)
            if viewModel.engine.phase != .placement {
                Label("\(score)점", systemImage: "star.fill")
                    .font(.caption2.monospacedDigit())
            }
        }
        .foregroundStyle(active ? .yellow : .white.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(active ? 0.14 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? .yellow.opacity(0.7) : .clear, lineWidth: 1.5))
        )
    }

    // MARK: 배너 & 타이머 & 주사위

    private var banner: some View {
        VStack(spacing: 8) {
            Text(viewModel.banner)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

            if viewModel.engine.phase == .placement, viewModel.isMyTurn,
               let roll = viewModel.pendingRoll {
                HStack(spacing: 8) {
                    Image(systemName: "dice.fill")
                    Text("\(roll)")
                        .font(.title2.monospacedDigit().bold())
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(.yellow))
            }

            if viewModel.engine.phase == .combo {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    ProgressView(value: Double(viewModel.secondsLeft),
                                 total: GameEngine.turnTimeLimit)
                        .tint(viewModel.secondsLeft <= 10 ? .red : .yellow)
                    Text("\(viewModel.secondsLeft)초")
                        .font(.caption.monospacedDigit().bold())
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: 상대 게임판 (축소)

    private var opponentBoard: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.opponentName)의 게임판")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 5),
                      spacing: 3) {
                ForEach(0..<GameEngine.cellCount, id: \.self) { cellIndex in
                    BoardCellView(
                        label: GameEngine.cellName(cellIndex),
                        revealedValue: viewModel.oppRevealed[cellIndex],
                        isFilled: viewModel.engine.phase == .placement
                            && viewModel.engine.boards[viewModel.localPlayer.opponent.rawValue][cellIndex] > 0,
                        isSelected: false,
                        isEndpoint: false,
                        compact: true
                    )
                }
            }
            .frame(maxWidth: 220)
        }
    }

    // MARK: 내 게임판

    private var myBoard: some View {
        VStack(spacing: 4) {
            Text("내 게임판")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<GameEngine.cellCount, id: \.self) { cellIndex in
                    BoardCellView(
                        label: GameEngine.cellName(cellIndex),
                        revealedValue: myCellValue(cellIndex),
                        isFilled: false,
                        isSelected: viewModel.anchorSelection == cellIndex,
                        isEndpoint: isEndpointCandidate(cellIndex),
                        compact: false
                    )
                    .onTapGesture { viewModel.tapCell(cellIndex) }
                }
            }
        }
    }

    /// 내 게임판에서 지금 보여줄 숫자 — 배치 단계에는 배치한 숫자 전부,
    /// 족보 제출 단계에는 공개 연출 중인 칸만 (암기!)
    private func myCellValue(_ cellIndex: Int) -> Int? {
        if viewModel.myBoardVisible {
            let value = viewModel.engine.boards[viewModel.localPlayer.rawValue][cellIndex]
            return value > 0 ? value : nil
        }
        return viewModel.myRevealed[cellIndex]
    }

    /// 첫 끝 칸을 고른 뒤 이어질 수 있는 반대쪽 끝 칸 표시
    private func isEndpointCandidate(_ cellIndex: Int) -> Bool {
        guard viewModel.engine.phase == .combo, viewModel.isMyTurn,
              let anchor = viewModel.anchorSelection else { return false }
        return viewModel.validEndpoints(from: anchor).contains(cellIndex)
    }

    // MARK: 하단 바

    private var bottomBar: some View {
        HStack {
            Button {
                showResignAlert = true
            } label: {
                Label("기권", systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Label("기록·스크린샷은 몰수패!", systemImage: "camera.viewfinder")
                .font(.caption2)
                .foregroundStyle(.red.opacity(0.8))
        }
    }

    // MARK: 게임 종료 오버레이

    private var resultTitle: String {
        if viewModel.engine.endedInDraw { return "🤝 무승부" }
        return viewModel.engine.winner == viewModel.localPlayer ? "🏆 승리!" : "💀 패배"
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 16) {
            Text(resultTitle)
                .font(.largeTitle.bold())
            Text("최종 승점 \(viewModel.myScore) : \(viewModel.opponentScore)")
                .font(.headline)
            Text(viewModel.banner)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("나가기") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.85)))
        .padding(40)
    }
}

/// 게임판 칸 하나 — 평소엔 좌표가 적힌 커버, 공개 시 숫자 표시.
struct BoardCellView: View {
    let label: String
    let revealedValue: Int?
    /// 배치 단계에서 상대 칸이 채워졌는지 (숫자는 비공개)
    let isFilled: Bool
    let isSelected: Bool
    let isEndpoint: Bool
    let compact: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 4 : 8)
                .fill(revealedValue != nil
                      ? AnyShapeStyle(Color(red: 0.93, green: 0.89, blue: 0.78))
                      : isFilled
                      ? AnyShapeStyle(Color(red: 0.35, green: 0.38, blue: 0.52))
                      : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.22, green: 0.25, blue: 0.40),
                                                              Color(red: 0.12, green: 0.14, blue: 0.26)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 4 : 8).stroke(
                        isSelected ? Color.yellow :
                        isEndpoint ? Color.green : Color.white.opacity(0.2),
                        lineWidth: isSelected || isEndpoint ? 2.5 : 1)
                )

            if let value = revealedValue {
                Text("\(value)")
                    .font(compact ? .caption.bold().monospacedDigit()
                                  : .title2.bold().monospacedDigit())
                    .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.30))
            } else {
                Text(label)
                    .font(compact ? .system(size: 8) : .caption2)
                    .foregroundStyle(.white.opacity(isFilled ? 0.9 : 0.45))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(duration: 0.3), value: revealedValue)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isEndpoint)
    }
}
