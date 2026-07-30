import SwiftUI

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ruleSection("🎯 목표",
                        "5×5 게임판에 배치된 숫자의 위치를 암기하고, 숫자를 조합해 상대보다 강한 족보를 " +
                        "만들어 승점을 모으는 게임입니다. 12라운드 뒤 승점이 높은 쪽이 승리합니다.")

                    ruleSection("🎲 게임판 설정",
                        """
                        • 각 플레이어는 5×5 게임판(A1~E5)을 지급받습니다.
                        • 선 플레이어부터 번갈아, 1~10이 적힌 10면체 주사위를 굴려 나온 숫자를 \
                        자신의 게임판 빈 칸에 하나씩 배치합니다.
                        • 25칸이 모두 찰 때까지 반복합니다.
                        """)

                    ruleSection("🧠 암기",
                        "게임판 설정이 끝나면 숫자는 모두 가려집니다. 이후에는 오직 암기한 내용만으로 " +
                        "족보를 선언해야 하며, 스크린샷 등 기록 행위가 감지되면 그 즉시 몰수패합니다.")

                    ruleSection("🃏 족보 제출",
                        """
                        • 자신의 게임판에서 가로/세로/대각선 중 한 방향으로 이어진 4칸을 골라 족보를 선언합니다.
                        • 이미 선언한 조합(라인)은 다시 사용할 수 없습니다.
                        • 매 라운드 두 플레이어가 한 번씩 선언하며, 먼저 선언하는 순서는 라운드마다 교대합니다.
                        • 제한 시간 1분 안에 선언하지 못하면 남은 라인 중 하나가 무작위로 선언됩니다.
                        • 족보가 높은 쪽이 승점 1점을 가져갑니다.
                        """)

                    ruleSection("🏆 족보 순위",
                        """
                        1위 쿼드 — 4개의 숫자가 모두 동일 (예: 1,1,1,1)
                        2위 로얄 스트레이트 — 순서대로 연속 (예: 1,2,3,4)
                        3위 스트레이트 — 연속이지만 순서가 뒤섞임 (예: 1,3,2,4)
                        4위 투페어 — 같은 숫자 2개가 2쌍 (예: 1,1,2,2)
                        5위 트리플 — 3개의 숫자가 동일 (예: 1,1,1,2)
                        6위 원페어 — 2개의 숫자가 동일 (예: 1,1,2,4)
                        7위 하이 — 위 어디에도 해당 없음 (예: 1,3,5,7)

                        같은 조합이면 사용한 숫자가 더 높은 쪽이 승리하고, 숫자마저 같으면 무승부입니다.
                        """)

                    ruleSection("💡 팁",
                        "배치 단계부터 전략이 시작됩니다. 같은 숫자를 한 라인에 모아 쿼드를 노리거나, " +
                        "연속된 숫자를 순서대로 놓아 로얄 스트레이트를 만들어 두세요. 라인 하나가 여러 조합과 " +
                        "겹치므로, 어느 라인을 어느 라운드에 소모할지가 승부처입니다.")
                }
                .padding()
            }
            .navigationTitle("게임 방법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func ruleSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}
