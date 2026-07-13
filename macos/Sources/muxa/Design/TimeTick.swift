import SwiftUI

extension View {
    /// `interval`(초)마다 `date`를 현재 시각으로 갱신한다.
    /// "3시간 38분 후"·"3분 전 갱신" 같은 상대 시각 표시가 화면에 굳어 있지 않게 하는 용도.
    /// 뷰가 사라지면 task가 취소돼 타이머도 멈춘다.
    func tick(every interval: TimeInterval, into date: Binding<Date>) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                date.wrappedValue = Date()
            }
        }
    }
}
