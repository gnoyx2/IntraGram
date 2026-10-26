import UIKit

// iOS 27.1+: 접는 iPhone이 알려 주는 접힘선(UIView.ReservedRegion .division)과 힌지 상태를 잼.
// Flutter iOS 엔진은 MediaQuery.displayFeatures를 안 채워서 창을 덮는 보이지 않는 이 뷰가 재고, 바뀔 때만 알림
// (lib/core/display_regions.dart). 비활성 접힘선(평평하게 폄)도 보내서 Android 평평한 폴드처럼 다룸
@available(iOS 27.1, *)
final class DisplayRegionProbe: UIView {
  private let onChange: ([String: Any]) -> Void
  private var status = UIHinge.Status.unknown
  private var reported: (status: UIHinge.Status, regions: [[Double]])?

  init(onChange: @escaping ([String: Any]) -> Void) {
    self.onChange = onChange
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // 접고 펴면 접힘선의 활성 여부가 바뀜. 창 크기·회전·커버 화면 전환은 layoutSubviews가 받음
    addInteraction(
      UIHingeInteraction { [weak self] _, update in
        self?.status = update.hinge?.status ?? .unknown
        self?.report()
      })
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    report()
  }

  // Dart가 시작할 때 물어보는 지금 값
  var state: [String: Any] { ["status": status.rawValue, "regions": regions] }

  // [x, y, 폭, 높이, 활성 1·0]. 창을 덮는 뷰 기준 포인트라 Flutter 논리 픽셀과 같음
  private var regions: [[Double]] {
    reservedRegions(kind: .division, options: .includeInactive).map { region in
      let frame = region.frame
      return [
        Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height),
        region.isActive ? 1 : 0,
      ]
    }
  }

  private func report() {
    let now = regions
    if let reported, reported.status == status, reported.regions == now { return }
    reported = (status, now)
    onChange(["status": status.rawValue, "regions": now])
  }
}
