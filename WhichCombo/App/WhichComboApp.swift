import SwiftUI

@main
struct WhichComboApp: App {
    init() {
        // 라인 테이블·족보 판정·대본 리플레이로 엔진 규칙을 검증 (DEBUG 전용)
        EngineSelfTest.run()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
