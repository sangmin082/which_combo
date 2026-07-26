import SwiftUI

struct HomeView: View {
    @State private var showDifficultyDialog = false
    @State private var soloGame: GameViewModel?
    @State private var showRules = false
    @State private var showOnlineLobby = false
    @State private var showStats = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.15),
                                        Color(red: 0.16, green: 0.08, blue: 0.18)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    VStack(spacing: 10) {
                        Text("🎲")
                            .font(.system(size: 72))
                        Text("위치, 콤보!")
                            .font(.system(size: 44, weight: .black, design: .serif))
                            .foregroundStyle(.white)
                        Text("DEATH GAME — WHICH COMBO")
                            .font(.caption.weight(.semibold))
                            .kerning(2)
                            .foregroundStyle(.yellow.opacity(0.8))
                    }

                    VStack(spacing: 14) {
                        menuButton("혼자 하기", subtitle: "AI와 암기 대결", icon: "person.fill") {
                            showDifficultyDialog = true
                        }
                        menuButton("둘이 하기", subtitle: "방을 만들고 코드로 초대", icon: "person.2.fill") {
                            showOnlineLobby = true
                        }
                        menuButton("전적", subtitle: "승패 기록 보기", icon: "chart.bar.fill") {
                            showStats = true
                        }
                        menuButton("게임 방법", subtitle: "규칙 읽기", icon: "book.fill") {
                            showRules = true
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    Text("⚠️ 숫자 위치를 기록하면 몰수패됩니다")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 8)
                }
            }
            .confirmationDialog("AI 난이도", isPresented: $showDifficultyDialog, titleVisibility: .visible) {
                ForEach(AIPlayer.Difficulty.allCases) { difficulty in
                    Button(difficulty.label) {
                        soloGame = GameViewModel(mode: .solo(difficulty))
                    }
                }
            }
            .fullScreenCover(item: $soloGame) { game in
                GameView(viewModel: game)
            }
            .sheet(isPresented: $showRules) {
                RulesView()
            }
            .sheet(isPresented: $showOnlineLobby) {
                OnlineLobbyView()
            }
            .sheet(isPresented: $showStats) {
                StatsView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func menuButton(_ title: String, subtitle: String, icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).opacity(0.6)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).opacity(0.5)
            }
            .foregroundStyle(.white)
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        }
    }
}

extension GameViewModel: Identifiable {}

#Preview {
    HomeView()
}
